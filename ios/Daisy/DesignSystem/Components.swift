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
        case .loaded(let value):
            content(value)
        }
    }
}

/// 서버 주소나 로그인이 없을 때.
struct NotConnectedView: View {
    var body: some View {
        ContentUnavailableView(
            "서버에 연결되지 않았어요",
            systemImage: "network.slash",
            description: Text("설정 탭에서 서버 주소를 넣고 로그인해 주세요.")
        )
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
        case .aws, .gcp: "cloud"
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
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: 12, alignment: .top)],
            alignment: .leading,
            spacing: 12
        ) {
            content()
        }
    }
}

extension View {
    /// 카드 (AfterPlan 카드 모양): 모서리 12, 옅은 면, 가는 선. 포인터가 올라가면 조금 진해져요.
    func cardStyle() -> some View { modifier(CardStyle()) }
}

private struct CardStyle: ViewModifier {
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.fill.quaternary),
                        in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
