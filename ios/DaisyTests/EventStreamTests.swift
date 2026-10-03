import Foundation
import Synchronization
import Testing
@testable import Daisy

/// SSE (SPEC §6-3): 프레임 파서 · 재연결(Last-Event-ID) · 폴링 간격. 웹 `realtime.ts`와 같은 규칙인지 봐요.
struct EventStreamTests {
    // MARK: 프레임 파서

    /// 서버(Spring `SseEmitter`) 모양: 콜론 뒤 공백 없음, heartbeat는 id 없이, 이벤트는 id = seq
    @Test func parsesServerFrames() {
        let text = """
        event:heartbeat
        data:{}

        id:7
        event:step.started
        data:{"seq":7,"ts":"2026-10-03T10:00:00Z","deployment_id":"dep_1","target_id":"tgt_aws","data":{"step":"plan"}}

        id:8
        event:resync
        data:{"last_seq":42}


        """
        let events = SSEParser.parse(text)
        #expect(events.count == 3)
        #expect(events[0] == ServerEvent(id: nil, event: "heartbeat", data: "{}"))
        #expect(events[1].id == 7)
        #expect(events[1].event == "step.started")
        #expect(events[1].data.hasPrefix("{\"seq\":7"))
        #expect(events[2].event == "resync")
        #expect(events[2].lastSeq == 42)
    }

    @Test func handlesCRLFCommentsAndMultilineData() {
        let text = ": keep-alive\r\nid: 3\r\nevent: log.batch\r\ndata: first\r\ndata:  second\r\n\r\n"
        let events = SSEParser.parse(text)
        // 콜론 뒤 공백은 하나만 떼요 (웹과 같아요)
        #expect(events == [ServerEvent(id: 3, event: "log.batch", data: "first\n second")])
    }

    @Test func skipsFramesWithoutDataAndKeepsIncompleteTail() {
        var parser = SSEParser()
        // data 없는 프레임은 버려요
        #expect(SSEParser.parse("id: 1\nevent: x\n\n").isEmpty)
        // 빈 줄이 오기 전까지는 이벤트가 아니에요
        let partial = "event: deployment.created\ndata: {}\n".utf8.compactMap { parser.append($0) }
        #expect(partial.isEmpty)
        #expect(parser.append(0x0A) == ServerEvent(id: nil, event: "deployment.created", data: "{}"))
    }

    @Test func defaultsAndBadIDs() {
        let events = SSEParser.parse("id: abc\ndata: 안녕하세요\n\n")
        // event가 없으면 message, 숫자가 아닌 id는 버려요. 한글(UTF-8 여러 바이트)도 그대로예요
        #expect(events == [ServerEvent(id: nil, event: "message", data: "안녕하세요")])
        #expect(ServerEvent(id: nil, event: "resync", data: "not json").lastSeq == nil)
    }

    // MARK: 재연결 규칙

    @Test func backoffAndStateMatchWeb() {
        #expect(EventStream.backoff(failures: 1) == .seconds(2))
        #expect(EventStream.backoff(failures: 2) == .seconds(4))
        #expect(EventStream.backoff(failures: 3) == .seconds(8))
        #expect(EventStream.backoff(failures: 4) == .seconds(10))
        #expect(EventStream.backoff(failures: 60) == .seconds(10))
        #expect(EventStream.state(afterFailures: 1) == .reconnecting)
        #expect(EventStream.state(afterFailures: 2) == .reconnecting)
        #expect(EventStream.state(afterFailures: 3) == .disconnected)
    }

    @Test func requestCarriesAuthLanguageAndCursor() {
        let stream = EventStream(baseURL: URL(string: "https://api.example.com")!, token: "t0k", language: .japanese)
        let request = stream.request(path: "deployments/dep_1/events", lastEventID: 12)
        #expect(request.url?.absoluteString == "https://api.example.com/deployments/dep_1/events")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "ja")
        #expect(request.value(forHTTPHeaderField: "Last-Event-ID") == "12")
        #expect(stream.request(path: "projects/p/events", lastEventID: nil).value(forHTTPHeaderField: "Last-Event-ID") == nil)
    }

    /// 스트림이 끝나면 마지막 seq로 다시 붙고, resync 뒤에는 서버가 준 last_seq부터, 401이면 멈춰요
    @Test func reconnectsWithLastEventID() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedSSEProtocol.self]
        ScriptedSSEProtocol.script.withLock {
            $0 = [
                (200, "event:heartbeat\ndata:{}\n\nid:5\nevent:step.started\ndata:{\"seq\":5}\n\n"),
                (200, "event:resync\ndata:{\"last_seq\":40}\n\n"),
                (401, ""),
            ]
        }
        ScriptedSSEProtocol.cursors.withLock { $0 = [] }
        var stream = EventStream(baseURL: URL(string: "https://api.example.com")!, token: "t",
                                 session: URLSession(configuration: config))
        stream.retryDelay = { _ in .zero }

        var signals: [RealtimeSignal] = []
        for await signal in stream.subscribe(path: "projects/prj_1/events", since: 2) { signals.append(signal) }

        #expect(ScriptedSSEProtocol.cursors.withLock { $0 } == ["2", "5", "40"])
        #expect(signals == [
            .state(.connected),
            .event(ServerEvent(id: nil, event: "heartbeat", data: "{}")),
            .event(ServerEvent(id: 5, event: "step.started", data: "{\"seq\":5}")),
            .state(.reconnecting),
            .state(.connected),
            .resync,
            .state(.reconnecting),
            .state(.disconnected),
        ])
    }

    // MARK: 폴링 간격 · 신호

    @Test func pollIntervalAdapts() {
        #expect(PollInterval.seconds(live: true, active: true) == 15)
        #expect(PollInterval.seconds(live: false, active: true) == 2)
        #expect(PollInterval.seconds(live: false) == 5)
        #expect(DeploymentState.awaitingApproval.isActive)
        #expect(!DeploymentState.succeeded.isActive)
    }

    @MainActor
    @Test func signalWakesPollRightAway() async {
        let signal = LiveSignal()
        let counter = Counter()
        let clock = ContinuousClock()
        let started = clock.now
        let task = Task { @MainActor in
            await poll(on: signal, every: { 60 }, until: { counter.calls >= 2 }) { counter.calls += 1 }
        }
        while counter.calls < 1 { await Task.yield() }
        signal.fire()
        await task.value
        #expect(counter.calls == 2)
        #expect(clock.now - started < .seconds(5))
    }

    @MainActor
    @Test func waitReturnsOnCancel() async {
        let signal = LiveSignal()
        let task = Task { @MainActor in await signal.wait(upTo: 60, after: signal.count) }
        await Task.yield()
        task.cancel()
        await task.value
        #expect(signal.count == 0)
    }
}

@MainActor
private final class Counter {
    var calls = 0
}

/// 요청마다 대본의 다음 응답을 줘요. 받은 Last-Event-ID를 적어 둬요
private final class ScriptedSSEProtocol: URLProtocol, @unchecked Sendable {
    static let script = Mutex<[(Int, String)]>([])
    static let cursors = Mutex<[String]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.cursors.withLock { $0.append(request.value(forHTTPHeaderField: "Last-Event-ID") ?? "-") }
        let (status, body) = Self.script.withLock { $0.isEmpty ? (401, "") : $0.removeFirst() }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": status == 200 ? "text/event-stream" : "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
