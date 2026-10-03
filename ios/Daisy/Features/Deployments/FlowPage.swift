import SwiftUI

/// 배포 흐름 화면(W-02 ~ W-08) 공통 틀: 제목 "배포" · 단계 표시 → 내용. 지금 단계 이름과 설명은 제목 말풍선에 있어요 (10/3).
/// 웹은 화면 ID overline(`W-06 · STEP 5`)을 두지만 와이어프레임 표식이라 앱에는 넣지 않아요.
struct FlowPage<Content: View, Bottom: View>: View {
    let step: Int
    let title: String
    let description: String
    @ViewBuilder var content: Content
    @ViewBuilder var bottom: Bottom
    @Environment(\.tabBarClearance) private var tabBarClearance
    @Environment(\.flowHeaderAccessory) private var flowHeaderAccessory
    @Environment(\.flowRefreshIssue) private var flowRefreshIssue

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

    /// 머리줄: 제목 "배포"(누르면 지금 단계 이름 · 설명 말풍선)와 오른쪽 위 버튼(iPhone "새 배포") 한 줄, 그 아래 단계 표시 (10/3)
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                HeaderTitle(.app(LocalizedStringResource("flow.title", defaultValue: "배포")), info: description, infoTitle: title)
                Spacer(minLength: 8)
                if let flowHeaderAccessory { flowHeaderAccessory }
            }
            FlowStepper(current: step)
            if let flowRefreshIssue { StaleNotice(issue: flowRefreshIssue) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

extension EnvironmentValues {
    /// 배포 흐름 머리줄 오른쪽 위에 둘 버튼 (iPhone 배포 탭의 "새 배포")
    @Entry var flowHeaderAccessory: AnyView? = nil
    /// 처음 불러온 뒤 다시 받기에 실패했어요. 머리줄 아래에 작게 알리고, 화면은 마지막으로 받은 값을 보여줘요 (D15)
    @Entry var flowRefreshIssue: FlowRefreshIssue? = nil
}

/// 다시 받기 실패 (D15): 서버 오류 문구 + 다시 시도
struct FlowRefreshIssue: Equatable {
    let message: String
    let retry: @MainActor () async -> Void

    /// 문구로만 비교해요 (다시 그릴 때마다 아래 화면을 무효화하지 않게)
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.message == rhs.message }
}

/// "최신 상태를 받지 못했어요 · 다시 시도" 한 줄. 마지막으로 받은 값이 오래됐을 수 있다는 표시예요 (D15)
struct StaleNotice: View {
    let issue: FlowRefreshIssue
    @State private var retrying = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath").foregroundStyle(.orange)
            Text("최신 상태를 받지 못했어요").foregroundStyle(.secondary)
            Button(retrying ? "다시 받는 중…" : "다시 시도") {
                Task {
                    retrying = true
                    await issue.retry()
                    retrying = false
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(retrying)
        }
        .font(.caption)
        .help(issue.message)
        .accessibilityElement(children: .combine)
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
