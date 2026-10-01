package com.teamdaisy.server.deployment.application;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import java.util.Collections;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;

class DeploymentQueryServiceTest {
  @Test
  void missingPolicyDeniesEvenEmptyQueries() {
    var jdbc = mock(NamedParameterJdbcTemplate.class);
    @SuppressWarnings("unchecked")
    ObjectProvider<ExecutionAccess> provider = mock(ObjectProvider.class);
    var service = new DeploymentQueryService(jdbc, provider, new ObjectMapper());
    assertEquals(
        ErrorCode.FORBIDDEN,
        assertThrows(DaisyException.class, () -> service.current("actor", "project", List.of()))
            .errorCode());
    assertEquals(
        ErrorCode.FORBIDDEN,
        assertThrows(DaisyException.class, () -> service.deployedTo("actor", "project", List.of()))
            .errorCode());
    verifyNoInteractions(jdbc);
  }

  @Test
  void batchesValidateIdsDuplicatesAndSizeBeforeSql() {
    var jdbc = mock(NamedParameterJdbcTemplate.class);
    @SuppressWarnings("unchecked")
    ObjectProvider<ExecutionAccess> provider = mock(ObjectProvider.class);
    var policy = mock(ExecutionAccess.class);
    when(provider.getIfAvailable()).thenReturn(policy);
    var service = new DeploymentQueryService(jdbc, provider, new ObjectMapper());
    for (var ids : List.of(List.of(" "), List.of("src", "src"), Collections.nCopies(101, "src"))) {
      assertEquals(
          ErrorCode.VALIDATION_FAILED,
          assertThrows(DaisyException.class, () -> service.deployedTo("actor", "project", ids))
              .errorCode());
    }
    var pointer = new DeploymentQueryService.CurrentPointer("target", null);
    assertEquals(
        ErrorCode.VALIDATION_FAILED,
        assertThrows(
                DaisyException.class,
                () -> service.current("actor", "project", List.of(pointer, pointer)))
            .errorCode());
    assertTrue(service.current("actor", "project", List.of(pointer)).isEmpty());
    verify(policy, times(5)).requireRead("actor", "project");
    verifyNoInteractions(jdbc);
  }
}
