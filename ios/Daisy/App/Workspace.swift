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
        case .overview: .app("개요")
        case .deployments: .app("배포")
        case .environments: .app("환경")
        case .history: .app("이력")
        case .scripts: .app("스크립트")
        case .aiUsage: .app("AI 사용량")
        case .settings: .app("설정")
        }
    }

    /// 웹 아이콘과 비슷한 SF Symbols
    var systemImage: String {
        switch self {
        case .overview: "cloud"
        case .deployments: "play"
        case .environments: "square.stack.3d.up"
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
    var tab: AppTab = .overview { didSet { recordNavigation() } } // NAV-HISTORY
    private var paths: [AppTab: [Route]] = [:]
    /// 뒤로 · 앞으로 이동 기록 (NavigationHistory.swift) // NAV-HISTORY
    let history = NavigationHistory() // NAV-HISTORY

    func path(for tab: AppTab) -> Binding<[Route]> {
        Binding(get: { self.paths[tab] ?? [] }, set: {
            let old = self.paths[tab] ?? [] // NAV-HISTORY
            self.paths[tab] = $0
            self.recordPathChange(in: tab, from: old, to: $0) // NAV-HISTORY
        })
    }

    /// 메뉴를 바꾸고 그 메뉴 안에서 곧장 한 화면으로 들어가요.
    func open(_ route: Route, in tab: AppTab = .deployments) {
        recordingOnce { // NAV-HISTORY
            self.tab = tab
            paths[tab] = [route]
        } // NAV-HISTORY
    }

    func push(_ route: Route) {
        paths[tab, default: []].append(route)
        recordNavigation() // NAV-HISTORY
    }

    /// 지금 화면을 다른 화면으로 바꿔요 (예: 새 배포를 시작하면 그 배포 화면으로).
    func replaceTop(with route: Route) {
        var path = paths[tab] ?? []
        if !path.isEmpty { path.removeLast() }
        path.append(route)
        paths[tab] = path
        recordNavigation() // NAV-HISTORY
    }

    func popToRoot() { paths[tab] = []; recordNavigation() } // NAV-HISTORY
}

/// 사이드바 · 개요가 함께 쓰는 프로젝트 상태. 프로젝트 SSE(E-02) 이벤트가 오면 바로, 아니면 폴링으로 새로 받아요
/// (SSE가 붙어 있으면 15초 안전망, 끊기면 5초)
@MainActor
@Observable
final class Workspace {
    private(set) var projects: [Project] = []
    private(set) var statuses: [TargetStatus] = []
    private(set) var targets: [DeployTarget] = []
    /// 사이드바 "배포" 배지: 승인 대기 중인 배포 수
    private(set) var awaitingApproval: [Deployment] = []
    private(set) var loadedOnce = false
    /// 프로젝트 채널 (`projects/{id}/events`). 개요 · 배포 목록 · 빌드 화면도 이 신호로 바로 다시 불러요
    let live = LiveChannel()
    /// REST 폴링 결과. 성공하면 `polling`, 실패하면 `reconnecting` · `disconnected`
    private var restConnection: ConnectionState = .reconnecting

    /// 지금 열려 있는 배포 채널 (RunView). 서버가 계정당 SSE를 4개까지만 받아서(Mac · iPhone · 웹을 같이 쓰면 금방 차요)
    /// 앱은 한 번에 하나만 열어요: 배포 채널이 열려 있는 동안 프로젝트 채널은 닫고, 배포 채널이 닫히면 이어 받아요
    private var borrowed: [ObjectIdentifier: LiveChannel] = [:]

    /// 프로젝트 채널을 잠시 닫아 둔 상태 (배포 채널이 대신 열려 있어요)
    var projectChannelPaused: Bool { !borrowed.isEmpty }

    /// 프로젝트 · 배포 채널 중 하나라도 붙어 있어요
    var isLive: Bool { live.isLive || borrowed.values.contains { $0.isLive } }

    /// 연결 표시: 스트림이 붙어 있으면 "실시간 연결됨", 끊기면 폴링으로 돌아가요
    var connection: ConnectionState {
        restConnection == .polling && isLive ? .connected : restConnection
    }

    /// 배포 채널을 열기 전에 불러요. 프로젝트 채널이 닫혀요 (RootView `.task(id:)`)
    func hold(_ channel: LiveChannel) {
        borrowed[ObjectIdentifier(channel)] = channel
    }

    /// 배포 채널을 닫은 뒤 불러요. 다른 배포 채널이 없으면 프로젝트 채널을 마지막 seq부터 다시 열어요
    func release(_ channel: LiveChannel) {
        borrowed[ObjectIdentifier(channel)] = nil
    }

    var project: Project? {
        projects.first { $0.id == currentProjectID }
    }

    private var currentProjectID: String?

    func run(using app: AppModel) async {
        await poll(on: live.changes, every: { PollInterval.seconds(live: self.live.isLive) }) {
            await self.refresh(using: app)
        }
    }

    /// 고른 프로젝트의 채널에 붙어 있어요. 로그인 · 프로젝트 · 잠시 닫음이 바뀌면 `.task(id:)`가 다시 불러요.
    /// 프로젝트 채널이 닫혀 있는 동안 이 화면들은 배포 채널 이벤트(`refreshSoon`)와 5초 폴링으로 버텨요
    func listen(using app: AppModel) async {
        guard !projectChannelPaused, let projectID = app.selectedProjectID else { return }
        await live.listen(app.eventStream, path: "projects/\(projectID)/events")
    }

    /// 배포 채널에서 상태가 바뀌면 사이드바 승인 대기 배지 · 개요 · 배포 목록도 바로 다시 불러요
    func refreshSoon() {
        live.changes.fire()
    }

    func refresh(using app: AppModel) async {
        guard let client = app.client else { restConnection = .disconnected; return }
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
            // 스트림이 붙어 있을 때만 "실시간 연결됨"이에요 (`connection`, 웹 #61과 같아요)
            restConnection = .polling
        } catch {
            app.handle(error)
            restConnection = loadedOnce ? .reconnecting : .disconnected
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
