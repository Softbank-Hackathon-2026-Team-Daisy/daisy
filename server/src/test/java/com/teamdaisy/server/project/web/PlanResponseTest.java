package com.teamdaisy.server.project.web;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.project.application.AiCostConverter;
import com.teamdaisy.server.project.application.DeploymentPlanReader.PlanRow;
import com.teamdaisy.server.project.application.DeploymentPlanReader.UsageTotals;
import java.math.BigDecimal;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** A-05·WR-06 응답 변환을 고정해요 (server/SPEC.md 「배포 plan 조회 A-05」). */
class PlanResponseTest {
  private static final ObjectMapper MAPPER = new ObjectMapper();

  private static JsonNode json(String value) throws Exception {
    return MAPPER.readTree(value.replace('\'', '"'));
  }

  @Test
  @DisplayName("요약은 저장값 그대로, 원천이 없는 summary·plan_text 는 null 이에요")
  void targetCopiesSummary() throws Exception {
    var row =
        new PlanRow(
            "tgt_aws",
            json(
                "{'counts':{'create':12,'update':1,'delete':2},'has_delete':true,"
                    + "'risks':[{'level':'high','rule':'sg-open-world',"
                    + "'resource':'aws_security_group.web','message':'열려 있음'}]}"),
            json("[]"));

    var target = PlanResponse.target(row);

    assertThat(target.counts()).isEqualTo(new PlanResponse.Counts(12, 1, 2));
    assertThat(target.hasDelete()).isTrue();
    assertThat(target.risks())
        .containsExactly(
            new PlanResponse.Risk("high", "sg-open-world", "aws_security_group.web", "열려 있음"));
    assertThat(target.summary()).isNull();
    assertThat(target.planText()).isNull();
  }

  @Test
  @DisplayName("actions 는 교체면 replace, read·no-op 만이면 목록에서 빠져요")
  void resourceActions() throws Exception {
    assertThat(PlanDetailResponse.action(json("['delete','create']"))).isEqualTo("replace");
    assertThat(PlanDetailResponse.action(json("['create','delete']"))).isEqualTo("replace");
    assertThat(PlanDetailResponse.action(json("['delete']"))).isEqualTo("delete");
    assertThat(PlanDetailResponse.action(json("['create']"))).isEqualTo("create");
    assertThat(PlanDetailResponse.action(json("['update']"))).isEqualTo("update");
    assertThat(PlanDetailResponse.action(json("['no-op']"))).isNull();
    assertThat(PlanDetailResponse.action(json("['read']"))).isNull();

    var detail =
        PlanDetailResponse.of(
            new PlanRow(
                "tgt_aws",
                json("{}"),
                json(
                    "[{'address':'a.x','actions':['create']},"
                        + "{'address':'a.y','actions':['no-op']},"
                        + "{'address':'a.z','actions':['delete','create']}]")));
    assertThat(detail.resources())
        .containsExactly(
            new PlanDetailResponse.Resource("a.x", "create"),
            new PlanDetailResponse.Resource("a.z", "replace"));
    assertThat(detail.planText()).isNull();
  }

  @Test
  @DisplayName("사용량 행이 없으면 calls 0, 토큰·원화는 0 이 아니라 null 이에요")
  void emptyUsageIsNotZeroCost() {
    var usage =
        PlanResponse.aiUsage(new UsageTotals(0, 0, null, null), new AiCostConverter("1400"));

    assertThat(usage.calls()).isZero();
    assertThat(usage.tokens()).isNull();
    assertThat(usage.costKrw()).isNull();
    assertThat(usage.estimated()).isFalse();
    assertThat(usage.exchangeRate()).isEqualByComparingTo("1400");
  }

  @Test
  @DisplayName("환율이 있으면 추정 원화와 환율을, 없으면 둘 다 null 을 줘요")
  void costNeedsRate() {
    var totals = new UsageTotals(3, 1, 7920L, new BigDecimal("0.147"));

    var withRate = PlanResponse.aiUsage(totals, new AiCostConverter("1400"));
    assertThat(withRate.costKrw()).isEqualTo(206L);
    assertThat(withRate.estimated()).isTrue();
    assertThat(withRate.unknownCalls()).isEqualTo(1);

    var noRate = PlanResponse.aiUsage(totals, new AiCostConverter(""));
    assertThat(noRate.costKrw()).isNull();
    assertThat(noRate.exchangeRate()).isNull();
    assertThat(noRate.estimated()).isFalse();
    assertThat(noRate.tokens()).isEqualTo(7920L);
  }

  @Test
  @DisplayName("인프라 초안처럼 action 문자열로 와도 읽어요 (#35)")
  void singleActionString() throws Exception {
    var detail =
        PlanDetailResponse.of(
            new PlanRow(
                "tgt_aws",
                json("{}"),
                json(
                    "[{'address':'a.x','type':'aws_s3_bucket','action':'create'},"
                        + "{'address':'a.y','type':'t','action':'replace'},"
                        + "{'address':'a.z','type':'t','action':'no-op'},"
                        + "{'address':'a.w','type':'t','action':'delete'}]")));
    assertThat(detail.resources())
        .containsExactly(
            new PlanDetailResponse.Resource("a.x", "create"),
            new PlanDetailResponse.Resource("a.y", "replace"),
            new PlanDetailResponse.Resource("a.w", "delete"));
  }
}
