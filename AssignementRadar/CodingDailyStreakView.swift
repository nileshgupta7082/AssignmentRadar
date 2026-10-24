//
//  CodingDailyStreakView.swift
//  AssignementRadar
//
//  Created for Coding Radar Daily Streak & Activity Calendar Component.
//

import SwiftUI

struct CodingDailyStreakView: View {
    let stats: CodingStreakStats
    let weeks: [[ContributionDay]]
    var onMarkSolvedTapped: (() -> Void)? = nil
    var onReminderTapped: (() -> Void)? = nil

    @AppStorage(CodingNotificationManager.notifyDailyChallengeKey) private var notifyDaily: Bool = true
    @AppStorage(CodingNotificationManager.dailyReminderHourKey) private var reminderHour: Int = CodingNotificationManager.defaultDailyHour
    @AppStorage(CodingNotificationManager.dailyReminderMinuteKey) private var reminderMinute: Int = CodingNotificationManager.defaultDailyMinute

    @Environment(\.colorScheme) private var colorScheme


    private var reminderFormattedText: String {
        guard notifyDaily else { return "Reminder Off" }
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.hour = reminderHour
        comps.minute = reminderMinute
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        if let d = calendar.date(from: comps) {
            return "Reminder: \(formatter.string(from: d))"
        }
        return "Reminder: \(reminderHour):\(String(format: "%02d", reminderMinute))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Header & Streak Numbers
            HStack(alignment: .center, spacing: 10) {
                // Streak Flame Icon
                ZStack {
                    Circle()
                        .fill(Color(hex: "#22C55E").opacity(0.16))
                        .frame(width: 38, height: 38)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: "#22C55E"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(stats.currentStreak) Day\(stats.currentStreak == 1 ? "" : "s")")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.theme.primaryText)

                        Text("Streak")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.theme.secondaryText)
                    }

                    HStack(spacing: 8) {
                        if stats.longestStreak > 0 {
                            Text("Best: \(stats.longestStreak)d")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.theme.secondaryText)
                        }

                        Text("Total: \(stats.totalProblemsSolved) solved")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.theme.secondaryText)
                    }
                }

                Spacer()

                // Today Status Badge
                if stats.isTodayActive {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text("Active Today (\(stats.problemsCompletedToday))")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "#22C55E").opacity(0.15))
                    .foregroundStyle(Color(hex: "#22C55E"))
                    .clipShape(Capsule())
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("No problems solved today")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.theme.secondarySurface)
                    .foregroundStyle(Color.theme.secondaryText)
                    .clipShape(Capsule())
                }
            }

            // MARK: - Activity Grid
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 3) {
                        // Weekday Labels
                        VStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { dayIndex in
                                Text(weekdayLabel(for: dayIndex))
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(Color.theme.secondaryText)
                                    .frame(width: 10, height: 11)
                            }
                        }
                        .padding(.trailing, 2)

                        // Week Columns
                        ForEach(weeks.indices, id: \.self) { weekIndex in
                            VStack(spacing: 3) {
                                ForEach(weeks[weekIndex]) { day in
                                    contributionCell(for: day)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                // Legend
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Less")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.theme.secondaryText)

                        cellView(color: inactiveCellColor)
                        cellView(color: Color(hex: "#22C55E").opacity(0.5))
                        cellView(color: Color(hex: "#22C55E"))
                        cellView(color: Color(hex: "#15803D"))

                        Text("More")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.theme.secondaryText)
                    }
                }
                .padding(.top, 1)
            }

            // MARK: - Bottom Actions Bar: Reminder Info & Mark Solved
            Divider()
                .background(Color.theme.divider)

            HStack {
                Button {
                    onReminderTapped?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: notifyDaily ? "bell.badge.fill" : "bell.slash")
                            .font(.caption2)
                            .foregroundStyle(notifyDaily ? Color(hex: "#FFA116") : Color.theme.secondaryText)
                        Text(reminderFormattedText)
                            .font(.caption2)
                            .foregroundStyle(Color.theme.secondaryText)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    onMarkSolvedTapped?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption2)
                        Text("Mark Solved")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(hex: "#22C55E").opacity(0.18))
                    .foregroundStyle(Color(hex: "#22C55E"))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.theme.divider, lineWidth: 0.5)
        )
    }

    // MARK: - Subcomponents

    @ViewBuilder
    private func contributionCell(for day: ContributionDay) -> some View {
        let fill = cellColor(for: day)

        RoundedRectangle(cornerRadius: 2)
            .fill(fill)
            .frame(width: 11, height: 11)
            .overlay(
                Group {
                    if day.isToday {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.theme.primaryText.opacity(0.6), lineWidth: 1)
                    }
                }
            )
            .accessibilityLabel(accessibilityText(for: day))
    }

    private func cellView(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 9, height: 9)
    }

    private var inactiveCellColor: Color {
        if colorScheme == .dark {
            return Color(hex: "#283022")
        } else {
            return Color(hex: "#E5E4D8")
        }
    }

    private func cellColor(for day: ContributionDay) -> Color {
        if day.isFuture {
            return inactiveCellColor.opacity(0.3)
        }
        switch day.intensityLevel {
        case 1:
            return Color(hex: "#22C55E").opacity(0.55)
        case 2:
            return Color(hex: "#22C55E")
        case 3:
            return Color(hex: "#15803D")
        default:
            return inactiveCellColor
        }
    }

    private func weekdayLabel(for index: Int) -> String {
        switch index {
        case 1: return "M"
        case 3: return "W"
        case 5: return "F"
        default: return ""
        }
    }

    private func accessibilityText(for day: ContributionDay) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let dateStr = formatter.string(from: day.date)
        if day.count == 0 {
            return "\(dateStr): No tasks completed"
        }
        return "\(dateStr): \(day.count) task\(day.count == 1 ? "" : "s") completed"
    }
}
