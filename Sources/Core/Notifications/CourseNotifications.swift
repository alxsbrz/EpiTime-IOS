import Foundation
import Observation
import UserNotifications

/// Local reminders before each course. Entirely on-device — no push server, no token.
@MainActor
@Observable
final class CourseNotifications {
    static let shared = CourseNotifications()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// iOS keeps at most 64 pending local notifications; we schedule the soonest ones.
    private let maxPending = 60
    private let threadID = "epitime.courses"

    private init() {}

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorizationStatus()
        return granted
    }

    func reschedule(for events: [CourseEvent], minutesBefore: Int, enabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard enabled else { return }
        await refreshAuthorizationStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        let now = Date()
        let horizon = now.adding(days: 7)
        let upcoming = events
            .filter { !$0.isCancelled && $0.start > now && $0.start < horizon }
            .sorted { $0.start < $1.start }
            .prefix(maxPending)

        for (index, event) in upcoming.enumerated() {
            let fireDate = event.start.adding(minutes: -minutesBefore)
            guard fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = event.title
            content.subtitle = event.kindLabel
            content.body = body(for: event, minutesBefore: minutesBefore)
            content.sound = .default
            content.threadIdentifier = threadID
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = max(0, 1 - Double(index) / Double(maxPending))

            let components = Calendar.epitime.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let request = UNNotificationRequest(
                identifier: "epitime.course.\(event.id)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func pendingCount() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests().count
    }

    private func body(for event: CourseEvent, minutesBefore: Int) -> String {
        var parts = ["Dans \(minutesBefore) min"]
        if let room = event.roomsLabel { parts.append(room) }
        if let teacher = event.teachers.first?.name { parts.append(teacher) }
        return parts.joined(separator: " · ")
    }
}
