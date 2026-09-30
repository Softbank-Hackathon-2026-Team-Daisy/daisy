package com.teamdaisy.server.history.application;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.deployment.application.ExecutionAccess;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

class EventSseServiceTest {
  private final EventJournal journal=mock(EventJournal.class);
  private final ExecutionAccess guard=mock(ExecutionAccess.class);
  @SuppressWarnings("unchecked")
  private final ObjectProvider<ExecutionAccess> provider=mock(ObjectProvider.class);

  private static class Capture extends SseEmitter {
    final List<String> wire=new ArrayList<>();
    final List<Object> bodies=new ArrayList<>();
    final CountDownLatch ended=new CountDownLatch(1);
    @Override public synchronized void send(SseEventBuilder builder) {
      StringBuilder text=new StringBuilder();
      builder.build().forEach(part->{ if(part.getData() instanceof String s) text.append(s); else bodies.add(part.getData()); });
      wire.add(text.toString());
    }
    @Override public void complete() { ended.countDown(); }
    @Override public void completeWithError(Throwable error) { ended.countDown(); }
  }
  private EventSseService service(Capture capture) {
    when(provider.getIfAvailable()).thenReturn(guard);
    return new EventSseService(journal,provider,1,1) {
      @Override protected SseEmitter createEmitter() { return capture; }
    };
  }

  @Test void deniedMembershipDoesNotCreateStream() {
    Capture capture=new Capture(); EventSseService service=service(capture);
    doThrow(new DaisyException(ErrorCode.NOT_FOUND)).when(journal).requireDeploymentProject("prj_1","dep_other");
    try {
      assertThrows(DaisyException.class,()->service.openDeployment("acct_1","prj_1","dep_other",null));
      assertTrue(capture.wire.isEmpty());
      verify(journal,never()).deploymentBounds(anyString());
    } finally { service.shutdown(); }
  }

  @Test void immediateHeartbeatAndFutureCursorResyncReleaseCapacity() {
    Capture capture=new Capture(); EventSseService service=service(capture);
    when(journal.projectBounds("prj_1")).thenReturn(new EventJournal.Bounds(1,3));
    try {
      service.openProject("acct_1","prj_1","4");
      assertTrue(capture.wire.get(0).contains("event:heartbeat"));
      assertFalse(capture.wire.get(0).contains("id:"));
      assertTrue(capture.wire.get(1).contains("event:resync"));
      assertEquals(0,capture.ended.getCount());
      // A completed resync must not occupy the one allowed connection slot.
      assertDoesNotThrow(()->service.openProject("acct_1","prj_1","4"));
    } finally { service.shutdown(); }
  }

  @Test void envelopeSkipsStaleAndRevocationStopsPolls() throws Exception {
    Capture capture=new Capture(); EventSseService service=service(capture);
    ObjectMapper mapper=new ObjectMapper(); Instant now=Instant.parse("2026-10-01T00:00:00Z");
    when(journal.projectBounds("prj_1")).thenReturn(new EventJournal.Bounds(1,2));
    when(journal.readProject("prj_1",0)).thenReturn(List.of(
        new EventJournal.PublicEvent(1,"dep_1","tgt_1","target.status_changed",mapper.createObjectNode(),null,null,null,"ignored_stale",now),
        new EventJournal.PublicEvent(2,"dep_1","tgt_1","target.status_changed",mapper.createObjectNode().put("status","running"),null,null,null,"applied",now)));
    doNothing().doNothing().doThrow(new DaisyException(ErrorCode.FORBIDDEN)).when(guard).requireRead("acct_1","prj_1");
    try {
      service.openProject("acct_1","prj_1",null);
      assertTrue(capture.ended.await(3,TimeUnit.SECONDS));
      synchronized(capture) {
        var envelopes=capture.bodies.stream().filter(EventSseService.Envelope.class::isInstance).map(EventSseService.Envelope.class::cast).toList();
        assertEquals(1,envelopes.size());
        assertEquals(new EventSseService.Envelope(2,now,"dep_1","tgt_1",mapper.createObjectNode().put("status","running")),envelopes.getFirst());
        assertFalse(capture.wire.stream().anyMatch(frame->frame.contains("id:1\n")));
      }
      reset(guard); // Revocation cleanup also frees the connection slot.
      assertDoesNotThrow(()->service.openProject("acct_1","prj_1","3"));
    } finally { service.shutdown(); }
  }

  @Test void logBatchUsesPublicLineShape() {
    ObjectMapper mapper=new ObjectMapper(); Instant now=Instant.parse("2026-10-01T00:00:00Z");
    var event=new EventJournal.PublicEvent(1,"dep_1","tgt_1","log.batch",mapper.createObjectNode(),"safe log chunk","apply","info","applied",now);
    var data=EventSseService.wireData(event);
    assertEquals(1,data.path("lines").size());
    var line=data.path("lines").get(0);
    assertEquals("safe log chunk",line.path("text").asText());
    assertEquals("tgt_1",line.path("target_id").asText());
    assertEquals("apply",line.path("step").asText());
    assertEquals("info",line.path("level").asText());
    assertEquals(now.toString(),line.path("ts").asText());
  }
}
