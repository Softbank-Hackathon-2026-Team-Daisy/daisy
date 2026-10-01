import SwiftUI

// 버튼 (Craft 레퍼런스): 동그란 글래스 버튼, 캡슐 버튼, 아이콘 · 글자 캡슐 세그먼트.
// macOS 26 · iOS 26 이상은 시스템 Liquid Glass, 그 전은 재질 + 가는 테두리로 비슷하게 그려요.

extension View {
    /// 글래스 면. 누를 수 있는 컨트롤에만 써요.
    @ViewBuilder
    func glassSurface(in shape: some Shape) -> some View {
        if #available(iOS 26, macOS 26, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.separator, lineWidth: 0.5))
        }
    }
}

/// 동그란 아이콘 버튼 (뒤로, 새로 고침, 더 보기).
struct GlassCircleButtonStyle: ButtonStyle {
    var diameter: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 15, weight: .medium))
            .frame(width: diameter, height: diameter)
            .contentShape(.circle)
            .glassSurface(in: .circle)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// 글자가 있는 캡슐 버튼. 앱의 모든 글자 버튼이 이 한 가지 모양이에요.
/// - `prominent`: 화면의 핵심 동작 하나 (웹의 Primary · 노란 버튼 자리). 강조색 글래스.
/// - `role: .destructive` 버튼은 빨간 글자.
/// - `fullWidth`: 폼 · 카드 폭을 꽉 채워요 (로그인, 새 배포).
struct GlassCapsuleButtonStyle: ButtonStyle {
    var prominent = false
    var fullWidth = false
    var height: CGFloat = 34
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: prominent ? .semibold : .medium))
            .foregroundStyle(foreground(configuration))
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .contentShape(.capsule)
            .modifier(CapsuleSurface(prominent: prominent && isEnabled))
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.45)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }

    private func foreground(_ configuration: Configuration) -> AnyShapeStyle {
        if configuration.role == .destructive { return AnyShapeStyle(.red) }
        if prominent && isEnabled { return AnyShapeStyle(.white) }
        return AnyShapeStyle(.primary)
    }
}

private struct CapsuleSurface: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if prominent {
            if #available(iOS 26, macOS 26, *) {
                content.glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
            } else {
                content.background(Color.accentColor, in: .capsule)
            }
        } else {
            content.glassSurface(in: .capsule)
        }
    }
}

extension ButtonStyle where Self == GlassCircleButtonStyle {
    static var glassCircle: GlassCircleButtonStyle { GlassCircleButtonStyle() }
}

extension ButtonStyle where Self == GlassCapsuleButtonStyle {
    static var glassCapsule: GlassCapsuleButtonStyle { GlassCapsuleButtonStyle() }
    /// 화면의 핵심 동작 하나 (승인하고 배포, 로그인 등).
    static var glassProminent: GlassCapsuleButtonStyle { GlassCapsuleButtonStyle(prominent: true) }
    static func glassCapsule(prominent: Bool = false, fullWidth: Bool = false, height: CGFloat = 34) -> GlassCapsuleButtonStyle {
        GlassCapsuleButtonStyle(prominent: prominent, fullWidth: fullWidth, height: height)
    }
}

/// 캡슐 안의 세그먼트. 고른 칸의 틴트가 스프링으로 미끄러져요 (사이드바와 같은 움직임).
struct GlassSegmented<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        let title: String
        var systemImage: String?
        var id: Value { value }
    }

    @Binding var selection: Value
    let items: [Item]
    @Namespace private var tint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let selected = item.value == selection
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                        selection = item.value
                    }
                } label: {
                    Group {
                        if let systemImage = item.systemImage {
                            Image(systemName: systemImage).accessibilityLabel(item.title)
                        } else {
                            Text(item.title)
                        }
                    }
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background {
                        if selected {
                            Capsule().fill(.fill.secondary)
                                .matchedGeometryEffect(id: "tint", in: tint)
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .glassSurface(in: .capsule)
    }
}
