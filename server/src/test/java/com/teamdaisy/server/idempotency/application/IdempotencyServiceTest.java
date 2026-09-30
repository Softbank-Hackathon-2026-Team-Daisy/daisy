package com.teamdaisy.server.idempotency.application;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.json.CanonicalJson;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;

class IdempotencyServiceTest {
  @Test void originalResponseReplaysAndDifferentBodyConflictsWithoutRunningAction() {
    var mapper=new ObjectMapper();var json=new CanonicalJson(mapper);var jdbc=mock(NamedParameterJdbcTemplate.class);
    var service=new IdempotencyService(jdbc,json,mapper);var body=mapper.createObjectNode().put("version",1);
    String hash=json.hash(mapper.valueToTree(Map.of("hash_format_version",1,"actor","actor","project","project","operation","create","resource","project","body",body)));
    when(jdbc.queryForList(anyString(),anyMap())).thenReturn(List.of(Map.of("id","project")));
    when(jdbc.queryForList(anyString(),any(MapSqlParameterSource.class))).thenReturn(List.of(Map.of("request_hash",hash,"response_status",201,"response_body","{\"deployment_id\":\"dep_1\"}")));
    var response=service.execute("actor","project","create","project","key",body,()->{throw new AssertionError("must replay");});
    assertEquals(201,response.status());assertEquals("dep_1",response.body().path("deployment_id").asText());
    var error=assertThrows(DaisyException.class,()->service.execute("actor","project","create","project","key",mapper.createObjectNode().put("version",2),()->{throw new AssertionError("must conflict");}));
    assertEquals(ErrorCode.STATE_CONFLICT,error.errorCode());verify(jdbc,never()).update(anyString(),any(MapSqlParameterSource.class));
  }
}
