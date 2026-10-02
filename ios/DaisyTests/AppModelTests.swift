import Foundation
import Testing
@testable import Daisy

struct AppModelTests {
    /// 서버 주소는 늘 Unibloom 서버(api.unibloom.cloud)예요. 예전에 저장된 주소는 무시해요 (10/2 결정)
    @Test @MainActor func defaultServerAddress() {
        let defaults = UserDefaults(suiteName: "AppModelTests-\(UUID())")!
        let first = AppModel(tokenStore: TokenStore(service: "AppModelTests-\(UUID())"), defaults: defaults)
        #expect(first.serverURL?.absoluteString == "https://api.unibloom.cloud")
        // 예전 앱이 저장해 둔 주소(예: 웹 주소)가 남아 있어도 늘 Unibloom 서버예요
        defaults.set("https://unibloom.cloud", forKey: "serverURL")
        let again = AppModel(tokenStore: TokenStore(service: "AppModelTests-\(UUID())"), defaults: defaults)
        #expect(again.serverURL?.absoluteString == "https://api.unibloom.cloud")
    }
}
