//
//  CodingRadarSettingsView.swift
//  AssignementRadar
//
//  Created for Coding Radar Notification Settings.
//

import SwiftUI
import UserNotifications
import SwiftData

struct CodingRadarSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var codingTasks: [CodingTask]
    @Query private var codingActivities: [CodingActivityRecord]

    // Notification Toggles & Time Preferences
    @AppStorage(CodingNotificationManager.notifyDailyChallengeKey) private var notifyDaily: Bool = true
    @AppStorage(CodingNotificationManager.dailyReminderHourKey) private var reminderHour: Int = CodingNotificationManager.defaultDailyHour
    @AppStorage(CodingNotificationManager.dailyReminderMinuteKey) private var reminderMinute: Int = CodingNotificationManager.defaultDailyMinute
    @AppStorage(CodingNotificationManager.notifyContestDayKey) private var notifyContestDay: Bool = true
    @AppStorage(CodingNotificationManager.notifyContest15mKey) private var notifyContest15m: Bool = true

    @State private var reminderTime: Date = {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.hour = UserDefaults.standard.object(forKey: CodingNotificationManager.dailyReminderHourKey) as? Int ?? CodingNotificationManager.defaultDailyHour
        comps.minute = UserDefaults.standard.object(forKey: CodingNotificationManager.dailyReminderMinuteKey) as? Int ?? CodingNotificationManager.defaultDailyMinute
        return calendar.date(from: comps) ?? Date()
    }()
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Notification Permission
                Section("Notification Permission") {
                    HStack {
                        Label {
                            Text("Permission")
                                .font(.subheadline)
                        } icon: {
                            Image(systemName: permissionIcon)
                                .foregroundStyle(permissionColor)
                        }

                        Spacer()

                        Text(permissionLabel)
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundStyle(permissionColor)
                    }

                    if authStatus == .denied {
                        Text("Notifications are currently disabled in iOS Settings. Enable them to receive daily streak alerts and contest countdowns.")
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)

                        Button("Open iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.theme.primaryAccent)
                    } else if authStatus == .notDetermined {
                        Button("Allow Notifications") {
                            Task {
                                await NotificationService.shared.requestAuthorizationIfNeeded()
                                await refreshAuthStatus()
                                await CodingNotificationManager.shared.reconcile(tasks: codingTasks, activities: codingActivities)
                            }
                        }
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.theme.primaryAccent)
                    }
                }

                // Section 2: Coding Streak Reminder
                Section("Daily Streak Reminder") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Daily Streak Reminder", isOn: $notifyDaily)
                            .font(.subheadline)
                            .onChange(of: notifyDaily) { _, _ in
                                triggerReconcile()
                            }

                        Text("Sends a smart reminder if you haven't completed any qualifying coding activity today.")
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)
                    }
                    .padding(.vertical, 2)

                    if notifyDaily {
                        DatePicker(
                            "Reminder Time",
                            selection: $reminderTime,
                            displayedComponents: .hourAndMinute
                        )
                        .font(.subheadline)
                        .onChange(of: reminderTime) { _, newTime in
                            let calendar = Calendar.current
                            let comps = calendar.dateComponents([.hour, .minute], from: newTime)
                            reminderHour = comps.hour ?? CodingNotificationManager.defaultDailyHour
                            reminderMinute = comps.minute ?? CodingNotificationManager.defaultDailyMinute
                            triggerReconcile()
                        }
                    }
                }

                // Section 3: Contest Reminders
                Section("Contest Reminders") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Contest Day (9:00 AM)", isOn: $notifyContestDay)
                            .font(.subheadline)
                            .onChange(of: notifyContestDay) { _, _ in
                                triggerReconcile()
                            }

                        Text("Sends a morning briefing at 9:00 AM for registered contests.")
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)
                    }
                    .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("15 Minutes Before Contest", isOn: $notifyContest15m)
                            .font(.subheadline)
                            .onChange(of: notifyContest15m) { _, _ in
                                triggerReconcile()
                            }

                        Text("Countdown alert before the contest begins so you can prepare.")
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)
                    }
                    .padding(.vertical, 2)
                }

                // Section 3: Streak & Privacy Policy Note
                Section("Streak Policy") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill")
                                .font(.footnote)
                                .foregroundStyle(Color(hex: "#22C55E"))

                            Text("Local Assignment Radar Streak")
                                .font(.footnote)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.theme.primaryText)
                        }

                        Text("Daily streaks are computed locally from your explicit task completions. Notifications are scheduled on-device through iOS UserNotifications without background timers.")
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Coding Radar Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.theme.primaryAccent)
                }
            }
            .task {
                await refreshAuthStatus()
            }
        }
    }

    private func refreshAuthStatus() async {
        authStatus = await NotificationService.shared.getAuthorizationStatus()
    }

    private func triggerReconcile() {
        Task {
            await CodingNotificationManager.shared.reconcile(tasks: codingTasks, activities: codingActivities)
        }
    }

    private var permissionIcon: String {
        switch authStatus {
        case .authorized, .provisional: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        default: return "questionmark.circle"
        }
    }

    private var permissionColor: Color {
        switch authStatus {
        case .authorized, .provisional: return Color(hex: "#22C55E")
        case .denied: return Color.theme.overdue
        default: return Color.theme.secondaryText
        }
    }

    private var permissionLabel: String {
        switch authStatus {
        case .authorized: return "Enabled"
        case .provisional: return "Provisional"
        case .denied: return "Disabled"
        case .notDetermined: return "Not Determined"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }
}
