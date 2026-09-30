import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case overview, deployments, approvals, history, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "현황"
        case .deployments: "배포"
        case .approvals: "승인"
        case .history: "커밋"
        case .settings: "설정"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .deployments: "arrow.up.circle"
        case .approvals: "checkmark.seal"
        case .history: "point.3.connected.trianglepath.dotted"
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

/// iOS는 탭, macOS는 사이드바로 같은 화면을 보여줘요.
struct RootView: View {
    @State private var tab: AppTab = .overview

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(AppTab.allCases, selection: $tab) { tab in
                Label(tab.title, systemImage: tab.systemImage).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            NavigationStack { tab.content }
                .id(tab)
        }
        #else
        TabView(selection: $tab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack { tab.content }
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        #endif
    }
}

#Preview {
    RootView().environment(AppModel())
}
