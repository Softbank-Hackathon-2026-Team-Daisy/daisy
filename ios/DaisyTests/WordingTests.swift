import Foundation
import Testing
@testable import Daisy

/// 웹(Figma 와이어프레임 v1.0)과 같은 문구를 쓰는지 확인해요.
struct WordingTests {
    private func target(_ json: String) throws -> Deployment.Target {
        try JSONDecoder.daisy.decode(Deployment.Target.self, from: Data(json.utf8))
    }

    @Test func progressLineMatchesWeb() throws {
        let running = try target(#"{ "target_id": "tgt_gcp", "step": "validate", "step_state": "running", "attempt": 1 }"#)
        #expect(running.progressText == "AI 생성 · validate 실행 중 · 시도 1/3")

        let reused = try target(#"{ "target_id": "tgt_onprem", "step": "plan", "step_state": "done", "attempt": 1, "reused_script": true }"#)
        #expect(reused.progressText == "재사용 · 이미지 태그만 교체 · plan 통과 · 시도 1/3")

        let stopped = try target(#"{ "target_id": "tgt_aws", "step": "validate", "step_state": "failed", "attempt": 3 }"#)
        #expect(stopped.progressText == "3회 실패 · 중단")
    }

    @Test func resourceSummaryUsesMinusSign() throws {
        let counts = try JSONDecoder.daisy.decode(Plan.Target.Counts.self, from: Data(#"{ "create": 6, "update": 0, "delete": 0 }"#.utf8))
        #expect(counts.summaryText == "리소스 +6 ~0 \u{2212}0")
    }

    @Test func webStatusNamesDecode() throws {
        let decode = { (raw: String) in try JSONDecoder.daisy.decode(DeploymentState.self, from: Data("\"\(raw)\"".utf8)) }
        #expect(try decode("rolled_back") == .rolledBack)
        #expect(try decode("warning") == .warning)
    }
}
