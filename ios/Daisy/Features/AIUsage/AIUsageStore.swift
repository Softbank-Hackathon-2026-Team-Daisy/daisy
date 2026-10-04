import Foundation
import Observation

/// W-12 AI 사용량 데이터 (10/3 신선도 검수 AI1 – AI4).
/// - 배포 목록(A-03)이 기준이에요. 목록을 못 받으면 "0회"로 가리지 않고 오류를 보여줘요 (AI2)
/// - 전체 사용량은 한 번 부를 때 한 번만 더해요 (AI4). 끝난 배포의 plan 합계(A-05)는 바뀌지 않아서 프로젝트마다 한 번만 받아요
/// - 배포 상세는 "프로젝트/배포" 맥락에 묶여서, 배포를 빨리 바꿔도 이전 배포의 늦은 응답이 덮어쓰지 않아요 (AI3)
@MainActor
@Observable
final class AIUsageStore {
    /// 배포 한 건 + plan 합계 + 호출 기록. plan · 기록이 아직 없으면(생성 전, 서버 준비 전) 배포에 온 값으로 보여줘요
    struct Detail: Equatable {
        let deployment: Deployment
        let totals: AIUsage?
        let calls: [AIUsage.Call]?
        var id: String { deployment.id }
        var summary: AIUsageSummary { AIUsageSummary(deployment, totals: totals, callLog: calls) }
    }

    let list = ScopedLoader<[Deployment]>()
    let overall = ScopedLoader<AIUsageTotals>()
    let detail = ScopedLoader<Detail>()

    /// 끝난 배포의 plan 합계 (배포 ID → 합계). 프로젝트가 바뀌면 비워요
    @ObservationIgnored private var finishedUsage: [String: AIUsage] = [:]
    @ObservationIgnored private var usageProjectID: String?

    static func detailScope(projectID: String, deploymentID: String) -> String { "\(projectID)/\(deploymentID)" }

    /// 지금 보는 화면(전체 · 배포 한 건)의 갱신 실패 표시
    func staleSince(projectID: String?, selectedID: String?) -> Date? {
        let shown = selectedID == nil ? overall.staleSince : detail.staleSince
        return [list.staleSince, shown].compactMap { $0 }.min()
    }

    /// 목록을 받고, 고른 것(전체 또는 배포 한 건)을 받아요. 고른 배포가 목록에서 사라졌으면 false (화면이 "전체"로 돌아가요)
    func refresh(using app: AppModel, projectID: String, selectedID: String?) async -> Bool {
        guard let client = app.client else { return true }
        await list.load(projectID, using: app) {
            try await Self.allDeployments(client: client, projectID: projectID)
        }
        // 목록을 처음부터 못 받았으면 화면이 그 오류를 보여줘요 (합계를 0으로 만들지 않아요)
        guard let deployments = list.value(for: projectID), app.selectedProjectID == projectID else { return true }
        if let selectedID {
            guard deployments.contains(where: { $0.id == selectedID }) else { return false }
            await loadDetail(using: app, client: client, projectID: projectID, deploymentID: selectedID)
        } else {
            await loadTotals(using: app, client: client, projectID: projectID, deployments: deployments)
        }
        return true
    }

    /// 전체 합계는 프로젝트의 모든 배포를 더해요. A-03은 한 번에 최근 20건이라 `next_cursor`가 없을 때까지 이어 받아요 (10/4)
    static func allDeployments(client: APIClient, projectID: String, maxPages: Int = 50) async throws -> [Deployment] {
        var all: [Deployment] = []
        var seen = Set<String>()
        var cursor: String?
        var pages = 0
        repeat {
            let page = try await client.send(.deployments(projectID: projectID, state: nil, cursor: cursor))
            for deployment in page.items where seen.insert(deployment.id).inserted { all.append(deployment) }
            cursor = page.nextCursor
            pages += 1
        } while cursor != nil && pages < maxPages
        return all
    }

    private func loadDetail(using app: AppModel, client: APIClient, projectID: String, deploymentID: String) async {
        await detail.load(Self.detailScope(projectID: projectID, deploymentID: deploymentID), using: app) {
            let deployment = try await client.send(.deployment(id: deploymentID))
            async let plan = Freshness.attempt { try await client.send(.plan(deploymentID: deploymentID)) }
            async let calls = Freshness.attempt { try await client.send(.aiUsage(projectID: projectID, deploymentID: deploymentID)).items }
            let (planResult, callsResult) = await (plan, calls)
            return Detail(deployment: deployment,
                          totals: Freshness.optional(planResult, using: app)?.aiUsage,
                          calls: Freshness.optional(callsResult, using: app))
        }
    }

    /// 배포마다 plan 합계(A-05)를 같이 불러서 더해요. 못 불러온 배포는 배포에 온 값으로 셈해요
    private func loadTotals(using app: AppModel, client: APIClient, projectID: String, deployments: [Deployment]) async {
        if usageProjectID != projectID { (finishedUsage, usageProjectID) = ([:], projectID) }
        let cached = finishedUsage
        let missing = deployments.map(\.id).filter { cached[$0] == nil }
        await overall.load(projectID, using: app) {
            let fetched = await withTaskGroup(of: (String, Result<AIUsage?, any Error>).self) { group in
                for id in missing {
                    group.addTask { (id, await Freshness.attempt { try await client.send(.plan(deploymentID: id)).aiUsage }) }
                }
                var results: [(String, Result<AIUsage?, any Error>)] = []
                for await result in group { results.append(result) }
                return results
            }
            var usages = cached.filter { id, _ in deployments.contains { $0.id == id } }
            for (id, result) in fetched {
                guard let usage = Freshness.optional(result, using: app).flatMap({ $0 }) else { continue }
                usages[id] = usage
                if usageProjectID == projectID, deployments.first(where: { $0.id == id })?.state.isFinished == true {
                    finishedUsage[id] = usage
                }
            }
            return AIUsageTotals(deployments, usages: usages)
        }
    }
}
