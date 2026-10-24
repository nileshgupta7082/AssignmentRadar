//
//  CalendarScheduleView.swift
//  AssignementRadar
//
//  Created for Assignment Radar Dashboard UX, Launch Animation & Calendar.
//

import SwiftUI
import SwiftData

/// Native SwiftUI Month Calendar and selected-day deadline schedule view.
struct CalendarScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // SwiftData single source of truth for all deadlines
    @Query(sort: \Assignment.dueDate, order: .forward) private var allAssignments: [Assignment]

    // Navigation and selection state
    @State private var displayedMonth: Date = Date()
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var assignmentToEdit: Assignment? = nil
    @State private var isShowingAddForDate: Bool = false
    @State private var isSyncingToCalendar: Bool = false
    @State private var syncReportAlertMessage: String? = nil
    @State private var isShowingSyncAlert: Bool = false
    @State private var isShowingSettingsSheet: Bool = false

    @ObservedObject private var syncService = CalendarSyncService.shared

    private let calendar = Calendar.current

    /// Non-archived assignments
    private var activeAssignments: [Assignment] {
        allAssignments.filter { !$0.isArchived }
    }

    /// Assignments and exams scheduled on the selected day
    private var selectedDayAssignments: [Assignment] {
        let targetStart = calendar.startOfDay(for: selectedDate)
        return activeAssignments.filter {
            calendar.startOfDay(for: $0.effectiveDate) == targetStart
        }.sorted { Assignment.urgencySortComparator(a: $0, b: $1, referenceDate: Date()) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Month Navigation & Today Shortcut
                    monthNavigationHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // Apple Calendar Sync Banner
                    appleCalendarSyncBanner

                    // Month Calendar Card
                    VStack(spacing: 10) {
                        weekdayHeadersView

                        monthGridView
                    }
                    .padding(14)
                    .themeCard()
                    .padding(.horizontal, 16)

                    // Legend of calendar markers
                    calendarLegendView
                        .padding(.horizontal, 16)

                    // Selected Day Schedule Section
                    selectedDayScheduleSection
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                }
            }
            .background(Color.theme.mainBackground)
            .navigationTitle("Calendar Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.theme.primaryAccent)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                isSyncingToCalendar = true
                                let summary = await syncService.syncAssignmentsWithReport(activeAssignments)
                                isSyncingToCalendar = false
                                syncReportAlertMessage = summary.resultMessage
                                isShowingSyncAlert = true
                            }
                        } label: {
                            if isSyncingToCalendar {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.theme.primaryAccent)
                            }
                        }
                        .disabled(isSyncingToCalendar)
                        .accessibilityLabel("Sync to Apple Calendar")

                        Button {
                            isShowingAddForDate = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.theme.primaryAccent)
                        }
                        .accessibilityLabel("Add task for selected date")
                    }
                }
            }
            .alert("Apple Calendar Sync", isPresented: $isShowingSyncAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(syncReportAlertMessage ?? "")
            }
            .sheet(item: $assignmentToEdit) { assignment in
                AssignmentEditorView(assignmentToEdit: assignment)
            }
            .sheet(isPresented: $isShowingAddForDate) {
                AssignmentEditorView(initialDueDate: selectedDate)
            }
            .sheet(isPresented: $isShowingSettingsSheet) {
                CalendarSettingsView()
            }
        }
    }

    // MARK: - Apple Calendar Sync Banner

    private var appleCalendarSyncBanner: some View {
        HStack(spacing: 8) {
            Button {
                isShowingSettingsSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundStyle(Color.theme.primaryAccent)
                    Text(syncService.currentDestinationCalendarName())
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.theme.primaryText)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Color.theme.secondaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.theme.secondarySurface)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                Task {
                    isSyncingToCalendar = true
                    let summary = await syncService.syncAssignmentsWithReport(activeAssignments)
                    isSyncingToCalendar = false
                    syncReportAlertMessage = summary.resultMessage
                    isShowingSyncAlert = true
                }
            } label: {
                HStack(spacing: 5) {
                    if isSyncingToCalendar {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                    }
                    Text(isSyncingToCalendar ? "Syncing..." : "Sync Apple Calendar")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.theme.primaryAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.theme.softAccentSurface)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSyncingToCalendar)
            .accessibilityLabel("Sync to Apple Calendar Now")
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Month Navigation Header

    private var monthNavigationHeader: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.theme.primaryText)
                    .padding(8)
                    .background(Color.theme.secondarySurface)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Previous month")

            Spacer()

            VStack(spacing: 2) {
                Text(monthTitle(for: displayedMonth))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.theme.primaryText)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut) {
                        displayedMonth = Date()
                        selectedDate = calendar.startOfDay(for: Date())
                    }
                } label: {
                    Text("Today")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.theme.primaryAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.theme.softAccentSurface)
                        .clipShape(Capsule())
                }
                .accessibilityLabel("Jump to today")

                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.theme.primaryText)
                        .padding(8)
                        .background(Color.theme.secondarySurface)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Next month")
            }
        }
    }

    // MARK: - Weekday Headers

    private var weekdayHeadersView: some View {
        let symbols = calendar.veryShortWeekdaySymbols
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                Text(symbols[index])
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.theme.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Month Grid

    private var monthGridView: some View {
        let days = daysInDisplayedMonth()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<days.count, id: \.self) { index in
                if let date = days[index] {
                    dayCellView(for: date)
                } else {
                    Color.clear
                        .frame(height: 38)
                }
            }
        }
    }

    private func dayCellView(for date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let itemsForDay = assignmentsForDate(date)

        let hasExam = itemsForDay.contains { $0.isExam }
        let hasOverdue = itemsForDay.contains { $0.isOverdue && !$0.isCompleted }
        let hasPending = itemsForDay.contains { !$0.isCompleted && !$0.isExam && !$0.isOverdue }
        let hasCompleted = itemsForDay.contains { $0.isCompleted }

        let dayNumber = calendar.component(.day, from: date)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDate = calendar.startOfDay(for: date)
            }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.theme.primaryAccent)
                            .frame(width: 30, height: 30)
                    } else if isToday {
                        Circle()
                            .stroke(Color.theme.primaryAccent, lineWidth: 1.5)
                            .frame(width: 30, height: 30)
                    }

                    Text("\(dayNumber)")
                        .font(.subheadline)
                        .fontWeight(isSelected || isToday ? .bold : .regular)
                        .foregroundStyle(
                            isSelected
                            ? Color.white
                            : (isToday ? Color.theme.primaryAccent : Color.theme.primaryText)
                        )
                }
                .frame(height: 30)

                // Event indicator dots
                HStack(spacing: 2) {
                    if hasExam {
                        Circle()
                            .fill(Color.theme.exam)
                            .frame(width: 4, height: 4)
                    }
                    if hasOverdue {
                        Circle()
                            .fill(Color.theme.overdue)
                            .frame(width: 4, height: 4)
                    }
                    if hasPending {
                        Circle()
                            .fill(isSelected ? Color.theme.primaryAccent : Color.theme.primaryAccent.opacity(0.85))
                            .frame(width: 4, height: 4)
                    }
                    if hasCompleted && !hasExam && !hasOverdue && !hasPending {
                        Circle()
                            .fill(Color.theme.success)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(monthTitle(for: date)), \(dayNumber), \(itemsForDay.count) deadlines")
    }

    // MARK: - Legend

    private var calendarLegendView: some View {
        HStack(spacing: 12) {
            legendItem(name: "Exam", color: Color.theme.exam)
            legendItem(name: "Assignment", color: Color.theme.primaryAccent)
            legendItem(name: "Overdue", color: Color.theme.overdue)
            legendItem(name: "Completed", color: Color.theme.success)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .font(.caption2)
        .foregroundStyle(Color.theme.secondaryText)
    }

    private func legendItem(name: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(name)
        }
    }

    // MARK: - Selected Day Schedule Section

    private var selectedDayScheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDateFormatted)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.theme.primaryText)

                    Text(calendar.isDateInToday(selectedDate) ? "Today" : (calendar.isDateInTomorrow(selectedDate) ? "Tomorrow" : ""))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.theme.primaryAccent)
                }

                Spacer()

                Text("\(selectedDayAssignments.count) \(selectedDayAssignments.count == 1 ? "item" : "items")")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.theme.secondarySurface)
                    .clipShape(Capsule())
            }

            if selectedDayAssignments.isEmpty {
                emptyDayView
            } else {
                VStack(spacing: 8) {
                    ForEach(selectedDayAssignments) { assignment in
                        calendarItemCard(assignment: assignment)
                    }
                }
            }
        }
    }

    private var emptyDayView: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 32))
                .foregroundStyle(Color.theme.secondaryText)
                .padding(.top, 12)

            Text("No Deadlines Scheduled")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.theme.primaryText)

            Text("No assignments or examinations are due on this date.")
                .font(.caption)
                .foregroundStyle(Color.theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                isShowingAddForDate = true
            } label: {
                Label("Add Deadline for This Date", systemImage: "plus")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.bordered)
            .tint(Color.theme.primaryAccent)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .themeCard()
    }

    private func calendarItemCard(assignment: Assignment) -> some View {
        Button {
            assignmentToEdit = assignment
        } label: {
            HStack(alignment: .top, spacing: 10) {
                // Complete toggle button
                Button {
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
                } label: {
                    Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(assignment.isCompleted ? Color.theme.primaryAccent : Color.theme.secondaryText)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)

                // Item info
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(assignment.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .strikethrough(assignment.isCompleted, color: Color.theme.secondaryText)
                            .foregroundStyle(assignment.isCompleted ? Color.theme.secondaryText : Color.theme.primaryText)
                            .lineLimit(2)

                        Spacer()

                        // Priority badge
                        Text(assignment.priority.rawValue)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(prioritySurface(assignment.priority))
                            .foregroundStyle(priorityColor(assignment.priority))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    HStack(spacing: 6) {
                        // Exam vs assignment badge
                        if assignment.isExam {
                            HStack(spacing: 3) {
                                Image(systemName: "graduationcap.circle.fill")
                                    .font(.caption2)
                                Text("Exam")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.theme.examSurface)
                            .foregroundStyle(Color.theme.exam)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else if assignment.source == "moodle" {
                            HStack(spacing: 3) {
                                Image(systemName: "graduationcap.fill")
                                    .font(.caption2)
                                Text("Moodle")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.theme.secondarySurface)
                            .foregroundStyle(Color.theme.secondaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        // Course tag
                        if !assignment.course.isEmpty {
                            Text(assignment.course)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.theme.secondarySurface)
                                .foregroundStyle(Color.theme.primaryText)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        Spacer()

                        // Time display
                        HStack(spacing: 3) {
                            Image(systemName: assignment.isOverdue && !assignment.isCompleted ? "exclamationmark.circle.fill" : "clock")
                                .font(.caption2)
                            Text(timeLabel(for: assignment))
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(
                            assignment.isCompleted
                            ? Color.theme.secondaryText
                            : (assignment.isOverdue ? Color.theme.overdue : Color.theme.primaryAccent)
                        )
                    }
                }
            }
            .padding(12)
            .themeCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date Math & Helpers

    private var selectedDateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        return formatter.string(from: selectedDate)
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func changeMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            withAnimation(.easeInOut(duration: 0.25)) {
                displayedMonth = newMonth
            }
        }
    }

    private func daysInDisplayedMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let firstDay = monthInterval.start
        let weekdayOfFirst = calendar.component(.weekday, from: firstDay) // 1 = Sunday
        let leadingBlanks = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)

        let numberOfDays = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
        for dayOffset in 0..<numberOfDays {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: firstDay) {
                days.append(calendar.startOfDay(for: date))
            }
        }
        return days
    }

    private func assignmentsForDate(_ date: Date) -> [Assignment] {
        let target = calendar.startOfDay(for: date)
        return activeAssignments.filter {
            calendar.startOfDay(for: $0.effectiveDate) == target
        }
    }

    private func timeLabel(for assignment: Assignment) -> String {
        if assignment.isExam, let session = assignment.sessionTime, !session.isEmpty {
            return session
        }
        return assignment.effectiveDate.formatted(date: .omitted, time: .shortened)
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
}
