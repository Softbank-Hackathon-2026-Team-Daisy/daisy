import Foundation
import Observation
import SwiftUI

// 화면 데이터 신선도 (10/3 신선도 검수 ②: O3 · H3 · E2 · SC3 · AI2 · AI3 · ST2 · D3 · X1 · X2).
// - 맥락(프로젝트 · 배포)이 바뀌면 이전 데이터를 버리고 `.loading`부터 다시 보여줘요 (이전 프로젝트 데이터를 새 프로젝트 아래 보이지 않게)
// - 늦게 온 응답(이전 맥락 · 더 먼저 보낸 요청)은 버려요
// - 한 번 받은 뒤 갱신에 실패하면 데이터는 그대로 두고 "갱신하지 못했어요 · 마지막 HH:mm"을 보여줘요
// - 실패는 `app.handle`로 넘겨서 401이면 로그아웃해요. 취소(화면이 사라짐 · 맥락이 바뀜)는 오류로 보지 않아요

/// 맥락 하나에 묶인 불러오기 상태. 값 타입이라 규칙을 단위 테스트로 확인해요 (`FreshnessTests`).
struct ScopedState<Value> {
    /// 지금 데이터(또는 불러오는 중인 요청)가 속한 맥락. 보통 프로젝트 ID, AI 사용량 배포 상세는 "프로젝트/배포"
    private(set) var scope: String?
    private(set) var state: LoadState<Value> = .idle
    /// 마지막으로 성공한 시각
    private(set) var updatedAt: Date?
    /// 한 번 받은 뒤 갱신에 실패한 시각. 다음 성공에서 지워져요
    private(set) var refreshFailedAt: Date?
    /// 보낸 요청 번호. 맥락이 바뀌거나 더 나중 요청이 반영되면 그보다 앞선 번호의 응답은 버려요
    private var issued = 0
    private var applied = 0

    /// 요청을 시작해요. 맥락이 바뀌었으면 이전 데이터를 버리고 `.loading`으로 돌려요. 돌려준 번호로 결과를 반영해요
    mutating func begin(_ scope: String) -> Int {
        if scope != self.scope {
            self.scope = scope
            state = .loading
            updatedAt = nil
            refreshFailedAt = nil
            // 이전 맥락에서 보낸 요청은 늦게 와도 반영하지 않아요
            applied = issued
        } else if case .idle = state {
            state = .loading
        }
        issued += 1
        return issued
    }

    /// 성공한 응답을 반영해요. 다른 맥락 · 이미 더 새 응답이 반영된 요청이면 버리고 false
    @discardableResult
    mutating func succeed(scope: String, generation: Int, at now: Date = .now, _ make: (Value?) -> Value) -> Bool {
        guard accepts(scope: scope, generation: generation) else { return false }
        applied = generation
        state = .loaded(make(state.value))
        updatedAt = now
        refreshFailedAt = nil
        return true
    }

    @discardableResult
    mutating func succeed(_ value: Value, scope: String, generation: Int, at now: Date = .now) -> Bool {
        succeed(scope: scope, generation: generation, at: now) { _ in value }
    }

    /// 실패를 반영해요. 받은 데이터가 있으면 그대로 두고 갱신 실패 시각만 남겨요. 처음부터 실패면 `.failed`
    @discardableResult
    mutating func fail(_ message: String, scope: String, generation: Int, at now: Date = .now) -> Bool {
        guard accepts(scope: scope, generation: generation) else { return false }
        applied = generation
        if state.value == nil {
            state = .failed(message)
        } else {
            refreshFailedAt = now
        }
        return true
    }

    /// 받은 값을 그 자리에서 고쳐요 (이력 "더 보기"로 더 받은 배포를 붙일 때). 맥락이 바뀌었으면 아무것도 안 해요
    @discardableResult
    mutating func update(scope: String, _ transform: (inout Value) -> Void) -> Bool {
        guard scope == self.scope, var value = state.value else { return false }
        transform(&value)
        state = .loaded(value)
        return true
    }

    /// 지금 맥락의 상태. 다른 맥락 것이면 로딩으로 보여줘요
    func state(for scope: String?) -> LoadState<Value> {
        scope != nil && scope == self.scope ? state : .loading
    }

    func value(for scope: String?) -> Value? {
        state(for: scope).value
    }

    /// 갱신에 실패해서 예전 데이터를 보여주는 중이면 마지막으로 받은 시각
    var staleSince: Date? {
        refreshFailedAt == nil ? nil : updatedAt
    }

    private func accepts(scope: String, generation: Int) -> Bool {
        scope == self.scope && generation > applied
    }
}

/// 화면이 쓰는 `ScopedState` 상자. `load`가 맥락 · 늦은 응답 · 오류 · 취소 규칙을 한곳에서 처리해요.
@MainActor
@Observable
final class ScopedLoader<Value> {
    private(set) var current = ScopedState<Value>()

    var scope: String? { current.scope }
    var staleSince: Date? { current.staleSince }

    func state(for scope: String?) -> LoadState<Value> { current.state(for: scope) }
    func value(for scope: String?) -> Value? { current.value(for: scope) }

    /// `fetch`로 받아 `merge`로 이전 값(같은 맥락일 때만)과 합쳐요
    func load<Fetched>(_ scope: String, using app: AppModel,
                       fetch: @MainActor () async throws -> Fetched,
                       merge: (Value?, Fetched) -> Value) async {
        let generation = current.begin(scope)
        do {
            let fetched = try await fetch()
            current.succeed(scope: scope, generation: generation) { merge($0, fetched) }
        } catch {
            if Freshness.isCancellation(error) { return }
            app.handle(error)
            current.fail(error.localizedDescription, scope: scope, generation: generation)
        }
    }

    func load(_ scope: String, using app: AppModel, fetch: @MainActor () async throws -> Value) async {
        await load(scope, using: app, fetch: fetch, merge: { _, value in value })
    }

    @discardableResult
    func update(scope: String, _ transform: (inout Value) -> Void) -> Bool {
        current.update(scope: scope, transform)
    }
}

enum Freshness {
    /// 화면이 사라지거나 맥락이 바뀌어 `.task`가 취소된 요청. 오류 화면 · 갱신 실패로 보이지 않게 무시해요 (X4).
    /// APIClient는 URLSession 오류를 `APIError.transport(문구)`로 감싸서, 그 문구가 취소 문구인지도 봐요
    static func isCancellation(_ error: Error) -> Bool {
        if Task.isCancelled || error is CancellationError { return true }
        if let error = error as? URLError, error.code == .cancelled { return true }
        if case APIError.transport(let message) = error, message == URLError(.cancelled).localizedDescription { return true }
        return false
    }

    /// 꼭 필요하지 않은 요청(plan 합계 · 호출 기록 등)의 결과. 실패하면 nil이지만 401은 `app.handle`로 넘겨요 (`try?`로 삼키지 않아요, X2)
    @MainActor
    static func optional<T>(_ result: Result<T, any Error>, using app: AppModel) -> T? {
        switch result {
        case .success(let value): return value
        case .failure(let error):
            // 여러 보조 요청이 한꺼번에 401이어도 로그아웃은 한 번만
            if !isCancellation(error), app.isSignedIn { app.handle(error) }
            return nil
        }
    }

    /// 동시에 보내는 보조 요청을 결과로 감싸요 (`async let`에서 써요)
    nonisolated static func attempt<T: Sendable>(_ operation: @Sendable () async throws -> T) async -> Result<T, any Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }

    /// 폴링 간격. `PollInterval`과 같지만, 진행 중인 배포가 있으면 SSE가 붙어 있어도 15초까지 늦추지 않아요 (O2):
    /// 프로젝트 채널에는 승인 · 배포 상태 이벤트가 오지 않아서(서버 EventJournal) 그 변화는 폴링으로만 알아요
    static func pollSeconds(live: Bool, active: Bool) -> Double {
        guard active else { return PollInterval.seconds(live: live) }
        return live ? PollInterval.normal : PollInterval.whileActive
    }
}

/// 갱신 실패 표시: "갱신하지 못했어요 · 마지막 21:10". 데이터는 그대로 두고 작게 알려요 (X1)
struct StaleBanner: View {
    let since: Date?

    static func text(_ since: Date) -> String {
        .app("갱신하지 못했어요 · 마지막 \(TimeText.clock(since))")
    }

    var body: some View {
        if let since {
            Label {
                Text(Self.text(since))
            } icon: {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
            }
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.orange.opacity(0.12), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }
    }
}
