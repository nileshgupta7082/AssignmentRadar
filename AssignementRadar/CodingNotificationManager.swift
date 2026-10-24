//
//  CodingNotificationManager.swift
//  AssignementRadar
//
//  Created for Coding Radar Daily Challenge and Contest Notifications.
//

import Foundation
import UserNotifications
import Combine

// MARK: - Reminder Plan (Pure Value for Scheduling and Testing)

/// Encapsulates a planned local notification.
struct CodingReminderPlan: Equatable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let title: String
    let body: String
    let triggerDate: Date
    let category: String
}

// MARK: - Coding Notification Manager

/// Coordinates local UserNotifications for Coding Radar daily challenges and registered contests.
/// Strictly decoupled from academic assignments and exam reminders.
final class CodingNotificationManager: ObservableObject {
    static let shared = CodingNotificationManager()

    // MARK: - User Preference Keys
    static let notifyDailyChallengeKey = "coding_notify_daily_challenge"
    static let dailyReminderHourKey = "coding_daily_reminder_hour"
    static let dailyReminderMinuteKey = "coding_daily_reminder_minute"

    static let notifyContestDayKey = "coding_notify_contest_day"
    static let contestDayHourKey = "coding_contest_day_hour"
    static let contestDayMinuteKey = "coding_contest_day_minute"

    static let notifyContest15mKey = "coding_notify_contest_15m"

    // Action & Category Identifiers
    static let streakReminderCategory = "CODING_STREAK_REMINDER"
    static let actionDoneId = "CODING_ACTION_DONE"
    static let actionSnooze1hId = "CODING_ACTION_SNOOZE_1H"

    // Default times
    static let defaultDailyHour = 21   // 9:00 PM
    static let defaultDailyMinute = 0
    static let defaultContestHour = 9  // 9:00 AM
    static let defaultContestMinute = 0

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        Self.registerCategories(center: center)
    }

    // MARK: - Category & Action Registration

    /// Registers the notification categories and actionable buttons with Apple's UserNotifications framework.
    static func registerCategories(center: UNUserNotificationCenter = .current()) {
        let doneAction = UNNotificationAction(
            identifier: actionDoneId,
            title: "Done",
            options: [.foreground]
        )
        let snoozeAction = UNNotificationAction(
            identifier: actionSnooze1hId,
            title: "Remind Me in 1 Hour",
            options: []
        )
        let streakCategory = UNNotificationCategory(
            identifier: streakReminderCategory,
            actions: [doneAction, snoozeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.getNotificationCategories { existing in
            var updated = existing
            updated.insert(streakCategory)
            center.setNotificationCategories(updated)
        }
    }

    // MARK: - Notification Identifier Generators

    /// Unique identifier for a daily streak reminder on a specific calendar date.
    static func streakReminderIdentifier(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "coding_streak_%04d_%02d_%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    /// Legacy identifier generator maintained for test and scheduling compatibility.
    static func dailyReminderIdentifier(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "coding_daily_%04d_%02d_%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    /// Unique deterministic identifier for the 1-hour snooze follow-up notification.
    static func followUpReminderIdentifier(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "coding_streak_followup_%04d_%02d_%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    /// Unique identifier for a contest-day 9:00 AM reminder.
    static func contestDayReminderIdentifier(for contestId: UUID) -> String {
        "coding_contest_day_\(contestId.uuidString)"
    }

    /// Unique identifier for a contest 15-minute countdown reminder.
    static func contest15MinReminderIdentifier(for contestId: UUID) -> String {
        "coding_contest_15m_\(contestId.uuidString)"
    }

    // MARK: - Pure Planning Functions (Deterministic & Testable)

    /// Computes whether a smart Coding Streak Reminder should be scheduled for a given day.
    ///
    /// Rules:
    /// - User notification setting must be enabled.
    /// - Checks whether the user has completed ANY qualifying activity today (LeetCode, GFG, manual, or daily challenge).
    /// - If any qualifying activity is completed on that day, NO reminder is sent.
    /// - Past trigger dates are skipped.
    static func calculateStreakReminderPlan(
        activities: [CodingActivityRecord] = [],
        tasks: [CodingTask] = [],
        calendar: Calendar = .current,
        now: Date = Date(),
        targetDate: Date? = nil,
        isEnabled: Bool = true,
        reminderHour: Int = defaultDailyHour,
        reminderMinute: Int = defaultDailyMinute
    ) -> CodingReminderPlan? {
        guard isEnabled else { return nil }

        let targetDay = targetDate ?? now

        var targetComps = calendar.dateComponents([.year, .month, .day], from: targetDay)
        targetComps.hour = reminderHour
        targetComps.minute = reminderMinute
        targetComps.second = 0

        guard let triggerDate = calendar.date(from: targetComps), triggerDate > now else {
            return nil
        }

        // Check if ANY qualifying activity or completed task exists on targetDay
        let hasCompletedActivity = activities.contains { activity in
            calendar.isDate(activity.completedAt, inSameDayAs: targetDay)
        }
        let hasCompletedTask = tasks.contains { task in
            task.isCompleted && calendar.isDate(task.completedAt ?? Date.distantPast, inSameDayAs: targetDay)
        }

        if hasCompletedActivity || hasCompletedTask {
            return nil // Already satisfied for today!
        }

        let identifier = streakReminderIdentifier(for: targetDay, calendar: calendar)
        return CodingReminderPlan(
            identifier: identifier,
            title: "Your coding streak is waiting!",
            body: "Solve a problem today to keep your coding streak alive.",
            triggerDate: triggerDate,
            category: streakReminderCategory
        )
    }

    /// Computes a one-time 1-hour follow-up notification plan.
    static func calculateFollowUpReminderPlan(
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> CodingReminderPlan {
        let identifier = followUpReminderIdentifier(for: now, calendar: calendar)
        let triggerDate = now.addingTimeInterval(3600) // Exactly 1 hour later
        return CodingReminderPlan(
            identifier: identifier,
            title: "Your coding streak is waiting!",
            body: "Solve a problem today to keep your coding streak alive.",
            triggerDate: triggerDate,
            category: streakReminderCategory
        )
    }

    /// Computes whether a daily challenge reminder should be scheduled for a given day (legacy & task-based).
    static func calculateDailyReminderPlan(
        tasks: [CodingTask],
        calendar: Calendar = .current,
        now: Date = Date(),
        targetDate: Date? = nil,
        isEnabled: Bool = true,
        reminderHour: Int = defaultDailyHour,
        reminderMinute: Int = defaultDailyMinute
    ) -> CodingReminderPlan? {
        guard isEnabled else { return nil }

        let targetDay = targetDate ?? now

        var targetComps = calendar.dateComponents([.year, .month, .day], from: targetDay)
        targetComps.hour = reminderHour
        targetComps.minute = reminderMinute
        targetComps.second = 0

        guard let triggerDate = calendar.date(from: targetComps), triggerDate > now else {
            return nil
        }

        // Check if at least one eligible daily coding question is configured for this day
        let hasConfiguredDailyQuestion = tasks.contains { task in
            task.isDailyQuestion &&
            (calendar.isDate(task.dueDate ?? Date.distantPast, inSameDayAs: targetDay) ||
             calendar.isDate(task.createdAt, inSameDayAs: targetDay))
        }

        guard hasConfiguredDailyQuestion else {
            return nil
        }

        // Check if user has completed at least one eligible daily question on this day
        let hasCompletedDailyQuestionToday = tasks.contains { task in
            task.isDailyQuestion &&
            task.isCompleted &&
            calendar.isDate(task.completedAt ?? Date.distantPast, inSameDayAs: targetDay)
        }

        if hasCompletedDailyQuestionToday {
            return nil
        }

        let identifier = dailyReminderIdentifier(for: targetDay, calendar: calendar)
        return CodingReminderPlan(
            identifier: identifier,
            title: "Time for your daily challenge",
            body: "You haven't completed a daily coding question today. Solve one to keep your Coding Radar streak going!",
            triggerDate: triggerDate,
            category: "CODING_DAILY_REMINDER"
        )
    }

    /// Computes the contest-day (9:00 AM) and 15-minute start reminders for a contest.
    ///
    /// Rules:
    /// - Only contests in the `.registered` state qualify.
    /// - Contests that have already ended are skipped.
    /// - If a contest starts before 9:00 AM, the 9:00 AM reminder is skipped.
    /// - If marked registered after 9:00 AM on contest day, the 9:00 AM reminder is skipped.
    /// - 15-minute reminder requires verified start time and must be in the future.
    static func calculateContestRemindersPlan(
        contest: CodingTask,
        calendar: Calendar = .current,
        now: Date = Date(),
        isDayReminderEnabled: Bool = true,
        is15MinReminderEnabled: Bool = true,
        dayReminderHour: Int = defaultContestHour,
        dayReminderMinute: Int = defaultContestMinute
    ) -> [CodingReminderPlan] {
        guard contest.isContest,
              !contest.isCompleted,
              contest.registrationStatus == .registered,
              contest.calendarEventId == nil else {
            return []
        }

        guard let contestDate = contest.startDate ?? contest.dueDate else {
            return []
        }

        // Skip ended contests
        guard contestDate > now else {
            return []
        }

        var plans: [CodingReminderPlan] = []

        // 1. Contest-Day 9:00 AM Reminder
        if isDayReminderEnabled {
            var dayComps = calendar.dateComponents([.year, .month, .day], from: contestDate)
            dayComps.hour = dayReminderHour
            dayComps.minute = dayReminderMinute
            dayComps.second = 0

            if let dayTriggerDate = calendar.date(from: dayComps) {
                // If contest starts before 9:00 AM, skip 9:00 AM reminder
                // If 9:00 AM is already in the past, skip stale reminder
                if contestDate >= dayTriggerDate && dayTriggerDate > now {
                    let timeFormatter = DateFormatter()
                    timeFormatter.timeStyle = .short
                    let timeStr = timeFormatter.string(from: contestDate)

                    let body: String
                    if contest.startDate != nil {
                        body = "\(contest.platformName) — \(contest.title) starts at \(timeStr). Get ready!"
                    } else {
                        body = "\(contest.platformName) — \(contest.title) is scheduled for today. Get ready!"
                    }

                    plans.append(
                        CodingReminderPlan(
                            identifier: contestDayReminderIdentifier(for: contest.id),
                            title: "Your contest is today",
                            body: body,
                            triggerDate: dayTriggerDate,
                            category: "CODING_CONTEST_DAY"
                        )
                    )
                }
            }
        }

        // 2. Contest 15-Minute Countdown Reminder
        if is15MinReminderEnabled, let verifiedStart = contest.startDate {
            let trigger15m = verifiedStart.addingTimeInterval(-15 * 60)
            if trigger15m > now && verifiedStart > now {
                plans.append(
                    CodingReminderPlan(
                        identifier: contest15MinReminderIdentifier(for: contest.id),
                        title: "Contest starts in 15 minutes",
                        body: "\(contest.platformName) — \(contest.title) is about to begin. Open the contest page and get ready!",
                        triggerDate: trigger15m,
                        category: "CODING_CONTEST_15MIN"
                    )
                )
            }
        }

        return plans
    }

    // MARK: - Asynchronous Reconciliation With UserNotifications

    /// Reconciles local pending notifications for Coding Radar based on current tasks, activities, and preferences.
    func reconcile(
        tasks: [CodingTask],
        activities: [CodingActivityRecord] = [],
        calendar: Calendar = .current,
        now: Date = Date()
    ) async {
        let authorized = await NotificationService.shared.isAuthorized()
        guard authorized else { return }

        // Read preferences
        let notifyDaily = UserDefaults.standard.object(forKey: Self.notifyDailyChallengeKey) as? Bool ?? true
        let dailyHour = UserDefaults.standard.object(forKey: Self.dailyReminderHourKey) as? Int ?? Self.defaultDailyHour
        let dailyMinute = UserDefaults.standard.object(forKey: Self.dailyReminderMinuteKey) as? Int ?? Self.defaultDailyMinute

        let notifyContestDay = UserDefaults.standard.object(forKey: Self.notifyContestDayKey) as? Bool ?? true
        let contestHour = UserDefaults.standard.object(forKey: Self.contestDayHourKey) as? Int ?? Self.defaultContestHour
        let contestMinute = UserDefaults.standard.object(forKey: Self.contestDayMinuteKey) as? Int ?? Self.defaultContestMinute

        let notifyContest15m = UserDefaults.standard.object(forKey: Self.notifyContest15mKey) as? Bool ?? true

        // 1. Reconcile Smart Streak Reminder for Today
        let todayStreakId = Self.streakReminderIdentifier(for: now, calendar: calendar)
        let followUpId = Self.followUpReminderIdentifier(for: now, calendar: calendar)
        let legacyDailyId = Self.dailyReminderIdentifier(for: now, calendar: calendar)

        let streakPlan = Self.calculateStreakReminderPlan(
            activities: activities,
            tasks: tasks,
            calendar: calendar,
            now: now,
            isEnabled: notifyDaily,
            reminderHour: dailyHour,
            reminderMinute: dailyMinute
        )

        if let plan = streakPlan {
            // Cancel legacy daily reminder to avoid duplicates
            center.removePendingNotificationRequests(withIdentifiers: [legacyDailyId])
            await schedulePlan(plan, calendar: calendar)
        } else {
            // Cancel today's pending streak reminder and any pending follow-up if already completed or disabled
            center.removePendingNotificationRequests(withIdentifiers: [todayStreakId, followUpId, legacyDailyId])
            center.removeDeliveredNotifications(withIdentifiers: [todayStreakId, followUpId, legacyDailyId])
        }

        // 2. Reconcile Registered Contests
        let contests = tasks.filter { $0.isContest }
        for contest in contests {
            let dayId = Self.contestDayReminderIdentifier(for: contest.id)
            let min15Id = Self.contest15MinReminderIdentifier(for: contest.id)

            if contest.registrationStatus != .registered || contest.isCompleted || contest.calendarEventId != nil {
                // Not registered, already complete, or handled by Apple Calendar alarms -> remove local notification requests
                center.removePendingNotificationRequests(withIdentifiers: [dayId, min15Id])
                continue
            }

            let plans = Self.calculateContestRemindersPlan(
                contest: contest,
                calendar: calendar,
                now: now,
                isDayReminderEnabled: notifyContestDay,
                is15MinReminderEnabled: notifyContest15m,
                dayReminderHour: contestHour,
                dayReminderMinute: contestMinute
            )

            // Day reminder
            if let dayPlan = plans.first(where: { $0.identifier == dayId }) {
                await schedulePlan(dayPlan, calendar: calendar)
            } else {
                center.removePendingNotificationRequests(withIdentifiers: [dayId])
            }

            // 15-minute reminder
            if let min15Plan = plans.first(where: { $0.identifier == min15Id }) {
                await schedulePlan(min15Plan, calendar: calendar)
            } else {
                center.removePendingNotificationRequests(withIdentifiers: [min15Id])
            }
        }
    }

    /// Helper to add a UNNotificationRequest matching a plan's calendar trigger.
    private func schedulePlan(_ plan: CodingReminderPlan, calendar: Calendar) async {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.categoryIdentifier = plan.category
        content.userInfo = ["source": "coding_radar", "planId": plan.identifier]

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: plan.triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule Coding Radar notification \(plan.identifier): \(error.localizedDescription)")
        }
    }

    /// Schedules a 1-hour follow-up notification.
    func scheduleOneHourFollowUpReminder(calendar: Calendar = .current, now: Date = Date()) async {
        let plan = Self.calculateFollowUpReminderPlan(calendar: calendar, now: now)
        await schedulePlan(plan, calendar: calendar)
    }

    /// Cancels all notifications for a specific contest when deleted or uncompleted.
    func cancelReminders(for contestId: UUID) {
        let ids = [
            Self.contestDayReminderIdentifier(for: contestId),
            Self.contest15MinReminderIdentifier(for: contestId)
        ]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// Cancels today's daily reminder (e.g. after user solves a daily problem).
    func cancelTodayDailyReminder(calendar: Calendar = .current, now: Date = Date()) {
        cancelTodayStreakReminders(calendar: calendar, now: now)
    }

    /// Cancels today's streak reminder and any active follow-up (e.g. after user completes an activity).
    func cancelTodayStreakReminders(calendar: Calendar = .current, now: Date = Date()) {
        let streakId = Self.streakReminderIdentifier(for: now, calendar: calendar)
        let followUpId = Self.followUpReminderIdentifier(for: now, calendar: calendar)
        let dailyId = Self.dailyReminderIdentifier(for: now, calendar: calendar)
        center.removePendingNotificationRequests(withIdentifiers: [streakId, followUpId, dailyId])
        center.removeDeliveredNotifications(withIdentifiers: [streakId, followUpId, dailyId])
    }
}
