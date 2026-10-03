import Observation
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// 앱 어디에 있는지: 메뉴 + 그 메뉴 안에서 들어간 화면들. 웹 주소 한 줄과 같아요.
struct NavigationLocation: Hashable {
    let tab: AppTab
    let path: [Route]
}

/// 웹 브라우저처럼 뒤로 · 앞으로 가는 이동 기록 (10/3).
/// 메뉴를 바꾸거나 화면에 들어가고 나올 때마다 한 칸씩 쌓이고, 뒤로 간 다음 새로 이동하면 앞쪽 기록은 지워요.
/// 기록대로 되돌리는 동안(`restoring`)에 생긴 변화는 다시 기록하지 않아요. 최근 `limit`칸까지만 둬요.
@MainActor
@Observable
final class NavigationHistory {
    static let defaultLimit = 50

    private(set) var entries: [NavigationLocation]
    private(set) var index = 0
    let limit: Int
    /// 기록대로 화면을 되돌리는 중. 이때 Router가 바뀌어도 새 기록을 만들지 않아요
    @ObservationIgnored private(set) var isRestoring = false

    init(start: NavigationLocation = NavigationLocation(tab: .overview, path: []), limit: Int = defaultLimit) {
        entries = [start]
        self.limit = max(1, limit)
    }

    var current: NavigationLocation { entries[index] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < entries.count - 1 }

    /// 같은 메뉴 안에서만 뒤로 갈 수 있나요. iPhone은 메뉴 첫 화면에서 다른 메뉴로 건너가지 않아요 (iOS 관례)
    var canGoBackWithinTab: Bool { canGoBack && entries[index - 1].tab == current.tab }

    /// 사용자가 새로 이동했어요. 지금 칸과 같으면(같은 값을 다시 쓴 경우) 아무것도 하지 않아요
    func record(_ location: NavigationLocation) {
        guard !isRestoring, location != current else { return }
        entries.removeSubrange((index + 1)...)
        entries.append(location)
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
        index = entries.count - 1
    }

    /// 시스템 뒤로(왼쪽 가장자리 쓸기 · 뒤로 버튼)로 화면이 닫혔어요. 바로 앞 칸과 같으면 기록에서도 한 칸 뒤로 가서
    /// 앞으로 가기를 남겨 두고, 아니면 새 이동으로 기록해요
    func recordPop(_ location: NavigationLocation) {
        guard !isRestoring, location != current else { return }
        if canGoBack, entries[index - 1] == location {
            index -= 1
        } else {
            record(location)
        }
    }

    /// 한 칸 뒤 위치. 옮겨 간 뒤 그 위치를 돌려줘요 (없으면 nil)
    func back() -> NavigationLocation? {
        guard canGoBack else { return nil }
        index -= 1
        return current
    }

    /// 한 칸 앞 위치. 옮겨 간 뒤 그 위치를 돌려줘요 (없으면 nil)
    func forward() -> NavigationLocation? {
        guard canGoForward else { return nil }
        index += 1
        return current
    }

    /// 이 안에서 일어난 화면 변화는 기록하지 않아요 (기록대로 되돌릴 때)
    func restoring(_ body: () -> Void) {
        let outer = isRestoring
        isRestoring = true
        defer { isRestoring = outer }
        body()
    }

    /// 로그아웃 · 계정 · 프로젝트가 바뀌면 이전 기록으로 돌아가지 않게 지금 위치 한 칸만 남겨요
    func clear(at location: NavigationLocation) {
        entries = [location]
        index = 0
    }
}

// MARK: - Router 연결

extension Router {
    /// 지금 위치 (메뉴 + 그 메뉴의 이동 경로)
    var location: NavigationLocation {
        NavigationLocation(tab: tab, path: path(for: tab).wrappedValue)
    }

    /// 사용자가 이동한 뒤 지금 위치를 기록해요
    func recordNavigation() {
        history.record(location)
    }

    /// 여러 값을 한꺼번에 바꾸는 이동(메뉴 + 경로)을 한 칸으로 기록해요
    func recordingOnce(_ change: () -> Void) {
        history.restoring(change)
        recordNavigation()
    }

    /// `NavigationStack`이 경로를 바꿨어요 (화면 들어가기 · 시스템 뒤로). 짧아졌으면 뒤로 간 것으로 봐요
    func recordPathChange(in tab: AppTab, from old: [Route], to new: [Route]) {
        guard tab == self.tab, old != new else { return }
        if new.count < old.count, Array(old.prefix(new.count)) == new {
            history.recordPop(location)
        } else {
            recordNavigation()
        }
    }

    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }

    /// 뒤로. `crossingTabs`가 false면(iPhone) 같은 메뉴 안에서만 가요
    func goBack(crossingTabs: Bool = true) {
        guard crossingTabs || history.canGoBackWithinTab, let target = history.back() else { return }
        apply(target)
    }

    func goForward() {
        guard let target = history.forward() else { return }
        apply(target)
    }

    /// 기록을 지금 위치 한 칸으로 비워요. 로그아웃 · 계정 · 프로젝트를 바꿔 경로를 비운 뒤 불러요
    func clearHistory() {
        history.clear(at: location)
    }

    /// 기록대로 되돌려요. 이 변화는 다시 기록하지 않아요
    private func apply(_ target: NavigationLocation) {
        history.restoring {
            path(for: target.tab).wrappedValue = target.path
            tab = target.tab
        }
    }
}

// MARK: - Mac 툴바 · 단축키

extension View {
    /// Mac: 들어간 화면의 시스템 뒤로 버튼(그 메뉴 안에서만 돌아가요)을 숨기고 툴바의 뒤로 · 앞으로가 대신해요.
    /// iPhone · iPad는 시스템 뒤로 버튼과 가장자리 쓸기를 그대로 둬요 (기록은 경로 변화로 따라가요)
    func historyReplacesSystemBack() -> some View {
        #if os(macOS)
        navigationBarBackButtonHidden(true)
        #else
        self
        #endif
    }
}

#if os(macOS)
/// Mac 창 툴바의 뒤로 · 앞으로 (⌘[ · ⌘]). 사이드바 버튼 옆에 같은 툴바 글래스로 붙어요
struct HistoryToolbarButtons: View {
    @Environment(Router.self) private var router

    var body: some View {
        Button { router.goBack() } label: {
            Label("뒤로", systemImage: "chevron.backward")
        }
        .help("뒤로")
        .keyboardShortcut("[", modifiers: .command)
        .disabled(!router.canGoBack)

        Button { router.goForward() } label: {
            Label("앞으로", systemImage: "chevron.forward")
        }
        .help("앞으로")
        .keyboardShortcut("]", modifiers: .command)
        .disabled(!router.canGoForward)
    }
}

/// ⌘← · ⌘→ 와 마우스 뒤로 · 앞으로 버튼(3 · 4번)도 받아요. 글자를 고치는 중이면 ⌘← · ⌘→는 커서 이동으로 남겨 둬요
private struct HistoryEventMonitor: ViewModifier {
    @Environment(Router.self) private var router
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                let router = router
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .otherMouseDown]) { event in
                    // 이벤트는 메인 스레드에서 와요
                    let handled = MainActor.assumeIsolated { HistoryEventMonitor.handle(event, router: router) }
                    return handled ? nil : event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    /// 뒤로 · 앞으로를 했으면 true (이벤트를 여기서 끝내요)
    private static func handle(_ event: NSEvent, router: Router) -> Bool {
        // 시트가 떠 있는 동안에는 뒤 화면을 옮기지 않아요
        if event.window?.sheetParent != nil || event.window?.attachedSheet != nil { return false }
        let back: Bool
        switch event.type {
        case .otherMouseDown:
            switch event.buttonNumber {
            case 3: back = true
            case 4: back = false
            default: return false
            }
        case .keyDown:
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard modifiers == .command else { return false }
            // 글자 입력 칸에서는 ⌘← · ⌘→가 줄 처음 · 끝으로 가는 커서 이동이에요
            if event.window?.firstResponder is NSText { return false }
            switch event.keyCode {
            case 123: back = true    // ←
            case 124: back = false   // →
            default: return false
            }
        default:
            return false
        }
        if back {
            guard router.canGoBack else { return false }
            router.goBack()
        } else {
            guard router.canGoForward else { return false }
            router.goForward()
        }
        return true
    }
}

extension View {
    /// Mac: ⌘← · ⌘→ · 마우스 뒤로 · 앞으로 버튼으로 이동 기록을 오가요
    func historyEventMonitor() -> some View {
        modifier(HistoryEventMonitor())
    }
}
#endif
