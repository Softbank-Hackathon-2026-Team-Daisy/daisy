import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case overview, deployments, approvals, history, settings

    var id: Self { self }

    /// 사이드바 본문 행. 설정은 왼쪽 아래 톱니로 가요.
    static let primary: [AppTab] = [.overview, .deployments, .approvals, .history]

    var title: String {
        switch self {
        case .overview: "개요"
        case .deployments: "배포"
        case .approvals: "승인"
        case .history: "이력"
        case .settings: "설정"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "cloud"
        case .deployments: "play"
        case .approvals: "checkmark.seal"
        case .history: "clock"
        case .settings: "gearshape"
        }
    }

    @MainActor @ViewBuilder
    var content: some View {
        switch self {
        case .overview: OverviewView()
        case .deployments: DeploymentsView()
        case .approvals: ApprovalsView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}

/// 화면 폭으로 모양을 골라요. 넓으면(iPad · Mac) 사이드바, 좁으면(iPhone) 아래 탭.
struct RootView: View {
    @State private var tab: AppTab = .overview

    /// 사이드바 240 + 본문 최소 460.
    static let sidebarBreakpoint: CGFloat = 700

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= Self.sidebarBreakpoint {
                SidebarLayout(tab: $tab)
            } else {
                TabLayout(tab: $tab)
            }
        }
    }
}

/// 좁은 화면: 시스템 탭.
private struct TabLayout: View {
    @Binding var tab: AppTab

    var body: some View {
        TabView(selection: $tab) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    NavigationStack { tab.content }
                }
            }
        }
    }
}

/// 넓은 화면: HUD 재질 사이드바 + 본문 한 장. 시스템 분할 대신 직접 나눠서 둘 사이에 선이 없어요.
private struct SidebarLayout: View {
    @Binding var tab: AppTab
    @State private var sidebarShown = true
    @AppStorage("sidebar.width") private var sidebarWidth = 240.0
    /// 가장자리를 끄는 동안의 폭. 끝나면 저장해요.
    @State private var draggedWidth: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            if sidebarShown {
                Sidebar(selection: $tab)
                    .frame(width: draggedWidth ?? sidebarWidth)
                    .overlay(alignment: .trailing) {
                        SidebarResizer(width: sidebarWidth, dragged: $draggedWidth) { sidebarWidth = $0 }
                    }
                    .transition(.move(edge: .leading))
                    .zIndex(1)
            }
            NavigationStack { tab.content }
                .id(tab)
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
