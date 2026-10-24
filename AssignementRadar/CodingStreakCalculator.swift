//
//  CodingStreakCalculator.swift
//  AssignementRadar
//
//  Created for Coding Radar Daily Streak & Activity Calendar.
//

import Foundation
import SwiftUI

// MARK: - Streak Statistics

/// Encapsulates calculated streak metrics and daily completion distributions.
struct CodingStreakStats: Equatable {
    let currentStreak: Int
    let longestStreak: Int
    let totalActiveDays: Int
    let totalProblemsSolved: Int
    let problemsCompletedToday: Int
    let isTodayActive: Bool
    let activeDates: Set<Date>
    let dailyCompletionsCount: [Date: Int]

    init(
        currentStreak: Int,
        longestStreak: Int,
        totalActiveDays: Int,
        totalProblemsSolved: Int? = nil,
        problemsCompletedToday: Int? = nil,
        isTodayActive: Bool? = nil,
        activeDates: Set<Date>,
        dailyCompletionsCount: [Date: Int]
    ) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.totalActiveDays = totalActiveDays
        let sumCounts = dailyCompletionsCount.values.reduce(0, +)
        self.totalProblemsSolved = totalProblemsSolved ?? sumCounts
        let todayVal = dailyCompletionsCount.first { Calendar.current.isDateInToday($0.key) }?.value ?? 0
        self.problemsCompletedToday = problemsCompletedToday ?? todayVal
        self.isTodayActive = isTodayActive ?? (self.problemsCompletedToday > 0)
        self.activeDates = activeDates
        self.dailyCompletionsCount = dailyCompletionsCount
    }
}

// MARK: - Contribution Day

/// Represents a single cell in the LeetCode-style contribution grid.
struct ContributionDay: Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    let count: Int
    let isFuture: Bool
    let isToday: Bool

    /// Activity intensity level:
    /// 0: Inactive
    /// 1: 1 completion (light green)
    /// 2: 2 completions (medium green)
    /// 3: 3+ completions (intense green)
    var intensityLevel: Int {
        if isFuture || count == 0 { return 0 }
        if count == 1 { return 1 }
        if count == 2 { return 2 }
        return 3
    }
}

// MARK: - Streak Calculator Engine

enum CodingStreakCalculator {
    /// Computes streak statistics from unified coding activity records and completed tasks.
    /// Multiple completions on one day count as a single active day.
    static func calculate(
        activities: [CodingActivityRecord] = [],
        tasks: [CodingTask] = [],
        calendar: Calendar = Calendar.current,
        now: Date = Date()
    ) -> CodingStreakStats {
        var dailyCounts: [Date: Int] = [:]
        var seenProblemKeys: Set<String> = []

        // 1. Process dedicated activity records
        for activity in activities {
            let start = calendar.startOfDay(for: activity.completedAt)
            let uniqueKey = "\(activity.platformId)_\(activity.providerSubmissionId ?? activity.problemTitle.lowercased())_\(start.timeIntervalSince1970)"
            if !seenProblemKeys.contains(uniqueKey) {
                seenProblemKeys.insert(uniqueKey)
                dailyCounts[start, default: 0] += 1
            }
        }

        // 2. Process completed coding tasks (e.g. daily question checkboxes, practice problems)
        for task in tasks where task.isCompleted {
            let completionDate = task.completedAt ?? task.createdAt
            let start = calendar.startOfDay(for: completionDate)
            let uniqueKey = "\(task.platformId)_\(task.providerEventId ?? task.title.lowercased())_\(start.timeIntervalSince1970)"
            if !seenProblemKeys.contains(uniqueKey) {
                seenProblemKeys.insert(uniqueKey)
                dailyCounts[start, default: 0] += 1
            }
        }

        let activeDates = Set(dailyCounts.keys)
        let totalActiveDays = activeDates.count
        let totalProblemsSolved = dailyCounts.values.reduce(0, +)
        let today = calendar.startOfDay(for: now)
        let problemsCompletedToday = dailyCounts[today, default: 0]
        let isTodayActive = activeDates.contains(today)

        guard !activeDates.isEmpty else {
            return CodingStreakStats(
                currentStreak: 0,
                longestStreak: 0,
                totalActiveDays: 0,
                totalProblemsSolved: 0,
                problemsCompletedToday: 0,
                isTodayActive: false,
                activeDates: [],
                dailyCompletionsCount: [:]
            )
        }

        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            return CodingStreakStats(
                currentStreak: 0,
                longestStreak: 0,
                totalActiveDays: totalActiveDays,
                totalProblemsSolved: totalProblemsSolved,
                problemsCompletedToday: problemsCompletedToday,
                isTodayActive: isTodayActive,
                activeDates: activeDates,
                dailyCompletionsCount: dailyCounts
            )
        }

        // Current streak:
        // 1. If active today, count consecutive active days going backwards ending today.
        // 2. If not active today, but active yesterday, count consecutive active days ending yesterday (streak maintained pending today).
        // 3. Otherwise streak is broken (0).
        var currentStreak = 0
        if activeDates.contains(today) {
            var checkDate = today
            while activeDates.contains(checkDate) {
                currentStreak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = prev
            }
        } else if activeDates.contains(yesterday) {
            var checkDate = yesterday
            while activeDates.contains(checkDate) {
                currentStreak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = prev
            }
        }

        // Longest streak:
        // Sort all unique active calendar days chronologically and find the maximum run of consecutive calendar days.
        let sortedDates = activeDates.sorted()
        var calculatedLongest = 0
        var currentRun = 0
        var previousDate: Date? = nil

        for date in sortedDates {
            if let prev = previousDate {
                if let nextDay = calendar.date(byAdding: .day, value: 1, to: prev),
                   calendar.isDate(nextDay, inSameDayAs: date) {
                    currentRun += 1
                } else {
                    currentRun = 1
                }
            } else {
                currentRun = 1
            }
            calculatedLongest = max(calculatedLongest, currentRun)
            previousDate = date
        }

        let longestStreak = max(calculatedLongest, currentStreak)

        return CodingStreakStats(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            totalActiveDays: totalActiveDays,
            totalProblemsSolved: totalProblemsSolved,
            problemsCompletedToday: problemsCompletedToday,
            isTodayActive: isTodayActive,
            activeDates: activeDates,
            dailyCompletionsCount: dailyCounts
        )
    }

    /// Convenience overload for existing task-only calls.
    static func calculate(
        tasks: [CodingTask],
        calendar: Calendar = Calendar.current,
        now: Date = Date()
    ) -> CodingStreakStats {
        calculate(activities: [], tasks: tasks, calendar: calendar, now: now)
    }

    /// Convenience overload for activity-only calls.
    static func calculate(
        activities: [CodingActivityRecord],
        calendar: Calendar = Calendar.current,
        now: Date = Date()
    ) -> CodingStreakStats {
        calculate(activities: activities, tasks: [], calendar: calendar, now: now)
    }

    /// Builds a matrix of rolling weeks for the LeetCode-inspired green contribution grid.
    /// Returns an array of columns (weeks), each containing 7 days.
    static func buildContributionGrid(
        activeCounts: [Date: Int],
        numberOfWeeks: Int = 14,
        calendar: Calendar = Calendar.current,
        now: Date = Date()
    ) -> [[ContributionDay]] {
        let today = calendar.startOfDay(for: now)

        // Find the start of the current week (weekday 1)
        let currentWeekDay = calendar.component(.weekday, from: today)
        // Days elapsed in the current week (0-indexed)
        let daysIntoWeek = (currentWeekDay - calendar.firstWeekday + 7) % 7

        guard let currentWeekStart = calendar.date(byAdding: .day, value: -daysIntoWeek, to: today),
              let gridStart = calendar.date(byAdding: .weekOfYear, value: -(numberOfWeeks - 1), to: currentWeekStart) else {
            return []
        }

        var weeks: [[ContributionDay]] = []

        for weekOffset in 0..<numberOfWeeks {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: gridStart) else { continue }
            var days: [ContributionDay] = []

            for dayOffset in 0..<7 {
                guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
                let normalized = calendar.startOfDay(for: dayDate)
                let count = activeCounts[normalized] ?? 0
                let isFuture = normalized > today
                let isToday = calendar.isDate(normalized, inSameDayAs: today)

                days.append(
                    ContributionDay(
                        date: normalized,
                        count: count,
                        isFuture: isFuture,
                        isToday: isToday
                    )
                )
            }
            weeks.append(days)
        }

        return weeks
    }
}
