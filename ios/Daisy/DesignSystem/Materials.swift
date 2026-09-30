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
                VisualEffect(material: .hudWindow)
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
                    VisualEffect(material: .underWindowBackground)
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
    func hidesSystemTitleBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}
