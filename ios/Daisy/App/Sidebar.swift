import SwiftUI

/// 넓은 화면의 길잡이 (AfterPlan 사이드바를 옮김).
/// 색 없이 중립 틴트와 굵기로 선택을 보여줘요. 틴트는 스프링으로 미끄러지고, 굵기는 즉시 바뀌어요.
struct Sidebar: View {
    @Binding var selection: AppTab
    @Environment(AppModel.self) private var app
    @Namespace private var tint
    @State private var hovered: AppTab?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var spring: Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(AppTab.primary) { tab in row(tab) }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            Spacer(minLength: 0)
            footer
        }
        // 선 없음: 재질이 바뀌는 곳이 본문과의 경계예요.
        .background(SidebarBackground())
    }

    /// Craft의 공간 이름 자리: 앱 이름과 연결 상태.
    private var header: some View {
        HStack(spacing: 10) {
            Image(.appLogo)
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
                .clipShape(.rect(cornerRadius: 7))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Daisy").font(.system(size: 15, weight: .semibold))
                Text(app.client == nil ? "서버 연결 안 됨" : (app.isViewer ? "읽기 전용" : "연결됨"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }

    private func row(_ tab: AppTab) -> some View {
        let selected = selection == tab
        return HStack(spacing: 10) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 16))
                .frame(width: 22)
            Text(tab.title)
                .font(.system(size: 15, weight: selected ? .semibold : .regular))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.fill.tertiary)
                    .matchedGeometryEffect(id: "tint", in: tint)
            } else if hovered == tab {
                RoundedRectangle(cornerRadius: 8).fill(.fill.quinary)
            }
        }
        .contentShape(.rect)
        .onTapGesture { withAnimation(spring) { selection = tab } }
        // 탭 제스처는 VoiceOver에 누르기 동작을 주지 않아서 따로 달아요.
        .accessibilityAction { withAnimation(spring) { selection = tab } }
        .onHover { inside in hovered = inside ? tab : (hovered == tab ? nil : hovered) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(tab.title)
    }

    /// 왼쪽 아래 설정 톱니 하나.
    private var footer: some View {
        HStack {
            Button {
                withAnimation(spring) { selection = .settings }
            } label: {
                Image(systemName: selection == .settings ? "gearshape.fill" : "gearshape")
                    .font(.system(size: 16))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("설정")
            .accessibilityLabel("설정")
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }
}
