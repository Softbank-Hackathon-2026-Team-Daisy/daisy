package com.teamdaisy.server.jenkins.application;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

import com.teamdaisy.server.jenkins.infrastructure.JenkinsClient;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;

class JenkinsConsoleWorkerTest {
  @Test
  void disabledTransportDoesNotClaimConsole() {
    var service = mock(JenkinsConsoleService.class);
    var client = mock(JenkinsClient.class);
    new JenkinsConsoleWorker(service, client).tick();
    verifyNoInteractions(service);
  }

  @Test
  void limitsHttpReadsAndRetainsCapturedOwnerCursor() {
    var service = mock(JenkinsConsoleService.class);
    var client = mock(JenkinsClient.class);
    when(client.enabled()).thenReturn(true);
    when(service.candidates()).thenReturn(List.of("a", "b", "c"));
    var owner = new JenkinsConsoleService.Owner("owner", "dep", "prj", "instance", "saved/job", 7, 103, false, Instant.EPOCH, "stream");
    when(service.owner(anyString())).thenReturn(owner);
    when(client.progressiveLog("saved/job", 7, 103)).thenReturn(new JenkinsClient.LogChunk(new byte[0], 103, false));
    new JenkinsConsoleWorker(service, client).tick();
    verify(client, times(2)).progressiveLog("saved/job", 7, 103);
    verify(service, times(2)).commit(eq(owner), any());
    verify(client, times(2)).progressiveLog(anyString(), anyLong(), anyLong());
  }
}
