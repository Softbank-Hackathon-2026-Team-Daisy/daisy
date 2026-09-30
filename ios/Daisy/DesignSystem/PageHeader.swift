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
            Text(title)
                .font(.title2.weight(.semibold))
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

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title, subtitle: subtitle) { trailing }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(title)
        .hidesSystemTitleBar()
    }
}
