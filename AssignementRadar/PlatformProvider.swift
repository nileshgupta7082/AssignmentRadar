//
//  PlatformProvider.swift
//  AssignementRadar
//
//  Created for Assignment Radar Multi-Platform Architecture.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

// MARK: - Connection & Status State

/// Explicit status of a platform integration provider.
enum ProviderConnectionStatus: Equatable {
    case connected(details: String)
    case notConnected(reason: String)
    case connecting
    case connectionUnavailable(reason: String)
    case syncing
    case error(message: String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var badgeText: String {
        switch self {
        case .connected: return "Connected"
        case .notConnected: return "Not Connected"
        case .connecting: return "Connecting"
        case .connectionUnavailable: return "Connection Unavailable"
        case .syncing: return "Syncing..."
        case .error: return "Error"
        }
    }

    var badgeColor: Color {
        switch self {
        case .connected: return .green
        case .notConnected: return .secondary
        case .connecting: return .blue
        case .connectionUnavailable: return .orange
        case .syncing: return .blue
        case .error: return .red
        }
    }

    var badgeIcon: String {
        switch self {
        case .connected: return "checkmark.circle.fill"
        case .notConnected: return "circle"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .connectionUnavailable: return "exclamationmark.triangle"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - LeetCode DTOs & Models

/// Daily coding challenge question retrieved from official LeetCode GraphQL API.
struct LeetCodeDailyQuestion: Identifiable, Equatable {
    var id: String { date }
    let date: String
    let title: String
    let titleSlug: String
    let difficulty: String
    let questionFrontendId: String
    let problemUrl: URL?
    let topicTags: [String]

    init(
        date: String,
        title: String,
        titleSlug: String,
        difficulty: String,
        questionFrontendId: String,
        problemUrl: URL?,
        topicTags: [String] = []
    ) {
        self.date = date
        self.title = title
        self.titleSlug = titleSlug
        self.difficulty = difficulty
        self.questionFrontendId = questionFrontendId
        self.problemUrl = problemUrl
        self.topicTags = topicTags
    }

    init(
        date: String,
        title: String,
        titleSlug: String,
        difficulty: String,
        questionFrontendId: String,
        problemUrl: URL?
    ) {
        self.init(
            date: date,
            title: title,
            titleSlug: titleSlug,
            difficulty: difficulty,
            questionFrontendId: questionFrontendId,
            problemUrl: problemUrl,
            topicTags: []
        )
    }

    var difficultyColor: Color {
        switch difficulty.lowercased() {
        case "easy": return .green
        case "medium": return .orange
        case "hard": return .red
        default: return .blue
        }
    }
}

/// Upcoming LeetCode coding contest with local start time and countdown awareness.
struct LeetCodeContest: Identifiable, Equatable {
    var id: String { titleSlug }
    let title: String
    let titleSlug: String
    let startTime: Date
    let durationSeconds: Int

    var contestUrl: URL? {
        URL(string: "https://leetcode.com/contest/\(titleSlug)")
    }

    var endTime: Date {
        startTime.addingTimeInterval(TimeInterval(durationSeconds))
    }

    /// Contest is starting within 24 hours.
    var isApproaching: Bool {
        let now = Date()
        return startTime > now && startTime.timeIntervalSince(now) <= 24 * 3600
    }

    /// Contest is currently in progress.
    var isLiveNow: Bool {
        let now = Date()
        return now >= startTime && now <= endTime
    }

    /// Formatted local start date and time.
    var formattedLocalDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }

    /// Human-readable duration (e.g., "1h 30m").
    var formattedDuration: String {
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        if minutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(minutes)m"
    }

    /// Relative time until contest begins.
    var relativeTimeDescription: String {
        let now = Date()
        if isLiveNow {
            return "Live Now"
        }
        if startTime < now {
            return "Ended"
        }
        let interval = startTime.timeIntervalSince(now)
        let hours = Int(interval) / 3600
        let days = hours / 24
        if days > 0 {
            return "Starts in \(days)d \(hours % 24)h"
        } else if hours > 0 {
            return "Starts in \(hours)h"
        } else {
            let minutes = max(1, Int(interval) / 60)
            return "Starts in \(minutes)m"
        }
    }
}

/// An accepted problem submission retrieved from LeetCode's public GraphQL API.
struct LeetCodeSubmissionItem: Identifiable, Equatable {
    let id: String
    let title: String
    let titleSlug: String
    let timestamp: Date

    var problemUrl: URL? {
        URL(string: "https://leetcode.com/problems/\(titleSlug)/")
    }
}

// MARK: - GeeksforGeeks DTOs & Models

/// Problem of the Day retrieved from GeeksforGeeks Practice API.
struct GeeksForGeeksPOTD: Identifiable, Equatable {
    let id: Int
    let date: String
    let title: String
    let difficulty: String
    let problemUrl: URL?
    let topicTags: [String]

    init(
        id: Int,
        date: String,
        title: String,
        difficulty: String,
        problemUrl: URL?,
        topicTags: [String] = []
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.difficulty = difficulty
        self.problemUrl = problemUrl
        self.topicTags = topicTags
    }

    init(
        id: Int,
        date: String,
        title: String,
        difficulty: String,
        problemUrl: URL?
    ) {
        self.init(
            id: id,
            date: date,
            title: title,
            difficulty: difficulty,
            problemUrl: problemUrl,
            topicTags: []
        )
    }

    var difficultyColor: Color {
        switch difficulty.lowercased() {
        case "easy", "basic", "school": return .green
        case "medium": return .orange
        case "hard": return .red
        default: return .blue
        }
    }
}


// MARK: - Modular Provider Protocol

/// Base protocol defining standard provider lifecycle and capabilities.
@MainActor
protocol PlatformProviderProtocol: AnyObject {
    var id: String { get }
    var name: String { get }
    var iconName: String { get }
    var status: ProviderConnectionStatus { get }
    var lastRefreshedAt: Date? { get }
    var isConfigured: Bool { get }
}

// MARK: - LeetCode Provider

@MainActor
final class LeetCodeProvider: ObservableObject, PlatformProviderProtocol {
    static let shared = LeetCodeProvider()

    let id = "leetcode"
    let name = "LeetCode"
    let iconName = "chevron.left.forwardslash.chevron.right"

    @Published var dailyQuestion: LeetCodeDailyQuestion?
    @Published var upcomingContests: [LeetCodeContest] = []
    @Published var status: ProviderConnectionStatus = .notConnected(reason: "Tap Refresh to fetch today's challenge")
    @Published var lastRefreshedAt: Date?
    @Published var lastError: String?

    var isConfigured: Bool { true }

    private let endpoint: URL = URL(string: "https://leetcode.com/graphql") ?? URL(fileURLWithPath: "/")
    private let userDefaultsKeyPrefix = "leetcode_daily_solved_"

    // MARK: - Local Completion Tracking

    /// Checks if a daily challenge has been marked complete locally.
    /// Distinguishes local checkbox from authoritative remote server submission.
    func isDailySolvedLocally(date: String) -> Bool {
        UserDefaults.standard.bool(forKey: "\(userDefaultsKeyPrefix)\(date)")
    }

    /// Toggles local completion state for today's challenge.
    func toggleDailySolvedLocally(date: String) {
        let current = isDailySolvedLocally(date: date)
        UserDefaults.standard.set(!current, forKey: "\(userDefaultsKeyPrefix)\(date)")
        objectWillChange.send()
    }

    // MARK: - Fetch Daily Question & Contests

    func refresh() async throws {
        status = .syncing
        lastError = nil

        do {
            async let fetchedDaily = fetchDailyQuestion()
            async let fetchedContests = fetchUpcomingContests()

            let (daily, contests) = try await (fetchedDaily, fetchedContests)

            self.dailyQuestion = daily
            self.upcomingContests = contests
            self.lastRefreshedAt = Date()
            self.status = .connected(details: "Live Daily Challenge & Contests")
        } catch {
            let errorDesc = "Unable to reach LeetCode: \(error.localizedDescription)"
            self.lastError = errorDesc
            if dailyQuestion == nil {
                self.status = .error(message: "Offline or unreachable")
            } else {
                // Keep existing cached data if temporarily offline
                self.status = .connected(details: "Cached from \(formattedLastRefresh)")
            }
            throw error
        }
    }

    private var formattedLastRefresh: String {
        guard let date = lastRefreshedAt else { return "earlier" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func fetchDailyQuestion() async throws -> LeetCodeDailyQuestion? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let query = """
        query questionOfToday {
          activeDailyCodingChallengeQuestion {
            date
            link
            question {
              questionFrontendId
              title
              titleSlug
              difficulty
              topicTags {
                name
              }
            }
          }
        }
        """

        let body: [String: Any] = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let activeQ = dataDict["activeDailyCodingChallengeQuestion"] as? [String: Any],
              let date = activeQ["date"] as? String,
              let link = activeQ["link"] as? String,
              let question = activeQ["question"] as? [String: Any],
              let title = question["title"] as? String,
              let titleSlug = question["titleSlug"] as? String,
              let difficulty = question["difficulty"] as? String else {
            return nil
        }

        let qId = question["questionFrontendId"] as? String ?? ""
        let cleanLink = link.hasPrefix("http") ? link : "https://leetcode.com\(link)"

        var parsedTags: [String] = []
        if let tagsArray = question["topicTags"] as? [[String: Any]] {
            parsedTags = tagsArray.compactMap { $0["name"] as? String }
        }

        return LeetCodeDailyQuestion(
            date: date,
            title: title,
            titleSlug: titleSlug,
            difficulty: difficulty,
            questionFrontendId: qId,
            problemUrl: URL(string: cleanLink),
            topicTags: parsedTags
        )
    }

    private func fetchUpcomingContests() async throws -> [LeetCodeContest] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let query = """
        query upcomingContests {
          upcomingContests {
            title
            titleSlug
            startTime
            duration
          }
        }
        """

        let body: [String: Any] = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let contestsArray = dataDict["upcomingContests"] as? [[String: Any]] else {
            return []
        }

        var results: [LeetCodeContest] = []
        for item in contestsArray {
            guard let title = item["title"] as? String,
                  let titleSlug = item["titleSlug"] as? String,
                  let startSeconds = item["startTime"] as? Int,
                  let duration = item["duration"] as? Int else {
                continue
            }
            let startDate = Date(timeIntervalSince1970: TimeInterval(startSeconds))
            results.append(LeetCodeContest(
                title: title,
                titleSlug: titleSlug,
                startTime: startDate,
                durationSeconds: duration
            ))
        }

        // Sort upcoming contests in chronological order
        return results.sorted { $0.startTime < $1.startTime }
    }

    /// Fetches recent verified Accepted (AC) submissions for a public LeetCode username.
    /// Uses official public GraphQL endpoint without requiring credentials or private session scraping.
    func fetchRecentAcSubmissions(username: String, limit: Int = 15) async throws -> [LeetCodeSubmissionItem] {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUsername.isEmpty else { return [] }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let query = """
        query getRecentSubmissions($username: String!, $limit: Int!) {
          recentAcSubmissionList(username: $username, limit: $limit) {
            id
            title
            titleSlug
            timestamp
          }
        }
        """

        let body: [String: Any] = [
            "query": query,
            "variables": [
                "username": cleanUsername,
                "limit": limit
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let list = dataDict["recentAcSubmissionList"] as? [[String: Any]] else {
            return []
        }

        var results: [LeetCodeSubmissionItem] = []
        for item in list {
            guard let id = item["id"] as? String,
                  let title = item["title"] as? String,
                  let titleSlug = item["titleSlug"] as? String,
                  let timestampStr = item["timestamp"] as? String,
                  let timeInterval = TimeInterval(timestampStr) else {
                continue
            }
            results.append(LeetCodeSubmissionItem(
                id: id,
                title: title,
                titleSlug: titleSlug,
                timestamp: Date(timeIntervalSince1970: timeInterval)
            ))
        }

        return results
    }
}

// MARK: - GeeksforGeeks Provider

@MainActor
final class GeeksForGeeksProvider: ObservableObject, PlatformProviderProtocol {
    static let shared = GeeksForGeeksProvider()

    let id = "geeksforgeeks"
    let name = "GeeksforGeeks"
    let iconName = "curlybraces"

    @Published var dailyProblem: GeeksForGeeksPOTD?
    @Published var status: ProviderConnectionStatus = .notConnected(reason: "Tap Refresh to fetch Problem of the Day")
    @Published var lastRefreshedAt: Date?
    @Published var lastError: String?

    static let contestsUnavailableReason: String = "GeeksforGeeks official portal requires session authentication for contest listings. Track custom GFG contests using '+ Add Event'."

    var isConfigured: Bool { true }

    private let endpoint: URL = URL(string: "https://practiceapi.geeksforgeeks.org/api/v1/problems-of-day/problem/today/") ?? URL(fileURLWithPath: "/")
    private let userDefaultsKeyPrefix = "gfg_potd_solved_"

    // MARK: - Local Completion Tracking

    /// Checks if today's POTD was completed locally.
    /// Distinguishes local progress from official GeeksforGeeks server submission.
    func isPOTDSolvedLocally(date: String) -> Bool {
        UserDefaults.standard.bool(forKey: "\(userDefaultsKeyPrefix)\(date)")
    }

    /// Toggles local completion state for today's POTD.
    func togglePOTDSolvedLocally(date: String) {
        let current = isPOTDSolvedLocally(date: date)
        UserDefaults.standard.set(!current, forKey: "\(userDefaultsKeyPrefix)\(date)")
        objectWillChange.send()
    }

    // MARK: - Fetch Problem of the Day

    func refresh() async throws {
        status = .syncing
        lastError = nil

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? Int,
                  let title = json["problem_name"] as? String,
                  let difficulty = json["difficulty"] as? String,
                  let urlString = json["problem_url"] as? String else {
                throw URLError(.cannotParseResponse)
            }

            let dateString = json["date"] as? String ?? ""
            let cleanDate = dateString.components(separatedBy: " ").first ?? dateString

            var parsedTopics: [String] = []
            if let tagsDict = json["tags"] as? [String: Any],
               let topics = tagsDict["topic_tags"] as? [String] {
                parsedTopics = topics
            }

            let potd = GeeksForGeeksPOTD(
                id: id,
                date: cleanDate,
                title: title,
                difficulty: difficulty,
                problemUrl: URL(string: urlString),
                topicTags: parsedTopics
            )

            self.dailyProblem = potd
            self.lastRefreshedAt = Date()
            self.status = .connected(details: "Live Problem of the Day")
        } catch {
            let desc = "Unable to reach GeeksforGeeks: \(error.localizedDescription)"
            self.lastError = desc
            if dailyProblem == nil {
                self.status = .error(message: "Offline or unreachable")
            }
            throw error
        }
    }
}


// MARK: - Moodle Provider

@MainActor
final class MoodleProvider: ObservableObject, PlatformProviderProtocol {
    static let shared = MoodleProvider()

    let id = "moodle"
    let name = "Moodle LMS"
    let iconName = "graduationcap.fill"

    @Published var status: ProviderConnectionStatus = .notConnected(reason: "Connect Moodle to sync deadlines")
    @Published var lastRefreshedAt: Date?
    @Published var lastError: String?
    @Published var lastImportedCount: Int = 0

    var isConfigured: Bool {
        let token = MoodleKeychainHelper.getToken()
        let user = UserDefaults.standard.string(forKey: "moodle_connected_user")
        let url = UserDefaults.standard.string(forKey: "moodle_site_url")
        return token != nil && user != nil && !(user?.isEmpty ?? true) && url != nil
    }

    func updateConnectionStatus() {
        if isConfigured {
            let user = UserDefaults.standard.string(forKey: "moodle_connected_user") ?? "Connected"
            status = .connected(details: user)
        } else {
            status = .notConnected(reason: "Connect Moodle to sync deadlines")
        }
    }

    /// Synchronizes assignments from Moodle LMS into SwiftData.
    /// Strictly preserves locally completed assignments, manual deadline edits, and user notes.
    func syncAssignments(modelContext: ModelContext) async throws -> (synced: Int, newCount: Int) {
        guard isConfigured,
              let token = MoodleKeychainHelper.getToken() else {
            status = .notConnected(reason: "Moodle credentials not configured")
            return (0, 0)
        }

        let siteUrl = UserDefaults.standard.string(forKey: "moodle_site_url") ?? MoodleService.defaultSiteUrl
        let rawUser = UserDefaults.standard.string(forKey: "moodle_connected_user") ?? "Student"
        let currentAccount = SessionManager.shared.currentAccountId ?? rawUser.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        status = .syncing
        lastError = nil

        // Fetch existing assignments from SwiftData
        let descriptor = FetchDescriptor<Assignment>()
        let allExisting = (try? modelContext.fetch(descriptor)) ?? []

        // Restrict Moodle matching exclusively to Moodle assignments belonging to this account (or unassigned Moodle items)
        // Manual assignments and scanned exams are NEVER matched or overwritten.
        let existingMoodleAssignments = allExisting.filter {
            $0.source == "moodle" && ($0.accountId == nil || $0.accountId?.lowercased() == currentAccount)
        }

        do {
            let drafts = try await MoodleService.shared.fetchAssignments(
                siteUrl: siteUrl,
                token: token,
                existingAssignments: existingMoodleAssignments
            )

            // Synchronize cloud task states to ensure cross-device and post-login restorations
            _ = try? await TaskSyncCoordinator.shared.syncWithBackend(modelContext: modelContext, accountId: currentAccount)

            var newAdded = 0
            var updated = 0

            for draft in drafts {
                let cleanTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanCourse = draft.course.trimmingCharacters(in: .whitespacesAndNewlines)

                // Match existing assignment primarily by moodleEventId, secondarily by (title, course)
                if let existing = existingMoodleAssignments.first(where: {
                    if let mId = $0.moodleEventId, !mId.isEmpty, mId == draft.moodleEventId { return true }
                    return $0.title.caseInsensitiveCompare(cleanTitle) == .orderedSame &&
                           $0.course.caseInsensitiveCompare(cleanCourse) == .orderedSame
                }) {
                    // Update server-driven fields while STRICTLY PRESERVING user completion status, archive state, and notes!
                    existing.sourceUrl = draft.sourceUrl
                    existing.moodleEventId = draft.moodleEventId
                    existing.dueDate = draft.dueDate
                    existing.priority = draft.priority
                    existing.accountId = currentAccount

                    // Save state to store & cloud backend
                    MoodleAccountTaskStore.shared.saveState(for: existing, accountId: currentAccount)
                    TaskSyncCoordinator.shared.recordTaskStateChange(for: existing, accountId: currentAccount)
                    updated += 1
                } else {
                    // Check if this student account previously completed or customized this task before logout (Cloud or Local)
                    let restored = TaskSyncCoordinator.shared.restoreTaskState(
                        source: "moodle",
                        moodleEventId: draft.moodleEventId,
                        title: cleanTitle,
                        course: cleanCourse,
                        accountId: currentAccount
                    )

                    let isCompleted = restored.isCompleted
                    let isArchived = restored.isArchived
                    let preservedNotes = (restored.notes?.isEmpty == false) ? (restored.notes ?? "") : draft.notes

                    // Create assignment with preserved completion state
                    let newAssignment = Assignment(
                        title: cleanTitle,
                        course: cleanCourse,
                        dueDate: draft.dueDate,
                        priority: draft.priority,
                        notes: preservedNotes,
                        isCompleted: isCompleted,
                        isArchived: isArchived,
                        source: "moodle",
                        moodleEventId: draft.moodleEventId,
                        sourceUrl: draft.sourceUrl,
                        accountId: currentAccount
                    )
                    modelContext.insert(newAssignment)

                    if !isCompleted {
                        NotificationService.shared.scheduleReminders(for: newAssignment)
                    }

                    // Keep persistent store and cloud backend synchronized
                    MoodleAccountTaskStore.shared.saveState(for: newAssignment, accountId: currentAccount)
                    TaskSyncCoordinator.shared.recordTaskStateChange(for: newAssignment, accountId: currentAccount)
                    newAdded += 1
                }
            }

            try? modelContext.save()

            let user = UserDefaults.standard.string(forKey: "moodle_connected_user") ?? "Student"
            self.lastImportedCount = drafts.count
            self.lastRefreshedAt = Date()
            self.status = .connected(details: user)

            return (drafts.count, newAdded)
        } catch {
            let desc = error.localizedDescription
            self.lastError = desc
            self.status = .error(message: desc)
            throw error
        }
    }
}
