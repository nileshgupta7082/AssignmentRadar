//
//  RefreshCoordinator.swift
//  AssignementRadar
//
//  Created for Assignment Radar Centralized Refresh Architecture.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

/// Central coordinator that orchestrates multi-platform synchronization,
/// handles concurrency locks, partial failures, deduplication, and persistence.
@MainActor
final class RefreshCoordinator: ObservableObject {
    static let shared = RefreshCoordinator()

    // MARK: - State Properties

    @Published var isRefreshing: Bool = false
    @Published var lastStatusMessage: String? = nil
    @Published var lastRefreshedAt: Date? = nil
    @Published var lastCodingRefreshedAt: Date? = nil
    @Published var isError: Bool = false

    // Provider References
    let moodleProvider = MoodleProvider.shared
    let leetCodeProvider = LeetCodeProvider.shared
    let gfgProvider = GeeksForGeeksProvider.shared

    private var messageDismissTask: Task<Void, Never>?

    init() {
        moodleProvider.updateConnectionStatus()
    }

    // MARK: - Synchronize Academic Workspace (Assignment Radar)

    /// Refreshes academic assignments from Moodle, local OCR tasks, cloud task state, and Apple Calendar.
    /// Strictly separated from coding feeds to preserve pure academic focus.
    func refreshAcademic(modelContext: ModelContext) async {
        guard !isRefreshing else { return }

        isRefreshing = true
        messageDismissTask?.cancel()

        var moodleSuccess = false
        var moodleNewCount = 0

        let isMoodleConfigured = moodleProvider.isConfigured

        if isMoodleConfigured {
            if let res = try? await moodleProvider.syncAssignments(modelContext: modelContext) {
                moodleSuccess = true
                moodleNewCount = res.newCount
            }
        } else {
            _ = try? await TaskSyncCoordinator.shared.syncWithBackend(modelContext: modelContext)
        }

        if moodleSuccess && CalendarSyncService.shared.isCalendarSyncEnabled {
            let descriptor = FetchDescriptor<Assignment>(predicate: #Predicate { !$0.isArchived })
            if let active = try? modelContext.fetch(descriptor) {
                await CalendarSyncService.shared.syncAssignments(active)
            }
        }

        self.lastRefreshedAt = Date()
        self.isRefreshing = false

        if isMoodleConfigured {
            if moodleSuccess {
                if moodleNewCount > 0 {
                    presentMessage("Moodle synced (\(moodleNewCount) new deadline\(moodleNewCount == 1 ? "" : "s")).", isError: false)
                } else {
                    presentMessage("Academic deadlines are up to date.", isError: false)
                }
            } else {
                presentMessage("Moodle sync failed. Check your network or credentials.", isError: true)
            }
        } else {
            presentMessage("Local academic deadlines up to date.", isError: false)
        }
    }

    // MARK: - Synchronize Coding Workspace (Coding Radar)

    /// Refreshes live coding challenge feeds (LeetCode, GFG) for connected platforms and syncs into SwiftData.
    func refreshCoding(modelContext: ModelContext) async {
        guard !isRefreshing else { return }

        isRefreshing = true
        messageDismissTask?.cancel()

        // 1. Check which platforms are tracked by the user
        let platformDescriptor = FetchDescriptor<TrackedPlatform>()
        let tracked = (try? modelContext.fetch(platformDescriptor)) ?? []
        let lcPlatform = tracked.first(where: { $0.platformId == "leetcode" })
        let gfgPlatform = tracked.first(where: { $0.platformId == "gfg" })
        let isLeetCodeTracked = lcPlatform != nil
        let isGFGTracked = gfgPlatform != nil

        var lcSuccess = false
        var gfgSuccess = false

        // 2. Fetch live data independently
        if isLeetCodeTracked {
            do {
                try await leetCodeProvider.refresh()
                lcSuccess = true
            } catch {
                print("LeetCode live refresh: \(error.localizedDescription)")
            }
        }

        if isGFGTracked {
            do {
                try await gfgProvider.refresh()
                gfgSuccess = true
            } catch {
                print("GeeksforGeeks live refresh: \(error.localizedDescription)")
            }
        }

        // 3. Sync into SwiftData
        let taskDescriptor = FetchDescriptor<CodingTask>()
        let existingTasks = (try? modelContext.fetch(taskDescriptor)) ?? []
        let calendar = Calendar.current
        let today = Date()

        // Sync LeetCode Daily Challenge
        if isLeetCodeTracked, let daily = leetCodeProvider.dailyQuestion {
            let cleanTitle = "\(daily.questionFrontendId). \(daily.title)"
            let dailyEventId = "leetcode_\(daily.date)"
            if let existing = existingTasks.first(where: {
                $0.platformId == "leetcode" && $0.isDailyQuestion &&
                ($0.providerEventId == dailyEventId || $0.providerEventId == daily.date || $0.officialUrl == daily.problemUrl?.absoluteString || calendar.isDate($0.dueDate ?? $0.createdAt, inSameDayAs: today))
            }) {
                existing.title = cleanTitle
                existing.difficulty = daily.difficulty
                existing.topicTags = daily.topicTags.isEmpty ? "Daily Challenge" : daily.topicTags.joined(separator: ", ")
                existing.officialUrl = daily.problemUrl?.absoluteString
                existing.providerEventId = dailyEventId
            } else {
                let newTask = CodingTask(
                    title: cleanTitle,
                    platformId: "leetcode",
                    platformName: "LeetCode",
                    taskType: .dailyQuestion,
                    difficulty: daily.difficulty,
                    topicTags: daily.topicTags.isEmpty ? "Daily Challenge" : daily.topicTags.joined(separator: ", "),
                    dueDate: calendar.date(bySettingHour: 23, minute: 59, second: 59, of: today) ?? today,
                    officialUrl: daily.problemUrl?.absoluteString,
                    notes: "LeetCode Daily Challenge (\(daily.date))",
                    isCompleted: leetCodeProvider.isDailySolvedLocally(date: daily.date),
                    isManualEvent: false,
                    providerEventId: dailyEventId
                )
                modelContext.insert(newTask)
            }
        }

        // Sync LeetCode Upcoming Contests
        if isLeetCodeTracked {
            for contest in leetCodeProvider.upcomingContests {
                let contestEventId = "leetcode_\(contest.titleSlug)"
                if let existing = existingTasks.first(where: {
                    $0.platformId == "leetcode" && $0.isContest &&
                    ($0.providerEventId == contestEventId || $0.providerEventId == contest.titleSlug || $0.officialUrl == contest.contestUrl?.absoluteString || $0.title == contest.title)
                }) {
                    existing.title = contest.title
                    existing.startDate = contest.startTime
                    existing.dueDate = contest.endTime
                    existing.endDate = contest.endTime
                    existing.officialUrl = contest.contestUrl?.absoluteString
                    existing.providerEventId = contestEventId
                } else {
                    let newContest = CodingTask(
                        title: contest.title,
                        platformId: "leetcode",
                        platformName: "LeetCode",
                        taskType: .contest,
                        registrationStatus: .interested,
                        startDate: contest.startTime,
                        dueDate: contest.endTime,
                        endDate: contest.endTime,
                        officialUrl: contest.contestUrl?.absoluteString,
                        notes: "Official LeetCode Contest (\(contest.formattedDuration))",
                        isCompleted: false,
                        isManualEvent: false,
                        providerEventId: contestEventId
                    )
                    modelContext.insert(newContest)
                }
            }
        }

        // Sync GeeksforGeeks Problem of the Day
        if isGFGTracked, let potd = gfgProvider.dailyProblem {
            let gfgEventId = "gfg_\(potd.date)"
            if let existing = existingTasks.first(where: {
                $0.platformId == "gfg" && $0.isDailyQuestion &&
                ($0.providerEventId == gfgEventId || $0.providerEventId == potd.date || $0.officialUrl == potd.problemUrl?.absoluteString || calendar.isDate($0.dueDate ?? $0.createdAt, inSameDayAs: today))
            }) {
                existing.title = potd.title
                existing.difficulty = potd.difficulty
                existing.topicTags = potd.topicTags.isEmpty ? "Problem of the Day" : potd.topicTags.joined(separator: ", ")
                existing.officialUrl = potd.problemUrl?.absoluteString
                existing.providerEventId = gfgEventId
            } else {
                let newTask = CodingTask(
                    title: potd.title,
                    platformId: "gfg",
                    platformName: "GeeksforGeeks",
                    taskType: .dailyQuestion,
                    difficulty: potd.difficulty,
                    topicTags: potd.topicTags.isEmpty ? "Problem of the Day" : potd.topicTags.joined(separator: ", "),
                    dueDate: calendar.date(bySettingHour: 23, minute: 59, second: 59, of: today) ?? today,
                    officialUrl: potd.problemUrl?.absoluteString,
                    notes: "GeeksforGeeks Problem of the Day (\(potd.date))",
                    isCompleted: gfgProvider.isPOTDSolvedLocally(date: potd.date),
                    isManualEvent: false,
                    providerEventId: gfgEventId
                )
                modelContext.insert(newTask)
            }
        }

        // Sync LeetCode Solved Problem Submissions (if handle is configured)
        if isLeetCodeTracked, let handle = lcPlatform?.customHandle?.trimmingCharacters(in: .whitespacesAndNewlines), !handle.isEmpty {
            do {
                let recentSubs = try await leetCodeProvider.fetchRecentAcSubmissions(username: handle, limit: 20)
                let activityDescriptor = FetchDescriptor<CodingActivityRecord>()
                let existingActivities = (try? modelContext.fetch(activityDescriptor)) ?? []

                for sub in recentSubs {
                    let isDuplicate = existingActivities.contains { record in
                        if let subId = record.providerSubmissionId, subId == sub.id {
                            return true
                        }
                        return record.platformId == "leetcode" &&
                               record.problemId == sub.titleSlug &&
                               calendar.isDate(record.completedAt, inSameDayAs: sub.timestamp)
                    }

                    if !isDuplicate {
                        let record = CodingActivityRecord(
                            platformId: "leetcode",
                            platformName: "LeetCode",
                            problemTitle: sub.title,
                            problemId: sub.titleSlug,
                            completedAt: sub.timestamp,
                            verificationSource: .providerSynced,
                            problemUrl: "https://leetcode.com/problems/\(sub.titleSlug)/",
                            providerSubmissionId: sub.id
                        )
                        modelContext.insert(record)
                    }
                }
            } catch {
                print("LeetCode recent submissions fetch error: \(error.localizedDescription)")
            }
        }

        try? modelContext.save()

        self.lastCodingRefreshedAt = Date()
        self.lastRefreshedAt = Date()
        self.isRefreshing = false

        // Reconcile notifications
        let refreshedTasks = (try? modelContext.fetch(taskDescriptor)) ?? []
        let activityDescriptor = FetchDescriptor<CodingActivityRecord>()
        let refreshedActivities = (try? modelContext.fetch(activityDescriptor)) ?? []
        await CodingNotificationManager.shared.reconcile(tasks: refreshedTasks, activities: refreshedActivities)

        if lcSuccess || gfgSuccess {
            presentMessage("Coding feeds synced.", isError: false)
        } else if isLeetCodeTracked || isGFGTracked {
            presentMessage("Could not refresh live feeds. Offline or unreachable.", isError: true)
        } else {
            presentMessage("Coding Radar up to date.", isError: false)
        }
    }

    /// Legacy / parameterless fallback refresh.
    func refreshCoding() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        messageDismissTask?.cancel()

        async let leetCodeTask: Bool = {
            (try? await self.leetCodeProvider.refresh()) != nil
        }()
        async let gfgTask: Bool = {
            (try? await self.gfgProvider.refresh()) != nil
        }()

        let (lcRes, gfgRes) = await (leetCodeTask, gfgTask)
        self.isRefreshing = false
        self.lastCodingRefreshedAt = Date()

        if lcRes || gfgRes {
            presentMessage("Coding challenge feeds updated.", isError: false)
        } else {
            presentMessage("Coding feeds unreachable. Manual tracking active.", isError: false)
        }
    }

    // MARK: - Synchronize All Configured Sources (Legacy / Comprehensive)

    /// Performs centralized refresh across all supported platforms concurrently.
    /// Handles partial failures gracefully without discarding successful updates.
    func refreshAll(modelContext: ModelContext) async {
        // Prevent multiple overlapping operations
        guard !isRefreshing else { return }

        isRefreshing = true
        messageDismissTask?.cancel()

        var moodleSuccess = false
        var moodleNewCount = 0
        var leetCodeSuccess = false
        var gfgSuccess = false

        // 1. Moodle & Cloud Backend Synchronization
        let isMoodleConfigured = moodleProvider.isConfigured

        // Launch operations concurrently
        async let moodleTask: (synced: Int, newCount: Int)? = {
            if isMoodleConfigured {
                return try? await self.moodleProvider.syncAssignments(modelContext: modelContext)
            } else {
                _ = try? await TaskSyncCoordinator.shared.syncWithBackend(modelContext: modelContext)
                return nil
            }
        }()

        async let leetCodeTask: Bool = {
            do {
                try await self.leetCodeProvider.refresh()
                return true
            } catch {
                return false
            }
        }()

        async let gfgTask: Bool = {
            do {
                try await self.gfgProvider.refresh()
                return true
            } catch {
                return false
            }
        }()

        // Await all independent sources
        let (moodleRes, leetCodeRes, gfgRes) = await (moodleTask, leetCodeTask, gfgTask)

        if let m = moodleRes {
            moodleSuccess = true
            moodleNewCount = m.newCount
        }
        leetCodeSuccess = leetCodeRes
        gfgSuccess = gfgRes

        // Synchronize with Apple Calendar if integration is enabled
        if moodleSuccess && CalendarSyncService.shared.isCalendarSyncEnabled {
            let descriptor = FetchDescriptor<Assignment>(predicate: #Predicate { !$0.isArchived })
            if let active = try? modelContext.fetch(descriptor) {
                await CalendarSyncService.shared.syncAssignments(active)
            }
        }

        // 2. Derive concise, user-friendly outcome message
        self.lastRefreshedAt = Date()
        self.isRefreshing = false

        if isMoodleConfigured {
            if moodleSuccess {
                if moodleNewCount > 0 {
                    presentMessage("Moodle (\(moodleNewCount) new) deadlines updated.", isError: false)
                } else {
                    presentMessage("Academic deadlines updated successfully.", isError: false)
                }
            } else {
                presentMessage("Moodle sync failed. Check your login.", isError: true)
            }
        } else {
            presentMessage("Academic schedule up to date.", isError: false)
        }
    }

    // MARK: - Toast Banner Helpers

    private func presentMessage(_ message: String, isError: Bool) {
        self.lastStatusMessage = message
        self.isError = isError

        // Automatically auto-dismiss toast after 4 seconds
        messageDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                withAnimation {
                    self.lastStatusMessage = nil
                }
            }
        }
    }

    func postStatusMessage(_ message: String, isError: Bool = false) {
        presentMessage(message, isError: isError)
    }

    func clearStatusMessage() {
        messageDismissTask?.cancel()
        withAnimation {
            lastStatusMessage = nil
        }
    }
}
