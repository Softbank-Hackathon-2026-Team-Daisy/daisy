import SwiftUI

/// 웹 L-01 · L-02 · L-03 전환 로딩: 쌓이는 인프라 블록 + "잠시만 기다려주세요" + 돌아가는 문구.
/// - 첫 문구는 화면별 고정, 그다음 01→10을 3.5초마다 (200ms 페이드 + 위로 4pt).
/// - 동작 줄이기면 블록 3개로 멈추고 문구도 돌리지 않아요.
/// - VoiceOver는 돌아가는 문구를 읽지 않고 단계만 알려요.
struct TransitionLoader: View {
    enum Stage {
        case repository, generate, deploy

        var firstCaption: String {
            switch self {
            case .repository: .app("저장소를 연결하고 있어요")
            case .generate: TransitionLoader.captions[0]
            case .deploy: .app("승인된 plan으로 배포를 준비하고 있어요")
            }
        }

        var meta: String {
            switch self {
            case .repository: "STEP 1 · REPO"
            case .generate: "STEP 4"
            case .deploy: "STEP 5"
            }
        }

        var step: Int {
            switch self {
            case .repository: 1
            case .generate: 4
            case .deploy: 5
            }
        }
    }

    nonisolated static var captions: [String] {
        [
            .app("AI가 환경별 인프라 코드를 만들고 있어요"),
            .app("deploy.yaml을 읽고 필요한 리소스를 고르고 있어요"),
            .app("terraform validate로 문법을 확인하고 있어요"),
            .app("terraform plan으로 바뀔 리소스를 계산하고 있어요"),
            .app("보안 그룹이 전체 공개되지 않았는지 살펴보고 있어요"),
            .app("오류가 나면 AI가 로그를 읽고 최대 3번까지 고쳐요"),
            .app("검증된 스크립트가 있으면 이미지 태그만 바꿔 재사용해요"),
            .app("모든 환경에 같은 커밋 해시 이미지가 올라가요"),
            .app("환경마다 state를 따로 보관해서 서로 부딪히지 않아요"),
            .app("인프라는 네트워크부터 한 층씩 쌓여요"),
        ]
    }

    let stage: Stage
    /// 선택한 환경 수. 있으면 Meta에 "· 3 ENVS"를 붙여요.
    var environments: Int?
    @State private var captionIndex = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            InfraBlock(animated: !reduceMotion)
                .frame(width: 172, height: 196)
            Text("잠시만 기다려주세요").font(.title3.weight(.semibold))
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .id(captionIndex)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 4)), removal: .opacity))
                .frame(height: 20)
                .accessibilityHidden(true)
            Text(stage.meta + (environments.map { " · \($0) ENVS" } ?? ""))
                .font(.caption2.monospaced().weight(.medium))
                .tracking(1)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("잠시만 기다려주세요. \(FlowStepper.labels[stage.step - 1]) 단계예요.")
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.5))
                withAnimation(.easeOut(duration: 0.2)) { captionIndex = (captionIndex + 1) % Self.captions.count }
            }
        }
    }

    private var caption: String {
        captionIndex < 0 ? stage.firstCaption : Self.captions[captionIndex]
    }
}

/// 고정된 땅 위로 같은 크기 블록 3개가 하나씩 내려앉았다가 한꺼번에 사라지기를 반복해요 (2:1 아이소메트릭).
struct InfraBlock: View {
    var animated = true
    @State private var stack = 3

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let tileW = w * 0.8
            let tileH = tileW / 2
            let blockH = tileH * 0.55
            let baseY = size.height - tileH / 2 - 4
            let centerX = w / 2
            // 땅
            drawSlab(in: &context, center: CGPoint(x: centerX, y: baseY), width: w * 0.95, depth: 6, alpha: 0.35)
            for level in 0..<stack {
                let y = baseY - 6 - CGFloat(level) * blockH
                drawBlock(in: &context, center: CGPoint(x: centerX, y: y), tileW: tileW, height: blockH)
            }
        }
        .task {
            guard animated else { stack = 3; return }
            while !Task.isCancelled {
                stack = 0
                for level in 1...3 {
                    try? await Task.sleep(for: .milliseconds(450))
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { stack = level }
                }
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(.easeOut(duration: 0.2)) { stack = 0 }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        .accessibilityHidden(true)
    }

    private func drawSlab(in context: inout GraphicsContext, center: CGPoint, width: CGFloat, depth: CGFloat, alpha: Double) {
        let h = width / 2
        var top = Path()
        top.move(to: CGPoint(x: center.x, y: center.y - h / 2))
        top.addLine(to: CGPoint(x: center.x + width / 2, y: center.y))
        top.addLine(to: CGPoint(x: center.x, y: center.y + h / 2))
        top.addLine(to: CGPoint(x: center.x - width / 2, y: center.y))
        top.closeSubpath()
        context.fill(top, with: .color(.secondary.opacity(alpha)))
    }

    private func drawBlock(in context: inout GraphicsContext, center: CGPoint, tileW: CGFloat, height: CGFloat) {
        let hw = tileW / 2
        let hh = tileW / 4
        let topCenter = CGPoint(x: center.x, y: center.y - height)
        var top = Path()
        top.move(to: CGPoint(x: topCenter.x, y: topCenter.y - hh))
        top.addLine(to: CGPoint(x: topCenter.x + hw, y: topCenter.y))
        top.addLine(to: CGPoint(x: topCenter.x, y: topCenter.y + hh))
        top.addLine(to: CGPoint(x: topCenter.x - hw, y: topCenter.y))
        top.closeSubpath()
        var left = Path()
        left.move(to: CGPoint(x: topCenter.x - hw, y: topCenter.y))
        left.addLine(to: CGPoint(x: topCenter.x, y: topCenter.y + hh))
        left.addLine(to: CGPoint(x: center.x, y: center.y + hh))
        left.addLine(to: CGPoint(x: center.x - hw, y: center.y))
        left.closeSubpath()
        var right = Path()
        right.move(to: CGPoint(x: topCenter.x + hw, y: topCenter.y))
        right.addLine(to: CGPoint(x: topCenter.x, y: topCenter.y + hh))
        right.addLine(to: CGPoint(x: center.x, y: center.y + hh))
        right.addLine(to: CGPoint(x: center.x + hw, y: center.y))
        right.closeSubpath()
        // 웹 규칙의 비율(윗면 55% · 왼면 82% · 오른면 100%)을 앱 강조색으로
        context.fill(top, with: .color(.accentColor.opacity(0.55)))
        context.fill(left, with: .color(.accentColor.opacity(0.82)))
        context.fill(right, with: .color(.accentColor))
    }
}
