import SwiftUI

/// 로그인 전에는 W-00 로그인, 로그인 뒤에는 화면 폭으로 모양을 골라요.
/// 넓으면(iPad · Mac) 사이드바, 좁으면(iPhone) 아래 탭.
struct RootView: View {
    @Environment(AppModel.self) private var app
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
            } else {
                LoginView()
            }
        }
        .environment(router)
        .environment(workspace)
        .environment(\.isSampleData, app.isSampleMode)
    }
}

/// 메뉴 한 칸의 내용 + 그 안에서 들어가는 화면들.
private struct TabStack: View {
    let tab: AppTab
    @Environment(Router.self) private var router

    var body: some View {
        NavigationStack(path: router.path(for: tab)) {
            tab.content
                .navigationDestination(for: Route.self) { $0.destination }
        }
    }
}

/// 좁은 화면: 시스템 탭. 다섯 개가 넘는 메뉴는 시스템이 "더 보기"로 묶어요.
private struct TabLayout: View {
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    TabStack(tab: tab)
                }
                .badge(tab == .deployments ? workspace.awaitingApproval.count : 0)
            }
        }
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
        }
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
    RootView().environment(AppModel())
}
