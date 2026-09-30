package com.teamdaisy.server.history.application;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.deployment.application.ExecutionAccess;
import jakarta.annotation.PreDestroy;
import java.io.IOException;
import java.util.Map;
import java.time.Instant;
import com.fasterxml.jackson.databind.JsonNode;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

/** Endpoint owners must supply the authenticated account ID; this service applies the shared guard. */
@Service
public class EventSseService {
  private final EventJournal journal;
  private final ObjectProvider<ExecutionAccess> access;
  private final int maxConnections;
  private final int maxPerActor;
  private final ConcurrentHashMap<Connection, Boolean> connections = new ConcurrentHashMap<>();
  // ponytail: two shared polling workers; add bounded nonblocking transport if slow clients saturate them.
  private final ScheduledThreadPoolExecutor scheduler = new ScheduledThreadPoolExecutor(2, runnable -> {
    Thread thread = new Thread(runnable, "event-replay"); thread.setDaemon(true); return thread;
  });

  public EventSseService(EventJournal journal, ObjectProvider<ExecutionAccess> access,
      @Value("${daisy.events.max-connections:128}") int maxConnections,
      @Value("${daisy.events.max-connections-per-actor:4}") int maxPerActor) {
    if(maxConnections<1 || maxPerActor<1) throw new IllegalArgumentException("Invalid SSE connection limits");
    this.journal=journal; this.access=access; this.maxConnections=maxConnections; this.maxPerActor=maxPerActor;
    scheduler.setRemoveOnCancelPolicy(true);
  }

  public SseEmitter openDeployment(String actorId,String projectId,String deploymentId,String lastEventId) {
    authorize(actorId,projectId);
    journal.requireDeploymentProject(projectId,deploymentId);
    return open(actorId,projectId,deploymentId,false,lastEventId);
  }
  public SseEmitter openProject(String actorId,String projectId,String lastEventId) {
    authorize(actorId,projectId);
    return open(actorId,projectId,projectId,true,lastEventId);
  }
  public record Envelope(long seq, Instant ts, String deploymentId, String targetId, JsonNode data) {}
  protected SseEmitter createEmitter() { return new SseEmitter(30*60*1000L); }
  private SseEmitter open(String actor,String projectId,String channel,boolean project,String lastEventId) {
    long cursor=parseCursor(lastEventId);
    EventJournal.Bounds bounds=project?journal.projectBounds(channel):journal.deploymentBounds(channel);
    SseEmitter emitter=createEmitter();
    Connection connection=new Connection(actor,projectId,channel,project,emitter,cursor);
    synchronized(connections) {
      if(connections.size()>=maxConnections || connections.keySet().stream().filter(c->actor.equals(c.actor)).count()>=maxPerActor)
        throw new DaisyException(ErrorCode.RATE_LIMITED);
      connections.put(connection,Boolean.TRUE);
    }
    emitter.onCompletion(connection::close);
    emitter.onTimeout(()-> { connection.close(); emitter.complete(); });
    emitter.onError(error->connection.close());
    try {
      emitter.send(SseEmitter.event().name("heartbeat").data(Map.of()));
      connection.lastHeartbeat=System.nanoTime();
      if(cursor>bounds.last() || cursor<bounds.first()-1) {
        emitter.send(SseEmitter.event().name("resync").data(Map.of("last_seq",bounds.last())));
        connection.close(); emitter.complete();
      } else {
        synchronized(connection) {
          if(!connection.closed) connection.task=scheduler.scheduleWithFixedDelay(connection::poll,0,1,TimeUnit.SECONDS);
        }
      }
      return emitter;
    } catch(IOException | RuntimeException error) {
      connection.close(); emitter.completeWithError(error); return emitter;
    }
  }
  private void authorize(String actor,String project) {
    if(actor==null || actor.isBlank() || project==null || project.isBlank()) throw new DaisyException(ErrorCode.UNAUTHENTICATED);
    ExecutionAccess guard=access.getIfAvailable();
    if(guard==null) throw new DaisyException(ErrorCode.FORBIDDEN);
    guard.requireRead(actor,project);
  }
  static long parseCursor(String input) {
    if(input==null || input.isBlank()) return 0;
    if(!input.matches("[0-9]{1,19}")) throw new DaisyException(ErrorCode.VALIDATION_FAILED);
    try { return Long.parseLong(input); }
    catch(NumberFormatException error) { throw new DaisyException(ErrorCode.VALIDATION_FAILED); }
  }
  @PreDestroy
  public void shutdown() {
    connections.keySet().forEach(c -> { c.close(); c.emitter.complete(); });
    scheduler.shutdownNow();
  }
  private final class Connection {
    private final String actor,projectId,channel;
    private final boolean project;
    private final SseEmitter emitter;
    private long cursor,lastHeartbeat;
    private boolean closed;
    private ScheduledFuture<?> task;
    Connection(String actor,String projectId,String channel,boolean project,SseEmitter emitter,long cursor) {
      this.actor=actor;this.projectId=projectId;this.channel=channel;this.project=project;this.emitter=emitter;this.cursor=cursor;
    }
    synchronized void close() {
      closed=true; if(task!=null) task.cancel(false); connections.remove(this);
    }
    synchronized void poll() {
      if(closed) return;
      try {
        authorize(actor,projectId);
        if(!project) journal.requireDeploymentProject(projectId,channel);
        EventJournal.Bounds bounds=project?journal.projectBounds(channel):journal.deploymentBounds(channel);
        if(cursor>bounds.last() || cursor<bounds.first()-1) {
          emitter.send(SseEmitter.event().name("resync").data(Map.of("last_seq",bounds.last())));
          close();emitter.complete();return;
        }
        for(EventJournal.PublicEvent event:project?journal.readProject(channel,cursor):journal.readDeployment(channel,cursor)) {
          if(closed) return;
          // Stale observations advance only the poll cursor; reconnecting may safely reread them.
          if(!"ignored_stale".equals(event.processingResult())) {
            JsonNode data=wireData(event);
            emitter.send(SseEmitter.event().id(Long.toString(event.seq())).name(event.eventType())
                .data(new Envelope(event.seq(),event.occurredAt(),event.deploymentId(),event.targetId(),data)));
          }
          cursor=event.seq();
        }
        if(System.nanoTime()-lastHeartbeat>=TimeUnit.SECONDS.toNanos(15)) {
          emitter.send(SseEmitter.event().name("heartbeat").data(Map.of())); lastHeartbeat=System.nanoTime();
        }
      } catch(Exception error) { close(); emitter.completeWithError(error); }
    }
  }
  static JsonNode wireData(EventJournal.PublicEvent event) {
    if(!"log.batch".equals(event.eventType())) return event.payload().deepCopy();
    var data=com.fasterxml.jackson.databind.node.JsonNodeFactory.instance.objectNode();
    data.putArray("lines").addObject().put("step",event.step()).put("target_id",event.targetId())
        .put("level",event.level()).put("text",event.message()==null?"":event.message())
        .put("ts",event.occurredAt().toString());
    return data;
  }
}
