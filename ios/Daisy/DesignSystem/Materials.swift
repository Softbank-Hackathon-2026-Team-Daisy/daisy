import SwiftUI
#if os(macOS)
import AppKit
#endif

// 창의 층 (AfterPlan macos-design.md §1–2를 옮김)
// - 사이드바: HUD 재질 한 장, 창 뒤 블렌딩, 창 활성 상태를 따르고 덧입힌 색 없음.
// - 본문: 모든 화면이 같은 바탕 한 장. 창 뒤가 비치는 재질, 투명도 줄이기면 불투명.
// - 사이드바와 본문 사이에는 선을 두지 않아요. 재질이 바뀌는 곳이 경계예요.

#if os(macOS)
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// 시스템 설정 › 모양의 Liquid Glass 비침 정도 (0 최소 … 1 최대). 공개 API가 없어서 전역 설정 `NSGlassTintAmount`를 읽어요
/// (10/3 실측: 최소 0 · 중간 약 0.49 · 최대 1). 값이 없거나 읽지 못하면 0 → 지금 모습 그대로예요.
/// 다른 앱(시스템 설정)에서 바꾼 값은 1초마다, 그리고 앱으로 돌아올 때 다시 읽어요.
@MainActor @Observable
final class SystemGlassLevel {
    static let shared = SystemGlassLevel()
    private(set) var value: Double = SystemGlassLevel.read()
    @ObservationIgnored private var timer: Timer?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in SystemGlassLevel.shared.refresh() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in SystemGlassLevel.shared.refresh() }
        }
    }

    func refresh() {
        let latest = Self.read()
        if abs(latest - value) > 0.001 { value = latest }
    }

    nonisolated static func read() -> Double {
        min(1, max(0, UserDefaults.standard.double(forKey: "NSGlassTintAmount")))
    }
}

/// 비침이 클수록 재질 뒤에 창 바탕색을 비례해서 받쳐 무게감을 줘요 (10/3 담당자: 비침을 키우면 사이드바 · 배경이 너무 가벼워 보여요).
/// 비침 최소(0)면 받침도 0이라 지금과 같아요.
private struct GlassWeight: ViewModifier {
    /// 비침 최대(1)일 때 받침 불투명도
    let maximum: Double
    @State private var glass = SystemGlassLevel.shared

    func body(content: Content) -> some View {
        content.overlay {
            Color(nsColor: .windowBackgroundColor)
                .opacity(glass.value * maximum)
                .animation(.easeOut(duration: 0.25), value: glass.value)
                .allowsHitTesting(false)
        }
    }
}
#endif

/// 사이드바 바탕. Mac은 HUD 재질, iPad는 가장 얇은 재질.
struct SidebarBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            #if os(macOS)
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                VisualEffect(material: .hudWindow).modifier(GlassWeight(maximum: 0.55))
            }
            #else
            if reduceTransparency {
                Color(uiColor: .secondarySystemBackground)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
            #endif
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// 본문 바탕 한 장. 툴바 아래까지 이어져요.
    func contentSurface() -> some View { modifier(ContentSurface()) }
}

private struct ContentSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background {
            Group {
                #if os(macOS)
                if reduceTransparency {
                    Color(nsColor: .controlBackgroundColor)
                } else {
                    VisualEffect(material: .underWindowBackground).modifier(GlassWeight(maximum: 0.45))
                }
                #else
                Color(uiColor: .systemBackground)
                #endif
            }
            .ignoresSafeArea()
        }
    }
}

extension View {
    /// 목록 · 폼이 자기 바탕을 칠하지 않고 본문 재질이 비치게 해요.
    func onContentSurface() -> some View {
        scrollContentBackground(.hidden)
    }

    /// 루트 화면은 큰 제목 머리줄(`PageHeader`)을 쓰므로 시스템 제목 막대를 숨겨요.
    /// Mac은 창 툴바가 제목을 그리지 않아서(`showsTitle: false`) 할 일이 없어요.
    /// 흐름 화면 제목: iOS는 막대 제목을 비워 뒤로 가기만 두고(화면 안 제목과 두 번 보이지 않게), macOS는 창 제목으로 써요.
    func flowNavigationTitle(_ title: String) -> some View {
        #if os(iOS)
        navigationTitle("").navigationBarTitleDisplayMode(.inline)
        #else
        navigationTitle(title)
        #endif
    }

    func hidesSystemTitleBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}
