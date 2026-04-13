import UserNotifications

enum NotificationService {
    @MainActor
    static func deviceConnected(name: String) {
        guard AppSettings.shared.notifyOnDeviceConnect else { return }
        let suffix = NSLocalizedString(" is ready. Tap to pull crash logs.", bundle: .main, comment: "")
        send(
            title: NSLocalizedString("iPhone Connected", bundle: .main, comment: ""),
            body: name + suffix,
            id: "device-connected"
        )
    }

    @MainActor
    static func analysisComplete(count: Int, verdict: String) {
        guard AppSettings.shared.notifyOnAnalysisComplete else { return }
        let fmt = NSLocalizedString("Analysis Complete — %lld logs", bundle: .main, comment: "")
        send(
            title: String(format: fmt, count),
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
