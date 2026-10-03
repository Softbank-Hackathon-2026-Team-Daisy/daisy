import Foundation

// SSE (SPEC §6-3 E-01 · E-02). 웹 `web/src/api/realtime.ts`와 같은 규칙이에요.
// 서버 형식: id(= seq) / event / data(한 줄 JSON), 빈 줄로 끊어요. 재연결은 Last-Event-ID 헤더.
// heartbeat는 15초마다(연결 직후 한 번 바로) — 그보다 오래 아무것도 안 오면 끊긴 걸로 보고 다시 붙어요.

/// SSE 이벤트 하나. `data`는 받은 글자 그대로예요 (봉투 `{ seq, ts, deployment_id, target_id, data }`)
struct ServerEvent: Sendable, Equatable {
    var id: Int64?
    var event: String
    var data: String

    /// `resync`의 `{ "last_seq": n }` — 이 seq부터 이어 붙어요
    var lastSeq: Int64? {
        struct Body: Decodable { let lastSeq: Int64? }
        return (try? JSONDecoder.daisy.decode(Body.self, from: Data(data.utf8)))?.lastSeq
    }
}

/// 바이트를 받아 SSE 프레임으로 묶어요. `\n` · `\r\n` 줄바꿈, `:`로 시작하는 줄은 주석이에요.
/// (`URLSession.AsyncBytes.lines`는 빈 줄을 건너뛰어서 프레임 끝을 알 수 없어요 → 바이트를 직접 읽어요)
struct SSEParser: Sendable {
    private var line: [UInt8] = []
    private var id: Int64?
    private var event: String?
    private var data: [String] = []

    /// 바이트 하나를 넣어요. 빈 줄로 프레임이 끝나면 이벤트를 돌려줘요
    mutating func append(_ byte: UInt8) -> ServerEvent? {
        guard byte == 0x0A else { line.append(byte); return nil }
        if line.last == 0x0D { line.removeLast() }
        defer { line.removeAll(keepingCapacity: true) }
        return consume(String(decoding: line, as: UTF8.self))
    }

    /// 줄 하나(줄바꿈 없이)를 넣어요
    mutating func consume(_ line: String) -> ServerEvent? {
        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = line[...]
            value = ""
        }
        switch field {
        case "id": id = Int64(value)
        case "event": event = String(value)
        case "data": data.append(String(value))
        default: break
        }
        return nil
    }

    /// data가 없는 프레임은 버려요 (웹과 같아요)
    private mutating func dispatch() -> ServerEvent? {
        defer { (id, event, data) = (nil, nil, []) }
        guard !data.isEmpty else { return nil }
        return ServerEvent(id: id, event: event ?? "message", data: data.joined(separator: "\n"))
    }

    /// 글자 전체를 프레임으로 (테스트 · 녹화 재생용). 빈 줄로 안 끝난 마지막 조각은 버려요
    static func parse(_ text: String) -> [ServerEvent] {
        var parser = SSEParser()
        return text.utf8.compactMap { parser.append($0) }
    }
}

/// SSE 연결 상태 (웹 `RealtimeState`)
enum RealtimeState: Sendable, Equatable {
    case connected, reconnecting, disconnected
}

/// 구독하는 쪽에 넘기는 신호
enum RealtimeSignal: Sendable, Equatable {
    case state(RealtimeState)
    case event(ServerEvent)
    /// 서버가 놓친 이벤트를 못 채워요 → 스냅샷을 다시 읽어요
    case resync
}

/// SSE 클라이언트. `APIClient`와 같은 서버 · 토큰 · 언어로 붙어요 (Bearer, R-01).
/// EventSource를 쓰지 않고 `URLSession.bytes`를 직접 읽어요 — 헤더를 붙여야 해서요.
struct EventStream: Sendable {
    let baseURL: URL
    let token: String?
    var session: URLSession = .shared
    var language: AppLanguage = .current
    /// n번 연속 실패한 뒤 쉬는 시간. 테스트는 0으로 바꿔요
    var retryDelay: @Sendable (Int) -> Duration = EventStream.backoff(failures:)

    /// heartbeat가 15초마다 와요. 이만큼 아무것도 안 오면 끊긴 걸로 봐요 (요청의 idle 제한시간)
    static let staleAfter: TimeInterval = 35
    /// 계정당 연결 상한(서버 4개)에 걸리면(429) 이만큼 쉬었다가 다시 붙어요. 그동안 화면은 폴링으로 버텨요
    static let tooManyWait: Duration = .seconds(60)

    init(baseURL: URL, token: String?, session: URLSession = .shared, language: AppLanguage = .current) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
        self.language = language
    }

    init(client: APIClient) {
        self.init(baseURL: client.baseURL, token: client.token, session: client.session, language: client.language)
    }

    /// 2초 · 4초 · 8초 … 최대 10초 (웹과 같아요)
    static func backoff(failures: Int) -> Duration {
        .milliseconds(min(1000 * (1 << min(failures, 10)), 10_000))
    }

    /// 3번 연속 실패하면 disconnected → 쓰는 쪽이 빠른 폴링으로 버텨요
    static func state(afterFailures failures: Int) -> RealtimeState {
        failures >= 3 ? .disconnected : .reconnecting
    }

    func request(path: String, lastEventID: Int64?) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(language.rawValue, forHTTPHeaderField: "Accept-Language")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let lastEventID { request.setValue(String(lastEventID), forHTTPHeaderField: "Last-Event-ID") }
        request.timeoutInterval = Self.staleAfter
        return request
    }

    /// 채널(`projects/{id}/events` · `deployments/{id}/events`)에 붙어요. 끊기면 Last-Event-ID로 다시 붙어요.
    /// 401 · 403 · 404는 다시 붙어도 안 되니 disconnected로 끝내요 (401은 폴링 쪽이 받아서 로그인 화면으로 보내요).
    /// 받는 쪽 Task가 취소되면 연결도 끊어요.
    func subscribe(path: String, since: Int64? = nil) -> AsyncStream<RealtimeSignal> {
        AsyncStream { continuation in
            let task = Task {
                await run(path: path, since: since, continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private enum Failure: Error { case stop, tooMany, status(Int) }

    private func run(path: String, since: Int64?, _ out: AsyncStream<RealtimeSignal>.Continuation) async {
        var lastID = since
        var failures = 0
        while !Task.isCancelled {
            do {
                let (bytes, response) = try await session.bytes(for: request(path: path, lastEventID: lastID))
                guard let http = response as? HTTPURLResponse else { throw Failure.status(0) }
                switch http.statusCode {
                case 401, 403, 404: throw Failure.stop
                case 429: throw Failure.tooMany
                case 200..<300 where http.mimeType == "text/event-stream": break
                default: throw Failure.status(http.statusCode)
                }
                failures = 0
                out.yield(.state(.connected))
                var parser = SSEParser()
                for try await byte in bytes {
                    guard let event = parser.append(byte) else { continue }
                    if event.event == "resync" {
                        // 보관 범위 밖이라 처음부터 다시 받으면 또 resync가 와요. 서버가 알려 준 last_seq부터 이어 붙어요
                        lastID = event.lastSeq
                        out.yield(.resync)
                        continue
                    }
                    if let id = event.id { lastID = id }
                    out.yield(.event(event))
                }
            } catch Failure.stop {
                out.yield(.state(.disconnected))
                return
            } catch Failure.tooMany {
                out.yield(.state(.disconnected))
                try? await Task.sleep(for: Self.tooManyWait)
                continue
            } catch {
                if Task.isCancelled { return }
            }
            // 서버가 스트림을 닫아도(30분 · resync 뒤) 실패처럼 다시 붙어요 (웹과 같아요)
            failures += 1
            out.yield(.state(Self.state(afterFailures: failures)))
            try? await Task.sleep(for: retryDelay(failures))
        }
    }
}
