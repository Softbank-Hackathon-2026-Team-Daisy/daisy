import Foundation
@testable import Daisy

/// 테스트 전용 샘플 JSON. 앱 코드에는 샘플 데이터를 두지 않아요 (목업 없음 규칙).
enum Fixture {
    static let names = ["tgt_onprem": "온프레미스", "tgt_aws": "AWS", "tgt_gcp": "GCP"]
    static func name(_ id: String) -> String { names[id] ?? id }

    /// 환경 한 줄: `state`가 nil이면 서버가 아직 환경별 상태를 안 보낸 경우예요.
    static func target(_ id: String, state: String? = nil, step: String, stepState: String,
                       attempt: Int = 1, reused: Bool = false) -> String {
        let stateField = state.map { #""state": "\#($0)", "# } ?? ""
        return #"{ "target_id": "\#(id)", \#(stateField)"step": "\#(step)", "step_state": "\#(stepState)", "attempt": \#(attempt), "reused_script": \#(reused) }"#
    }

    static func deployment(_ state: String, targets: [String], extra: String = "") throws -> Deployment {
        let json = #"""
        { "id": "dep_42", "project_id": "prj_1", "commit": "a1b2c3d4e5f6", "state": "\#(state)",
          "targets": [\#(targets.joined(separator: ","))]\#(extra.isEmpty ? "" : ", " + extra) }
        """#
        return try JSONDecoder.daisy.decode(Deployment.self, from: Data(json.utf8))
    }
}
