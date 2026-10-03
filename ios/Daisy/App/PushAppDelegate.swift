import SwiftUI
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// 푸시의 운영체제 쪽 (SPEC §6-5). iOS · macOS가 다른 부분만 여기 모아요 (플랫폼 분기는 App/에서만).
// 서버 등록 · 화면 열기는 `Core/Push/PushRegistry`가 해요.

/// 앱 델리게이트: APNs 기기 토큰을 받고, 알림 센터 델리게이트를 앱이 다 켜지기 전에 걸어요
/// (그래야 꺼진 앱을 알림으로 켰을 때도 누른 알림이 들어와요). `DaisyApp`에서 어댑터로 붙여요.
#if os(iOS)
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistry.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PushRegistry.log.notice("APNs 등록 실패: \(error.localizedDescription, privacy: .public)")
    }
}
#else
final class PushAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistry.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PushRegistry.log.notice("APNs 등록 실패: \(error.localizedDescription, privacy: .public)")
    }
}
#endif

extension PushAppDelegate: UNUserNotificationCenterDelegate {
    /// 앱이 앞에 있을 때 온 알림: 설정 › 알림 스위치가 켜진 종류만 배너로 보여줘요
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let payload = PushPayload(userInfo: notification.request.content.userInfo)
        guard payload?.presentsInForeground(defaults: .standard) ?? true else { return [] }
        return [.banner, .list, .sound]
    }

    /// 알림을 눌렀을 때: 열 화면을 남겨 두면 RootView가 로그인 상태에서 열어요
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let payload = PushPayload(userInfo: response.notification.request.content.userInfo) else { return }
        await MainActor.run { PushRegistry.shared.pendingOpen = payload }
    }
}

extension DevicePlatform {
    static var current: DevicePlatform {
        #if os(iOS)
        .ios
        #else
        .macos
        #endif
    }
}

extension PushSystem {
    /// 실제 운영체제: UserNotifications 권한 + UIApplication · NSApplication 원격 알림 등록
    static var live: PushSystem {
        PushSystem(
            platform: .current,
            requestAuthorization: {
                (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            },
            authorizationStatus: {
                switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
                case .authorized, .provisional: .allowed
                case .denied: .denied
                case .notDetermined: .notDetermined
                #if os(iOS)
                case .ephemeral: .allowed
                #endif
                @unknown default: .unknown
                }
            },
            registerForRemoteNotifications: {
                #if os(iOS)
                UIApplication.shared.registerForRemoteNotifications()
                #else
                NSApplication.shared.registerForRemoteNotifications()
                #endif
            }
        )
    }
}

extension PushRegistry {
    /// 기기 설정의 이 앱 알림 화면 (설정 › 알림 "알림 설정 열기")
    static var systemSettingsURL: URL? {
        #if os(iOS)
        URL(string: UIApplication.openNotificationSettingsURLString)
        #else
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")")
        #endif
    }
}
