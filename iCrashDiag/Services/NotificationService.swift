import UserNotifications

enum NotificationService {
    @MainActor
    static func deviceConnected(name: String) {
        guard AppSettings.shared.notifyOnDeviceConnect else { return }
        send(
            title: "iPhone Connected",
            body: "\(name) is ready. Tap to pull crash logs.",
            id: "device-connected"
        )
    }

    @MainActor
    static func analysisComplete(count: Int, verdict: String) {
        guard AppSettings.shared.notifyOnAnalysisComplete else { return }
        send(
            title: "Analysis Complete — \(count) logs",
            body: verdict,
            id: "analysis-complete"
        )
    }

    private static func send(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
