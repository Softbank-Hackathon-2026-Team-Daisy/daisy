import SwiftUI
import CoreImage.CIFilterBuiltins
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// 웹 디자인 시스템 컴포넌트의 문구 · 역할을 앱 모양(카드 · 글래스 · 시스템 색)으로 옮긴 것.
// 이름은 Figma 컴포넌트 이름과 같게 (Status Badge → StatusBadge, Env Tag → EnvTag).

// MARK: - 카드 (제목 + 오른쪽 컨트롤)

/// 제목이 있는 카드. 웹 화면의 "환경별 현재 버전", "지금 할 일" 같은 상자예요.
struct SectionCard<Trailing: View, Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(_ title: String, subtitle: String? = nil,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                trailing
            }
            content
        }
        .cardStyle()
    }
}

// MARK: - 환경 태그 · 아바타

struct EnvTag: View {
    let type: TargetType
    /// 앱이 아직 모르는 환경 이름
    var label: String? = nil

    var body: some View {
        Label(label ?? type.displayName, systemImage: label == nil ? type.systemImage : "cloud")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.fill.tertiary, in: .capsule)
            .fixedSize()
    }
}

extension TargetType {
    /// 웹 아이콘과 비슷한 SF Symbols: server → server.rack, cloud → cloud
    var systemImage: String {
        switch self {
        case .onprem: "server.rack"
        case .aws, .gcp, .azure: "cloud"
        case .unknown: "questionmark.circle"
        }
    }

    /// 로그 출처 이름 (웹 Log Viewer: onprem · aws · gcp)
    var logSource: String {
        switch self {
        case .onprem: "onprem"
        case .aws: "aws"
        case .gcp: "gcp"
        case .azure: "azure"
        case .unknown: "?"
        }
    }
}

/// 배포자 표시 (웹 Avatar: 이름 첫 글자).
struct Avatar: View {
    let name: String?

    var body: some View {
        Text(name.flatMap { $0.first.map(String.init) } ?? "?")
            .font(.caption2.weight(.semibold))
            .frame(width: 22, height: 22)
            .background(.fill.secondary, in: .circle)
            .accessibilityLabel(name ?? String.app("알 수 없음"))
    }
}

// MARK: - 스텝퍼 (배포 흐름 공통)

/// 웹 Stepper: 저장소 연결 · 이미지 빌드 · 대상 환경 · 생성 · 검증 · 승인 · 배포 · 결과. 표시 전용이에요.
struct FlowStepper: View {
    /// 고른 언어로 그때그때 만들어요 (설정에서 언어를 바꾸면 바로 바뀌게)
    static var labels: [String] {
        [.app("저장소 연결"), .app("이미지 빌드"), .app("대상 환경"), .app("생성 · 검증"), .app("승인 · 배포"), .app("결과")]
    }
    /// 1부터 6
    let current: Int

    var body: some View {
        // 좁은 화면에서도 지금 단계가 보이게 가운데로 스크롤해요
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(Self.labels.enumerated()), id: \.offset) { index, label in
                    let step = index + 1
                    if index > 0 {
                        Capsule()
                            .fill(step <= current ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary))
                            .frame(width: 24, height: 2)
                    }
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().fill(step < current ? AnyShapeStyle(.tint)
                                          : step == current ? AnyShapeStyle(.tint.opacity(0.18))
                                          : AnyShapeStyle(.fill.tertiary))
                            if step < current {
                                Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(.white)
                            } else {
                                Text("\(step)").font(.caption2.weight(.semibold))
                                    .foregroundStyle(step == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            }
                        }
                        .frame(width: 22, height: 22)
                        Text(label)
                            .font(.caption.weight(step == current ? .semibold : .regular))
                            .foregroundStyle(step > current ? .secondary : .primary)
                    }
                    .id(step)
                }
            }
            .padding(.vertical, 2)
        }
        // 가로 스크롤은 iPhone 탭 바용 아래 여백(contentMargins)을 받지 않아요
        .contentMargins(.vertical, 0, for: .scrollContent)
        .onAppear { proxy.scrollTo(current, anchor: .center) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.labels.count)단계 중 \(current)단계 \(Self.labels[max(0, min(current, 6) - 1)])")
    }
}

// MARK: - 단계 한 줄 (Step Item)

struct StepItemRow: View {
    let name: String
    let state: StepState
    var durationMs: Int?
    var startedAt: Date?

    init(_ item: StepItem) {
        name = item.name
        state = item.state
        durationMs = item.durationMs
        startedAt = item.startedAt
    }

    init(name: String, state: StepState, durationMs: Int? = nil) {
        self.name = name
        self.state = state
        self.durationMs = durationMs
    }

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 18)
            Text(name).font(.subheadline)
            Spacer(minLength: 8)
            timeText.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(minHeight: 28)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .running: ProgressView().controlSize(.small)
        case .waiting, .unknown: Image(systemName: "clock").foregroundStyle(.secondary)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var timeText: some View {
        switch state {
        case .running:
            if let startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Duration.seconds(context.date.timeIntervalSince(startedAt)).daisyText + "…")
                }
            } else {
                Text("…")
            }
        case .waiting, .unknown:
            Text("—")
        case .skipped:
            Text("건너뜀")
        case .done, .failed:
            Text(durationMs.map { Duration.milliseconds($0).daisyText } ?? "—")
        }
    }
}

extension Duration {
    /// 웹 표기: "42s", "1m 03s"
    var daisyText: String {
        let total = max(0, Int(components.seconds))
        if total < 60 { return "\(total)s" }
        return "\(total / 60)m " + String(format: "%02ds", total % 60)
    }
}

// MARK: - 정보 줄 (Info Row)

struct InfoRow: View {
    let key: String
    let value: String?
    var monospaced = false

    init(_ key: String, _ value: String?, monospaced: Bool = false) {
        self.key = key
        self.value = value
        self.monospaced = monospaced
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key).font(.subheadline).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            // 값이 없으면 "—" (웹과 같아요). 팀이 아직 안 정한 칸은 화면이 "[미정]"을 직접 넘겨요
            Text(value ?? "—")
                .font(monospaced ? .subheadline.monospaced() : .subheadline)
                .foregroundStyle(value == nil ? .secondary : .primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 알림 상자 (Alert)

struct InlineAlert: View {
    enum Kind { case info, success, warning, danger }

    let kind: Kind
    let title: String
    var message: String?

    init(_ kind: Kind, _ title: String, _ message: String? = nil) {
        self.kind = kind
        self.title = title
        self.message = message
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                if let message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.1), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch kind {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .info: .blue
        case .success: .green
        case .warning: .orange
        case .danger: .red
        }
    }
}

// MARK: - 토스트 (Toast)

struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let kind: InlineAlert.Kind
    let title: String
    var message: String?
}

extension View {
    /// 화면 아래에 3초 동안 떠 있다가 사라지는 알림. 닫기 버튼도 있어요.
    func toast(_ message: Binding<ToastMessage?>) -> some View {
        overlay(alignment: .bottom) {
            if let toast = message.wrappedValue {
                HStack(alignment: .top) {
                    InlineAlert(toast.kind, toast.title, toast.message)
                    Button {
                        message.wrappedValue = nil
                    } label: {
                        Label("닫기", systemImage: "xmark")
                    }
                    .buttonStyle(GlassCircleButtonStyle(diameter: 28))
                }
                .padding(8)
                .glassSurface(in: .rect(cornerRadius: 16))
                .frame(maxWidth: 420)
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(3))
                    if message.wrappedValue?.id == toast.id { message.wrappedValue = nil }
                }
            }
        }
        .animation(.snappy, value: message.wrappedValue)
    }
}

// MARK: - 코드 블록 (Code Block)

enum Clipboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

struct CodeBlock: View {
    let header: String
    var aiGenerated = false
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if aiGenerated {
                    Text("AI").font(.caption2.weight(.bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.tint.opacity(0.18), in: .capsule)
                }
                Text(header).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Button {
                    Clipboard.copy(code)
                    copied = true
                } label: {
                    Label(copied ? "복사했어요" : "복사", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(GlassCircleButtonStyle(diameter: 28))
                .help("복사")
            }
            .padding(10)
            Divider()
            ScrollView(.horizontal) {
                Text(code)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding(12)
            }
            .contentMargins(.vertical, 0, for: .scrollContent)
            // 가로 ScrollView는 세로로 늘어나요. 그리드 안에서 화면보다 길게 늘어나 빈 공간이 생겨서 코드 높이로 고정해요 (W-05)
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(.fill.quaternary, in: .rect(cornerRadius: 10))
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

// MARK: - 리소스 변경 행 (Resource Diff Row)

struct ResourceDiffRow: View {
    let resource: PlanResource

    var body: some View {
        HStack(spacing: 10) {
            Text(symbol).font(.body.monospaced().weight(.bold)).foregroundStyle(color).frame(width: 16)
            Text(resource.address).font(.subheadline.monospaced()).lineLimit(1)
            Spacer(minLength: 8)
            if let cost = resource.monthlyCostKrw {
                Text(cost == 0 ? "₩0" : "\(cost > 0 ? "+" : "\u{2212}")₩\(abs(cost).appFormatted)/월")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 28)
    }

    private var symbol: String {
        switch resource.action {
        case .create: "+"
        case .update: "~"
        case .delete: "\u{2212}"
        case .replace: "\u{00B1}"
        case .unknown: "?"
        }
    }

    private var color: Color {
        switch resource.action {
        case .create: .green
        case .update: .orange
        case .delete: .red
        case .replace: .purple
        case .unknown: .secondary
        }
    }
}

// MARK: - 동일성 검증 표 (Parity Table)

struct ParityTable: View {
    let parity: Parity
    let targets: [TargetType]

    static func label(_ key: String) -> String {
        switch key {
        case "digest": .app("이미지 digest")
        case "commit": .app("커밋")
        case "version": .app("앱 버전")
        case "health": .app("헬스체크")
        default: key
        }
    }

    var body: some View {
        SectionCard(.app("동일성 검증"), subtitle: .app("모든 환경이 같은 상태인지 비교해요")) {
            Label("\(parity.matching)/\(parity.total) 일치",
                  systemImage: parity.matching == parity.total ? "checkmark.circle" : "exclamationmark.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(parity.matching == parity.total ? .green : .orange)
        } content: {
            // 넓으면 표, 좁으면 항목별 목록 (도영 님 메모: 좁은 화면은 목록으로)
            ViewThatFits(in: .horizontal) {
                grid.frame(minWidth: 560)
                list
            }
        }
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                Text("항목")
                ForEach(Array(targets.enumerated()), id: \.offset) { _, type in Text(type.displayName) }
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Divider()
            ForEach(parity.rows) { row in
                GridRow {
                    Text(Self.label(row.key)).font(.subheadline)
                    ForEach(row.cells, id: \.self) { cell($0) }
                }
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parity.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.label(row.key)).font(.subheadline.weight(.medium))
                    ForEach(Array(zip(targets, row.cells)), id: \.1) { type, cellValue in
                        HStack { Text(type.displayName).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading); cell(cellValue) }
                    }
                }
            }
        }
    }

    private func cell(_ cell: Parity.Row.Cell) -> some View {
        Label {
            Text(cell.value ?? "—").font(.caption.monospaced())
        } icon: {
            if cell.failed {
                Image(systemName: "xmark.circle").foregroundStyle(.red)
            } else if cell.value != nil {
                Image(systemName: "checkmark.circle").foregroundStyle(.green)
            }
        }
    }
}

// MARK: - 실행 한 줄 (Run List Item)

struct RunListItem: View {
    let deployment: Deployment
    /// 화면마다 다른 라벨 (개요 "배포 완료" · "중단"). 없으면 배포 상태
    var badge: StatusBadge? = nil

    var body: some View {
        HStack(spacing: 10) {
            badge ?? deployment.badge
            CommitLabel(commit: deployment.commit)
            Text(deployment.commitMessage ?? "").font(.subheadline).lineLimit(1)
            Spacer(minLength: 8)
            Avatar(name: deployment.createdBy)
            if let createdAt = deployment.createdAt {
                RelativeTime(date: createdAt).font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }
}

/// 웹 시각 표기: "방금", "12분 전", "어제".
struct RelativeTime: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(TimeText.relative(date, now: context.date))
        }
    }
}

// MARK: - 연결 표시 (Connection Indicator)

/// `polling`: 실시간(SSE) 전, 5초 폴링 중이에요 (웹과 같아요. 실시간 연결로 보이지 않게)
enum ConnectionState: Equatable {
    case connected, polling, reconnecting, disconnected
}

struct ConnectionIndicator: View {
    let state: ConnectionState
    var retry: (() -> Void)?
    /// 글자 없이 심볼만 (사이드바 계정 줄 오른쪽 끝, 10/3). 글자는 도움말 · 손쉬운 사용으로 남아요
    var iconOnly = false

    var body: some View {
        if iconOnly {
            indicator.labelStyle(.iconOnly).help(helpText)
        } else {
            indicator
        }
    }

    private var helpText: String {
        switch state {
        case .connected: .app("실시간 연결됨")
        case .polling: .app("5초마다 새로고침")
        case .reconnecting: .app("재연결 중…")
        case .disconnected: .app("연결 끊김 · 다시 시도")
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch state {
        case .connected:
            Label("실시간 연결됨", systemImage: "cellularbars").foregroundStyle(.green).font(.caption.weight(.medium))
        case .polling:
            Label("5초마다 새로고침", systemImage: "arrow.clockwise").foregroundStyle(.secondary).font(.caption.weight(.medium))
        case .reconnecting:
            Label("재연결 중…", systemImage: "cellularbars").foregroundStyle(.orange).font(.caption.weight(.medium))
        case .disconnected:
            Button {
                retry?()
            } label: {
                Label("연결 끊김 · 다시 시도", systemImage: "cellularbars")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .font(.caption.weight(.medium))
        }
    }
}

// MARK: - QR

struct QRCodeImage: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("QR 코드")
        } else {
            Image(systemName: "qrcode").resizable().scaledToFit().foregroundStyle(.secondary)
        }
    }

    static func render(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
