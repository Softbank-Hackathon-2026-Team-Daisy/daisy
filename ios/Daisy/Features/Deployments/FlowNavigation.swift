import SwiftUI

// 배포 흐름의 화면 이동 (10/3 데이터 신선도 검수 D12 · D13 · P5). 규칙은 `RunNavigation`(RunLogic.swift)에 두고 테스트해요.

extension Router {
    /// 정한 탭의 맨 위 화면을 바꿔요. 요청을 기다리는 동안 다른 탭으로 옮겨 갔어도 원래 탭 경로만 바꿔요 (D13)
    func replaceTop(with route: Route, in tab: AppTab) {
        let path = path(for: tab)
        var routes = path.wrappedValue
        if !routes.isEmpty { routes.removeLast() }
        routes.append(route)
        path.wrappedValue = routes
    }

    /// 정한 탭에 화면을 하나 더 열어요 (D13)
    func push(_ route: Route, in tab: AppTab) {
        path(for: tab).wrappedValue.append(route)
    }

    /// 다시 시도로 생긴 새 배포를 열어요. 원래 배포 화면 위에 쌓지 않고 바꿔 끼워요 (D12).
    /// 배포 탭에서는 루트(DeploymentsView)가 `.started`를 이어받아 경로를 비워요
    func openRetry(_ started: String, source: String, in tab: AppTab) {
        let path = path(for: tab)
        path.wrappedValue = RunNavigation.afterRetry(path.wrappedValue, started: started, source: source)
    }
}

extension EnvironmentValues {
    /// 배포 탭 루트가 이 배포 화면을 보여주고 있을 때, 이 화면에서 시작한 새 배포(다시 시도)를 루트가 바로 이어받아요.
    /// 없으면(다른 탭 · 위에 연 화면) `Router.openRetry`로 열어요
    @Entry var adoptDeployment: DeploymentAdopter? = nil
}

/// 배포 탭 루트의 "이 배포를 이어받아요". 화면이 다시 그려질 때마다 아래 화면을 무효화하지 않게 루트가 보여주는 배포로만 비교해요
struct DeploymentAdopter: Equatable {
    /// 루트가 지금 보여주는 배포
    let owner: String
    let adopt: @MainActor (String) -> Void

    @MainActor func callAsFunction(_ deploymentID: String) { adopt(deploymentID) }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.owner == rhs.owner }
}
