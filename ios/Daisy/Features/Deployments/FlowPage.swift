import SwiftUI

/// 배포 흐름 화면(W-02 ~ W-08) 공통 틀: 스텝퍼 → 제목 → 설명 → 내용.
/// 웹은 화면 ID overline(`W-06 · STEP 5`)을 두지만 와이어프레임 표식이라 앱에는 넣지 않아요.
struct FlowPage<Content: View, Bottom: View>: View {
    let step: Int
    let title: String
    let description: String
    @ViewBuilder var content: Content
    @ViewBuilder var bottom: Bottom
    @Environment(\.tabBarClearance) private var tabBarClearance

    init(step: Int, title: String, description: String,
         @ViewBuilder content: () -> Content,
         @ViewBuilder bottom: () -> Bottom = { EmptyView() }) {
        self.step = step
        self.title = title
        self.description = description
        self.content = content()
        self.bottom = bottom()
    }

    /// 단계 표시 · 제목 · 설명은 위쪽 머리줄(`pinnedHeader`, 루트 화면과 같아요: iOS 반투명 · macOS 재질 없음)에 두고, 본문만 스크롤돼요 (10/1)
    var body: some View {
        scroll
            .pinnedHeader { header }
            .flowNavigationTitle(title)
    }

    /// 아래 고정 줄(W-06 승인 바)이 있을 때만 아래 inset을 둬요.
    /// 빈 `EmptyView`를 inset에 넣으면 남은 높이를 다 차지해서 스크롤 끝에 화면만큼 빈 공간이 생겼어요 (W-05, 10/1)
    @ViewBuilder
    private var scroll: some View {
        let page = ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(20)
        }
        if Bottom.self == EmptyView.self {
            page
        } else {
            page.safeAreaInset(edge: .bottom, spacing: 0) { bottom.padding(.bottom, tabBarClearance) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowStepper(current: step)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title).font(.title2.weight(.semibold))
                    SampleBadge()  // SAMPLE-MODE
                }
                if !description.isEmpty {
                    Text(description).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
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
