import SwiftUI

@main
struct DaisyApp: App {
    @State private var app = DaisyApp.isTestHost
        ? AppModel(tokenStore: TokenStore(service: "com.teamdaisy.daisy.test-host"), defaults: UserDefaults(suiteName: "DaisyTestHost")!)
        : AppModel()

    /// 단위 테스트가 앱을 띄울 때는 사용자 키체인 · 설정을 읽지 않아요.
    /// 서명이 다른 테스트 빌드가 키체인을 읽으면 허용 창이 떠서 테스트 러너가 멈춰요 (10/1).
    private static var isTestHost: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                #if os(macOS)
                // Mac 창은 늘 사이드바 모양이 되도록 최소 폭을 둬요.
                .frame(minWidth: 820, minHeight: 540)
                #endif
        }
        #if os(macOS)
        // 표준 창 + unified 툴바, 제목은 그리지 않아요 (각 화면이 큰 제목 머리줄을 가져요).
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1100, height: 720)
        #endif
    }
}
