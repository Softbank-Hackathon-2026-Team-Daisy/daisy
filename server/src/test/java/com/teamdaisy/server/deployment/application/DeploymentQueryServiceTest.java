package com.teamdaisy.server.deployment.application;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.jdbc.core.RowCallbackHandler;
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
    assertEquals(
        ErrorCode.FORBIDDEN,
        assertThrows(
                DaisyException.class, () -> service.currentByTarget("actor", "project", List.of()))
            .errorCode());
    assertEquals(
        ErrorCode.FORBIDDEN,
        assertThrows(DaisyException.class, () -> service.projectIdOf("actor", "dep")).errorCode());
    verifyNoInteractions(jdbc);
  }

  @Test
  void accessFailuresAreNeverConvertedToUnverifiedOrAProjectId() {
    var jdbc = mock(NamedParameterJdbcTemplate.class);
    @SuppressWarnings("unchecked")
    ObjectProvider<ExecutionAccess> provider = mock(ObjectProvider.class);
    var policy = mock(ExecutionAccess.class);
    when(provider.getIfAvailable()).thenReturn(policy);
    var service = new DeploymentQueryService(jdbc, provider, new ObjectMapper());
    when(jdbc.queryForList(anyString(), eq(Map.of("id", "dep")), eq(String.class)))
        .thenReturn(List.of("project"));
    for (var code : List.of(ErrorCode.NOT_FOUND, ErrorCode.FORBIDDEN, ErrorCode.UNAUTHENTICATED)) {
      doThrow(new DaisyException(code)).when(policy).requireRead("actor", "project");
      assertEquals(
          code,
          assertThrows(
                  DaisyException.class,
                  () ->
                      service.currentByTarget(
                          "actor",
                          "project",
                          List.of(new DeploymentQueryService.CurrentPointer("target", "dt"))))
              .errorCode());
      assertEquals(
          code,
          assertThrows(
                  DaisyException.class,
                  () -> service.currentByTarget("actor", "project", List.of()))
              .errorCode());
      assertEquals(
          code,
          assertThrows(DaisyException.class, () -> service.projectIdOf("actor", "dep"))
              .errorCode());
    }
    verify(jdbc, times(3)).queryForList(anyString(), eq(Map.of("id", "dep")), eq(String.class));
    verifyNoMoreInteractions(jdbc);
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
    assertEquals(
        ErrorCode.VALIDATION_FAILED,
        assertThrows(
                DaisyException.class,
                () -> service.currentByTarget("actor", "project", List.of(pointer, pointer)))
            .errorCode());
    assertEquals(
        "none",
        service.currentByTarget("actor", "project", List.of(pointer)).get("target").status());
    verify(policy, times(7)).requireRead("actor", "project");
    verifyNoInteractions(jdbc);
  }

  @Test
  void databaseFailureIsNotReportedAsAnUnverifiedPointer() {
    var jdbc = mock(NamedParameterJdbcTemplate.class);
    @SuppressWarnings("unchecked")
    ObjectProvider<ExecutionAccess> provider = mock(ObjectProvider.class);
    when(provider.getIfAvailable()).thenReturn(mock(ExecutionAccess.class));
    var failure = new DataAccessResourceFailureException("TEST-ONLY database unavailable");
    doThrow(failure).when(jdbc).query(anyString(), anyMap(), any(RowCallbackHandler.class));
    var service = new DeploymentQueryService(jdbc, provider, new ObjectMapper());
    assertSame(
        failure,
        assertThrows(
            DataAccessResourceFailureException.class,
            () ->
                service.currentByTarget(
                    "actor",
                    "project",
                    List.of(new DeploymentQueryService.CurrentPointer("target", "dt")))));
  }
}
