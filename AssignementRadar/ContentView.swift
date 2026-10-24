//
//  ContentView.swift
//  AssignementRadar
//
//  Created for Assignment Radar Milestone 1 & Complete UI/UX Refinement.
//

import SwiftUI
import SwiftData
import UserNotifications
import Combine

/// Filter options for the primary assignment dashboard.
enum AssignmentFilter: String, CaseIterable, Identifiable {
    case pending = "Pending"
    case completed = "Completed"

    var id: String { rawValue }
}

/// The main dashboard view displaying upcoming assignments, statistics, filters, and theme controls.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentTime: Date = Date()

    // Fetch all assignments sorted by upcoming due date
    @Query(sort: \Assignment.dueDate, order: .forward) private var assignments: [Assignment]

    // Dashboard State
    @State private var selectedFilter: AssignmentFilter = .pending
    @State private var isShowingCalendarSheet: Bool = false
    @State private var isShowingCalendarSettingsSheet: Bool = false
    @State private var isShowingCalendarSyncAlert: Bool = false
    @State private var calendarSyncAlertMessage: String? = nil
    @State private var isShowingAddSheet: Bool = false
    @State private var isShowingScannerSheet: Bool = false
    @State private var isShowingMoodleSheet: Bool = false
    @State private var isShowingRemindersSheet: Bool = false
    @State private var isShowingProfileSheet: Bool = false
    @State private var selectedAssignmentForEdit: Assignment? = nil

    // Refresh Coordinator
    @ObservedObject private var refreshCoordinator = RefreshCoordinator.shared

    // Cloud Task State Sync Coordinator
    @ObservedObject private var syncCoordinator = TaskSyncCoordinator.shared

    // Notification Service Observer
    @ObservedObject private var notificationService = NotificationService.shared

    // App Appearance Theme
    @AppStorage("selected_app_theme") private var selectedThemeRaw: String = AppTheme.system.rawValue

    // Moodle Connected User Profile
    @AppStorage("moodle_connected_user") private var moodleConnectedUser: String?

    private var isMoodleConnected: Bool {
        MoodleKeychainHelper.getToken() != nil &&
        moodleConnectedUser != nil &&
        !(moodleConnectedUser?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private var selectedTheme: AppTheme {
        get { AppTheme(rawValue: selectedThemeRaw) ?? .system }
        set { selectedThemeRaw = newValue.rawValue }
    }

    // Filter assignments strictly based on the user's selected tab, sorted by smart urgency prioritization
    // Exclude archived tasks from active dashboard views
    // Exclude incomplete items that are overdue by 7 days or more from the front page
    private var filteredAssignments: [Assignment] {
        let now = currentTime
        let active = assignments.filter { !$0.isArchived }
        let filtered: [Assignment]
        switch selectedFilter {
        case .pending:
            // Incomplete, non-archived assignments or exams, excluding items overdue by 7 days or more
            filtered = active.filter { !$0.isCompleted && !$0.isOverdueBy(days: 7, referenceDate: now) }
        case .completed:
            // Completed items according to existing data model and archive behavior
            filtered = active.filter { $0.isCompleted }
        }
        return filtered.sorted { Assignment.urgencySortComparator(a: $0, b: $1, referenceDate: now) }
    }

    // Quick statistics (excludes archived tasks and tasks overdue by 7 days or more)
    private var pendingCount: Int {
        let now = currentTime
        return assignments.filter { !$0.isArchived && !$0.isCompleted && !$0.isOverdueBy(days: 7, referenceDate: now) }.count
    }

    private var overdueCount: Int {
        let now = currentTime
        return assignments.filter { !$0.isArchived && !$0.isCompleted && $0.isOverdue && !$0.isOverdueBy(days: 7, referenceDate: now) }.count
    }

    private var completedCount: Int {
        assignments.filter { !$0.isArchived && $0.isCompleted }.count
    }

    /// Clean, concise greeting extracting student display name if connected.
    private var friendlyGreeting: String {
        if isMoodleConnected, let user = moodleConnectedUser?.trimmingCharacters(in: .whitespacesAndNewlines), !user.isEmpty {
            let words = user.components(separatedBy: .whitespaces)
            let nameParts = words.filter { word in
                !word.allSatisfy { $0.isNumber } && word.count > 1
            }
            if let firstName = nameParts.first {
                let formatted = firstName.prefix(1).uppercased() + firstName.dropFirst().lowercased()
                return "Welcome back, \(formatted)"
            }
            return "Welcome back, \(user)"
        }
        return "Welcome back"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // Header: Clean title and concise greeting
                    dashboardHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 10)

                    // Refined, compact statistics cards
                    statsHeader
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)

                    // Filter Segmented Control (All, Pending, Overdue)
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(AssignmentFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                    // Main Content List or Empty State
                    if filteredAssignments.isEmpty {
                        emptyStateView
                            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 70) }
                    } else {
                        List {
                            ForEach(filteredAssignments) { assignment in
                                AssignmentRowView(assignment: assignment, filter: selectedFilter) {
                                    toggleCompletion(for: assignment)
                                }
                                .listRowBackground(Color.theme.cardBackground)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedAssignmentForEdit = assignment
                                }
                                // Swipe Right (Leading): Complete task
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    if !assignment.isCompleted {
                                        Button {
                                            completeAssignment(assignment)
                                        } label: {
                                            Label("Complete", systemImage: "checkmark.circle.fill")
                                        }
                                        .tint(Color.theme.primaryAccent)
                                    }
                                }
                                // Swipe Left (Trailing): Archive and Low Priority
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        withAnimation {
                                            assignment.isArchived = true
                                            NotificationService.shared.cancelReminders(for: assignment.id)
                                            try? modelContext.save()
                                        }
                                    } label: {
                                        Label("Archive", systemImage: "archivebox.fill")
                                    }
                                    .tint(Color.theme.warning)

                                    if assignment.priority != .low {
                                        Button {
                                            withAnimation {
                                                assignment.priority = .low
                                                try? modelContext.save()
                                            }
                                        } label: {
                                            Label("Low Priority", systemImage: "arrow.down.circle")
                                        }
                                        .tint(Color.theme.secondaryText)
                                    }
                                }
                                // Context Menu alternative for accessibility and long-press
                                .contextMenu {
                                    Button {
                                        toggleCompletion(for: assignment)
                                    } label: {
                                        Label(
                                            assignment.isCompleted ? "Mark Incomplete" : "Mark Complete",
                                            systemImage: assignment.isCompleted ? "circle" : "checkmark.circle.fill"
                                        )
                                    }

                                    Button {
                                        withAnimation {
                                            assignment.isArchived = true
                                            if assignment.source == "moodle" {
                                                MoodleAccountTaskStore.shared.saveState(for: assignment)
                                            }
                                            TaskSyncCoordinator.shared.recordTaskStateChange(for: assignment)
                                            NotificationService.shared.cancelReminders(for: assignment.id)
                                            try? modelContext.save()
                                        }
                                    } label: {
                                        Label("Archive Task", systemImage: "archivebox.fill")
                                    }

                                    if assignment.priority != .low {
                                        Button {
                                            withAnimation {
                                                assignment.priority = .low
                                                try? modelContext.save()
                                            }
                                        } label: {
                                            Label("Set to Low Priority", systemImage: "arrow.down.circle")
                                        }
                                    }

                                    Button {
                                        selectedAssignmentForEdit = assignment
                                    } label: {
                                        Label("Edit Assignment", systemImage: "pencil")
                                    }

                                    Button {
                                        Task {
                                            let (_, status, error) = await CalendarSyncService.shared.syncAssignmentWithDetail(assignment, force: true)
                                            if let error = error {
                                                refreshCoordinator.postStatusMessage(error)
                                            } else {
                                                refreshCoordinator.postStatusMessage("Synced \"\(assignment.title)\" to Apple Calendar (\(status.rawValue)).")
                                            }
                                        }
                                    } label: {
                                        Label(assignment.calendarEventId != nil ? "Update in Apple Calendar" : "Sync to Apple Calendar", systemImage: "calendar.badge.plus")
                                    }
                                }
                                .accessibilityAction(named: assignment.isCompleted ? "Mark Incomplete" : "Complete Task") {
                                    toggleCompletion(for: assignment)
                                }
                                .accessibilityAction(named: "Archive Task") {
                                    withAnimation {
                                        assignment.isArchived = true
                                        NotificationService.shared.cancelReminders(for: assignment.id)
                                        try? modelContext.save()
                                    }
                                }
                                .accessibilityAction(named: "Set Priority to Low") {
                                    withAnimation {
                                        assignment.priority = .low
                                        try? modelContext.save()
                                    }
                                }
                            }
                            .onDelete(perform: deleteAssignments)
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                        .background(Color.theme.mainBackground)
                        .refreshable {
                            await refreshCoordinator.refreshAcademic(modelContext: modelContext)
                        }
                        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 70) }
                    }
                }

                // Toast status banner
                if let message = refreshCoordinator.lastStatusMessage {
                    statusToastView(message: message)
                }

                // Refined, subtle floating refresh button
                floatingRefreshButton
            }
            .background(Color.theme.mainBackground)
            .toolbar(.hidden, for: .navigationBar)
            // Sheet for User Profile Dropdown Menu
            .sheet(isPresented: $isShowingProfileSheet) {
                ProfileMenuView()
                    .environment(\.modelContext, modelContext)
            }
            // Sheet to connect to Moodle
            .sheet(isPresented: $isShowingMoodleSheet) {
                MoodleConnectView()
                    .environment(\.modelContext, modelContext)
            }
            // Sheet to scan datesheet/notice with Vision OCR
            .sheet(isPresented: $isShowingScannerSheet) {
                NoticeScannerView()
                    .environment(\.modelContext, modelContext)
            }
            // Sheet to configure reminder intervals and permissions
            .sheet(isPresented: $isShowingRemindersSheet) {
                ReminderPreferencesSheet(assignments: assignments)
            }
            // Sheet for Calendar Schedule
            .sheet(isPresented: $isShowingCalendarSheet) {
                CalendarScheduleView()
                    .environment(\.modelContext, modelContext)
            }
            // Sheet for Calendar Settings
            .sheet(isPresented: $isShowingCalendarSettingsSheet) {
                CalendarSettingsView()
                    .environment(\.modelContext, modelContext)
            }
            .alert("Apple Calendar Sync", isPresented: $isShowingCalendarSyncAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(calendarSyncAlertMessage ?? "")
            }
            // Sheet to create a new assignment
            .sheet(isPresented: $isShowingAddSheet) {
                AssignmentEditorView()
            }
            // Sheet to edit an existing assignment
            .sheet(item: $selectedAssignmentForEdit) { assignment in
                AssignmentEditorView(assignmentToEdit: assignment)
            }
            .onChange(of: notificationService.pendingOpenedAssignmentId) {
                guard let targetId = notificationService.pendingOpenedAssignmentId else { return }
                if let match = assignments.first(where: { $0.id == targetId }) {
                    selectedAssignmentForEdit = match
                } else {
                    refreshCoordinator.postStatusMessage("The notification target assignment or exam could not be found.")
                }
                notificationService.pendingOpenedAssignmentId = nil
            }
            .task {
                guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }

                currentTime = Date()
                await NotificationService.shared.requestAuthorizationIfNeeded()
                NotificationService.shared.syncAllReminders(for: assignments)

                if (moodleConnectedUser == nil || moodleConnectedUser?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true),
                   let token = MoodleKeychainHelper.getToken(),
                   let siteUrl = UserDefaults.standard.string(forKey: "moodle_site_url") {
                    do {
                        let info = try await MoodleService.shared.testConnection(siteUrl: siteUrl, token: token)
                        moodleConnectedUser = info.displayName
                        UserDefaults.standard.set(info.displayName, forKey: "moodle_connected_user")
                    } catch {
                        // Keep fallback
                    }
                }

                if refreshCoordinator.lastRefreshedAt == nil {
                    await refreshCoordinator.refreshAcademic(modelContext: modelContext)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    currentTime = Date()
                }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { newTime in
                currentTime = newTime
            }
        }
        .preferredColorScheme(selectedTheme.colorScheme)
    }

    // MARK: - Options Menu & Navigation

    /// Consolidated options menu keeping the navigation bar uncluttered.
    private var dashboardOptionsMenu: some View {
        Menu {
            Section {
                Button {
                    Task {
                        let summary = await CalendarSyncService.shared.syncAssignmentsWithReport(assignments)
                        calendarSyncAlertMessage = summary.resultMessage
                        isShowingCalendarSyncAlert = true
                    }
                } label: {
                    Label("Sync to Apple Calendar", systemImage: "arrow.triangle.2.circlepath")
                }

                Button {
                    isShowingCalendarSheet = true
                } label: {
                    Label("Calendar Schedule", systemImage: "calendar")
                }

                Button {
                    isShowingCalendarSettingsSheet = true
                } label: {
                    Label("Calendar Settings", systemImage: "calendar.badge.clock")
                }

                Button {
                    isShowingProfileSheet = true
                } label: {
                    Label(isMoodleConnected ? "Student Profile" : "Account & Workspaces", systemImage: "person.crop.circle")
                }

                Button {
                    isShowingRemindersSheet = true
                } label: {
                    Label("Reminder Preferences", systemImage: "bell.badge")
                }
            }

            Section("Appearance") {
                ForEach(AppTheme.allCases) { theme in
                    Button {
                        selectedThemeRaw = theme.rawValue
                    } label: {
                        HStack {
                            Label(theme.rawValue, systemImage: theme.iconName)
                            if selectedThemeRaw == theme.rawValue {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    Task {
                        await refreshCoordinator.refreshAcademic(modelContext: modelContext)
                    }
                } label: {
                    Label("Refresh Deadlines", systemImage: "arrow.clockwise")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
                .foregroundStyle(Color.theme.primaryText)
        }
        .accessibilityLabel("Dashboard Options")
    }

    // MARK: - Floating Refresh & Status Views

    /// Refined, restrained manual refresh button pinned to lower-right corner.
    private var floatingRefreshButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                await refreshCoordinator.refreshAcademic(modelContext: modelContext)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.theme.cardBackground)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(Color.theme.divider, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)

                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.theme.primaryAccent)
                    .rotationEffect(.degrees(refreshCoordinator.isRefreshing ? 360 : 0))
                    .animation(
                        refreshCoordinator.isRefreshing
                        ? Animation.linear(duration: 1.0).repeatForever(autoreverses: false)
                        : .default,
                        value: refreshCoordinator.isRefreshing
                    )
            }
        }
        .disabled(refreshCoordinator.isRefreshing)
        .accessibilityLabel("Refresh deadlines")
        .accessibilityHint("Synchronizes assignments from Moodle and checks academic deadlines")
        .padding(.trailing, 18)
        .padding(.bottom, 16)
    }

    /// User-friendly toast banner displaying outcome messages.
    private func statusToastView(message: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: refreshCoordinator.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(refreshCoordinator.isError ? Color.theme.warning : Color.theme.success)

                Text(message)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.theme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 4)

                Button {
                    refreshCoordinator.clearStatusMessage()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(Color.theme.secondaryText)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.theme.divider, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
            .padding(.horizontal, 16)
            .padding(.bottom, 72)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.easeInOut, value: refreshCoordinator.lastStatusMessage)
    }

    // MARK: - Header & Statistics

    /// Primary header with title, concise greeting, and action buttons.
    private var dashboardHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Assignment Radar")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.theme.primaryText)

                    // Subtle, unobtrusive cloud sync indicator
                    if syncCoordinator.syncStatus != .synced {
                        HStack(spacing: 4) {
                            Image(systemName: syncCoordinator.syncStatus.iconName)
                                .font(.caption2)
                                .foregroundStyle(syncCoordinator.syncStatus.iconColor)

                            if case .offline(let count) = syncCoordinator.syncStatus, count > 0 {
                                Text("\(count)")
                                    .font(.caption2)
                                    .foregroundStyle(Color.theme.secondaryText)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.theme.cardBackground)
                        .clipShape(Capsule())
                    }
                }

                Text(friendlyGreeting)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.theme.secondaryText)
            }

            Spacer()

            // Top-right action buttons
            HStack(spacing: 12) {
                // Scan Notice (Kept prominent and accessible for student OCR workflow & UI tests)
                Button {
                    isShowingScannerSheet = true
                } label: {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.body)
                        .foregroundStyle(Color.theme.primaryText)
                }
                .accessibilityLabel("Scan Notice")

                // Add Assignment / Exam
                Button {
                    isShowingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.theme.primaryAccent)
                }
                .accessibilityLabel("Add Assignment")

                // Consolidated Settings & Appearance Menu
                dashboardOptionsMenu
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Two summary cards at the top of the dashboard showing Pending and Completed counts.
    private var statsHeader: some View {
        HStack(spacing: 12) {
            statCard(
                title: "Pending",
                count: pendingCount,
                accentColor: Color.theme.primaryAccent,
                surfaceColor: Color.theme.softAccentSurface,
                icon: "clock"
            )
            statCard(
                title: "Completed",
                count: completedCount,
                accentColor: Color.theme.success,
                surfaceColor: Color.theme.successSurface,
                icon: "checkmark.circle"
            )
        }
    }

    private func statCard(title: String, count: Int, accentColor: Color, surfaceColor: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(accentColor)
                Spacer()
                Text("\(count)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(accentColor)
            }
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(Color.theme.secondaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .themeCard()
    }

    /// Clean empty state shown when no assignments match the active filter.
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(
                emptyStateTitle,
                systemImage: emptyStateIcon
            )
        } description: {
            Text(emptyStateDescription)
        } actions: {
            if selectedFilter == .pending {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button {
                            isShowingScannerSheet = true
                        } label: {
                            Label("Scan Notice", systemImage: "doc.text.viewfinder")
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.theme.primaryAccent)

                        Button {
                            isShowingAddSheet = true
                        } label: {
                            Label("Add Manually", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.theme.primaryAccent)
                    }

                    Button {
                        isShowingMoodleSheet = true
                    } label: {
                        Label("Connect Moodle", systemImage: "graduationcap.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.theme.primaryAccent)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        switch selectedFilter {
        case .pending:
            return "No Pending Deadlines"
        case .completed:
            return "No Completed Tasks"
        }
    }

    private var emptyStateIcon: String {
        switch selectedFilter {
        case .pending:
            return "clock.badge.checkmark"
        case .completed:
            return "checkmark.circle"
        }
    }

    private var emptyStateDescription: String {
        switch selectedFilter {
        case .pending:
            return "You have no upcoming incomplete assignments or exams. Tap + to add one or scan a notice."
        case .completed:
            return "Completed assignments will appear here once you finish them."
        }
    }

    // MARK: - Actions

    private func toggleCompletion(for assignment: Assignment) {
        withAnimation {
            assignment.isCompleted.toggle()
            if assignment.source == "moodle" {
                MoodleAccountTaskStore.shared.saveState(for: assignment)
            }
            TaskSyncCoordinator.shared.recordTaskStateChange(for: assignment)
            if assignment.isCompleted {
                NotificationService.shared.cancelReminders(for: assignment.id)
            } else {
                NotificationService.shared.scheduleReminders(for: assignment)
            }
            try? modelContext.save()
            Task {
                await CalendarSyncService.shared.handleAssignmentCompletionChanged(assignment)
            }
        }
    }

    private func completeAssignment(_ assignment: Assignment) {
        withAnimation {
            assignment.isCompleted = true
            if assignment.source == "moodle" {
                MoodleAccountTaskStore.shared.saveState(for: assignment)
            }
            TaskSyncCoordinator.shared.recordTaskStateChange(for: assignment)
            NotificationService.shared.cancelReminders(for: assignment.id)
            try? modelContext.save()
            Task {
                await CalendarSyncService.shared.handleAssignmentCompletionChanged(assignment)
            }
        }
    }

    private func deleteAssignments(at offsets: IndexSet) {
        for index in offsets {
            let assignmentToDelete = filteredAssignments[index]
            NotificationService.shared.cancelReminders(for: assignmentToDelete.id)
            if let calId = assignmentToDelete.calendarEventId {
                CalendarSyncService.shared.removeLinkedEvent(withIdentifier: calId)
            }
            modelContext.delete(assignmentToDelete)
        }
        try? modelContext.save()
    }
}

// MARK: - Assignment Row View (Restrained Hierarchy)

/// A dedicated row view representing a single assignment item in the list with smart urgency indicators.
struct AssignmentRowView: View {
    let assignment: Assignment
    var filter: AssignmentFilter = .pending
    let onToggleComplete: () -> Void

    var body: some View {
        let urgency = assignment.urgency()

        HStack(alignment: .top, spacing: 12) {
            // Checkbox button
            Button(action: onToggleComplete) {
                Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(assignment.isCompleted ? Color.theme.primaryAccent : Color.theme.secondaryText)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            // Assignment Details (Strict 3-piece Visual Hierarchy)
            VStack(alignment: .leading, spacing: 2) {
                // 1. Assignment or exam topic — primary text, most prominent
                Text(assignment.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .strikethrough(assignment.isCompleted, color: Color.theme.secondaryText)
                    .foregroundStyle(assignment.isCompleted ? Color.theme.secondaryText : Color.theme.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // 2. Course code — smaller, secondary text directly below the topic (omitted cleanly if empty)
                let cleanCourse = assignment.course
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&#039;", with: "'")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanCourse.isEmpty {
                    Text(cleanCourse)
                        .font(.footnote)
                        .foregroundStyle(Color.theme.secondaryText)
                        .lineLimit(1)
                }

                // 3. Submission or examination date and time — one concise line below the course code
                conciseDeadlineView(urgency: urgency)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .opacity(assignment.isCompleted ? 0.75 : 1.0)
    }

    // MARK: - Subcomponents

    private func sourceBadge(name: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(name)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.theme.secondarySurface)
        .foregroundStyle(Color.theme.secondaryText)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func priorityBadgeView(priority: Priority) -> some View {
        Text(priority.rawValue)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(prioritySurface(priority))
            .foregroundStyle(priorityColor(priority))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func priorityColor(_ priority: Priority) -> Color {
        switch priority {
        case .high: return Color.theme.overdue
        case .medium: return Color.theme.warning
        case .low: return Color.theme.secondaryText
        }
    }

    private func prioritySurface(_ priority: Priority) -> Color {
        switch priority {
        case .high: return Color.theme.overdueSurface
        case .medium: return Color.theme.warningSurface
        case .low: return Color.theme.secondarySurface
        }
    }

    private func urgencyBadgeView(urgency: Urgency) -> some View {
        Text(urgency.rawValue)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(urgencySurface(urgency))
            .foregroundStyle(urgencyColor(urgency))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func urgencyColor(_ urgency: Urgency) -> Color {
        switch urgency {
        case .overdue: return Color.theme.overdue
        case .dueSoon: return Color.theme.warning
        case .upcoming: return Color.theme.primaryAccent
        case .later: return Color.theme.secondaryText
        case .completed: return Color.theme.secondaryText
        }
    }

    private func urgencySurface(_ urgency: Urgency) -> Color {
        switch urgency {
        case .overdue: return Color.theme.overdueSurface
        case .dueSoon: return Color.theme.warningSurface
        case .upcoming: return Color.theme.softAccentSurface
        case .later: return Color.theme.secondarySurface
        case .completed: return Color.theme.secondarySurface
        }
    }

    /// Single concise deadline label without redundant icons.
    private func conciseDeadlineView(urgency: Urgency) -> some View {
        Group {
            if assignment.hasValidDeadline {
                let label = Self.conciseDeadlineLabel(
                    for: assignment.effectiveDate,
                    urgency: urgency,
                    isExam: assignment.isExam,
                    sessionTime: assignment.sessionTime
                )

                Text(label)
                    .font(.subheadline)
                    .fontWeight((urgency == .overdue && !assignment.isCompleted) || urgency == .dueSoon ? .semibold : .regular)
                    .lineLimit(1)
                    .foregroundStyle(deadlineColor(urgency: urgency))
            } else {
                Text("No deadline set")
                    .font(.subheadline)
                    .foregroundStyle(Color.theme.secondaryText)
            }
        }
    }

    // MARK: - Concise Deadline Formatting Helper

    /// Produces a single, clear, concise deadline label adhering to:
    /// - Normal: "Due Sat, 31 Oct · 9:32 AM"
    /// - Overdue: "Overdue · 16 Dec 2022" (including time when useful)
    /// - Exams: "Exam Sat, 31 Oct · 10:00 AM" (or session time)
    /// - Cross-year: includes 4-digit year correctly
    static func conciseDeadlineLabel(
        for date: Date?,
        urgency: Urgency,
        isExam: Bool,
        sessionTime: String? = nil,
        referenceDate: Date = Date(),
        calendar: Calendar = Calendar.current
    ) -> String {
        guard let date = date else {
            return "No deadline set"
        }

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "d MMM yyyy"
        let datePart = dayFormatter.string(from: date)

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "h:mm a"
        let timeStr = timeFormatter.string(from: date)

        if isExam {
            let session = sessionTime?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let session = session, !session.isEmpty {
                return "Exam \(datePart) · \(session)"
            } else {
                return "Exam \(datePart) · \(timeStr)"
            }
        }

        if urgency == .overdue {
            return "Overdue · \(datePart)"
        }

        return "Due \(datePart) · \(timeStr)"
    }

    // MARK: - Relative Date Formatting Helper (Legacy/Fallback)

    static func relativeDeadlineText(for date: Date, urgency: Urgency, isExam: Bool) -> String {
        let calendar = Calendar.current
        let now = Date()

        if urgency == .overdue {
            let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
            if days <= 0 {
                return isExam ? "Exam passed today" : "Overdue today"
            } else if days == 1 {
                return isExam ? "Exam passed yesterday" : "Overdue by 1 day"
            } else {
                return isExam ? "Exam passed \(days)d ago" : "Overdue by \(days) days"
            }
        }

        if calendar.isDateInToday(date) {
            return isExam ? "Exam today" : "Due today"
        } else if calendar.isDateInTomorrow(date) {
            return isExam ? "Exam tomorrow" : "Due tomorrow"
        } else {
            let days = calendar.dateComponents([.day], from: now, to: date).day ?? 0
            if days > 1 && days <= 7 {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE"
                return isExam ? "Exam on \(formatter.string(from: date))" : "Due \(formatter.string(from: date))"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "d MMM"
                return isExam ? "Exam \(formatter.string(from: date))" : "Due \(formatter.string(from: date))"
            }
        }
    }

    // MARK: - Test Compatibility Helpers

    /// Determines whether the urgency badge should be displayed based on the active tab:
    /// - Pending tab: Hide redundant "Upcoming" and "Later" badges. Only show urgency indicator if overdue or due soon (<24h).
    /// - Completed tab: All completed tasks have finished, hide urgency badges.
    static func shouldDisplayUrgencyBadge(filter: AssignmentFilter, urgency: Urgency, isCompleted: Bool) -> Bool {
        if isCompleted {
            return false
        }
        switch filter {
        case .pending:
            return urgency == .overdue || urgency == .dueSoon
        case .completed:
            return false
        }
    }

    private func shouldShowUrgencyBadge(urgency: Urgency) -> Bool {
        Self.shouldDisplayUrgencyBadge(filter: filter, urgency: urgency, isCompleted: assignment.isCompleted)
    }

    static func deadlineDisplayColor(urgency: Urgency, isCompleted: Bool) -> Color {
        if isCompleted {
            return Color.secondary
        }
        switch urgency {
        case .overdue:
            return Color.red
        case .dueSoon:
            return Color.orange
        default:
            return Color.secondary
        }
    }

    private func deadlineColor(urgency: Urgency) -> Color {
        if assignment.isCompleted {
            return Color.theme.secondaryText
        }
        switch urgency {
        case .overdue:
            return Color.theme.overdue
        case .dueSoon:
            return Color.theme.warning
        default:
            return Color.theme.secondaryText
        }
    }
}

// MARK: - Reminder Preferences Sheet

/// Settings sheet allowing students to configure reminder intervals and inspect notification status.
struct ReminderPreferencesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let assignments: [Assignment]

    @AppStorage("notify_24h_before") private var notify24h: Bool = true
    @AppStorage("notify_3h_before") private var notify3h: Bool = true
    @AppStorage("notify_at_deadline") private var notifyAtDeadline: Bool = true

    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "bell.badge.fill")
                                .font(.title3)
                                .foregroundStyle(Color.theme.primaryAccent)
                            Text("Smart Deadline Reminders")
                                .font(.headline)
                        }

                        Text("Assignment Radar schedules local on-device alerts before your academic deadlines so you never miss homework submissions, lab reports, or exams.")
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)
                    }
                    .padding(.vertical, 4)
                }

                Section("Notification Permission") {
                    HStack {
                        Label("Status", systemImage: statusIcon)
                        Spacer()
                        Text(statusText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(statusColor)
                    }

                    if authStatus == .denied {
                        Text("Notifications are currently disabled in iOS Settings. You can enable them anytime.")
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)

                        Button("Open iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    } else if authStatus == .notDetermined {
                        Button("Allow Notifications") {
                            Task {
                                await NotificationService.shared.requestAuthorizationIfNeeded()
                                authStatus = await NotificationService.shared.getAuthorizationStatus()
                                NotificationService.shared.syncAllReminders(for: assignments)
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }

                Section("Reminder Intervals") {
                    Toggle("24 Hours Before Deadline", isOn: $notify24h)
                        .onChange(of: notify24h) { _, _ in
                            NotificationService.shared.syncAllReminders(for: assignments)
                        }

                    Toggle("3 Hours Before Deadline", isOn: $notify3h)
                        .onChange(of: notify3h) { _, _ in
                            NotificationService.shared.syncAllReminders(for: assignments)
                        }

                    Toggle("At Deadline (0 Minutes)", isOn: $notifyAtDeadline)
                        .onChange(of: notifyAtDeadline) { _, _ in
                            NotificationService.shared.syncAllReminders(for: assignments)
                        }
                }

                Section("Active Schedule") {
                    let activeCount = assignments.filter { !$0.isCompleted && $0.hasValidDeadline && $0.dueDate > Date() }.count
                    HStack {
                        Label("Eligible Upcoming Deadlines", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        Text("\(activeCount)")
                            .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle("Reminder Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .task {
                authStatus = await NotificationService.shared.getAuthorizationStatus()
            }
        }
    }

    private var statusText: String {
        switch authStatus {
        case .authorized: return "Enabled"
        case .provisional: return "Provisional"
        case .denied: return "Disabled in Settings"
        case .notDetermined: return "Not Determined"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }

    private var statusColor: Color {
        switch authStatus {
        case .authorized, .provisional: return Color.theme.success
        case .denied: return Color.theme.overdue
        case .notDetermined: return Color.theme.warning
        default: return Color.theme.secondaryText
        }
    }

    private var statusIcon: String {
        switch authStatus {
        case .authorized, .provisional: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        default: return "questionmark.circle"
        }
    }
}
