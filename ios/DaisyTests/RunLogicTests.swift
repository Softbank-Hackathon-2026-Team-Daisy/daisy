import Foundation
import Testing
@testable import Daisy

/// 배포 한 건 화면 규칙 (`RunStage`, `RetryRequest`, `FlowCopy`).
/// 근거: 9/30 서버 확정 상태 두 층(은현 님 Slack), Q7 "한 환경 실패해도 나머지 계속", 9/30 도영 님 와이어프레임 수정.
struct RunLogicTests {
    typealias F = Fixture

    // MARK: 화면 고르기

    @Test("상태 두 층 → 웹 흐름 화면", arguments: [
        ("awaiting_approval", [F.target("tgt_aws", state: "awaiting_approval", step: "risk_check", stepState: "done")], RunStage.approval),
        ("running", [F.target("tgt_aws", state: "validating", step: "validate", stepState: "running")], .generate),
        ("queued", [F.target("tgt_aws", state: "waiting", step: "generate", stepState: "waiting")], .generate),
        ("running", [F.target("tgt_aws", state: "applying", step: "apply", stepState: "running"),
                     F.target("tgt_gcp", state: "validating", step: "plan", stepState: "running")], .apply),
        ("succeeded", [F.target("tgt_aws", state: "succeeded", step: "health_check", stepState: "done")], .result),
        ("partially_succeeded", [F.target("tgt_aws", state: "succeeded", step: "health_check", stepState: "done"),
                                 F.target("tgt_gcp", state: "failed", step: "health_check", stepState: "failed")], .result),
        ("cancelled", [F.target("tgt_aws", state: "cancelled", step: "plan", stepState: "done")], .result),
        ("rolling_back", [F.target("tgt_aws", step: "apply", stepState: "running")], .result),   // 모르는 값 → 결과 화면
    ])
    func stageForState(state: String, targets: [String], expected: RunStage) throws {
        #expect(RunStage(try F.deployment(state, targets: targets)) == expected)
    }

    /// W-05b: 한 환경만 3회 실패하고 나머지는 검증 중 → 배포는 running이지만 W-05b를 보여줘요
    @Test func oneTargetFailedWhileOthersContinue() throws {
        let deployment = try F.deployment("running", targets: [
            F.target("tgt_onprem", state: "awaiting_approval", step: "risk_check", stepState: "done"),
            F.target("tgt_aws", state: "failed", step: "plan", stepState: "failed", attempt: 3),
            F.target("tgt_gcp", state: "validating", step: "validate", stepState: "running"),
        ])
        #expect(RunStage(deployment) == .stopped)
    }

    /// 모든 환경이 apply 전에 실패 → failed + W-05b
    @Test func allTargetsFailedBeforeApply() throws {
        let deployment = try F.deployment("failed", targets: [
            F.target("tgt_aws", state: "failed", step: "validate", stepState: "failed", attempt: 3),
            F.target("tgt_gcp", state: "failed", step: "generate", stepState: "failed", attempt: 3),
        ])
        #expect(RunStage(deployment) == .stopped)
    }

    /// apply까지 간 뒤 실패 → W-08 결과 (원인 보기 · 다시 시도)
    @Test func failedAfterApplyShowsResult() throws {
        let deployment = try F.deployment("failed", targets: [
            F.target("tgt_aws", state: "failed", step: "apply", stepState: "failed"),
        ])
        #expect(RunStage(deployment) == .result)
    }

    /// 서버가 환경별 `state`를 아직 안 보내도 step · step_state로 판단해요
    @Test func worksWithoutTargetState() throws {
        let deployment = try F.deployment("running", targets: [
            F.target("tgt_aws", step: "apply", stepState: "running"),
        ])
        #expect(RunStage(deployment) == .apply)
    }

    // MARK: 다시 시도

    /// "AWS만 다시 시도" = 같은 커밋 · 그 환경만으로 새 배포 (WR-05)
    @Test func retryOnlyFailedTarget() throws {
        let deployment = try F.deployment("running", targets: [
            F.target("tgt_onprem", state: "validating", step: "plan", stepState: "running"),
            F.target("tgt_aws", state: "failed", step: "plan", stepState: "failed", attempt: 3),
        ])
        let retry = RetryRequest.only("tgt_aws", of: deployment)
        #expect(retry == RetryRequest(projectID: "prj_1", commit: "a1b2c3d4e5f6", targetIDs: ["tgt_aws"]))
    }

    // MARK: 문구 (웹 와이어프레임과 글자 단위로 같아야 해요)

    @Test func stoppedCopyMatchesWireframe() throws {
        let deployment = try F.deployment("running", targets: [
            F.target("tgt_onprem", state: "awaiting_approval", step: "risk_check", stepState: "done"),
            F.target("tgt_aws", state: "failed", step: "plan", stepState: "failed", attempt: 3),
            F.target("tgt_gcp", state: "validating", step: "validate", stepState: "running"),
        ])
        let copy = FlowCopy.stopped(deployment, name: F.name)
        #expect(copy.title == "AWS만 멈췄어요")
        #expect(copy.description == "AWS는 3번 모두 실패해서 멈췄어요. 온프레미스 · GCP는 그대로 계속 진행해요.")
        #expect(copy.toastTitle == "AWS 검증 실패 · 나머지 환경은 계속")
    }

    @Test func stoppedCopyWhenEveryTargetFailed() throws {
        let deployment = try F.deployment("failed", targets: [
            F.target("tgt_aws", state: "failed", step: "validate", stepState: "failed", attempt: 3),
        ])
        let copy = FlowCopy.stopped(deployment, name: F.name)
        #expect(copy.title == "배포를 중단했어요")
        #expect(copy.toastTitle == "AWS 검증 실패 · 배포 중단")
    }

    @Test func partialResultCopyMatchesWireframe() throws {
        let deployment = try F.deployment("partially_succeeded", targets: [
            F.target("tgt_onprem", state: "succeeded", step: "health_check", stepState: "done"),
            F.target("tgt_aws", state: "succeeded", step: "health_check", stepState: "done"),
            F.target("tgt_gcp", state: "failed", step: "health_check", stepState: "failed"),
        ])
        #expect(FlowCopy.result(deployment, name: F.name)
                == "온프레미스 · AWS는 성공, GCP는 헬스체크에서 실패했어요. 성공한 환경끼리 같은 이미지인지 확인해요.")
        #expect(deployment.state.badge.text == "일부 성공")
        // 동일성 검증은 성공한 환경끼리만
        #expect(FlowCopy.parityTargets(deployment) == ["tgt_onprem", "tgt_aws"])
    }

    @Test func fullSuccessComparesEveryTarget() throws {
        let deployment = try F.deployment("succeeded", targets: [
            F.target("tgt_aws", state: "succeeded", step: "health_check", stepState: "done"),
        ])
        #expect(FlowCopy.result(deployment, name: F.name) == "모든 환경이 같은 이미지로 떠 있는지 확인해요.")
        #expect(FlowCopy.parityTargets(deployment) == nil)
    }

    /// 롤백은 새 배포 한 건이에요. 상태는 일반 배포와 같아요 (WR-14)
    @Test func rollbackIsAnOrdinaryDeployment() throws {
        let deployment = try F.deployment("awaiting_approval",
                                          targets: [F.target("tgt_aws", state: "awaiting_approval", step: "risk_check", stepState: "done")],
                                          extra: #""kind": "rollback", "rolled_back_from": "dep_41""#)
        #expect(deployment.isRollback)
        #expect(deployment.rolledBackFrom == "dep_41")
        #expect(RunStage(deployment) == .approval)
    }
}
