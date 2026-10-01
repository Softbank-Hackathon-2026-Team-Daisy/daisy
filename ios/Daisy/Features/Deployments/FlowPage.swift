import SwiftUI

/// 배포 흐름 화면(W-02 ~ W-08) 공통 틀: 스텝퍼 → 제목 → 설명 → 내용.
/// 웹은 화면 ID overline(`W-06 · STEP 5`)을 두지만 와이어프레임 표식이라 앱에는 넣지 않아요.
struct FlowPage<Content: View, Bottom: View>: View {
    let step: Int
    let title: String
    let description: String
    @ViewBuilder var content: Content
    @ViewBuilder var bottom: Bottom

    init(step: Int, title: String, description: String,
         @ViewBuilder content: () -> Content,
         @ViewBuilder bottom: () -> Bottom = { EmptyView() }) {
        self.step = step
        self.title = title
        self.description = description
        self.content = content()
        self.bottom = bottom()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FlowStepper(current: step)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(.title2.weight(.semibold))
                        SampleBadge()
                    }
                    Text(description).font(.callout).foregroundStyle(.secondary)
                }
                content
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottom }
        .flowNavigationTitle(title)
    }
}

/// 흐름 화면 아래쪽 버튼 줄 (웹: 왼쪽 정렬 버튼 줄)
struct FlowButtons<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
            content
            Spacer(minLength: 0)
        }
    }
}

/// 환경 이름을 탭처럼 고르는 캡슐 (웹 Tabs: 온프레미스 · AWS · GCP)
struct EnvironmentTabs: View {
    @Binding var selection: String?
    let targetIDs: [String]
    @Environment(Workspace.self) private var workspace

    var body: some View {
        if targetIDs.count > 1 {
            GlassSegmented(selection: Binding(
                get: { selection ?? targetIDs.first ?? "" },
                set: { selection = $0 }
            ), items: targetIDs.map { .init(value: $0, title: workspace.name(of: $0)) })
        }
    }
}
