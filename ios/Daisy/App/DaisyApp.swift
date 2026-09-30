import SwiftUI

@main
struct DaisyApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
    }
}
