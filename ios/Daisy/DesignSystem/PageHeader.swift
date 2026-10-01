import SwiftUI

/// 화면 머리줄 (Craft 레퍼런스): 왼쪽 큰 제목, 오른쪽에 그 화면의 글래스 컨트롤.
/// 좁은 화면(iPhone)에서는 컨트롤을 제목 아래 줄로 내려서 설명과 세그먼트가 눌리지 않게 해요.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    private var isCompact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 10) {
                    titles
                    HStack(spacing: 10) {
                        trailing
                        Spacer(minLength: 0)
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    titles
                    Spacer(minLength: 12)
                    trailing
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.semibold))
                SampleBadge()
            }
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

/// 루트 화면 공통 틀: 머리줄 + 본문. 제목은 접근성과 창 제목에도 쓰여요.
struct PageScaffold<Trailing: View, Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
        self.content = content()
    }

    /// 본문은 머리줄 뒤까지 스크롤되고, 머리줄은 뒤가 비치는 반투명 재질(`.ultraThinMaterial`)이에요 (10/1 담당자 결정).
    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                PageHeader(title, subtitle: subtitle) { trailing }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, ignoresSafeAreaEdges: .top)
            }
            .navigationTitle(title)
            .hidesSystemTitleBar()
    }
}
