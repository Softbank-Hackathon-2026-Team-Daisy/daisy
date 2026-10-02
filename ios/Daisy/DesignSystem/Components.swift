import SwiftUI

/// 화면 하나의 불러오기 상태.
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }
}

/// `LoadState`에 따라 진행 표시 · 오류 · 내용을 보여줘요.
struct LoadStateView<Value, Content: View>: View {
    let state: LoadState<Value>
    var retry: (() async -> Void)?
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("불러오지 못했어요", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                if let retry {
                    Button("다시 시도") { Task { await retry() } }
                }
            }
            .emptyStateCentered()
        case .loaded(let value):
            content(value)
        }
    }
}

/// 로그인이 없을 때 (서버 주소는 고정이에요).
struct NotConnectedView: View {
    var body: some View {
        ContentUnavailableView(
            "서버에 연결되지 않았어요",
            systemImage: "network.slash",
            description: Text("다시 로그인해 주세요.")
        )
        .emptyStateCentered()
    }
}

/// 프로젝트를 고르지 않았을 때.
struct NoProjectView: View {
    var body: some View {
        ContentUnavailableView(
            "프로젝트를 골라 주세요",
            systemImage: "folder",
            description: Text("개요 탭 위쪽에서 프로젝트를 선택해요.")
        )
        .emptyStateCentered()
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// 커밋 해시 앞 7자리.
struct CommitLabel: View {
    let commit: String

    var body: some View {
        Text(commit.prefix(7))
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
    }
}

struct EnvironmentIcon: View {
    let type: TargetType

    var body: some View {
        Image(systemName: systemImage)
            .foregroundStyle(.tint)
            .frame(width: 28)
            .accessibilityLabel(type.displayName)
    }

    private var systemImage: String {
        switch type {
        case .onprem: "server.rack"
        case .aws, .gcp, .azure: "cloud"
        case .unknown: "questionmark.circle"
        }
    }
}

/// 5초마다 `body`를 실행해요. 화면이 사라지면 `.task`가 취소되면서 멈춰요 (D2 폴링, SPEC §6-3).
/// `until`이 true가 되면 더 부르지 않아요 — 끝난 배포 · 빌드는 멈춰요 (웹 `useResource`의 `done`, 10/1 웹 결정).
@MainActor
func poll(every seconds: Double = 5, until done: @MainActor () -> Bool = { false },
          _ body: @MainActor () async -> Void) async {
    while !Task.isCancelled {
        await body()
        if done() { return }
        try? await Task.sleep(for: .seconds(seconds))
    }
}

/// 화면 폭에 맞춰 열 수가 바뀌는 그리드. 폰은 1열, iPad · Mac은 여러 열.
struct AdaptiveGrid<Content: View>: View {
    var minimumWidth: CGFloat = 300
    /// 카드가 늘 줄 폭을 다 써요: 열 수를 카드 수의 약수 중 들어가는 가장 큰 값으로 (4장 → 4 · 2 · 1열, 빈 칸 없음). AI 사용량 타일 (10/3)
    var fillsWidth = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        // LazyVGrid는 카드 높이가 나중에 바뀌면(스크립트 로딩 등) 스크롤 높이를 크게 잡아 아래에 빈 공간이 생겨서 (W-05, 10/1)
        // 카드 몇 개뿐인 화면이라 지연 없는 레이아웃으로 그려요.
        AdaptiveColumns(minimumWidth: minimumWidth, spacing: 12, equalRowHeights: Self.equalRowHeights, fillsWidth: fillsWidth) {
            content()
        }
        .environment(\.fillsRowHeight, Self.equalRowHeights)
    }

    /// Mac에서만 한 줄의 카드를 가장 높은 카드 높이로 맞춰요 (10/3 담당자: 글자 길이에 따라 카드 아래가 들쭉날쭉한 것).
    /// iPhone · iPad는 지금처럼 카드마다 제 높이예요
    static var equalRowHeights: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
}

extension EnvironmentValues {
    /// 이 카드가 줄 높이만큼 늘어나도 되는지. `AdaptiveGrid`(Mac)와 `equalCardHeights()`가 바로 아래 카드에만 켜고,
    /// 카드는 제 안쪽에서 다시 꺼요 (카드 안의 카드 · 내용은 늘어나지 않게)
    @Entry var fillsRowHeight = false
}

extension View {
    /// 가로 줄(HStack)의 카드들을 가장 높은 카드 높이로 맞춰요. Mac에서만, 그 밖에는 아무것도 바꾸지 않아요 (개요 "환경별 현재 버전 · 지금 할 일")
    @ViewBuilder
    func equalCardHeights() -> some View {
        #if os(macOS)
        environment(\.fillsRowHeight, true).fixedSize(horizontal: false, vertical: true)
        #else
        self
        #endif
    }
}

/// 폭에 맞춰 열 수를 정하고(최소 폭 이상), 줄마다 가장 큰 카드 높이로 위 정렬해요.
/// `equalRowHeights`면 놓을 때 그 줄 높이를 같이 제안해서, 늘어날 수 있는 카드(`fillsRowHeight`)가 줄 높이를 채워요.
/// 줄 높이는 늘 높이 제안 없이(nil) 잰 값이라 켜도 줄 높이 · 전체 높이는 그대로예요
private struct AdaptiveColumns: Layout {
    let minimumWidth: CGFloat
    let spacing: CGFloat
    var equalRowHeights = false
    var fillsWidth = false

    private func columns(for width: CGFloat) -> Int {
        max(1, Int((width + spacing) / (minimumWidth + spacing)))
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> (columnWidth: CGFloat, heights: [CGFloat], count: Int) {
        let fit = columns(for: width)
        let count = fillsWidth && !subviews.isEmpty
            ? (1...min(fit, subviews.count)).last { subviews.count % $0 == 0 } ?? 1
            : fit
        let columnWidth = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        let proposal = ProposedViewSize(width: columnWidth, height: nil)
        let heights = stride(from: 0, to: subviews.count, by: count).map { start in
            subviews[start..<min(start + count, subviews.count)].map { $0.sizeThatFits(proposal).height }.max() ?? 0
        }
        return (columnWidth, heights, count)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minimumWidth
        let layout = rows(subviews, width: width)
        let height = layout.heights.reduce(0, +) + spacing * CGFloat(max(0, layout.heights.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = rows(subviews, width: bounds.width)
        var y = bounds.minY
        for (row, height) in layout.heights.enumerated() {
            for column in 0..<layout.count {
                let index = row * layout.count + column
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(column) * (layout.columnWidth + spacing)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: layout.columnWidth, height: equalRowHeights ? height : nil))
            }
            y += height + spacing
        }
    }
}

extension View {
    /// "아무것도 없음" 안내(심볼 + 문구)는 어디에 놓여도 늘 좌우 가운데예요 (10/3 담당자). 카드 안처럼 왼쪽 정렬 줄에 있어도요
    func emptyStateCentered() -> some View {
        frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
    }

    /// 카드 (AfterPlan 카드 모양): 모서리 12, 옅은 면, 가는 선. 포인터가 올라가면 조금 진해져요.
    func cardStyle() -> some View { modifier(CardStyle()) }
}

private struct CardStyle: ViewModifier {
    @State private var hovered = false
    @Environment(\.fillsRowHeight) private var fillsRowHeight

    func body(content: Content) -> some View {
        content
            .environment(\.fillsRowHeight, false)
            .padding(14)
            .modifier(RowHeightFill(active: fillsRowHeight))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.fill.quaternary),
                        in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

/// 줄 높이 채우기: 내용은 제 높이 그대로(위 정렬) 두고 카드 면만 제안받은 높이까지 늘려요. 꺼져 있으면 아무것도 하지 않아요
private struct RowHeightFill: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: .infinity, alignment: .top)
        } else {
            content
        }
    }
}
