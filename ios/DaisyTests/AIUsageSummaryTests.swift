import Foundation
import Testing
@testable import Daisy

/// W-12 AI 사용량 — 배포 단위 (9/30 와이어프레임 수정, 서버: GET /deployments/{id}의 ai_usage).
struct AIUsageSummaryTests {
    typealias F = Fixture

    private func deployment(usage: String) throws -> Deployment {
        try F.deployment("succeeded", targets: [
            F.target("tgt_onprem", state: "succeeded", step: "health_check", stepState: "done", reused: true),
            F.target("tgt_aws", state: "succeeded", step: "health_check", stepState: "done", attempt: 2),
            F.target("tgt_gcp", state: "succeeded", step: "health_check", stepState: "done"),
        ], extra: #""ai_usage": \#(usage)"#)
    }

    /// 와이어프레임 예시: AWS 생성 실패 → 수정 2/3 통과, GCP 생성 통과, 온프레미스 재사용
    private let wireframeUsage = #"""
    { "tokens": 7920, "cost_krw": 206, "exchange_rate": 1380, "estimated": true, "calls": 3,
      "items": [
        { "at": "2026-10-03T12:12:30Z", "target_id": "tgt_aws", "step": "generate", "attempt": 1, "tokens": 3120, "cost_krw": 82, "status": "failed" },
        { "at": "2026-10-03T12:12:50Z", "target_id": "tgt_aws", "step": "fix", "attempt": 2, "tokens": 1860, "cost_krw": 48, "status": "succeeded", "note": "보안 그룹 0.0.0.0/0 수정" },
        { "at": "2026-10-03T12:11:10Z", "target_id": "tgt_gcp", "step": "generate", "attempt": 1, "tokens": 2940, "cost_krw": 76, "status": "succeeded" }
      ] }
    """#

    @Test func tilesMatchWireframe() throws {
        let summary = AIUsageSummary(try deployment(usage: wireframeUsage))
        #expect(summary.calls == 3)
        #expect(summary.tokens == 7920)
        #expect(summary.costKrw == 206)
        #expect(summary.reusedTargetIDs == ["tgt_onprem"])   // "재사용한 환경 1곳 · 온프레미스 · AI 호출 0회"
    }

    @Test func rowsIncludeReusedTargetWithoutCall() throws {
        let rows = AIUsageSummary(try deployment(usage: wireframeUsage)).rows
        #expect(rows.count == 4)
        #expect(rows.map(\.task) == ["보안 그룹 0.0.0.0/0 수정", "Terraform 생성 (deploy.yaml)",
                                     "Terraform 생성 (deploy.yaml)", "— 검증된 스크립트 재사용"])
        #expect(rows.map(\.attempt) == ["2/3", "1/3", "1/3", "—"])
        #expect(rows.map(\.result) == [.passed, .failed, .passed, .noCall])
        #expect(rows.last?.tokens == 0 && rows.last?.costKrw == 0)
        #expect(AIUsageSummary.Result.noCall.text == "AI 호출 없음")
    }

    /// 서버가 합계만 주고 `calls` · `items`를 안 주면 0회 · 재사용 줄만 보여줘요 (없는 걸 지어내지 않아요)
    @Test func summaryOnlyUsage() throws {
        let summary = AIUsageSummary(try deployment(usage: #"{ "tokens": 5000, "cost_krw": 120, "estimated": true }"#))
        #expect(summary.calls == 0)
        #expect(summary.tokens == 5000)
        #expect(summary.rows.map(\.result) == [.noCall])
    }

    @Test func noUsageYet() throws {
        let plain = try F.deployment("running", targets: [F.target("tgt_aws", state: "generating", step: "generate", stepState: "running")])
        let summary = AIUsageSummary(plain)
        #expect(summary.calls == 0 && summary.tokens == 0 && summary.costKrw == nil && summary.rows.isEmpty)
    }

    @Test func pickerTitleLooksLikeWeb() throws {
        let deployment = try F.deployment("succeeded", targets: [], extra: #""created_at": "2026-10-03T12:10:00Z""#)
        let title = AIUsageSummary.pickerTitle(deployment)
        #expect(title.hasPrefix("dep_42 · a1b2c3d · "))
        #expect(title.hasSuffix(" 배포"))
    }
}
