import SwiftUI

/// 로그인 전에는 W-00 로그인, 로그인 뒤에는 화면 폭으로 모양을 골라요.
/// 넓으면(iPad · Mac) 사이드바, 좁으면(iPhone) 아래 탭.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = Router()
    @State private var workspace = Workspace()

    /// 사이드바 240 + 본문 최소 460.
    static let sidebarBreakpoint: CGFloat = 700

    var body: some View {
        Group {
            if app.isSignedIn {
                GeometryReader { proxy in
                    if proxy.size.width >= Self.sidebarBreakpoint {
                        SidebarLayout()
                    } else {
                        TabLayout()
                    }
                }
                .task(id: app.token) { await workspace.run(using: app) }
                // 프로젝트 SSE(E-02): 로그인 · 프로젝트가 바뀌거나 앱이 오래 뒤에 있다 오면 다시 붙어요.
                // 배포 채널이 열려 있는 동안은 닫아 둬요 (한 번에 하나)
                .task(id: ProjectChannelKey(token: app.token, projectID: app.selectedProjectID,
                                            paused: workspace.projectChannelPaused, reconnects: workspace.reconnects)) {
                    await workspace.listen(using: app)
                }
                // 로그인할 때 · 앱을 켤 때마다 알림 권한을 묻고 기기를 등록해요 (서버에 아직 없으면 다음에 다시)
                .task(id: app.token) { await app.push.activate(for: app) }
            } else {
                LoginView()
            }
        }
        // 계정 · 프로젝트가 바뀌면 이 창의 Workspace · Router를 바로 비워요 (AppModel이 알려요)
        .onAppear { app.bind(workspace: workspace, router: router) }
        // 알림을 누르면 그 프로젝트의 승인 · 배포 화면으로. 꺼진 앱이 알림으로 켜질 때도 처음 그릴 때 열어요.
        // 로그아웃 상태에서 누른 알림은 버려요 — 나중에 다른 계정으로 로그인해서 열리지 않게 (P3)
        .onChange(of: app.push.pendingOpen, initial: true) { _, payload in
            guard let payload else { return }
            app.push.pendingOpen = nil
            guard app.isSignedIn else { return }
            app.bind(workspace: workspace, router: router)
            payload.open(app: app, router: router)
            workspace.refreshSoon()
        }
        // 앱이 다시 앞으로 오면(백그라운드 · 잠자기 · 다른 앱에서 돌아옴) 모든 화면이 바로 다시 읽어요 (L3)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                workspace.sceneDidBecomeActive()
            } else {
                workspace.sceneDidResignActive()
            }
        }
        .environment(router)
        .environment(workspace)
    }
}

/// 프로젝트 채널을 다시 열어야 하는 때: 로그인 · 프로젝트 · 잠시 닫음 · 다시 앞으로 옴이 바뀔 때
private struct ProjectChannelKey: Equatable {
    let token: String?
    let projectID: String?
    let paused: Bool
    let reconnects: Int
}

/// 메뉴 한 칸의 내용 + 그 안에서 들어가는 화면들.
private struct TabStack: View {
    let tab: AppTab
    @Environment(Router.self) private var router

    var body: some View {
        NavigationStack(path: router.path(for: tab)) {
            tab.content
                .navigationDestination(for: Route.self) { $0.destination.historyReplacesSystemBack() } // NAV-HISTORY
        }
    }
}

/// 좁은 화면: 아래에 얇은 글래스 캡슐 탭 바. 글씨 없이 SF Symbols만 보여줘요 (10/1 담당자 결정).
/// 아이콘만이라 일곱 메뉴가 한 줄에 다 들어가서 시스템 "더 보기"가 없어요. 이름은 VoiceOver로 읽어요.
private struct TabLayout: View {
    @Environment(Router.self) private var router

    var body: some View {
        TabStack(tab: router.tab)
            .id(router.tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 모든 화면의 스크롤 끝에 조금 여백을 둬요. 탭 바(safeAreaInset) 위로 마지막 줄까지 보여요 (10/1)
            .contentMargins(.bottom, 40, for: .scrollContent)
            // 화면 아래 고정 줄(W-06 승인 바)은 이 높이만큼 올라가서 탭 바 위에 놓여요
            .environment(\.tabBarClearance, SlimTabBar.height + 8)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SlimTabBar()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
            }
    }
}

/// 아이콘 탭 한 줄. 선택 표시는 사이드바와 같은 `.fill.tertiary` 알약이 스프링으로 미끄러져요.
private struct SlimTabBar: View {
    static let height: CGFloat = 44
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tint

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                item(tab)
            }
        }
        .padding(4)
        .frame(height: Self.height)
        .glassSurface(in: .capsule)
    }

    private func item(_ tab: AppTab) -> some View {
        let selected = router.tab == tab
        // 가장 최근 배포가 승인을 기다릴 때만 점 하나 (S1, 사이드바 배지와 같은 기준)
        let badge = tab == .deployments && workspace.actionableApproval != nil ? 1 : 0
        return Button {
            // 지금 메뉴를 다시 누르면 그 메뉴의 처음 화면으로 (A5, 사이드바와 같아요)
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                if router.tab == tab { router.popToRoot() } else { router.tab = tab }
            }
        } label: {
            // 선택한 메뉴만 채운 아이콘(cloud.fill · play.fill …). 채운 버전이 없는 심볼은 그대로예요
            Image(systemName: tab.systemImage)
                .symbolVariant(selected ? .fill : .none)
                .font(.system(size: 16, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if selected {
                        Capsule().fill(.fill.tertiary)
                            .matchedGeometryEffect(id: "tab", in: tint)
                    }
                }
                // 승인 대기가 있으면 "배포" 아이콘에 점 하나 (숫자는 VoiceOver로)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Circle().fill(.red).frame(width: 6, height: 6).offset(x: -12, y: 7)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge > 0 ? String.app("\(tab.title), 승인 대기 \(badge)건") : tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 넓은 화면: HUD 재질 사이드바 + 본문 한 장. 시스템 분할 대신 직접 나눠서 둘 사이에 선이 없어요.
private struct SidebarLayout: View {
    @Environment(Router.self) private var router
    @State private var sidebarShown = true
    @AppStorage("sidebar.width") private var sidebarWidth = 240.0
    /// 가장자리를 끄는 동안의 폭. 끝나면 저장해요.
    @State private var draggedWidth: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            if sidebarShown {
                Sidebar()
                    .frame(width: draggedWidth ?? sidebarWidth)
                    .overlay(alignment: .trailing) {
                        SidebarResizer(width: sidebarWidth, dragged: $draggedWidth) { sidebarWidth = $0 }
                    }
                    .transition(.move(edge: .leading))
                    .zIndex(1)
            }
            TabStack(tab: router.tab)
                .id(router.tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentSurface()
                // 사이드바를 닫으면 아래에서 iPhone과 같은 얇은 탭 바가 올라와요 (10/3 담당자). 사이드바가 없으니
                // 탭 바 화면처럼 굴러가요: 스크롤 끝 여백, 아래 고정 줄, 배포 머리줄 "새 배포", 설정 로그아웃
                .contentMargins(.bottom, sidebarShown ? 0 : 40, for: .scrollContent)
                .environment(\.tabBarClearance, sidebarShown ? 0 : SlimTabBar.height + 8)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !sidebarShown {
                        SlimTabBar()
                            .frame(maxWidth: 440)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
        }
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy) { sidebarShown.toggle() }
                } label: {
                    Label(sidebarShown ? "사이드바 가리기" : "사이드바 보기", systemImage: "sidebar.left")
                }
                .help(sidebarShown ? "사이드바 가리기 (⌃⌘S)" : "사이드바 보기 (⌃⌘S)")
                .keyboardShortcut("s", modifiers: [.control, .command])
            }
            ToolbarItemGroup(placement: .navigation) { HistoryToolbarButtons() } // NAV-HISTORY
        }
        .historyEventMonitor() // NAV-HISTORY
        // 사이드바와 본문이 툴바 아래까지 올라가고, 툴바는 아무것도 칠하지 않아요.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
    }
}

/// 사이드바 가장자리를 끌어 폭을 190–420으로 조절해요. 보이지 않고 포인터만 받아요.
private struct SidebarResizer: View {
    let width: Double
    @Binding var dragged: Double?
    let commit: (Double) -> Void

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(.rect)
            .offset(x: 4)
            #if os(macOS)
            .pointerStyle(.columnResize)
            #endif
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in dragged = min(420, max(190, width + drag.translation.width)) }
                    .onEnded { _ in
                        if let dragged { commit(dragged) }
                        dragged = nil
                    }
            )
            .accessibilityHidden(true)
    }
}

#Preview {
    RootView().environment(AppModel()).environment(LanguageStore.shared)
}
