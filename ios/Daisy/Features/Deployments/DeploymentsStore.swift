import Foundation
import Observation

/// 배포 목록(A-03)과 배포 한 건(A-04).
/// 목록은 프로젝트에 묶여요: 프로젝트가 바뀌면 `.loading`부터, 이전 프로젝트 응답은 버리고, 한 번 받은 뒤 실패하면
/// 목록은 그대로 두고 `staleSince`로 알려요 (10/3 신선도 검수 D3 · H3 · X1). 이력은 `next_cursor`로 더 받아요 (H5)
@MainActor
@Observable
final class DeploymentsStore {
    private let pages = ScopedLoader<DeploymentListing>()
    /// 마지막으로 부른 상태 거르기 (없으면 전체)
    private var filter: DeploymentState?
    private(set) var loadingMore = false
    private(set) var loadMoreError: String?

    /// 지금 맥락(마지막으로 부른 프로젝트)의 목록. 배포 탭은 `.task(id: 프로젝트)`가 바로 `refresh`를 불러서 바뀐 프로젝트로 넘어가요
    var list: LoadState<[Deployment]> {
        map(pages.state(for: pages.scope))
    }

    /// 이 프로젝트의 목록. 다른 프로젝트 것이면 `.loading`
    func list(for projectID: String?) -> LoadState<[Deployment]> {
        map(pages.state(for: projectID.map { Self.scope($0, filter) }))
    }

    /// 다음 페이지가 있으면 "더 보기"를 보여줘요
    func nextCursor(for projectID: String?) -> String? {
        pages.value(for: projectID.map { Self.scope($0, filter) })?.nextCursor
    }

    var staleSince: Date? { pages.staleSince }

    /// 끝나지 않은 배포(대기 · 진행 중 · 결정이 필요한 승인 대기)가 있으면 폴링을 짧게 해요
    func hasActive(for projectID: String?) -> Bool {
        guard let all = list(for: projectID).value else { return false }
        return all.contains { [.queued, .running].contains($0.state) } || DecisionRule.needingDecision(in: all) != nil
    }

    /// 첫 페이지를 다시 받아요. "더 보기"로 더 받은 지난 배포는 남겨 둬요
    func refresh(using app: AppModel, state: DeploymentState? = nil) async {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        filter = state
        let scope = Self.scope(projectID, state)
        if pages.scope != scope { (loadingMore, loadMoreError) = (false, nil) }
        await pages.load(scope, using: app) {
            try await client.send(.deployments(projectID: projectID, state: state))
        } merge: { previous, first in
            DeploymentListing.refreshed(previous, first: first)
        }
    }

    /// "더 보기": `next_cursor`로 다음 페이지를 받아 뒤에 붙여요 (H5)
    func loadMore(using app: AppModel) async {
        guard !loadingMore, let client = app.client, let projectID = app.selectedProjectID,
              let cursor = nextCursor(for: projectID) else { return }
        let state = filter
        let scope = Self.scope(projectID, state)
        loadingMore = true
        loadMoreError = nil
        defer { loadingMore = false }
        do {
            let page = try await client.send(.deployments(projectID: projectID, state: state, cursor: cursor))
            pages.update(scope: scope) { $0 = $0.appending(page) }
        } catch {
            if Freshness.isCancellation(error) { return }
            app.handle(error)
            if pages.scope == scope { loadMoreError = error.localizedDescription }
        }
    }

    private static func scope(_ projectID: String, _ state: DeploymentState?) -> String {
        state.map { "\(projectID)?state=\($0.rawValue)" } ?? projectID
    }

    private func map(_ state: LoadState<DeploymentListing>) -> LoadState<[Deployment]> {
        switch state {
        case .idle: .idle
        case .loading: .loading
        case .failed(let message): .failed(message)
        case .loaded(let listing): .loaded(listing.items)
        }
    }
}

/// 받은 배포 목록(최신순)과 다음 페이지 cursor.
struct DeploymentListing: Equatable {
    var items: [Deployment]
    var nextCursor: String?
    /// "더 보기"로 첫 페이지 뒤를 더 받았어요
    var loadedMore = false

    /// 첫 페이지를 새로 받았을 때. 더 받은 적이 없으면 첫 페이지 그대로, 있으면 첫 페이지 + 그 뒤에 이미 받은 지난 배포(중복 없이)
    static func refreshed(_ previous: DeploymentListing?, first: Page<Deployment>) -> DeploymentListing {
        guard let previous, previous.loadedMore else {
            return DeploymentListing(items: first.items, nextCursor: first.nextCursor)
        }
        let ids = Set(first.items.map(\.id))
        return DeploymentListing(items: first.items + previous.items.filter { !ids.contains($0.id) },
                                 nextCursor: previous.nextCursor, loadedMore: true)
    }

    /// 다음 페이지를 뒤에 붙여요 (이미 있는 배포는 빼요)
    func appending(_ page: Page<Deployment>) -> DeploymentListing {
        let ids = Set(items.map(\.id))
        return DeploymentListing(items: items + page.items.filter { !ids.contains($0.id) },
                                 nextCursor: page.nextCursor, loadedMore: true)
    }
}

@MainActor
@Observable
final class DeploymentDetailStore {
    let deploymentID: String
    private(set) var deployment: LoadState<Deployment> = .idle

    init(deploymentID: String) {
        self.deploymentID = deploymentID
    }

    func refresh(using app: AppModel) async {
        guard let client = app.client else { return }
        if deployment.value == nil { deployment = .loading }
        do {
            deployment = .loaded(try await client.send(.deployment(id: deploymentID)))
        } catch {
            app.handle(error)
            if deployment.value == nil { deployment = .failed(error.localizedDescription) }
        }
    }

    /// 끝난 배포는 더 폴링하지 않아요.
    var isFinished: Bool { deployment.value?.state.isFinished ?? false }
}
