import Foundation
import Observation
import SwiftUI

/// 사이드바 메뉴 (웹 사이드바와 같은 구성).
/// PROJECT: 개요 · 배포 · 환경 · 이력 · 스크립트 / 아래: AI 사용량 · 설정
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case overview, deployments, environments, history, scripts, aiUsage, settings

    var id: Self { self }

    static let projectMenu: [AppTab] = [.overview, .deployments, .environments, .history, .scripts]
    static let bottomMenu: [AppTab] = [.aiUsage, .settings]

    var title: String {
        switch self {
        case .overview: "개요"
        case .deployments: "배포"
        case .environments: "환경"
        case .history: "이력"
        case .scripts: "스크립트"
        case .aiUsage: "AI 사용량"
        case .settings: "설정"
        }
    }

    /// 웹 아이콘과 비슷한 SF Symbols
    var systemImage: String {
        switch self {
        case .overview: "cloud"
        case .deployments: "play"
        case .environments: "server.rack"
        case .history: "clock"
        case .scripts: "apple.terminal"
        case .aiUsage: "chart.bar"
        case .settings: "gearshape"
        }
    }

    @MainActor @ViewBuilder
    var content: some View {
        switch self {
        case .overview: OverviewView()
        case .deployments: DeploymentsView()
        case .environments: EnvironmentsView()
        case .history: HistoryView()
        case .scripts: ScriptsView()
        case .aiUsage: AIUsageView()
        case .settings: SettingsView()
        }
    }
}

/// 화면 안에서 들어가는 곳.
enum Route: Hashable {
    /// 배포 한 건 (W-05 ~ W-08 중 지금 단계)
    case run(String)
    /// 방금 시작한 배포: L-02 전환 로딩부터
    case started(String)
    /// W-06 변경 사항 확인 후 승인
    case plan(String)
    /// W-03 이미지 빌드: 이 커밋의 Jenkins CI 진행 (9/30 회의: GitHub Actions 대신 Jenkins). 끝나면 W-04로 넘어가요
    case build(commit: String)
    /// 새 배포: W-03 이미지 빌드부터 (가장 최근 빌드, 웹 사이드바 "새 배포"와 같아요)
    case newDeployment
    /// W-04를 특정 커밋으로 (W-03에서 넘어올 때)
    case selectTargets(commit: String)
    /// 새 프로젝트 연결: W-02 애플리케이션 연결
    case connectProject
    /// 로그 (W-05b 오류 로그 보기, W-08 원인 보기)
    case logs(deploymentID: String, targetID: String?)

    @MainActor @ViewBuilder
    var destination: some View {
        switch self {
        case .run(let id): RunView(deploymentID: id)
        case .started(let id): RunView(deploymentID: id, loader: .generate)
        case .plan(let id): PlanApprovalView(deploymentID: id)
        case .build(let commit): BuildStage(commit: commit)
        case .newDeployment: BuildStage()
        case .selectTargets(let commit): TargetSelectView(commit: commit)
        case .connectProject: ConnectAppView()
        case .logs(let id, let target): LogsView(deploymentID: id, targetID: target)
        }
    }
}

/// 메뉴 선택과 메뉴별 이동 경로. 사이드바의 "새 배포" 같은 버튼이 어느 화면에서든 이동할 수 있게 해요.
@MainActor
@Observable
final class Router {
    var tab: AppTab = .overview
    private var paths: [AppTab: [Route]] = [:]

    func path(for tab: AppTab) -> Binding<[Route]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    /// 메뉴를 바꾸고 그 메뉴 안에서 곧장 한 화면으로 들어가요.
    func open(_ route: Route, in tab: AppTab = .deployments) {
        self.tab = tab
        paths[tab] = [route]
    }

    func push(_ route: Route) {
        paths[tab, default: []].append(route)
    }

    /// 지금 화면을 다른 화면으로 바꿔요 (예: 새 배포를 시작하면 그 배포 화면으로).
    func replaceTop(with route: Route) {
        var path = paths[tab] ?? []
        if !path.isEmpty { path.removeLast() }
        path.append(route)
        paths[tab] = path
    }

    func popToRoot() { paths[tab] = [] }
}

/// 사이드바 · 개요가 함께 쓰는 프로젝트 상태. 5초마다 새로 받아요 (SSE 전까지 폴링).
@MainActor
@Observable
final class Workspace {
    private(set) var projects: [Project] = []
    private(set) var statuses: [TargetStatus] = []
    private(set) var targets: [DeployTarget] = []
    /// 사이드바 "배포" 배지: 승인 대기 중인 배포 수
    private(set) var awaitingApproval: [Deployment] = []
    private(set) var connection: ConnectionState = .reconnecting
    private(set) var loadedOnce = false

    var project: Project? {
        projects.first { $0.id == currentProjectID }
    }

    private var currentProjectID: String?

    func run(using app: AppModel) async {
        await poll { await self.refresh(using: app) }
    }

    func refresh(using app: AppModel) async {
        guard let client = app.client else { connection = .disconnected; return }
        do {
            projects = try await client.send(.projects()).items
            if app.selectedProjectID == nil || !projects.contains(where: { $0.id == app.selectedProjectID }) {
                app.selectedProjectID = projects.first?.id
            }
            currentProjectID = app.selectedProjectID
            if let projectID = app.selectedProjectID {
                async let statuses = try? client.send(.targetStatuses(projectID: projectID)).items
                async let targets = try? client.send(.deployTargets(projectID: projectID)).items
                async let waiting = try? client.send(.deployments(projectID: projectID, state: .awaitingApproval)).items
                self.statuses = await statuses ?? self.statuses
                self.targets = await targets ?? self.targets
                self.awaitingApproval = await waiting ?? []
            } else {
                statuses = []; targets = []; awaitingApproval = []
            }
            connection = .connected
        } catch {
            app.handle(error)
            connection = loadedOnce ? .reconnecting : .disconnected
        }
        loadedOnce = true
    }

    struct EnvironmentSummary: Identifiable {
        let id: String
        let type: TargetType
        let name: String
        let health: Health
    }

    /// 사이드바 ENVIRONMENTS 목록. 환경 목록 API가 아직 없으면 현재 상태(A-02)로 대신해요.
    var environments: [EnvironmentSummary] {
        if !targets.isEmpty {
            return targets.map { target in
                let health = statuses.first { $0.targetId == target.id }?.health ?? .unknown
                return EnvironmentSummary(id: target.id, type: target.type, name: target.name, health: health)
            }
        }
        return statuses.map { EnvironmentSummary(id: $0.targetId, type: $0.type, name: $0.name, health: $0.health) }
    }
}

extension Workspace {
    /// 배포 대상 ID → 환경 종류 (온프레미스 · AWS · GCP)
    func type(of targetID: String) -> TargetType {
        environments.first { $0.id == targetID }?.type ?? .unknown
    }

    /// 화면에 쓸 환경 이름: 종류를 알면 "온프레미스", 모르면 ID
    func name(of targetID: String) -> String {
        let type = type(of: targetID)
        return type == .unknown ? targetID : type.displayName
    }
}
