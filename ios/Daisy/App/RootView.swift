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

/// 좁은 화면(iPhone)은 탭, 넓은 화면(iPad · Mac)은 사이드바로 시스템이 알아서 바꿔요.
/// 플랫폼이 아니라 화면 폭에 따라 달라져요 (`.sidebarAdaptable`).
struct RootView: View {
    @State private var tab: AppTab = .overview

    var body: some View {
        TabView(selection: $tab) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    NavigationStack { tab.content }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview {
    RootView().environment(AppModel())
}
