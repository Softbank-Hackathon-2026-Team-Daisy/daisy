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

/// 글자가 있는 캡슐 버튼 (프로젝트 고르기, 필터 메뉴).
struct GlassCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .contentShape(.capsule)
            .glassSurface(in: .capsule)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == GlassCircleButtonStyle {
    static var glassCircle: GlassCircleButtonStyle { GlassCircleButtonStyle() }
}

extension ButtonStyle where Self == GlassCapsuleButtonStyle {
    static var glassCapsule: GlassCapsuleButtonStyle { GlassCapsuleButtonStyle() }
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
