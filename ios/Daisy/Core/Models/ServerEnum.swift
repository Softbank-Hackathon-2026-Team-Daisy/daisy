import Foundation

/// 서버가 문자열로 보내는 enum. 모르는 값이 와도 디코딩이 실패하지 않고 `unknownCase`가 돼요 (SPEC R-07).
protocol ServerEnum: RawRepresentable<String>, Decodable, Sendable, Hashable {
    static var unknownCase: Self { get }
}

extension ServerEnum {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.unknownCase
    }
}
