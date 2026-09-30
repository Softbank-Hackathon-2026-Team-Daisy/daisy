import Foundation
import Observation

/// 현황: 프로젝트 목록(A-01)과 환경별 현재 상태(A-02).
@MainActor
@Observable
final class OverviewStore {
    private(set) var projects: LoadState<[Project]> = .idle
    private(set) var statuses: LoadState<[TargetStatus]> = .idle

    func loadProjects(using app: AppModel) async {
        guard let client = app.client else { return }
        if projects.value == nil { projects = .loading }
        do {
            let page = try await client.send(.projects())
            projects = .loaded(page.items)
            if app.selectedProjectID == nil || !page.items.contains(where: { $0.id == app.selectedProjectID }) {
                app.selectedProjectID = page.items.first?.id
            }
        } catch {
            app.handle(error)
            projects = .failed(error.localizedDescription)
        }
    }

    /// 폴링 중에는 이전 값을 유지해서 화면이 깜빡이지 않게 해요.
    func refreshStatuses(using app: AppModel) async {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        if statuses.value == nil { statuses = .loading }
        do {
            statuses = .loaded(try await client.send(.targetStatuses(projectID: projectID)).items)
        } catch {
            app.handle(error)
            if statuses.value == nil { statuses = .failed(error.localizedDescription) }
        }
    }

    func reset() {
        statuses = .idle
    }
}

extension [TargetStatus] {
    /// 배포된 환경이 모두 같은 커밋인지. 이식성("같은 이미지를 모든 환경에")을 보여주는 값이에요.
    var deployedCommits: Set<String> { Set(compactMap { $0.current?.commit }) }
    var isConsistent: Bool { deployedCommits.count <= 1 }
}
