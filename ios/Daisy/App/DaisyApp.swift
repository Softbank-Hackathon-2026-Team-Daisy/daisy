import SwiftUI

@main
struct DaisyApp: App {
    @State private var app = AppModel()

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
