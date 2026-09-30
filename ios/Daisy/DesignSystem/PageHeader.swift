import SwiftUI

/// 화면 머리줄 (Craft 레퍼런스): 왼쪽 큰 제목, 오른쪽에 그 화면의 글래스 컨트롤.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
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
