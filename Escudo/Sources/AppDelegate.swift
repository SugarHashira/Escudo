//
//  AppDelegate.swift
//  Escudo
//

import SwiftUI
import BackgroundTasks
import UserNotifications

extension Notification.Name {
    static let openReviewUnknown = Notification.Name("escudo.openReviewUnknown")
    static let openCategoryLog   = Notification.Name("escudo.openCategoryLog")
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.sugarhashira.Escudo.sync",
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            self.handleBGSync(task: processingTask)
        }
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BankSyncCoordinator.scheduleBackgroundSync()
    }

    // MARK: - Background sync

    private func handleBGSync(task: BGProcessingTask) {
        BankSyncCoordinator.scheduleBackgroundSync()
        let work = Task { @MainActor in
            await BankSyncCoordinator.shared.backgroundSyncAndNotify()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    // MARK: - Notification tap → deep-link

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.userInfo["action"] as? String == "reviewUnknown" {
            NotificationCenter.default.post(name: .openReviewUnknown, object: nil)
        }
        completionHandler()
    }

    // MARK: - URL handling

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if url.scheme == "escudo" {
            Task { @MainActor in
                EnableBankingService.handleCallback(url: url)
                SIBSService.handleCallback(url: url)
            }
            return true
        }
        return false
    }
}
