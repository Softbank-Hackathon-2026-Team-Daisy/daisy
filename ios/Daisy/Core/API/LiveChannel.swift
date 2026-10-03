import Foundation
import Observation

/// "다시 불러와" 신호. 폴링이 기다리는 동안 신호가 오면 바로 깨요 (`poll(live:every:until:_:)`).
@MainActor
final class LiveSignal {
    /// 신호가 올 때마다 하나씩 올라가요
    private(set) var count = 0
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    func fire() {
        count += 1
        let all = waiters
        waiters = [:]
        all.values.forEach { $0.resume() }
    }

    /// `seconds` 동안 기다려요. 그 사이 신호가 오거나(`count`가 `seen`과 달라지면) Task가 취소되면 바로 돌아와요
    func wait(upTo seconds: Double, after seen: Int) async {
        guard count == seen, !Task.isCancelled else { return }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters[id] = continuation
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(seconds))
                    self?.resume(id)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.resume(id) }
        }
    }

    private func resume(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume()
    }
}

/// SSE 채널 하나에 붙어서 화면이 바로 다시 불러오게 해요 (웹 `useRealtime`).
/// 이벤트 내용을 직접 쌓지 않고 신호만 줘요 — 화면은 스냅샷(A-04 등)을 다시 읽어요.
/// 여러 이벤트가 한꺼번에 오면(재생 · resync) 300ms 안의 것은 한 번으로 묶어요. 로그(`log.batch`)는 `logs`로 따로 1초에 한 번.
@MainActor
@Observable
final class LiveChannel {
    /// 스트림이 붙어 있는 동안 true. 이때는 폴링을 느리게(안전망) 해요
    private(set) var isLive = false
    /// 상태 · 단계 · 승인 · 목록 이벤트 (heartbeat · log.batch 빼고 전부), 연결이 붙거나 끊길 때
    @ObservationIgnored let changes = LiveSignal()
    /// `log.batch`
    @ObservationIgnored let logs = LiveSignal()
    /// 이벤트가 오면 부르는 곳 (배포 채널 → 사이드바 승인 대기 배지 등)
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    @ObservationIgnored private var changePending = false
    @ObservationIgnored private var logPending = false

    static let batchWindow: Duration = .milliseconds(300)
    static let logWindow: Duration = .seconds(1)

    /// 채널에 붙어 있어요. 부른 Task가 취소되면(화면이 사라지면) 끊어요. `stream`이 없으면(예시 데이터 모드 · 로그아웃) 바로 돌아와요
    func listen(_ stream: EventStream?, path: String) async {
        guard let stream else { return }
        defer { setLive(false) }
        for await signal in stream.subscribe(path: path) {
            switch signal {
            case .state(let state): setLive(state == .connected)
            case .resync: schedule(logs: false)
            case .event(let event):
                switch event.event {
                case "heartbeat": break
                case "log.batch": schedule(logs: true)
                default: schedule(logs: false)
                }
            }
        }
    }

    private func setLive(_ live: Bool) {
        guard live != isLive else { return }
        isLive = live
        // 붙으면 그 사이 놓친 걸, 끊기면 빠른 폴링 간격으로 — 한 번 바로 다시 불러요
        changes.fire()
    }

    /// 묶음 창이 열려 있으면 그 창에 합쳐요. 계속 이벤트가 와도 창마다 한 번은 불러요 (debounce처럼 미루지 않아요)
    private func schedule(logs isLog: Bool) {
        if isLog {
            guard !logPending else { return }
            logPending = true
        } else {
            guard !changePending else { return }
            changePending = true
        }
        Task { [weak self] in
            try? await Task.sleep(for: isLog ? Self.logWindow : Self.batchWindow)
            guard let self else { return }
            if isLog {
                logPending = false
                logs.fire()
            } else {
                changePending = false
                changes.fire()
                onChange?()
            }
        }
    }
}

/// 폴링 간격 (초). SSE가 붙어 있으면 안전망으로 느리게, 끊겼는데 배포가 진행 중이면 빠르게, 아니면 5초
enum PollInterval {
    static let whileLive: Double = 15
    static let whileActive: Double = 2
    static let normal: Double = 5

    static func seconds(live: Bool, active: Bool = false) -> Double {
        live ? whileLive : active ? whileActive : normal
    }
}

extension DeploymentState {
    /// 대기 · 진행 · 승인 대기: 끝나지 않은 배포
    var isActive: Bool { [.queued, .running, .awaitingApproval].contains(self) }
}
