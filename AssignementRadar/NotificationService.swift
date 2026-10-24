//
//  NotificationService.swift
//  AssignementRadar
//
//  Created for Smart Deadline Reminders.
//

import Foundation
import UserNotifications
import SwiftUI
import Combine

/// Manages local deadline reminder notifications using Apple's UserNotifications framework.
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let center: UNUserNotificationCenter

    /// Target assignment ID queued for deep-linking/opening upon notification tap
    @Published var pendingOpenedAssignmentId: UUID? = nil

    /// Flag to present the "Mark Problem Solved" confirmation flow when user taps "Done" on a streak notification
    @Published var showConfirmSolvedProblemSheet: Bool = false

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        self.center.delegate = self
        CodingNotificationManager.registerCategories(center: self.center)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier

        // Route to Coding Radar workspace if notification originated from Coding Radar
        if let source = userInfo["source"] as? String, source == "coding_radar" {
            await MainActor.run {
                UserDefaults.standard.set(AppWorkspace.codingRadar.rawValue, forKey: "selected_app_workspace")
            }

            if actionIdentifier == CodingNotificationManager.actionSnooze1hId {
                await CodingNotificationManager.shared.scheduleOneHourFollowUpReminder()
                return
            } else if actionIdentifier == CodingNotificationManager.actionDoneId {
                // User tapped "Done" action on streak notification.
                // Requirement: "Done should open Coding Radar's completion flow or record completion only if the user explicitly confirms that they completed a qualifying coding activity. Do not automatically mark a problem solved just because the user taps Done."
                await MainActor.run {
                    self.showConfirmSolvedProblemSheet = true
                }
                return
            }
            return
        }

        guard let idString = userInfo["assignmentId"] as? String,
              let uuid = UUID(uuidString: idString) else {
            return
        }

        await MainActor.run {
            UserDefaults.standard.set(AppWorkspace.assignmentRadar.rawValue, forKey: "selected_app_workspace")
            self.pendingOpenedAssignmentId = uuid
        }
    }

    // MARK: - Reminder Intervals

    /// Configurable reminder intervals before an assignment deadline.
    enum ReminderOffset: TimeInterval, CaseIterable, Identifiable {
        case twentyFourHours = 86400  // 24 hours before
        case threeHours = 10800       // 3 hours before
        case atDeadline = 0           // At deadline

        var id: Double { rawValue }

        var identifierSuffix: String {
            switch self {
            case .twentyFourHours: return "24h"
            case .threeHours: return "3h"
            case .atDeadline: return "0m"
            }
        }

        var titlePrefix: String {
            switch self {
            case .twentyFourHours: return "⏰ Due in 24 Hours"
            case .threeHours: return "🚨 Due in 3 Hours"
            case .atDeadline: return "⏳ Deadline Reached"
            }
        }

        var preferenceKey: String {
            switch self {
            case .twentyFourHours: return "notify_24h_before"
            case .threeHours: return "notify_3h_before"
            case .atDeadline: return "notify_at_deadline"
            }
        }

        var isEnabled: Bool {
            UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
        }
    }

    // MARK: - Notification Identifier Management

    /// Stable unique notification identifier for an assignment and reminder interval.
    static func identifier(for assignmentId: UUID, offset: ReminderOffset) -> String {
        "radar_rem_\(assignmentId.uuidString)_\(offset.identifierSuffix)"
    }

    /// All potential reminder identifiers for a given assignment.
    static func allIdentifiers(for assignmentId: UUID) -> [String] {
        ReminderOffset.allCases.map { identifier(for: assignmentId, offset: $0) }
    }

    // MARK: - Authorization

    /// Prompts the user once for notification authorization with an explanation if not yet determined.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                return granted
            } catch {
                print("Notification authorization request failed: \(error.localizedDescription)")
                return false
            }
        case .authorized, .provisional:
            return true
        case .denied, .ephemeral:
            // Do not repeatedly ask after denial
            return false
        @unknown default:
            return false
        }
    }

    /// Checks if notifications are authorized.
    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Returns current UNAuthorizationStatus.
    func getAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Examination Session Time Parsing

    /// Parses the start time from an examination session slot (e.g., "10:00 AM - 01:00 PM" -> (10, 0)).
    ///
    /// CRITICAL REQUIREMENT: When a range is present, ONLY the start time is extracted. The end time is never used as the start time.
    static func parseSessionStartTime(from sessionString: String?) -> (hour: Int, minute: Int)? {
        guard let text = sessionString?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        // 1. Check for range separators ("to", "-", "–", "—")
        // We isolate the starting portion before the range separator to guarantee the end time is NEVER interpreted as the start time.
        let rangePattern = #"^(.*?)\s*(?:to|[-–—])\s*(.*)$"#
        var candidateStart = text
        var candidateEnd: String? = nil

        if let regex = try? NSRegularExpression(pattern: rangePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r1 = Range(match.range(at: 1), in: text),
           let r2 = Range(match.range(at: 2), in: text) {
            candidateStart = String(text[r1]).trimmingCharacters(in: .whitespaces)
            candidateEnd = String(text[r2]).trimmingCharacters(in: .whitespaces)
        }

        // 2. Parse hour and minute from candidateStart
        if let parsed = parseHourAndMinute(from: candidateStart, endContext: candidateEnd) {
            return parsed
        }

        // 3. Fallback to named academic sessions if text is not standard numbers
        let lower = text.lowercased()
        if lower.contains("morning session") || lower.contains("morning slot") {
            return (10, 0)
        } else if lower.contains("evening session") || lower.contains("afternoon session") || lower.contains("evening slot") || lower.contains("afternoon slot") {
            return (14, 0)
        }

        return nil
    }

    /// Parses the end time from an examination session slot (e.g., "10:00 AM - 01:00 PM" -> (13, 0)).
    static func parseSessionEndTime(from sessionString: String?) -> (hour: Int, minute: Int)? {
        guard let text = sessionString?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        let rangePattern = #"^(.*?)\s*(?:to|[-–—])\s*(.*)$"#
        if let regex = try? NSRegularExpression(pattern: rangePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r2 = Range(match.range(at: 2), in: text) {
            let candidateEnd = String(text[r2]).trimmingCharacters(in: .whitespaces)
            return parseHourAndMinute(from: candidateEnd)
        }
        return nil
    }

    private static func parseHourAndMinute(from text: String, endContext: String? = nil) -> (hour: Int, minute: Int)? {
        // Matches e.g. "10:00 AM", "02:00 PM", "9:30 am", "14:00", "10:00"
        let timeRegex = try? NSRegularExpression(pattern: #"\b(\d{1,2}):(\d{2})(?:\s*(AM|PM|am|pm))?\b"#)
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = timeRegex?.firstMatch(in: text, range: nsRange),
              let rH = Range(match.range(at: 1), in: text),
              let rM = Range(match.range(at: 2), in: text),
              let rawHour = Int(text[rH]),
              let minute = Int(text[rM]),
              rawHour >= 0 && rawHour <= 23,
              minute >= 0 && minute <= 59 else {
            return nil
        }

        var hour = rawHour
        var meridiem: String? = nil
        if match.range(at: 3).location != NSNotFound, let rMer = Range(match.range(at: 3), in: text) {
            meridiem = String(text[rMer]).uppercased()
        }

        // If start has no explicit AM/PM, but endContext specifies PM (e.g. "2:00 - 5:00 PM")
        if meridiem == nil, let end = endContext?.uppercased(), end.contains("PM") {
            // Afternoon examination slot (1..7 PM)
            if hour >= 1 && hour <= 7 {
                hour += 12
            }
        } else if let mer = meridiem {
            if mer == "PM" && hour < 12 {
                hour += 12
            } else if mer == "AM" && hour == 12 {
                hour = 0
            }
        }

        return (hour, minute)
    }

    /// Determines which reminder offsets are eligible to trigger in the future for an assignment or exam at a reference time.
    static func futureEligibleOffsets(for assignment: Assignment, referenceDate: Date = Date(), calendar: Calendar = .current) -> [ReminderOffset] {
        let eventDate = assignment.effectiveEventDate(at: calendar)
        guard !assignment.isCompleted, assignment.hasValidDeadline, eventDate > referenceDate else {
            return []
        }
        return ReminderOffset.allCases.filter { offset in
            let triggerDate = eventDate.addingTimeInterval(-offset.rawValue)
            return triggerDate > referenceDate
        }
    }

    /// Generates deterministic reminder trigger specifications for testing and verification.
    static func calculateReminderDetails(
        for assignment: Assignment,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [(offset: ReminderOffset, triggerDate: Date, title: String, body: String, category: String)] {
        let eventDate = assignment.effectiveEventDate(at: calendar)
        guard !assignment.isCompleted, assignment.hasValidDeadline, eventDate > referenceDate else {
            return []
        }

        var results: [(offset: ReminderOffset, triggerDate: Date, title: String, body: String, category: String)] = []

        for offset in ReminderOffset.allCases {
            let triggerDate = eventDate.addingTimeInterval(-offset.rawValue)
            guard triggerDate > referenceDate else {
                continue
            }

            let title: String
            let body: String
            let category: String

            if assignment.isExam {
                category = "EXAM_REMINDER"
                switch offset {
                case .twentyFourHours:
                    title = "📝 Exam in 24 Hours: \(assignment.title)"
                case .threeHours:
                    title = "🚨 Exam in 3 Hours: \(assignment.title)"
                case .atDeadline:
                    title = "🔔 Exam Starting Now: \(assignment.title)"
                }

                let dateString = eventDate.formatted(date: .abbreviated, time: .shortened)
                if let session = assignment.sessionTime, !session.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !assignment.course.isEmpty {
                        body = "\(assignment.course) • Exam session: \(session) (\(dateString))"
                    } else {
                        body = "Exam session: \(session) (\(dateString))"
                    }
                } else {
                    if !assignment.course.isEmpty {
                        body = "\(assignment.course) • Exam scheduled for \(dateString)"
                    } else {
                        body = "Exam scheduled for \(dateString)"
                    }
                }
            } else {
                category = "ASSIGNMENT_REMINDER"
                title = "\(offset.titlePrefix): \(assignment.title)"
                if !assignment.course.isEmpty {
                    body = "\(assignment.course) • Due at \(eventDate.formatted(date: .abbreviated, time: .shortened))"
                } else {
                    body = "Due at \(eventDate.formatted(date: .abbreviated, time: .shortened))"
                }
            }

            results.append((offset: offset, triggerDate: triggerDate, title: title, body: body, category: category))
        }

        return results
    }

    // MARK: - Scheduling

    /// Schedules deadline reminders for an assignment or exam relative to its actual deadline or start time.
    func scheduleReminders(for assignment: Assignment) {
        let eventDate = assignment.effectiveEventDate()

        // Cancel outstanding notifications if item is complete, has no valid deadline, or start time has already passed
        if assignment.isCompleted || !assignment.hasValidDeadline || eventDate <= Date() {
            cancelReminders(for: assignment.id)
            return
        }

        let assignmentId = assignment.id
        let title = assignment.title
        let course = assignment.course
        let isExam = assignment.isExam
        let sessionTime = assignment.sessionTime

        Task {
            let authorized = await isAuthorized()
            guard authorized else { return }

            let now = Date()

            for offset in ReminderOffset.allCases {
                let reqId = Self.identifier(for: assignmentId, offset: offset)

                guard offset.isEnabled else {
                    center.removePendingNotificationRequests(withIdentifiers: [reqId])
                    continue
                }

                // Prevent duplicate notifications if Apple Calendar alerts are handling this deadline
                if CalendarSyncService.shared.isCalendarSyncEnabled &&
                   CalendarSyncService.shared.calendarAlertsEnabled &&
                   assignment.calendarEventId != nil {
                    if offset == .twentyFourHours || offset == .threeHours {
                        center.removePendingNotificationRequests(withIdentifiers: [reqId])
                        continue
                    }
                }

                let triggerDate = eventDate.addingTimeInterval(-offset.rawValue)
                // Schedule only if the trigger date is strictly in the future
                guard triggerDate > now else {
                    center.removePendingNotificationRequests(withIdentifiers: [reqId])
                    continue
                }

                let content = UNMutableNotificationContent()
                if isExam {
                    switch offset {
                    case .twentyFourHours:
                        content.title = "📝 Exam in 24 Hours: \(title)"
                    case .threeHours:
                        content.title = "🚨 Exam in 3 Hours: \(title)"
                    case .atDeadline:
                        content.title = "🔔 Exam Starting Now: \(title)"
                    }

                    let dateString = eventDate.formatted(date: .abbreviated, time: .shortened)
                    if let session = sessionTime, !session.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if !course.isEmpty {
                            content.body = "\(course) • Exam session: \(session) (\(dateString))"
                        } else {
                            content.body = "Exam session: \(session) (\(dateString))"
                        }
                    } else {
                        if !course.isEmpty {
                            content.body = "\(course) • Exam scheduled for \(dateString)"
                        } else {
                            content.body = "Exam scheduled for \(dateString)"
                        }
                    }
                    content.categoryIdentifier = "EXAM_REMINDER"
                    content.userInfo = [
                        "assignmentId": assignmentId.uuidString,
                        "isExam": "true",
                        "offset": offset.identifierSuffix
                    ]
                } else {
                    content.title = "\(offset.titlePrefix): \(title)"
                    if !course.isEmpty {
                        content.body = "\(course) • Due at \(eventDate.formatted(date: .abbreviated, time: .shortened))"
                    } else {
                        content.body = "Due at \(eventDate.formatted(date: .abbreviated, time: .shortened))"
                    }
                    content.categoryIdentifier = "ASSIGNMENT_REMINDER"
                    content.userInfo = [
                        "assignmentId": assignmentId.uuidString,
                        "isExam": "false",
                        "offset": offset.identifierSuffix
                    ]
                }
                content.sound = .default

                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: triggerDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

                let request = UNNotificationRequest(identifier: reqId, content: content, trigger: trigger)

                do {
                    try await center.add(request)
                } catch {
                    print("Failed to schedule notification \(reqId): \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Cancellation

    /// Cancels all scheduled and delivered notifications for an assignment or exam.
    func cancelReminders(for assignmentId: UUID) {
        let ids = Self.allIdentifiers(for: assignmentId)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    // MARK: - Batch Synchronization

    /// Synchronizes reminders for a collection of assignments and exams (e.g., on app launch or after Moodle sync).
    func syncAllReminders(for assignments: [Assignment]) {
        for assignment in assignments {
            let eventDate = assignment.effectiveEventDate()
            if assignment.isCompleted || !assignment.hasValidDeadline || eventDate <= Date() {
                cancelReminders(for: assignment.id)
            } else {
                scheduleReminders(for: assignment)
            }
        }
    }

    // MARK: - Hackathon & Competition Event Reminders

    /// Stable unique notification identifier for an event registration or submission deadline.
    static func hackathonIdentifier(for eventId: UUID, deadlineType: String, offset: ReminderOffset) -> String {
        "radar_event_\(eventId.uuidString)_\(deadlineType)_\(offset.identifierSuffix)"
    }

    /// All potential reminder identifiers for a given hackathon or competition event.
    static func allHackathonIdentifiers(for eventId: UUID) -> [String] {
        var ids: [String] = []
        for type in ["reg", "sub"] {
            for offset in ReminderOffset.allCases {
                ids.append(hackathonIdentifier(for: eventId, deadlineType: type, offset: offset))
            }
        }
        return ids
    }

    /// Schedules deadline reminders for a hackathon's registration and project submission deadlines.
    func scheduleReminders(for event: Hackathon) {
        if event.isAttendedOrCompleted {
            cancelReminders(forHackathonId: event.id)
            return
        }

        let eventId = event.id
        let title = event.title
        let organizer = event.organizer
        let regDeadline = event.registrationDeadline
        let subDeadline = event.submissionDeadline

        Task {
            let authorized = await isAuthorized()
            guard authorized else { return }

            let now = Date()

            // 1. Registration Deadline Reminders
            if let reg = regDeadline, reg > now {
                for offset in ReminderOffset.allCases {
                    let reqId = Self.hackathonIdentifier(for: eventId, deadlineType: "reg", offset: offset)

                    guard offset.isEnabled else {
                        center.removePendingNotificationRequests(withIdentifiers: [reqId])
                        continue
                    }

                    let triggerDate = reg.addingTimeInterval(-offset.rawValue)
                    guard triggerDate > now else {
                        center.removePendingNotificationRequests(withIdentifiers: [reqId])
                        continue
                    }

                    let content = UNMutableNotificationContent()
                    content.title = "\(offset.titlePrefix) (Reg): \(title)"
                    if !organizer.isEmpty {
                        content.body = "Registration closes at \(reg.formatted(date: .abbreviated, time: .shortened)) • Hosted by \(organizer)"
                    } else {
                        content.body = "Registration closes at \(reg.formatted(date: .abbreviated, time: .shortened))"
                    }
                    content.sound = .default
                    content.categoryIdentifier = "HACKATHON_REMINDER"
                    content.userInfo = [
                        "hackathonId": eventId.uuidString,
                        "type": "reg",
                        "offset": offset.identifierSuffix
                    ]

                    let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    let request = UNNotificationRequest(identifier: reqId, content: content, trigger: trigger)

                    do {
                        try await center.add(request)
                    } catch {
                        print("Failed to schedule hackathon reg reminder \(reqId): \(error.localizedDescription)")
                    }
                }
            } else {
                let regIds = ReminderOffset.allCases.map { Self.hackathonIdentifier(for: eventId, deadlineType: "reg", offset: $0) }
                center.removePendingNotificationRequests(withIdentifiers: regIds)
            }

            // 2. Project / Round Submission Deadline Reminders
            if let sub = subDeadline, sub > now {
                for offset in ReminderOffset.allCases {
                    let reqId = Self.hackathonIdentifier(for: eventId, deadlineType: "sub", offset: offset)

                    guard offset.isEnabled else {
                        center.removePendingNotificationRequests(withIdentifiers: [reqId])
                        continue
                    }

                    let triggerDate = sub.addingTimeInterval(-offset.rawValue)
                    guard triggerDate > now else {
                        center.removePendingNotificationRequests(withIdentifiers: [reqId])
                        continue
                    }

                    let content = UNMutableNotificationContent()
                    content.title = "\(offset.titlePrefix) (Project): \(title)"
                    content.body = "Project/round submission due at \(sub.formatted(date: .abbreviated, time: .shortened))"
                    content.sound = .default
                    content.categoryIdentifier = "HACKATHON_REMINDER"
                    content.userInfo = [
                        "hackathonId": eventId.uuidString,
                        "type": "sub",
                        "offset": offset.identifierSuffix
                    ]

                    let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    let request = UNNotificationRequest(identifier: reqId, content: content, trigger: trigger)

                    do {
                        try await center.add(request)
                    } catch {
                        print("Failed to schedule hackathon sub reminder \(reqId): \(error.localizedDescription)")
                    }
                }
            } else {
                let subIds = ReminderOffset.allCases.map { Self.hackathonIdentifier(for: eventId, deadlineType: "sub", offset: $0) }
                center.removePendingNotificationRequests(withIdentifiers: subIds)
            }
        }
    }

    /// Cancels all scheduled and delivered notifications for a hackathon.
    func cancelReminders(forHackathonId eventId: UUID) {
        let ids = Self.allHackathonIdentifiers(for: eventId)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// Synchronizes reminders for a collection of hackathons.
    func syncAllHackathonReminders(for events: [Hackathon]) {
        for event in events {
            if event.isAttendedOrCompleted {
                cancelReminders(forHackathonId: event.id)
            } else {
                scheduleReminders(for: event)
            }
        }
    }
}
