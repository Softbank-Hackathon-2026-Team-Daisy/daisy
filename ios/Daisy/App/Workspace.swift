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

/// 계정 · 프로젝트 맥락이 바뀐 것. `AppModel`이 바로(같은 호출 안에서) 묶인 `Workspace` · `Router`에 알려요
enum ContextChange: Equatable {
    /// 로그인 · 로그아웃 · 만료 · 다른 계정 · 예시 데이터 모드 들어가기/나오기 (토큰이 바뀜)
    case account
    /// 고른 프로젝트가 바뀜 (사이드바 · 개요 전환, 알림, 연결 · 해제)
    case project(String?)
}

/// 메뉴 선택과 메뉴별 이동 경로. 사이드바의 "새 배포" 같은 버튼이 어느 화면에서든 이동할 수 있게 해요.
///
/// 경로 규칙 (C2 · P2 · D4 · L1, 10/3):
/// - `open(_:)`은 화면마다 정한 메뉴(`Route.home`)의 경로만 비우고 그 화면을 엽니다. 새 프로젝트 연결은 개요,
///   나머지(배포 · 승인 · 알림)는 배포 메뉴예요. 그래서 "새 프로젝트 연결"이 배포 메뉴에서 하던 작업을 지우지 않아요
/// - 같은 화면이 이미 그 메뉴 맨 위에 있으면 그대로 둬요 (알림을 두 번 눌러도 같은 화면이 두 번 열리지 않아요)
/// - 프로젝트가 바뀌면 모든 메뉴 경로를 비워요 (이전 프로젝트 화면이 새 projectID로 요청하지 않게). 연결 흐름
///   (`.connectProject`로 시작한 경로)만 남아요 — 그 흐름이 새 프로젝트를 고른 거라서요
/// - 계정이 바뀌면 메뉴도 개요로 돌아가고 경로를 모두 비워요
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

    /// 메뉴를 바꾸고 그 메뉴 안에서 곧장 한 화면으로 들어가요. 메뉴를 안 주면 화면마다 정한 곳(`Route.home`)이에요
    func open(_ route: Route, in tab: AppTab? = nil) {
        let tab = tab ?? route.home
        recordingOnce { // NAV-HISTORY
            self.tab = tab
            if paths[tab]?.last == route { return }
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

    /// 계정 · 프로젝트가 바뀌었을 때 (`AppModel`이 불러요). 이동 기록도 지금 위치에서 새로 시작해요
    func apply(_ change: ContextChange) {
        switch change {
        case .account:
            history.restoring { // NAV-HISTORY
                tab = .overview
                paths = [:]
            }
        case .project:
            history.restoring { // NAV-HISTORY
                paths = paths.filter { $0.value.first == .connectProject }
            }
        }
        clearHistory() // NAV-HISTORY
    }
}

extension Route {
    /// `Router.open`이 메뉴를 받지 않았을 때 여는 메뉴
    var home: AppTab {
        switch self {
        case .connectProject: .overview
        default: .deployments
        }
    }
}

/// 사이드바 · 개요가 함께 쓰는 프로젝트 상태. 프로젝트 SSE(E-02) 이벤트가 오면 바로, 아니면 폴링으로 새로 받아요.
///
/// 다른 화면과의 약속:
/// - `live.changes`: "지금 다시 불러와" 신호 하나. 화면은 `poll(on: workspace.live.changes, every: …)`로 기다려요.
///   프로젝트 채널 이벤트, 연결이 붙거나 끊길 때, 앱이 다시 앞으로 올 때(`sceneDidBecomeActive`), 프로젝트를 바꾼 직후,
///   `refreshSoon()`을 부를 때 울려요
/// - `refreshSoon()`: 승인 · 거절 · 배포 시작처럼 서버 상태를 바꾼 직후 부르면 배지 · 개요 · 목록이 바로 다시 읽어요
/// - `actionableApproval`: 배지 · "지금 할 일"이 가리키는 배포 (가장 최근 배포가 승인 대기이고 아직 승인 안 된 환경이 있을 때)
@MainActor
@Observable
final class Workspace {
    private(set) var projects: [Project] = []
    private(set) var statuses: [TargetStatus] = []
    private(set) var targets: [DeployTarget] = []
    /// A-03 첫 페이지 (최신순, 상태로 거르지 않아요). 첫 건이 "가장 최근 배포"예요 (배포 메뉴와 같은 기준).
    /// 개요의 "지금 할 일" · "최근 실행"이 같은 응답을 쓰면 서로 어긋나지 않아요 (O4)
    private(set) var recentDeployments: [Deployment] = []
    private(set) var loadedOnce = false
    /// 마지막으로 프로젝트 현황을 모두 받은 시각 (사이드바 연결 표시 도움말)
    private(set) var lastRefreshedAt: Date?
    /// 앱이 다시 앞으로 와서 실시간 연결을 새로 열어야 할 때 올라가요. SSE를 여는 `.task(id:)` 키에 넣으면 그때 다시 붙어요
    private(set) var reconnects = 0
    /// 프로젝트 채널 (`projects/{id}/events`). 개요 · 배포 목록 · 빌드 화면도 이 신호로 바로 다시 불러요
    let live = LiveChannel()
    /// REST 폴링 결과. 성공하면 `polling`, 실패하면 `reconnecting` · `disconnected`
    private var restConnection: ConnectionState = .reconnecting

    /// 계정이 바뀔 때마다 올라가요. 그 전에 보낸 요청의 응답은 버려요
    @ObservationIgnored private var accountEpoch = 0
    /// 계정 · 프로젝트가 바뀔 때마다 올라가요. 그 전에 보낸 프로젝트 요청의 응답은 버려요 (S3 · S4)
    @ObservationIgnored private var projectEpoch = 0
    /// 동시에 돈 refresh 가운데 늦게 시작한 것의 응답만 남겨요
    @ObservationIgnored private var refreshCount = 0
    @ObservationIgnored private var appliedRefresh = 0
    /// 앱이 뒤로 간 시각. 오래 있다 오면 실시간 연결을 새로 열어요
    @ObservationIgnored private var resignedAt: Date?

    /// 지금 열려 있는 배포 채널 (RunView). 서버가 계정당 SSE를 4개까지만 받아서(Mac · iPhone · 웹을 같이 쓰면 금방 차요)
    /// 앱은 한 번에 하나만 열어요: 배포 채널이 열려 있는 동안 프로젝트 채널은 닫고, 배포 채널이 닫히면 이어 받아요
    private var borrowed: [ObjectIdentifier: LiveChannel] = [:]

    /// 프로젝트 채널을 잠시 닫아 둔 상태 (배포 채널이 대신 열려 있어요)
    var projectChannelPaused: Bool { !borrowed.isEmpty }

    /// 프로젝트 · 배포 채널 중 하나라도 붙어 있어요
    var isLive: Bool { live.isLive || borrowed.values.contains { $0.isLive } }

    /// 연결 표시: 스트림이 붙어 있으면 "실시간 연결됨", 끊기면 폴링으로 돌아가요. 범위는 이 프로젝트 현황이에요 (S6)
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

    /// 지금 데이터가 가리키는 프로젝트. 프로젝트를 바꾸면 응답을 기다리지 않고 바로 바뀌어요 (S5)
    private(set) var currentProjectID: String?

    /// 가장 최근 배포 (A-03 첫 건)
    var latestDeployment: Deployment? { recentDeployments.first }

    /// 사이드바 "배포" 배지 · iPhone 빨간 점 · 개요 "지금 할 일": 가장 최근 배포가 승인 대기이고 아직 승인하지 않은 환경이
    /// 있을 때만 그 배포예요 (S1, 배포 메뉴와 같은 기준 · `Deployment.needsDecision`). 승인 뒤 apply 전이거나
    /// 새 배포에 밀려 버려진 예전 승인 대기는 세지 않아요
    var actionableApproval: Deployment? {
        guard let latest = latestDeployment, latest.needsDecision else { return nil }
        return latest
    }

    /// 예전 이름 (개요가 써요). 이제 `actionableApproval` 하나이거나 비어 있어요
    var awaitingApproval: [Deployment] { actionableApproval.map { [$0] } ?? [] }

    /// 가장 최근 배포가 끝나지 않았어요 (대기 · 진행 · 승인 대기). 이때는 SSE가 붙어 있어도 짧게 다시 읽어요 (`PollInterval.project`)
    var hasActiveDeployment: Bool { latestDeployment?.state.isActive ?? false }

    func run(using app: AppModel) async {
        await poll(on: live.changes, every: { PollInterval.project(live: self.live.isLive, active: self.hasActiveDeployment) }) {
            await self.refresh(using: app)
        }
    }

    /// 고른 프로젝트의 채널에 붙어 있어요. 로그인 · 프로젝트 · 잠시 닫음 · 다시 앞으로 옴(`reconnects`)이 바뀌면
    /// `.task(id:)`가 다시 불러요. 프로젝트 채널이 닫혀 있는 동안 이 화면들은 배포 채널 이벤트(`refreshSoon`)와 폴링으로 버텨요
    func listen(using app: AppModel) async {
        guard !projectChannelPaused, let projectID = app.selectedProjectID else { return }
        await live.listen(app.eventStream, path: "projects/\(projectID)/events")
    }

    /// "지금 다시 불러와" (`live.changes`를 울려요). 승인 · 거절 · 배포 시작처럼 서버 상태를 바꾼 직후, 배포 채널에서 상태가
    /// 바뀐 때 불러요. 사이드바 배지 · 개요 · 배포 목록처럼 `live.changes`를 기다리는 화면이 모두 바로 다시 읽어요.
    /// 다른 화면이 쓰는 이름이라 바꾸지 않아요
    func refreshSoon() {
        live.changes.fire()
    }

    // MARK: 맥락 · 생명주기

    /// 계정 · 프로젝트가 바뀌었을 때 (`AppModel`이 바로 불러요).
    /// 계정: 모두 비우고 처음 상태로. 프로젝트: 이전 프로젝트의 환경 · 커밋 · 배지를 바로 비우고 다시 읽어요 (S3 · S5 · P1)
    func apply(_ change: ContextChange) {
        switch change {
        case .account:
            accountEpoch += 1
            clearProjectData(for: nil)
            projects = []
            loadedOnce = false
            restConnection = .reconnecting
            live.forgetCursor()
        case .project(let projectID):
            clearProjectData(for: projectID)
            refreshSoon()
        }
    }

    private func clearProjectData(for projectID: String?) {
        projectEpoch += 1
        currentProjectID = projectID
        statuses = []
        targets = []
        recentDeployments = []
        lastRefreshedAt = nil
    }

    /// 앱이 뒤로 가거나 비활성이 될 때
    func sceneDidResignActive(now: Date = .now) {
        if resignedAt == nil { resignedAt = now }
    }

    /// 앱이 다시 앞으로 왔을 때 (L3): 바로 다시 읽고, 실시간 연결이 끊겼거나 heartbeat 간격보다 오래 뒤에 있었으면
    /// 연결을 새로 열어요 (뒤에 있는 동안 iOS가 연결을 끊어도 앱은 한참 뒤에야 알아요)
    func sceneDidBecomeActive(now: Date = .now) {
        // 처음 켤 때(뒤로 간 적 없음)는 연결이 막 열리는 중이라 다시 열지 않아요
        let away = resignedAt.map { now.timeIntervalSince($0) }
        resignedAt = nil
        if let away, !live.isLive || away >= Self.reconnectAfter { reconnects += 1 }
        refreshSoon()
    }

    static let reconnectAfter: TimeInterval = 15

    // MARK: 새로고침

    func refresh(using app: AppModel) async {
        guard let client = app.client else { restConnection = .disconnected; return }
        let account = accountEpoch
        refreshCount += 1
        let order = refreshCount
        do {
            let projects = try await client.send(.projects()).items
            guard account == accountEpoch else { return }
            self.projects = projects
            if app.selectedProjectID == nil || !projects.contains(where: { $0.id == app.selectedProjectID }) {
                app.selectedProjectID = projects.first?.id
            }
            // AppModel에 묶이지 않은 Workspace(테스트 · 첫 로드)도 고른 프로젝트를 따라가요
            if currentProjectID != app.selectedProjectID { clearProjectData(for: app.selectedProjectID) }
            guard let projectID = app.selectedProjectID else {
                finish(.polling)
                return
            }
            let epoch = projectEpoch
            async let statuses = Self.capture { try await client.send(.targetStatuses(projectID: projectID)).items }
            async let targets = Self.capture { try await client.send(.deployTargets(projectID: projectID)).items }
            async let deployments = Self.capture { try await client.send(.deployments(projectID: projectID)).items }
            let results = await (statuses, targets, deployments)
            // 그사이 계정 · 프로젝트가 바뀌었거나 더 늦게 시작한 refresh가 이미 반영했으면 버려요 (S3 · S4)
            guard epoch == projectEpoch, projectID == app.selectedProjectID, order > appliedRefresh else { return }
            appliedRefresh = order
            let failures = [results.0.error, results.1.error, results.2.error].compactMap { $0 }
            if let expired = failures.first(where: { ($0 as? APIError)?.isUnauthenticated == true }) {
                app.handle(expired)  // 401을 삼키지 않아요 → 로그인 화면 (X2)
                return
            }
            // 실패한 것은 이 프로젝트의 이전 값을 그대로 둬요 (O5: 승인 대기 요청만 실패해도 배지가 지워지지 않아요)
            if case .success(let value) = results.0 { self.statuses = value }
            if case .success(let value) = results.1 { self.targets = value }
            if case .success(let value) = results.2 { self.recentDeployments = value }
            if failures.isEmpty { lastRefreshedAt = .now }
            // 스트림이 붙어 있을 때만 "실시간 연결됨"이에요 (`connection`, 웹 #61과 같아요)
            finish(.polling)
        } catch {
            // 취소된 요청(화면이 사라짐 · 다시 시작)은 실패가 아니에요 (X4)
            guard !error.isCancellation, account == accountEpoch else { return }
            app.handle(error)
            finish(loadedOnce ? .reconnecting : .disconnected)
        }
    }

    private func finish(_ connection: ConnectionState) {
        restConnection = connection
        loadedOnce = true
    }

    /// 요청 하나의 결과. `try?`처럼 오류를 버리지 않아서 401 · 취소를 가려낼 수 있어요 (X2)
    private nonisolated static func capture<T: Sendable>(_ body: @Sendable () async throws -> T) async -> Result<T, any Error> {
        do { return .success(try await body()) } catch { return .failure(error) }
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

extension Result {
    /// 실패면 그 오류
    var error: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
