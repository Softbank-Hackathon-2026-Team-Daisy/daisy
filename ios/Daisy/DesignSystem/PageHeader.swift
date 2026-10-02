import SwiftUI

/// 화면 머리줄 (Craft 레퍼런스): 왼쪽 제목 한 줄, 오른쪽 위에 그 화면의 글래스 컨트롤.
/// 설명은 머리줄에 늘어놓지 않고 제목을 누르면 아래쪽 말풍선으로 보여줘요 (10/3 담당자 결정, 앱만).
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
            HeaderTitle(title, info: subtitle)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

/// 머리줄 제목. 설명이 있으면 누를 때 제목 아래 말풍선으로 떠요. 제목은 줄이지 않아요 (옆 컨트롤이 줄어요)
struct HeaderTitle: View {
    let title: String
    var info: String?
    /// 말풍선 첫 줄 (배포 흐름: 지금 단계 이름)
    var infoTitle: String?
    @State private var showsInfo = false

    init(_ title: String, info: String? = nil, infoTitle: String? = nil) {
        self.title = title
        self.info = info?.isEmpty == true ? nil : info
        self.infoTitle = infoTitle
    }

    var body: some View {
        HStack(spacing: 8) {
            if info != nil || infoTitle != nil {
                Button { showsInfo.toggle() } label: { label }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("설명 보기"))
                    .popover(isPresented: $showsInfo, arrowEdge: .top) { bubble }
            } else {
                label
            }
            SampleBadge()  // SAMPLE-MODE
        }
        .fixedSize()
        .layoutPriority(1)
    }

    private var label: some View {
        Text(title).font(.title2.weight(.semibold)).lineLimit(1)
    }

    private var bubble: some View {
        // 말풍선 폭을 정해 줘야 긴 설명이 한 줄로 늘어나지 않고 줄바꿈돼요
        VStack(alignment: .leading, spacing: 6) {
            if let infoTitle { Text(infoTitle).font(.headline) }
            if let info { Text(info).font(.callout).foregroundStyle(.secondary) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 280, alignment: .leading)
        .padding(16)
        .presentationCompactAdaptation(.popover)
    }
}

/// 펼침 버튼 목록의 한 줄
struct ExpandingMenuOption: Identifiable {
    let id: String
    let title: String
    var systemImage: String?
    var isSelected = false
    var isDisabled = false
    /// 이 줄 위에 구분선
    var separated = false
    let action: () -> Void
}

/// 평소엔 새로 고침과 같은 크기의 동그란 아이콘 버튼이에요. 한 번 누르면 좌우로 펼쳐져 지금 고른 이름을 보여주고,
/// 펼친 채로 한 번 더 누르면 목록이 떠요. 이름은 머리줄에 남는 폭만큼만 보이고(…) 아래 화살표는 늘 보여요 (10/3)
/// 다시 접히는 때 (10/3 담당자): 펼친 채 2초 동안 아무것도 안 하면, 목록이 닫히면 바로, Mac은 포인터가 벗어나면 바로.
/// 목록이 열려 있는 동안에는 접지 않아요 (Mac은 포인터가 올라가 있는 동안 2초 타이머도 멈춰요).
/// 목록은 버튼에 붙은 말풍선이에요. 시스템 메뉴는 버튼 모양을 바꾸면 같이 닫혀서 쓰지 않아요.
struct ExpandingMenuButton: View {
    let systemImage: String
    let title: String
    @Binding var isExpanded: Bool
    let options: [ExpandingMenuOption]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var showsList = false
    @State private var collapseTask: Task<Void, Never>?

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                if isExpanded {
                    Text(title).lineLimit(1).truncationMode(.tail)
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                }
            }
            .font(.system(size: isExpanded ? 13 : 15, weight: .medium))
            .padding(.horizontal, isExpanded ? 14 : 0)
            .frame(minWidth: 34, minHeight: 34, maxHeight: 34)
            .contentShape(.capsule)
            .glassSurface(in: .capsule)
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .popover(isPresented: $showsList, arrowEdge: .top) { list }
        .onChange(of: showsList) { _, shown in
            if !shown { setExpanded(false) }
        }
        #if os(macOS)
        .onHover { inside in
            if inside {
                collapseTask?.cancel()
            } else if isExpanded && !showsList {
                setExpanded(false)
            }
        }
        #endif
        .onDisappear { collapseTask?.cancel() }
    }

    private func tap() {
        if isExpanded {
            collapseTask?.cancel()
            showsList = true
        } else {
            setExpanded(true)
            collapseTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                setExpanded(false)
            }
        }
    }

    private func setExpanded(_ value: Bool) {
        collapseTask?.cancel()
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) { isExpanded = value }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(options) { option in
                    if option.separated { Divider().padding(.vertical, 4) }
                    Button {
                        showsList = false
                        option.action()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark").font(.caption.weight(.semibold))
                                .opacity(option.isSelected ? 1 : 0)
                            if let image = option.systemImage { Image(systemName: image) }
                            Text(option.title).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(option.isDisabled)
                    .opacity(option.isDisabled ? 0.45 : 1)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(minWidth: 240, maxHeight: 420)
        .fixedSize(horizontal: false, vertical: options.count < 9)
        .presentationCompactAdaptation(.popover)
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
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .pinnedHeader { PageHeader(title, subtitle: subtitle) { trailing } }
            .navigationTitle(title)
            .hidesSystemTitleBar()
    }
}

extension View {
    /// 화면 위 머리줄.
    /// - iOS: 본문이 머리줄 뒤까지 스크롤되고, 머리줄은 뒤가 비치는 반투명 재질(`.ultraThinMaterial`)이에요 (10/1).
    /// - macOS: 머리줄을 본문 위에 그냥 얹어요. 재질 띠가 창 툴바까지 덮어 내비게이션 바처럼 보이지 않게 (10/1 담당자 결정).
    func pinnedHeader<Header: View>(@ViewBuilder _ header: () -> Header) -> some View {
        modifier(PinnedHeader(header: header()))
    }
}

private struct PinnedHeader<Header: View>: ViewModifier {
    let header: Header

    func body(content: Content) -> some View {
        #if os(iOS)
        content.safeAreaInset(edge: .top, spacing: 0) {
            header
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, ignoresSafeAreaEdges: .top)
        }
        #else
        VStack(spacing: 0) {
            header.frame(maxWidth: .infinity, alignment: .leading)
            content
        }
        #endif
    }
}
