import Foundation
import UserNotifications

class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private var previousStates: [String: String] = [:]
    private var previousRestartCounts: [String: Int] = [:]
    private var isAvailable = false

    override init() {
        super.init()
    }

    func requestPermission() {
        // UNUserNotificationCenter crashes without a proper app bundle.
        // Guard against this for `swift run` / CLI builds.
        guard Bundle.main.bundleIdentifier != nil else { return }

        isAvailable = true
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func checkForChanges(environment: PM2Environment, processes: [PM2Process]) {
        for process in processes {
            let key = "\(environment.path):\(process.pmId)"
            let previousStatus = previousStates[key]
            let previousRestarts = previousRestartCounts[key]

            if previousStatus == "online" && process.status == "errored" {
                sendNotification(
                    title: "Process Crashed",
                    body: "\(process.name) in \(environment.name) has errored"
                )
            }

            if let prev = previousRestarts, process.restartCount > prev && process.isOnline {
                sendNotification(
                    title: "Process Restarted",
                    body: "\(process.name) in \(environment.name) restarted (count: \(process.restartCount))"
                )
            }

            previousStates[key] = process.status
            previousRestartCounts[key] = process.restartCount
        }
    }

    private func sendNotification(title: String, body: String) {
        guard isAvailable else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
