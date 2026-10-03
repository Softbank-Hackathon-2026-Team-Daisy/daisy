import SwiftUI

@main
struct DaisyApp: App {
    @State private var app = DaisyApp.isTestHost
        ? AppModel(tokenStore: TokenStore(service: "com.teamdaisy.daisy.test-host"), defaults: UserDefaults(suiteName: "DaisyTestHost")!)
        : AppModel()
    /// 설정 › 언어 (10/2). 바꾸면 아래 `\.locale`이 바뀌어서 다시 켜지 않아도 화면 글자가 바로 바뀌어요
    @State private var language = LanguageStore.shared
    /// APNs 기기 토큰 · 알림 누름을 받아요 (SPEC §6-5)
    #if os(iOS)
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    #else
    @NSApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    #endif

    /// 단위 테스트가 앱을 띄울 때는 사용자 키체인 · 설정을 읽지 않아요.
    /// 서명이 다른 테스트 빌드가 키체인을 읽으면 허용 창이 떠서 테스트 러너가 멈춰요 (10/1).
    nonisolated static var isTestHost: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(language)
                // `Text("…")` 같은 SwiftUI 글자는 이 로케일의 언어로 String Catalog에서 찾아요
                .environment(\.locale, language.locale)
                #if os(macOS)
                // Mac 창은 늘 사이드바 모양이 되도록 최소 폭을 둬요.
                .frame(minWidth: 820, minHeight: 540)
                #endif
        }
        #if os(macOS)
        // 표준 창 + unified 툴바, 제목은 그리지 않아요 (각 화면이 큰 제목 머리줄을 가져요).
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1100, height: 720)
        // Mac은 창 하나만 (L4): 창마다 Workspace · SSE 연결이 따로 생겨 서로 어긋나고 계정당 SSE 상한(4개)을 써 버려서요.
        // "새로운 윈도우"(⌘N)를 빼고, 탭으로 창을 늘리는 것도 막아요(PushAppDelegate). 창을 닫았다가 Dock을 누르면 다시 하나 열려요
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        #endif
    }
}
