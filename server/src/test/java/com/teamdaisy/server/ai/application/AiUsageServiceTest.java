package com.teamdaisy.server.ai.application;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.json.CanonicalJson;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;

class AiUsageServiceTest {
  private final ObjectMapper mapper=new ObjectMapper().findAndRegisterModules();
  private final NamedParameterJdbcTemplate jdbc=mock(NamedParameterJdbcTemplate.class);
  private final JenkinsCommandService commands=mock(JenkinsCommandService.class);
  private final CanonicalJson json=new CanonicalJson(mapper);
  private final AiUsageService service=new AiUsageService(jdbc,mapper,json,commands);
  private AiUsageService.UsageInput input(BigDecimal cost,String basis) {
    return new AiUsageService.UsageInput("jenkins:instance:job:1","call_1","provider","model","generate",1,
        "unknown",null,null,null,cost,basis,Instant.parse("2026-10-01T00:00:00Z"));
  }
  private void scope(boolean reused) {
    when(commands.requireScope("exe_1","dep_1","dt_1")).thenReturn(new JenkinsCommandService.CommandScope(
        "exe_1","dep_1","prj_1","req_1","prepare",null,"instance","job","submitted","succeeded",null,1L,mapper.createObjectNode()));
    when(jdbc.queryForList(anyString(),anyMap())).thenAnswer(call->{
      String sql=call.getArgument(0);
      if(sql.contains("from ai_usage"))return List.of();
      if(sql.contains("from deployment_target"))return List.of(Map.of("project_id","prj_1","ai_reused",reused));
      return List.of(Map.of("id","prj_1"));
    });
  }
  @Test void lateFirstUsagePreservesUnknownAndReuseConflicts() {
    scope(false);
    assertFalse(service.receive("exe_1","dep_1","dt_1",input(null,null)).duplicate());
    var captor=ArgumentCaptor.forClass(MapSqlParameterSource.class);
    verify(jdbc).update(contains("insert into ai_usage"),captor.capture());
    for(String field:List.of("cost","basis","input","output","details"))assertNull(captor.getValue().getValue(field));
    scope(true);
    var error=assertThrows(DaisyException.class,()->service.receive("exe_1","dep_1","dt_1",input(null,null)));
    assertEquals(ErrorCode.STATE_CONFLICT,error.errorCode());
  }
  @Test void sourceCallDuplicateIsImmutable() {
    scope(false);
    var input=input(null,null);
    String hash=json.hash(mapper.valueToTree(Map.of("execution_id","exe_1","deployment_target_id","dt_1","usage",input)));
    when(jdbc.queryForList(contains("from ai_usage"),anyMap())).thenReturn(List.of(Map.of("id","aiu_1","payload_hash",hash)));
    assertEquals(new AiUsageService.Receipt("aiu_1",true),service.receive("exe_1","dep_1","dt_1",input));
    var error=assertThrows(DaisyException.class,()->service.receive("exe_1","dep_1","dt_1",input(new BigDecimal("1.5"),"reported")));
    assertEquals(ErrorCode.STATE_CONFLICT,error.errorCode());
    verify(jdbc,never()).update(anyString(),any(MapSqlParameterSource.class));
  }
  @Test void numericLimitsAndUnknownDetailKeysFailBeforeDatabase() {
    for(BigDecimal invalid:List.of(new BigDecimal("-1"),new BigDecimal("0.00000000001"),new BigDecimal("10000000000")))
      assertThrows(DaisyException.class,()->service.validate(input(invalid,"reported")));
    assertThrows(DaisyException.class,()->service.validate(input(null,"reported")));
    assertThrows(DaisyException.class,()->service.validate(input(BigDecimal.ONE,null)));
    var unsafe=new AiUsageService.UsageInput("source","call","provider","model","generate",1,"failed",null,null,
        mapper.createObjectNode().put("prompt","secret"),null,null,Instant.now());
    assertThrows(DaisyException.class,()->service.validate(unsafe));
    assertDoesNotThrow(()->service.validate(input(new BigDecimal("9999999999.9999999999"),"reported")));
    verifyNoInteractions(jdbc,commands);
  }
}
