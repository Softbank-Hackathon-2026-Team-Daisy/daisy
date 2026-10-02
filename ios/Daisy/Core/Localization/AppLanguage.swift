import Foundation
import Observation
import Synchronization

// 앱 화면 언어 (설정 › 언어, 10/2 담당자 요청): 한국어 · English · 日本語, 기본값은 기기 언어.
// 원문은 한국어(해요체)이고 번역은 String Catalog `Resources/Localizable.xcstrings`에 있어요.
// - `Text("…")` · `Button("…")` 같은 SwiftUI 글자는 루트에 넣은 `\.locale`로 찾아요.
// - `String`으로 넘기는 글자(배지 · 알림 · 오류 · 문구 규칙)는 `String.app("…")`으로 만들어요.
//   `String(localized:)`는 기기 언어로만 찾아서, 앱에서 고른 언어로 바로 바뀌지 않아요.
// - 서버가 보낸 글자(오류 message, plan 위험 설명, 로그 등)는 번역하지 않고 그대로 보여줘요 (SPEC §3-3).

/// 앱이 가진 화면 언어
enum AppLanguage: String, CaseIterable, Sendable {
    case korean = "ko"
    case english = "en"
    case japanese = "ja"

    /// "en-GB" · "ja_JP" 같은 코드도 받아요. 앱에 없는 언어면 nil
    init?(code: String) {
        let base = code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? code
        self.init(rawValue: base)
    }

    /// 화면 · 숫자 표기에 쓸 로케일. 지역(KR · US …)은 기기 설정을 그대로 둬요
    var locale: Locale {
        var components = Locale.Components(locale: .current)
        components.languageComponents = Locale.Language.Components(identifier: rawValue)
        return Locale(components: components)
    }

    /// 테스트가 언어를 잠깐 바꿔 볼 때 써요. 다른 테스트와 같이 돌아도 서로 섞이지 않아요 (TaskLocal)
    @TaskLocal static var override: AppLanguage?

    /// 지금 화면에 쓰는 언어. SwiftUI 화면이 이 값을 읽으면 설정이 바뀔 때 다시 그려져요 (Observation)
    static var current: AppLanguage { override ?? LanguageStore.shared.resolved }

    /// 기기 언어 중 앱에 있는 첫 언어. 없으면 OS가 고른 개발 언어(한국어)예요
    static func device(preferred: [String] = Bundle.main.preferredLocalizations) -> AppLanguage {
        preferred.lazy.compactMap(AppLanguage.init(code:)).first ?? .korean
    }
}

/// 설정 › 언어에서 고르는 값
enum LanguageSetting: String, CaseIterable, Identifiable, Sendable {
    case system
    case korean = "ko"
    case english = "en"
    case japanese = "ja"

    var id: Self { self }

    /// 고정한 언어. "기기 설정 따르기"면 nil
    var language: AppLanguage? { AppLanguage(rawValue: rawValue) }

    /// 설정 화면 이름. 언어 이름은 늘 그 언어로 써요 (어느 언어로 보고 있어도 찾을 수 있게)
    var title: String {
        switch self {
        case .system: .app("기기 설정 따르기")
        case .korean: "한국어"
        case .english: "English"
        case .japanese: "日本語"
        }
    }
}

/// 고른 언어를 UserDefaults에 두고, 바뀌면 화면이 다시 그려지게 알려요.
/// API 클라이언트 · 오류 문구처럼 메인 스레드 밖에서도 읽어서 `Mutex`로 지켜요.
final class LanguageStore: Observable, Sendable {
    /// 앱 전체가 쓰는 하나. 단위 테스트 호스트는 따로 둔 UserDefaults를 쓰고, 기본값이 한국어예요 (기존 테스트가 한국어 문구를 확인해요)
    static let shared = DaisyApp.isTestHost
        ? LanguageStore(defaults: UserDefaults(suiteName: "DaisyTestHost") ?? .standard, fallback: .korean)
        : LanguageStore(defaults: .standard)

    static let key = "appLanguage"

    private let registrar = ObservationRegistrar()
    private let state: Mutex<LanguageSetting>
    /// UserDefaults는 스레드 안전해요 (Apple 문서)
    nonisolated(unsafe) private let defaults: UserDefaults
    private let device: AppLanguage

    /// - fallback: 저장된 값이 없을 때 쓸 설정
    /// - device: "기기 설정 따르기"일 때의 언어
    init(defaults: UserDefaults, fallback: LanguageSetting = .system, device: AppLanguage = AppLanguage.device()) {
        self.defaults = defaults
        self.device = device
        state = Mutex(defaults.string(forKey: Self.key).flatMap(LanguageSetting.init(rawValue:)) ?? fallback)
    }

    var setting: LanguageSetting {
        get {
            registrar.access(self, keyPath: \.setting)
            return state.withLock { $0 }
        }
        set {
            registrar.withMutation(of: self, keyPath: \.setting) {
                state.withLock { $0 = newValue }
            }
            defaults.set(newValue.rawValue, forKey: Self.key)
        }
    }

    /// 실제로 보여줄 언어
    var resolved: AppLanguage { setting.language ?? device }

    /// 루트 `\.locale`에 넣는 값
    var locale: Locale { resolved.locale }
}

extension String {
    /// 앱에서 고른 언어로 찾은 글자. `String`을 받는 곳(배지 · 알림 · 문구 규칙 · 오류)에 써요.
    /// 매개변수가 `LocalizedStringResource`라서 Xcode가 글자를 String Catalog로 뽑아 가요.
    static func app(_ resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = AppLanguage.current.locale
        return String(localized: resource)
    }
}

extension BinaryInteger {
    /// 고른 언어의 숫자 표기 ("1,380")
    var appFormatted: String { Int(self).formatted(.number.locale(AppLanguage.current.locale)) }
}
