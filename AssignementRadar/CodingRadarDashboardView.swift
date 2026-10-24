//
//  CodingRadarDashboardView.swift
//  AssignementRadar
//
//  Created for Coding Radar Dedicated Workspace & Dashboard.
//

import SwiftUI
import SwiftData

enum CodingEventFilter: String, CaseIterable, Identifiable {
    case upcoming = "Upcoming"
    case completed = "Completed"
    case all = "All"

    var id: String { rawValue }
}

struct CodingRadarDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @Query(sort: \CodingTask.createdAt, order: .reverse) private var allCodingTasks: [CodingTask]
    @Query(sort: \CodingActivityRecord.completedAt, order: .reverse) private var allCodingActivities: [CodingActivityRecord]
    @Query(sort: \TrackedPlatform.addedAt, order: .forward) private var trackedPlatforms: [TrackedPlatform]

    @ObservedObject private var refreshCoordinator = RefreshCoordinator.shared
    @ObservedObject private var leetCodeProvider = LeetCodeProvider.shared
    @ObservedObject private var gfgProvider = GeeksForGeeksProvider.shared
    @ObservedObject private var notificationService = NotificationService.shared

    @State private var selectedEventFilter: CodingEventFilter = .upcoming
    @State private var isShowingAddEventSheet: Bool = false
    @State private var isShowingAddTaskSheet: Bool = false
    @State private var isShowingCatalogSheet: Bool = false
    @State private var isShowingSettingsSheet: Bool = false
    @State private var isShowingMarkSolvedSheet: Bool = false
    @State private var selectedPlatformForDetail: TrackedPlatform? = nil
    @State private var selectedEventForDetail: CodingTask? = nil

    // MARK: - Daily Streak State

    private var streakStats: CodingStreakStats {
        CodingStreakCalculator.calculate(activities: allCodingActivities, tasks: allCodingTasks)
    }

    private var contributionWeeks: [[ContributionDay]] {
        CodingStreakCalculator.buildContributionGrid(
            activeCounts: streakStats.dailyCompletionsCount,
            numberOfWeeks: 14
        )
    }


    // MARK: - Partitioned Task Groups (3 Core Sections)

    private var dailyQuestions: [CodingTask] {
        allCodingTasks.filter { $0.isDailyQuestion }
            .sorted { ($0.dueDate ?? $0.createdAt) > ($1.dueDate ?? $1.createdAt) }
    }

    private var upcomingContests: [CodingTask] {
        let now = Date()
        return allCodingTasks.filter { $0.isContest && ($0.startDate ?? Date.distantPast) > now.addingTimeInterval(-7200) }
            .sorted { ($0.startDate ?? Date.distantFuture) < ($1.startDate ?? Date.distantFuture) }
    }

    private var filteredEvents: [CodingTask] {
        let events = allCodingTasks.filter { $0.isEvent }
        switch selectedEventFilter {
        case .upcoming:
            return events.filter { !$0.isCompleted }
                .sorted { $0.nextRelevantDate < $1.nextRelevantDate }
        case .completed:
            return events.filter { $0.isCompleted }
                .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
        case .all:
            return events.sorted { $0.nextRelevantDate < $1.nextRelevantDate }
        }
    }

    private var isLeetCodeTracked: Bool {
        trackedPlatforms.contains(where: { $0.platformId == "leetcode" })
    }

    private var isGFGTracked: Bool {
        trackedPlatforms.contains(where: { $0.platformId == "gfg" })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - 1. Dashboard Header
                    codingHeaderView
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // MARK: - 2. Daily Streak Component
                    CodingDailyStreakView(
                        stats: streakStats,
                        weeks: contributionWeeks,
                        onMarkSolvedTapped: {
                            isShowingMarkSolvedSheet = true
                        },
                        onReminderTapped: {
                            isShowingSettingsSheet = true
                        }
                    )
                    .padding(.horizontal, 16)

                    // MARK: - 3. Daily Questions
                    dailyQuestionsSectionView
                        .padding(.horizontal, 16)

                    // MARK: - 4. Upcoming Contests
                    upcomingContestsSectionView
                        .padding(.horizontal, 16)

                    // MARK: - 5. My Events & Hackathons
                    myEventsSectionView
                        .padding(.horizontal, 16)

                    // MARK: - 6. Tracked Platforms Bar
                    platformsSectionView
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }
            }
            .refreshable {
                await refreshCoordinator.refreshCoding(modelContext: modelContext)
            }
            .background(Color.theme.mainBackground)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingAddEventSheet) {
                CodingEventEditorView()
            }
            .sheet(isPresented: $isShowingAddTaskSheet) {
                AddCodingTaskView()
            }
            .sheet(isPresented: $isShowingCatalogSheet) {
                AddPlatformCatalogView()
            }
            .sheet(isPresented: $isShowingSettingsSheet) {
                CodingRadarSettingsView()
            }
            .sheet(isPresented: $isShowingMarkSolvedSheet) {
                MarkProblemSolvedSheetView()
            }
            .sheet(item: $selectedPlatformForDetail) { platform in
                PlatformDetailSheetView(platform: platform)
            }
            .sheet(item: $selectedEventForDetail) { event in
                CodingEventDetailSheetView(event: event)
            }
            .onChange(of: notificationService.showConfirmSolvedProblemSheet) { _, shouldShow in
                if shouldShow {
                    isShowingMarkSolvedSheet = true
                    notificationService.showConfirmSolvedProblemSheet = false
                }
            }
            .task {
                if refreshCoordinator.lastCodingRefreshedAt == nil {
                    await refreshCoordinator.refreshCoding(modelContext: modelContext)
                }
            }
        }
    }

    // MARK: - Header & Overview Subviews

    private var codingHeaderView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Coding Radar")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.theme.primaryText)

                if let lastSync = refreshCoordinator.lastCodingRefreshedAt {
                    Text("Synced \(lastSync.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(Color.theme.secondaryText)
                }
            }

            Spacer()

            // Header Actions
            HStack(spacing: 12) {
                // Sync button
                Button {
                    Task {
                        await refreshCoordinator.refreshCoding(modelContext: modelContext)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                        .foregroundStyle(Color.theme.secondaryText)
                        .rotationEffect(refreshCoordinator.isRefreshing ? .degrees(360) : .zero)
                        .animation(refreshCoordinator.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: refreshCoordinator.isRefreshing)
                }
                .accessibilityLabel("Sync Coding Feeds")
                .disabled(refreshCoordinator.isRefreshing)

                // Add Coding Event / Contest
                Button {
                    isShowingAddEventSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.theme.primaryAccent)
                }
                .accessibilityLabel("Add Manual Event")

                // Consolidated Options Menu
                Menu {
                    Button {
                        isShowingSettingsSheet = true
                    } label: {
                        Label("Notification Settings", systemImage: "bell.badge")
                    }

                    Button {
                        isShowingAddEventSheet = true
                    } label: {
                        Label("Add Manual Event / Hackathon", systemImage: "calendar.badge.plus")
                    }

                    Button {
                        isShowingAddTaskSheet = true
                    } label: {
                        Label("Add Coding Task", systemImage: "plus")
                    }

                    Button {
                        isShowingCatalogSheet = true
                    } label: {
                        Label("Add Platform", systemImage: "square.grid.2x2")
                    }

                    Button {
                        Task {
                            await refreshCoordinator.refreshCoding(modelContext: modelContext)
                        }
                    } label: {
                        Label("Sync Live Feeds", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(Color.theme.primaryText)
                }
                .accessibilityLabel("Add Item")
            }
        }
    }

    // MARK: - My Platforms Section

    private var platformsSectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("My Platforms")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.theme.primaryText)

                Spacer()

                Button {
                    isShowingCatalogSheet = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.caption2.bold())
                        Text("Add")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Color.theme.primaryAccent)
                }
            }

            if trackedPlatforms.isEmpty {
                VStack(spacing: 8) {
                    Text("No platforms tracked yet.")
                        .font(.footnote)
                        .foregroundStyle(Color.theme.secondaryText)

                    Button {
                        isShowingCatalogSheet = true
                    } label: {
                        Text("+ Add Platform from Catalog")
                            .font(.footnote)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.theme.secondarySurface)
                            .foregroundStyle(Color.theme.primaryAccent)
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.theme.divider, lineWidth: 0.5)
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(trackedPlatforms) { platform in
                            platformCard(platform: platform)
                        }
                    }
                }
            }
        }
    }

    private func platformCard(platform: TrackedPlatform) -> some View {
        let cat = PlatformCatalog.find(id: platform.platformId)
        let platformColor = PlatformCatalog.color(for: platform.platformId)

        return Button {
            selectedPlatformForDetail = platform
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: cat?.iconName ?? "terminal")
                        .font(.system(size: 15))
                        .foregroundStyle(platformColor)

                    Text(platform.platformName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.theme.primaryText)
                        .lineLimit(1)
                }

                Text(cat?.supportsAutomaticData == true ? "Live Data" : "Manual")
                    .font(.caption2)
                    .foregroundStyle(Color.theme.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minWidth: 120, alignment: .leading)
            .background(Color.theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.theme.divider, lineWidth: 0.5)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(platformColor)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section 1: Daily Questions View

    private var dailyQuestionsSectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.subheadline)
                        .foregroundStyle(Color.theme.primaryAccent)

                    Text("Daily Questions")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.theme.primaryText)
                }

                Spacer()

                if isLeetCodeTracked || isGFGTracked {
                    Button {
                        Task {
                            await refreshCoordinator.refreshCoding(modelContext: modelContext)
                        }
                    } label: {
                        Text("Sync Feeds")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.theme.primaryAccent)
                    }
                }
            }

            if !isLeetCodeTracked && !isGFGTracked {
                VStack(spacing: 8) {
                    Text("Connect LeetCode or GeeksforGeeks to sync daily coding challenges automatically.")
                        .font(.footnote)
                        .foregroundStyle(Color.theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    Button {
                        isShowingCatalogSheet = true
                    } label: {
                        Text("+ Connect Coding Platforms")
                            .font(.footnote)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.theme.primaryAccent)
                            .foregroundStyle(Color.theme.cardBackground)
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.theme.divider, lineWidth: 0.5)
                )
            } else if dailyQuestions.isEmpty {
                VStack(spacing: 8) {
                    Text("No daily questions loaded yet.")
                        .font(.footnote)
                        .foregroundStyle(Color.theme.secondaryText)

                    Button {
                        Task {
                            await refreshCoordinator.refreshCoding(modelContext: modelContext)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Fetch Today's Challenges")
                        }
                        .font(.footnote)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.theme.secondarySurface)
                        .foregroundStyle(Color.theme.primaryAccent)
                        .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.theme.divider, lineWidth: 0.5)
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(dailyQuestions) { task in
                        dailyQuestionCard(task: task)
                    }
                }
            }
        }
    }

    private func dailyQuestionCard(task: CodingTask) -> some View {
        let platformColor = PlatformCatalog.color(for: task.platformId)

        return HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button {
                withAnimation {
                    task.isCompleted.toggle()
                    task.completedAt = task.isCompleted ? Date() : nil
                    try? modelContext.save()
                    Task {
                        await CodingNotificationManager.shared.reconcile(tasks: allCodingTasks)
                        await CalendarSyncService.shared.handleCodingTaskCompletionChanged(task)
                    }
                }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(task.isCompleted ? Color(hex: "#22C55E") : Color.theme.secondaryText)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            // Details
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(task.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(task.isCompleted ? Color.theme.secondaryText : Color.theme.primaryText)
                        .strikethrough(task.isCompleted, color: Color.theme.secondaryText)
                        .lineLimit(2)

                    Spacer()

                    if let diff = task.difficulty {
                        Text(diff)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(difficultyBackground(diff))
                            .foregroundStyle(difficultyColor(diff))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    // Platform tag
                    HStack(spacing: 4) {
                        Circle()
                            .fill(platformColor)
                            .frame(width: 6, height: 6)

                        Text(task.platformName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.theme.primaryText)
                    }

                    if let tags = task.topicTags, !tags.isEmpty {
                        Text("· \(tags)")
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)
                            .lineLimit(1)
                    }
                }
            }

            // Direct Problem URL Button
            if let urlStr = task.officialUrl, let url = URL(string: urlStr) {
                Button {
                    openURL(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.subheadline)
                        .foregroundStyle(platformColor)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .accessibilityLabel("Open problem URL")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.theme.divider, lineWidth: 0.5)
        )
    }

    // MARK: - Section 2: Upcoming Contests View

    private var upcomingContestsSectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "trophy")
                        .font(.subheadline)
                        .foregroundStyle(Color.theme.primaryAccent)

                    Text("Upcoming Contests")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.theme.primaryText)
                }

                Spacer()

                Button {
                    isShowingAddEventSheet = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.caption2.bold())
                        Text("Add")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Color.theme.primaryAccent)
                }
            }

            if upcomingContests.isEmpty {
                VStack(spacing: 8) {
                    Text("No upcoming coding contests tracked.")
                        .font(.footnote)
                        .foregroundStyle(Color.theme.secondaryText)

                    Button {
                        isShowingAddEventSheet = true
                    } label: {
                        Text("+ Add Contest or Round")
                            .font(.footnote)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.theme.secondarySurface)
                            .foregroundStyle(Color.theme.primaryAccent)
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.theme.divider, lineWidth: 0.5)
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(upcomingContests) { contest in
                        contestCard(contest: contest)
                    }
                }
            }

        }
    }

    private func contestCard(contest: CodingTask) -> some View {
        let platformColor = PlatformCatalog.color(for: contest.platformId.isEmpty ? contest.platformName : contest.platformId)

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(contest.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(contest.isCompleted ? Color.theme.secondaryText : Color.theme.primaryText)
                        .lineLimit(2)

                    Spacer()

                    // Registration Status Menu
                    Menu {
                        ForEach(ContestRegistrationStatus.allCases) { status in
                            Button {
                                withAnimation {
                                    contest.registrationStatus = status
                                    if status == .completed {
                                        contest.isCompleted = true
                                        contest.completedAt = Date()
                                    }
                                    try? modelContext.save()
                                    Task {
                                        await CodingNotificationManager.shared.reconcile(tasks: allCodingTasks)
                                    }
                                }
                            } label: {
                                HStack {
                                    Label(status.rawValue, systemImage: status.iconName)
                                    if contest.registrationStatus == status {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: contest.registrationStatus.iconName)
                                .font(.system(size: 10))
                            Text(contest.registrationStatus.rawValue)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(contest.registrationStatus == .registered ? Color(hex: "#22C55E").opacity(0.18) : Color.theme.secondarySurface)
                        .foregroundStyle(contest.registrationStatus == .registered ? Color(hex: "#22C55E") : Color.theme.secondaryText)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
                    // Platform badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(platformColor)
                            .frame(width: 6, height: 6)

                        Text(contest.platformName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.theme.primaryText)
                    }

                    if let timeline = contest.formattedTimeline {
                        Text("· \(timeline)")
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)
                    }
                }
            }

            // Direct Official URL
            if let urlStr = contest.officialUrl, let url = URL(string: urlStr) {
                Button {
                    openURL(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.subheadline)
                        .foregroundStyle(platformColor)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .accessibilityLabel("Open contest page")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.theme.divider, lineWidth: 0.5)
        )
    }

    // MARK: - Section 3: My Events & Hackathons View

    private var myEventsSectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "laptopcomputer.and.arrow.down")
                        .font(.subheadline)
                        .foregroundStyle(Color.theme.primaryAccent)

                    Text("My Events & Hackathons")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.theme.primaryText)
                }

                Spacer()

                Button {
                    isShowingAddEventSheet = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.caption2.bold())
                        Text("Add Event")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Color.theme.primaryAccent)
                }
            }

            // Filter Tabs
            Picker("Event Filter", selection: $selectedEventFilter) {
                ForEach(CodingEventFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            if filteredEvents.isEmpty {
                VStack(spacing: 8) {
                    Text(selectedEventFilter == .completed ? "No completed events." : "No manual events or hackathons added yet.")
                        .font(.footnote)
                        .foregroundStyle(Color.theme.secondaryText)

                    if selectedEventFilter != .completed {
                        Button {
                            isShowingAddEventSheet = true
                        } label: {
                            Text("+ Add Event or Hackathon")
                                .font(.footnote)
                                .fontWeight(.medium)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.theme.primaryAccent)
                                .foregroundStyle(Color.theme.cardBackground)
                                .clipShape(Capsule())
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.theme.divider, lineWidth: 0.5)
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredEvents) { event in
                        Button {
                            selectedEventForDetail = event
                        } label: {
                            eventCard(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func eventCard(event: CodingTask) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button {
                withAnimation {
                    event.isCompleted.toggle()
                    event.completedAt = event.isCompleted ? Date() : nil
                    if event.isCompleted {
                        event.registrationStatus = .completed
                    }
                    try? modelContext.save()
                    Task {
                        await CodingNotificationManager.shared.reconcile(tasks: allCodingTasks)
                        await CalendarSyncService.shared.handleCodingTaskCompletionChanged(event)
                    }
                }
            } label: {
                Image(systemName: event.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(event.isCompleted ? Color(hex: "#22C55E") : Color.theme.secondaryText)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(event.isCompleted ? Color.theme.secondaryText : Color.theme.primaryText)
                        .strikethrough(event.isCompleted, color: Color.theme.secondaryText)
                        .lineLimit(2)

                    Spacer()

                    // Event Type Tag
                    Text(event.taskType.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.theme.secondarySurface)
                        .foregroundStyle(Color.theme.primaryAccent)
                        .clipShape(Capsule())
                }

                HStack(spacing: 8) {
                    if !event.platformName.isEmpty && event.platformName != "Custom" {
                        Text(event.platformName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.theme.primaryText)
                    }

                    if let start = event.startDate {
                        Text(start.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)
                    }

                    if event.calendarEventId != nil {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.caption2)
                            .foregroundStyle(Color.theme.primaryAccent)
                            .accessibilityLabel("Synced with Apple Calendar")
                    }

                    Spacer()

                    // Registration Status Pill
                    HStack(spacing: 3) {
                        Image(systemName: event.registrationStatus.iconName)
                            .font(.system(size: 9))
                        Text(event.registrationStatus.rawValue)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(event.registrationStatus == .registered ? Color(hex: "#22C55E").opacity(0.18) : Color.theme.secondarySurface)
                    .foregroundStyle(event.registrationStatus == .registered ? Color(hex: "#22C55E") : Color.theme.secondaryText)
                    .clipShape(Capsule())
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(Color.theme.secondaryText.opacity(0.5))
                .padding(.top, 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.theme.divider, lineWidth: 0.5)
        )
    }

    // MARK: - Difficulty Helpers

    private func difficultyColor(_ diff: String) -> Color {
        switch diff.lowercased() {
        case "easy", "basic", "school": return Color(hex: "#22C55E")
        case "medium": return Color(hex: "#F59E0B")
        case "hard": return Color(hex: "#EF4444")
        default: return Color.theme.primaryAccent
        }
    }

    private func difficultyBackground(_ diff: String) -> Color {
        difficultyColor(diff).opacity(0.15)
    }
}
