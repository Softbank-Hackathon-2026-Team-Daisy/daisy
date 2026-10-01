import SwiftUI

extension EnvironmentValues {
    /// MOCK: 예시 데이터로 둘러보는 중인지. 켜지면 화면마다 `SampleBadge`가 떠요.
    @Entry var isSampleData = false
}

/// "예시 데이터" 배지. 목업은 숨기지 않아요 (루트 AGENTS.md §4-6).
struct SampleBadge: View {
    @Environment(\.isSampleData) private var isSampleData

    var body: some View {
        if isSampleData {
            Label("예시 데이터", systemImage: "shippingbox")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.orange.opacity(0.15), in: .capsule)
                .accessibilityLabel("예시 데이터로 보는 중이에요")
                .help("서버 없이 앱에 들어 있는 예시 데이터를 보여주고 있어요. 바꾸는 동작은 막혀 있어요.")
        }
    }
}
