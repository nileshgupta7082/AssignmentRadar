//
//  ConnectedPlatformsView.swift
//  AssignementRadar
//
//  Created for Assignment Radar Connected Platforms & Coding Hub.
//

import SwiftUI
import SwiftData

/// Unified Coding Hub and Connected Platforms screen providing daily coding challenges,
/// upcoming contests, academic synchronization status, and calendar settings.
struct ConnectedPlatformsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var assignments: [Assignment]
    @Query(sort: \Hackathon.createdAt, order: .reverse) private var hackathons: [Hackathon]

    @ObservedObject private var refreshCoordinator = RefreshCoordinator.shared
    @ObservedObject private var leetCodeProvider = LeetCodeProvider.shared
    @ObservedObject private var gfgProvider = GeeksForGeeksProvider.shared
    @ObservedObject private var calendarSyncService = CalendarSyncService.shared

    @AppStorage("moodle_connected_user") private var moodleConnectedUser: String?
    @AppStorage("moodle_connected_site") private var moodleConnectedSite: String?
    @AppStorage("moodle_site_url") private var moodleSiteUrl: String?

    // Sheet states
    @State private var isShowingMoodleSheet: Bool = false
    @State private var isShowingHackathonsSheet: Bool = false
    @State private var isShowingCalendarSheet: Bool = false
    @State private var isShowingLeetCodeSheet: Bool = false
    @State private var isShowingGFGSheet: Bool = false
    @State private var isShowingDisconnectAlert: Bool = false

    private var isMoodleConnected: Bool {
        MoodleKeychainHelper.getToken() != nil &&
        moodleConnectedUser != nil &&
        !(moodleConnectedUser?.isEmpty ?? true)
    }

    private var moodleImportedCount: Int {
        assignments.filter { $0.source == "moodle" }.count
    }

    // MARK: - Overview Metrics

    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private var leetCodeSolvedToday: Bool {
        let date = leetCodeProvider.dailyQuestion?.date ?? todayDateString
        return leetCodeProvider.isDailySolvedLocally(date: date)
    }

    private var gfgSolvedToday: Bool {
        let date = gfgProvider.dailyProblem?.date ?? todayDateString
        return gfgProvider.isPOTDSolvedLocally(date: date)
    }

    private var completedChallengesCount: Int {
        (leetCodeSolvedToday ? 1 : 0) + (gfgSolvedToday ? 1 : 0)
    }

    private var nextContestInfo: (title: String, countdown: String)? {
        let now = Date()

        // 1. Check LeetCode contests
        let upcomingLeetCode = leetCodeProvider.upcomingContests.first { $0.endTime > now }

        // 2. Check Local Hackathons
        let upcomingHackathon = hackathons.first { $0.status(at: now) != .completed }

        if let lc = upcomingLeetCode, let hk = upcomingHackathon {
            if lc.startTime < hk.eventStartDate {
                return (lc.title, lc.relativeTimeDescription)
            } else {
                return (hk.title, hk.countdownLabel(at: now))
            }
        } else if let lc = upcomingLeetCode {
            return (lc.title, lc.relativeTimeDescription)
        } else if let hk = upcomingHackathon {
            return (hk.title, hk.countdownLabel(at: now))
        }
        return nil
    }

    private var nextAcademicDeadline: Assignment? {
        let now = Date()
        return assignments
            .filter { !$0.isArchived && !$0.isCompleted && $0.hasValidDeadline && $0.effectiveDate > now }
            .sorted { $0.effectiveDate < $1.effectiveDate }
            .first
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - 1. Consolidated Overview Card
                Section {
                    consolidatedOverviewView
                }
                .listRowBackground(Color.theme.cardBackground)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                // MARK: - 2. Coding Today (LeetCode & GFG)
                Section("Coding Today") {
                    codingTodaySectionView
                }
                .listRowBackground(Color.theme.cardBackground)

                // MARK: - 3. Coding Contests & Hackathons
                Section("Contests & Hackathons") {
                    contestsAndHackathonsSectionView
                }
                .listRowBackground(Color.theme.cardBackground)

                // MARK: - 4. Platforms & Academic Integrations (Compact Settings List)
                Section("Connected Platforms") {
                    // Moodle LMS Row
                    moodleRowView

                    // Apple Calendar Row
                    appleCalendarRowView

                    // LeetCode Provider Row
                    leetCodeRowView

                    // GeeksforGeeks Provider Row
                    gfgRowView

                    // Local Hackathons Row
                    hackathonsRowView
                }
                .listRowBackground(Color.theme.cardBackground)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.theme.mainBackground)
            .navigationTitle("Coding & Platforms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task {
                            await refreshCoordinator.refreshAll(modelContext: modelContext)
                        }
                    } label: {
                        if refreshCoordinator.isRefreshing {
                            ProgressView()
                                .tint(Color.theme.primaryAccent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.body)
                                .foregroundStyle(Color.theme.primaryAccent)
                        }
                    }
                    .disabled(refreshCoordinator.isRefreshing)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(Color.theme.primaryAccent)
                }
            }
            .sheet(isPresented: $isShowingMoodleSheet) {
                MoodleConnectView()
                    .environment(\.modelContext, modelContext)
            }
            .sheet(isPresented: $isShowingHackathonsSheet) {
                HackathonsListView()
                    .environment(\.modelContext, modelContext)
            }
            .sheet(isPresented: $isShowingCalendarSheet) {
                CalendarSettingsView()
                    .environment(\.modelContext, modelContext)
            }
            .sheet(isPresented: $isShowingLeetCodeSheet) {
                LeetCodeDetailView()
            }
            .sheet(isPresented: $isShowingGFGSheet) {
                GFGDetailView()
            }
            .alert("Log Out of Moodle?", isPresented: $isShowingDisconnectAlert) {
                Button("Log Out", role: .destructive) {
                    SessionManager.shared.logOut(modelContext: modelContext)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Moodle-imported assignments will be removed. Your manually created assignments, scanned exams, and local hackathons will remain safely preserved.")
            }
            .task {
                if refreshCoordinator.lastRefreshedAt == nil {
                    await refreshCoordinator.refreshAll(modelContext: modelContext)
                }
            }
        }
    }

    // MARK: - 1. Consolidated Overview Component

    private var consolidatedOverviewView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Daily Academic & Coding Summary", systemImage: "sparkles")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.theme.primaryAccent)
                Spacer()
                if let lastSync = refreshCoordinator.lastRefreshedAt {
                    Text(lastSync.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(Color.theme.secondaryText)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                // Challenges Today
                overviewTile(
                    title: "Coding Today",
                    value: "2 Challenges",
                    icon: "chevron.left.forwardslash.chevron.right",
                    color: Color.theme.primaryAccent
                )

                // Solved Today
                overviewTile(
                    title: "Solved Today",
                    value: "\(completedChallengesCount)/2 Solved",
                    icon: completedChallengesCount == 2 ? "checkmark.seal.fill" : "circle.dashed",
                    color: completedChallengesCount > 0 ? Color.theme.success : Color.theme.secondaryText
                )

                // Next Contest
                if let contest = nextContestInfo {
                    overviewTile(
                        title: "Next Contest",
                        value: contest.countdown,
                        icon: "trophy.fill",
                        color: Color.theme.warning,
                        subtitle: contest.title
                    )
                } else {
                    overviewTile(
                        title: "Next Contest",
                        value: "No Live Contest",
                        icon: "trophy",
                        color: Color.theme.secondaryText
                    )
                }

                // Next Deadline
                if let next = nextAcademicDeadline {
                    let deadlineStr = next.dueDate.formatted(date: .abbreviated, time: .shortened)
                    overviewTile(
                        title: "Next Deadline",
                        value: deadlineStr,
                        icon: "clock.badge.exclamationmark",
                        color: Color.theme.primaryAccent,
                        subtitle: next.title
                    )
                } else {
                    overviewTile(
                        title: "Next Deadline",
                        value: "All Caught Up",
                        icon: "checkmark.circle",
                        color: Color.theme.success
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func overviewTile(title: String, value: String, icon: String, color: Color, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.theme.secondaryText)
            }
            Text(value)
                .font(.footnote)
                .fontWeight(.bold)
                .foregroundStyle(Color.theme.primaryText)
                .lineLimit(1)

            if let sub = subtitle {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(Color.theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.theme.secondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 2. Coding Today Section

    private var codingTodaySectionView: some View {
        VStack(spacing: 12) {
            // LeetCode Card
            HStack(alignment: .top, spacing: 10) {
                Button {
                    let date = leetCodeProvider.dailyQuestion?.date ?? todayDateString
                    leetCodeProvider.toggleDailySolvedLocally(date: date)
                } label: {
                    Image(systemName: leetCodeSolvedToday ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(leetCodeSolvedToday ? Color.theme.success : Color.theme.secondaryText)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("LeetCode Daily")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.theme.secondaryText)

                        if let diff = leetCodeProvider.dailyQuestion?.difficulty {
                            difficultyBadge(diff, color: leetCodeProvider.dailyQuestion?.difficultyColor ?? .blue)
                        }
                    }

                    if let title = leetCodeProvider.dailyQuestion?.title {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.theme.primaryText)
                            .lineLimit(1)
                    } else {
                        Text("Daily challenge unavailable offline")
                            .font(.subheadline)
                            .foregroundStyle(Color.theme.secondaryText)
                    }

                    HStack(spacing: 8) {
                        if let url = leetCodeProvider.dailyQuestion?.problemUrl {
                            Link(destination: url) {
                                Label("Open Problem", systemImage: "arrow.up.right.square")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(Color.theme.primaryAccent)
                        }

                        Button {
                            isShowingLeetCodeSheet = true
                        } label: {
                            Text("Details & Contests")
                                .font(.caption)
                                .foregroundStyle(Color.theme.secondaryText)
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer()
            }
            .padding(.vertical, 4)

            Divider()
                .background(Color.theme.divider)

            // GeeksforGeeks Card
            HStack(alignment: .top, spacing: 10) {
                Button {
                    let date = gfgProvider.dailyProblem?.date ?? todayDateString
                    gfgProvider.togglePOTDSolvedLocally(date: date)
                } label: {
                    Image(systemName: gfgSolvedToday ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(gfgSolvedToday ? Color.theme.success : Color.theme.secondaryText)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("GeeksforGeeks POTD")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.theme.secondaryText)

                        if let diff = gfgProvider.dailyProblem?.difficulty {
                            difficultyBadge(diff, color: gfgProvider.dailyProblem?.difficultyColor ?? .green)
                        }
                    }

                    if let title = gfgProvider.dailyProblem?.title {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.theme.primaryText)
                            .lineLimit(1)
                    } else {
                        Text("Problem of the day unavailable offline")
                            .font(.subheadline)
                            .foregroundStyle(Color.theme.secondaryText)
                    }

                    HStack(spacing: 8) {
                        if let url = gfgProvider.dailyProblem?.problemUrl {
                            Link(destination: url) {
                                Label("Open Problem", systemImage: "arrow.up.right.square")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(Color.theme.primaryAccent)
                        }

                        Button {
                            isShowingGFGSheet = true
                        } label: {
                            Text("Details")
                                .font(.caption)
                                .foregroundStyle(Color.theme.secondaryText)
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private func difficultyBadge(_ diff: String, color: Color) -> some View {
        Text(diff.capitalized)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - 3. Contests & Hackathons Section

    private var contestsAndHackathonsSectionView: some View {
        VStack(alignment: .leading, spacing: 10) {
            let now = Date()

            // LeetCode Upcoming Contests
            ForEach(leetCodeProvider.upcomingContests.prefix(2)) { contest in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.body)
                        .foregroundStyle(Color.theme.warning)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(contest.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.theme.primaryText)
                            Spacer()
                            Text(contest.relativeTimeDescription)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(contest.isLiveNow ? Color.theme.overdueSurface : Color.theme.softAccentSurface)
                                .foregroundStyle(contest.isLiveNow ? Color.theme.overdue : Color.theme.primaryAccent)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        Text("Starts: \(contest.formattedLocalDate) (\(contest.formattedDuration))")
                            .font(.caption2)
                            .foregroundStyle(Color.theme.secondaryText)

                        if let url = contest.contestUrl {
                            Link("Open Contest Page", destination: url)
                                .font(.caption2)
                                .foregroundStyle(Color.theme.primaryAccent)
                                .padding(.top, 1)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            // Local Hackathons
            ForEach(hackathons.prefix(2)) { hackathon in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "trophy.fill")
                        .font(.body)
                        .foregroundStyle(Color.theme.exam)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(hackathon.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.theme.primaryText)
                            Spacer()
                            Text(hackathon.countdownLabel(at: now))
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.theme.examSurface)
                                .foregroundStyle(Color.theme.exam)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        Text("\(hackathon.organizer) • \(hackathon.formattedEventDate)")
                            .font(.caption2)
                            .foregroundStyle(Color.theme.secondaryText)

                        if let urlStr = hackathon.eventUrl, let url = URL(string: urlStr) {
                            Link("Event Link", destination: url)
                                .font(.caption2)
                                .foregroundStyle(Color.theme.primaryAccent)
                                .padding(.top, 1)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            // Manage Button
            Button {
                isShowingHackathonsSheet = true
            } label: {
                HStack {
                    Spacer()
                    Label("Manage Local Hackathons (\(hackathons.count))", systemImage: "plus.circle")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }
            }
            .padding(.top, 4)
            .foregroundStyle(Color.theme.primaryAccent)
        }
    }

    // MARK: - 4. Compact Platforms Rows

    private var moodleRowView: some View {
        HStack(spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .font(.body)
                .foregroundStyle(Color.theme.primaryAccent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Moodle LMS")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.theme.primaryText)

                if isMoodleConnected {
                    Text("\(moodleConnectedUser ?? "Connected") • \(moodleImportedCount) assignments")
                        .font(.caption2)
                        .foregroundStyle(Color.theme.secondaryText)
                } else {
                    Text("Not connected")
                        .font(.caption2)
                        .foregroundStyle(Color.theme.secondaryText)
                }
            }

            Spacer()

            if isMoodleConnected {
                Button("Manage") {
                    isShowingMoodleSheet = true
                }
                .buttonStyle(.bordered)
                .font(.caption)
                .tint(Color.theme.primaryAccent)
            } else {
                Button("Connect") {
                    isShowingMoodleSheet = true
                }
                .buttonStyle(.borderedProminent)
                .font(.caption)
                .tint(Color.theme.primaryAccent)
            }
        }
        .padding(.vertical, 2)
    }

    private var appleCalendarRowView: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.body)
                .foregroundStyle(Color.theme.primaryAccent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Calendar")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.theme.primaryText)

                Text(calendarSyncService.isCalendarSyncEnabled ? "Auto-Sync Enabled" : "Sync Disabled")
                    .font(.caption2)
                    .foregroundStyle(calendarSyncService.isCalendarSyncEnabled ? Color.theme.success : Color.theme.secondaryText)
            }

            Spacer()

            Button("Settings") {
                isShowingCalendarSheet = true
            }
            .buttonStyle(.bordered)
            .font(.caption)
            .tint(Color.theme.primaryAccent)
        }
        .padding(.vertical, 2)
    }

    private var leetCodeRowView: some View {
        HStack(spacing: 12) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.body)
                .foregroundStyle(Color.theme.warning)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("LeetCode")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.theme.primaryText)

                Text(leetCodeProvider.status.badgeText)
                    .font(.caption2)
                    .foregroundStyle(Color.theme.secondaryText)
            }

            Spacer()

            Button("Details") {
                isShowingLeetCodeSheet = true
            }
            .buttonStyle(.bordered)
            .font(.caption)
            .tint(Color.theme.secondaryText)
        }
        .padding(.vertical, 2)
    }

    private var gfgRowView: some View {
        HStack(spacing: 12) {
            Image(systemName: "curlybraces")
                .font(.body)
                .foregroundStyle(Color.theme.success)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("GeeksforGeeks")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.theme.primaryText)

                Text(gfgProvider.status.badgeText)
                    .font(.caption2)
                    .foregroundStyle(Color.theme.secondaryText)
            }

            Spacer()

            Button("Details") {
                isShowingGFGSheet = true
            }
            .buttonStyle(.bordered)
            .font(.caption)
            .tint(Color.theme.secondaryText)
        }
        .padding(.vertical, 2)
    }

    private var hackathonsRowView: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.body)
                .foregroundStyle(Color.theme.exam)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Local Hackathons")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.theme.primaryText)

                Text("\(hackathons.count) events saved")
                    .font(.caption2)
                    .foregroundStyle(Color.theme.secondaryText)
            }

            Spacer()

            Button("Manage") {
                isShowingHackathonsSheet = true
            }
            .buttonStyle(.bordered)
            .font(.caption)
            .tint(Color.theme.secondaryText)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - LeetCode Detail Sheet

struct LeetCodeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var provider = LeetCodeProvider.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Daily Coding Challenge") {
                    if let daily = provider.dailyQuestion {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(daily.title)
                                .font(.headline)
                                .foregroundStyle(Color.theme.primaryText)

                            HStack {
                                Text(daily.difficulty)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(daily.difficultyColor)
                                Spacer()
                                Text(daily.date)
                                    .font(.caption)
                                    .foregroundStyle(Color.theme.secondaryText)
                            }

                            if let url = daily.problemUrl {
                                Link("Solve on LeetCode.com", destination: url)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.theme.primaryAccent)
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("No daily challenge loaded. Tap Refresh to fetch.")
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)
                    }
                }
                .listRowBackground(Color.theme.cardBackground)

                Section("Upcoming Verified Contests") {
                    if provider.upcomingContests.isEmpty {
                        Text("No upcoming contests found.")
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)
                    } else {
                        ForEach(provider.upcomingContests) { contest in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(contest.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(contest.relativeTimeDescription)
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(Color.theme.primaryAccent)
                                }

                                Text("Start: \(contest.formattedLocalDate) • Duration: \(contest.formattedDuration)")
                                    .font(.caption2)
                                    .foregroundStyle(Color.theme.secondaryText)

                                if let url = contest.contestUrl {
                                    Link("Contest Link", destination: url)
                                        .font(.caption2)
                                        .foregroundStyle(Color.theme.primaryAccent)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .listRowBackground(Color.theme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Color.theme.mainBackground)
            .navigationTitle("LeetCode Hub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.theme.primaryAccent)
                }
            }
        }
    }
}

// MARK: - GeeksforGeeks Detail Sheet

struct GFGDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var provider = GeeksForGeeksProvider.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Problem of the Day") {
                    if let potd = provider.dailyProblem {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(potd.title)
                                .font(.headline)
                                .foregroundStyle(Color.theme.primaryText)

                            HStack {
                                Text(potd.difficulty)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(potd.difficultyColor)
                                Spacer()
                                Text(potd.date)
                                    .font(.caption)
                                    .foregroundStyle(Color.theme.secondaryText)
                            }

                            if let url = potd.problemUrl {
                                Link("Solve on GeeksforGeeks Practice", destination: url)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.theme.primaryAccent)
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("No Problem of the Day loaded. Tap Refresh to fetch.")
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)
                    }
                }
                .listRowBackground(Color.theme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Color.theme.mainBackground)
            .navigationTitle("GeeksforGeeks Hub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.theme.primaryAccent)
                }
            }
        }
    }
}
