import Foundation
import Testing
@testable import Daisy

/// 예시 데이터 모드는 푸시 권한을 묻지 않고, APNs에 등록하지 않고, 서버에 기기를 보내지 않아요 (SPEC §6-5).
/// 예시 데이터 모드를 없앨 때 이 파일도 같이 지워요.
struct SampleModePushTests {
    @Test @MainActor func sampleModeNeverRegisters() async {
        let fake = PushFake()
        let app = PushFake.appModel(push: fake.registry)
        app.enterSampleMode(role: "owner")
        #expect(app.isSignedIn && app.isSampleMode)

        await fake.registry.activate(for: app)
        fake.registry.didRegister(deviceToken: Data([0x01, 0x02]))
        await fake.registry.lastRequest?.value
        app.signOut()
        await fake.registry.lastRequest?.value

        #expect(fake.asked == 0 && fake.registered == 0)
        #expect(fake.sent.all.isEmpty)
    }
}
