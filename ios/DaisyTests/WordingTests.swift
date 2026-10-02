import Foundation
import Testing
@testable import Daisy

/// 웹(Figma 와이어프레임 v1.0)과 같은 문구를 쓰는지 확인해요.
struct WordingTests {
    private func target(_ json: String) throws -> Deployment.Target {
        try JSONDecoder.daisy.decode(Deployment.Target.self, from: Data(json.utf8))
    }

    /// W-05 · W-05b 환경별 한 줄: 웹 `flow.ts` generateRow와 같은 문구 · 배지
    @Test func generateRowMatchesWeb() throws {
        let running = try target(#"{ "target_id": "tgt_gcp", "state": "validating", "step": "validate", "step_state": "running", "attempt": 1 }"#)
        #expect(running.generateRow.note == "AI 생성 · validate 실행 중 · 시도 1/3")
        #expect(running.generateRow.badge.text == "검증 중")

        let generating = try target(#"{ "target_id": "tgt_gcp", "state": "generating", "step": "generate", "step_state": "running", "attempt": 1 }"#)
        #expect(generating.generateRow.note == "AI 생성 · 시도 1/3")
        #expect(generating.generateRow.badge.text == "생성 중")

        let reused = try target(#"{ "target_id": "tgt_onprem", "state": "awaiting_approval", "step": "risk_check", "step_state": "done", "attempt": 1, "reused_script": true }"#)
        #expect(reused.generateRow.note == "재사용 · 이미지 태그만 교체 · 시도 1/3 통과")
        #expect(reused.generateRow.badge.text == "검증 통과")

        let fixing = try target(#"{ "target_id": "tgt_aws", "state": "validating", "step": "risk_check", "step_state": "failed", "attempt": 2, "error_summary": "0.0.0.0/0" }"#)
        #expect(fixing.generateRow.note == "AI 생성 · 위험 설정 발견 → AI 수정 중 · 시도 2/3")

        let stopped = try target(#"{ "target_id": "tgt_aws", "state": "failed", "step": "validate", "step_state": "failed", "attempt": 3 }"#)
        #expect(stopped.generateRow.note == "3회 실패 · 중단")
        #expect(stopped.generateRow.badge.text == "실패")

        let waiting = try target(#"{ "target_id": "tgt_aws", "state": "waiting", "step": "generate", "step_state": "waiting", "attempt": 1 }"#)
        #expect(waiting.generateRow.note == "대기 중")
    }

    /// 서버가 `steps`를 안 주면 웹처럼 단계를 추정해요 (W-05 4단계, W-07 4단계)
    @Test func fallbackStepsMatchWeb() throws {
        let validating = try target(#"{ "target_id": "tgt_aws", "state": "validating", "step": "plan", "step_state": "running", "attempt": 1 }"#)
        #expect(validating.generateSteps.map(\.name) == ["Terraform 생성 (AI)", "terraform validate", "terraform plan", "위험 설정 검사"])
        #expect(validating.generateSteps.map(\.state) == [.done, .done, .running, .waiting])

        let reused = try target(#"{ "target_id": "tgt_onprem", "state": "awaiting_approval", "step": "risk_check", "step_state": "done", "attempt": 1, "reused_script": true }"#)
        #expect(reused.generateSteps.first?.name == "스크립트 재사용")
        #expect(reused.generateSteps.allSatisfy { $0.state == .done })

        let verifying = try target(#"{ "target_id": "tgt_aws", "state": "verifying", "step": "health_check", "step_state": "running", "attempt": 1 }"#)
        #expect(verifying.applySteps.map(\.name) == ["이미지 pull", "terraform apply", "state 저장", "헬스체크"])
        #expect(verifying.applySteps.map(\.state) == [.done, .done, .done, .running])

        let applyFailed = try target(#"{ "target_id": "tgt_aws", "state": "failed", "step": "apply", "step_state": "failed", "attempt": 1 }"#)
        #expect(applyFailed.applySteps.map(\.state) == [.done, .failed, .waiting, .waiting])
    }

    /// 상태 라벨은 웹 `api/status.ts`와 같아요 (취소됨 · 확인 중 · 롤백됨)
    @Test func statusLabelsMatchWeb() throws {
        #expect(DeploymentState.cancelled.badge.text == "취소됨")
        #expect(TargetState.verifying.badge.text == "확인 중")
        #expect(TargetState.cancelled.badge.text == "취소됨")
        #expect(Health.unknown.badge.text == "확인 전")
        let rollback = try Fixture.deployment("succeeded", targets: [], extra: #""kind": "rollback""#)
        #expect(rollback.badge.text == "롤백됨")
        let normal = try Fixture.deployment("succeeded", targets: [])
        #expect(normal.badge.text == "성공")
    }

    /// 웹 utils/format.ts: 24시간제 "21:10", 상대 시각 "n분 전 · n시간 전 · 어제 · M/D"
    @Test func timeFormatsMatchWeb() {
        let seoul = TimeZone(identifier: "Asia/Seoul")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 21, minute: 10, second: 5))!
        #expect(TimeText.clock(evening, timeZone: seoul) == "21:10")
        #expect(TimeText.clockSeconds(evening, timeZone: seoul) == "21:10:05")
        #expect(TimeText.dayClock(evening, timeZone: seoul) == "10/3 21:10")
        #expect(TimeText.relative(evening.addingTimeInterval(-20), now: evening, calendar: calendar) == "방금")
        #expect(TimeText.relative(evening.addingTimeInterval(-12 * 60), now: evening, calendar: calendar) == "12분 전")
        #expect(TimeText.relative(evening.addingTimeInterval(-3 * 3600), now: evening, calendar: calendar) == "3시간 전")
        #expect(TimeText.relative(evening.addingTimeInterval(-24 * 3600), now: evening, calendar: calendar) == "어제")
        #expect(TimeText.relative(evening.addingTimeInterval(-4 * 24 * 3600), now: evening, calendar: calendar) == "9/29")
    }

    @Test func resourceSummaryUsesMinusSign() throws {
        let counts = try JSONDecoder.daisy.decode(Plan.Target.Counts.self, from: Data(#"{ "create": 6, "update": 0, "delete": 0 }"#.utf8))
        #expect(counts.summaryText == "리소스 생성 6 · 변경 0 · 삭제 0")
    }

    /// 9/30 서버 확정 두 층 상태. 빠진 값(building 등)은 unknown으로 받아요.
    @Test func serverStateNamesDecode() throws {
        let decode = { (raw: String) in try JSONDecoder.daisy.decode(DeploymentState.self, from: Data("\"\(raw)\"".utf8)) }
        #expect(try decode("partially_succeeded") == .partiallySucceeded)
        #expect(try decode("running") == .running)
        #expect(try decode("building") == .unknown)
        let target = { (raw: String) in try JSONDecoder.daisy.decode(TargetState.self, from: Data("\"\(raw)\"".utf8)) }
        #expect(try target("verifying") == .verifying)
        #expect(try target("awaiting_approval") == .awaitingApproval)
    }

    /// W-01 동일성 검증: 배포된 첫 환경의 image digest가 기준이에요 (웹 개요와 같아요)
    @Test func parityFromDigests() throws {
        let statuses = try JSONDecoder.daisy.decode([TargetStatus].self, from: Data(#"""
        [ { "target_id": "tgt_onprem", "type": "onprem", "name": "온프레미스", "health": "healthy", "image_digest": "sha256:aaa", "current": { "commit": "abc1234" } },
          { "target_id": "tgt_aws", "type": "aws", "name": "AWS", "health": "healthy", "image_digest": "sha256:aaa", "current": { "commit": "abc1234" } },
          { "target_id": "tgt_gcp", "type": "gcp", "name": "GCP", "health": "unhealthy", "image_digest": "sha256:bbb", "current": { "commit": "abc1234" } } ]
        """#.utf8))
        let parity = Parity(statuses: statuses)
        // 기준(온프레미스)과 digest가 같은 환경 수 → 2/3 (개요 카드와 같은 숫자)
        #expect(parity.total == 3)
        #expect(parity.matching == 2)
        #expect(parity.rows.first { $0.key == "digest" }?.cells.map(\.failed) == [false, false, true])
        // 헬스 요약이 없으면 "정상" · "실패" (웹 개요와 같아요)
        #expect(parity.rows.first { $0.key == "health" }?.cells.map(\.value) == ["정상", "정상", "실패"])
        #expect(statuses.parityMatching == 2)
    }

    /// W-08 동일성 검증: 이 배포의 환경별 결과로, 성공한 환경끼리 비교하고 "앱 버전" 줄이 있어요 (웹 결과 화면)
    @Test func resultParityUsesDeploymentTargets() throws {
        let deployment = try Fixture.deployment("partially_succeeded", targets: [
            #"{ "target_id": "tgt_onprem", "state": "succeeded", "step": "health_check", "step_state": "done", "attempt": 1, "image_digest": "sha256:aaa" }"#,
            #"{ "target_id": "tgt_aws", "state": "succeeded", "step": "health_check", "step_state": "done", "attempt": 1, "image_digest": "sha256:aaa" }"#,
            #"{ "target_id": "tgt_gcp", "state": "failed", "step": "health_check", "step_state": "failed", "attempt": 1, "health_summary": "503" }"#,
        ], extra: #""version": "v7""#)
        let parity = Parity(deployment: deployment)
        #expect(parity.matching == 2 && parity.total == 3)
        #expect(parity.rows.map(\.key) == ["digest", "commit", "version", "health"])
        #expect(parity.rows[2].cells.map(\.value) == ["v7", "v7", "v7"])
        // 성공은 헬스 요약 그대로(없으면 "—"), 실패는 요약 · "실패" (웹 결과 화면과 같아요)
        #expect(parity.rows[3].cells.map(\.value) == ["—", "—", "503"])
        #expect(parity.rows[3].cells.map(\.failed) == [false, false, true])
    }

    /// 로그 · deploy.yaml 오류는 웹 목업 모양(`at` · `message`, 문자열 배열)도 받아요
    @Test func tolerantShapes() throws {
        let log = try JSONDecoder.daisy.decode(LogLine.self, from: Data(#"{ "seq": 3, "at": "2026-10-03T12:00:00Z", "target_id": "tgt_aws", "level": "info", "message": "terraform init" }"#.utf8))
        #expect(log.text == "terraform init" && log.ts != nil)
        let manifest = try JSONDecoder.daisy.decode(Manifest.self, from: Data(#"{ "errors": ["port가 없어요", { "path": "healthcheck", "message": "/로 시작해야 해요" }] }"#.utf8))
        #expect(manifest.errors?.map(\.message) == ["port가 없어요", "/로 시작해야 해요"])
    }

    /// W-02 저장소 URL 형식 (웹과 같은 규칙)
    @Test func githubURLValidation() {
        let ok = ["https://github.com/team-daisy/sample-monolith", "https://github.com/a.b/c_d/"]
        let bad = ["github.com/team/app", "https://gitlab.com/team/app", "https://github.com/team", "owner/repo"]
        #expect(ok.allSatisfy { $0.wholeMatch(of: ConnectAppView.githubURL) != nil })
        #expect(bad.allSatisfy { $0.wholeMatch(of: ConnectAppView.githubURL) == nil })
    }
}
