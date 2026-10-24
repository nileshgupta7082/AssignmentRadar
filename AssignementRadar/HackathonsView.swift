//
//  HackathonsView.swift
//  AssignementRadar
//
//  Created for Assignment Radar Hackathon & Competition Tracking.
//

import SwiftUI
import SwiftData

/// Filter tab options for hackathons.
enum HackathonFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case upcoming = "Upcoming"
    case completed = "Completed"

    var id: String { rawValue }
}

/// Main view displaying the user's saved local hackathons and competitions.
struct HackathonsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Hackathon.createdAt, order: .reverse) private var hackathons: [Hackathon]

    @State private var selectedFilter: HackathonFilter = .all
    @State private var isShowingAddSheet: Bool = false
    @State private var hackathonToDelete: Hackathon? = nil
    @State private var isShowingDeleteAlert: Bool = false

    private var filteredHackathons: [Hackathon] {
        let now = Date()
        switch selectedFilter {
        case .all:
            return hackathons
        case .upcoming:
            return hackathons.filter { $0.status(at: now) != .completed }
        case .completed:
            return hackathons.filter { $0.status(at: now) == .completed }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter Segmented Control
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(HackathonFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 8)

                if filteredHackathons.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(filteredHackathons) { hackathon in
                            NavigationLink {
                                HackathonDetailView(hackathon: hackathon)
                            } label: {
                                HackathonCardView(hackathon: hackathon) {
                                    withAnimation {
                                        hackathon.isAttendedOrCompleted.toggle()
                                        try? modelContext.save()
                                        if hackathon.isAttendedOrCompleted {
                                            NotificationService.shared.cancelReminders(forHackathonId: hackathon.id)
                                        } else {
                                            NotificationService.shared.scheduleReminders(for: hackathon)
                                        }
                                    }
                                }
                            }
                            .listRowBackground(Color.theme.cardBackground)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    hackathonToDelete = hackathon
                                    isShowingDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color.theme.mainBackground)
                }
            }
            .background(Color.theme.mainBackground)
            .navigationTitle("Hackathons & Contests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body)
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Add Hackathon")
                }
            }
            .sheet(isPresented: $isShowingAddSheet) {
                HackathonEditorView()
            }
            .alert("Delete Hackathon", isPresented: $isShowingDeleteAlert, presenting: hackathonToDelete) { item in
                Button("Delete", role: .destructive) {
                    NotificationService.shared.cancelReminders(forHackathonId: item.id)
                    modelContext.delete(item)
                    try? modelContext.save()
                }
                Button("Cancel", role: .cancel) {}
            } message: { item in
                Text("Are you sure you want to delete '\(item.title)'? This action cannot be undone.")
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(
                selectedFilter == .completed ? "No Completed Events" : "No Hackathons Tracked",
                systemImage: selectedFilter == .completed ? "checkmark.circle" : "trophy"
            )
        } description: {
            Text(
                selectedFilter == .completed
                ? "Events marked as attended or completed will appear here."
                : "Add your upcoming hackathons, coding contests, and tech challenges to track deadlines in one place."
            )
        } actions: {
            if selectedFilter != .completed {
                Button {
                    isShowingAddSheet = true
                } label: {
                    Label("Add Event", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.theme.primaryAccent)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Compact Event List Card (No Long Descriptions)

/// Streamlined row view representing a hackathon or competition card in the list.
/// Displays ONLY:
/// 1. Event title
/// 2. Organizer (if available)
/// 3. Event date or date range
/// 4. Online/offline/hybrid mode
/// 5. One compact, relevant status or deadline indicator
struct HackathonCardView: View {
    let hackathon: Hackathon
    let onToggleComplete: () -> Void

    var body: some View {
        let status = hackathon.status()

        HStack(alignment: .top, spacing: 12) {
            // Checkbox button for quick toggle
            Button(action: onToggleComplete) {
                Image(systemName: hackathon.isAttendedOrCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(hackathon.isAttendedOrCompleted ? Color.theme.primaryAccent : Color.theme.secondaryText)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                // 1. Title & Organizer
                VStack(alignment: .leading, spacing: 2) {
                    Text(hackathon.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .strikethrough(hackathon.isAttendedOrCompleted, color: Color.theme.secondaryText)
                        .foregroundStyle(hackathon.isAttendedOrCompleted ? Color.theme.secondaryText : Color.theme.primaryText)
                        .lineLimit(2)

                    if !hackathon.organizer.isEmpty {
                        Text(hackathon.organizer)
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)
                            .lineLimit(1)
                    }
                }

                // 2. Date or Date Range + Mode + One Compact Status Indicator
                HStack(alignment: .center, spacing: 8) {
                    // Mode Tag
                    Label(hackathon.mode.rawValue, systemImage: hackathon.mode.iconName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.theme.secondarySurface)
                        .foregroundStyle(Color.theme.primaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    // Event Date / Range
                    if let start = hackathon.startDate {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                            if let end = hackathon.endDate {
                                Text("\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))")
                            } else {
                                Text(start.formatted(date: .abbreviated, time: .omitted))
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(Color.theme.secondaryText)
                    } else if let reg = hackathon.registrationDeadline {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text("Reg: \(reg.formatted(date: .abbreviated, time: .omitted))")
                        }
                        .font(.caption2)
                        .foregroundStyle(Color.theme.secondaryText)
                    }

                    Spacer(minLength: 4)

                    // One compact status indicator
                    compactStatusBadge(status: status)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(hackathon.isAttendedOrCompleted ? 0.75 : 1.0)
    }

    private func compactStatusBadge(status: HackathonStatus) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 6, height: 6)
            Text(status.rawValue)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusSurface(status))
        .foregroundStyle(statusColor(status))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func statusColor(_ status: HackathonStatus) -> Color {
        switch status {
        case .upcoming:
            return Color.theme.primaryAccent
        case .regClosingSoon:
            return Color.theme.warning
        case .ongoing:
            return Color.theme.exam
        case .completed:
            return Color.theme.secondaryText
        }
    }

    private func statusSurface(_ status: HackathonStatus) -> Color {
        switch status {
        case .upcoming:
            return Color.theme.secondarySurface
        case .regClosingSoon:
            return Color.theme.warningSurface
        case .ongoing:
            return Color.theme.examSurface
        case .completed:
            return Color.theme.secondarySurface
        }
    }
}

// MARK: - Dedicated Event Detail View

/// Full read-only detail view for a tracked hackathon or competition event.
struct HackathonDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let hackathon: Hackathon

    @State private var isShowingEditSheet: Bool = false
    @State private var isShowingDeleteAlert: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Main Header Card
                headerCard

                // Full Description Card
                if !hackathon.eventDescription.isEmpty {
                    descriptionCard
                }

                // Schedule & Deadlines Card
                deadlinesCard

                // Venue & Logistics Card
                logisticsCard

                // External Link Card
                if let url = URL(string: hackathon.websiteUrl),
                   UIApplication.shared.canOpenURL(url) {
                    websiteCard(url: url)
                }

                // Actions Footer
                actionsFooter
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color.theme.mainBackground)
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    isShowingEditSheet = true
                }
                .font(.subheadline)
                .fontWeight(.medium)
            }
        }
        .sheet(isPresented: $isShowingEditSheet) {
            HackathonEditorView(hackathonToEdit: hackathon)
        }
        .alert("Delete Event", isPresented: $isShowingDeleteAlert) {
            Button("Delete", role: .destructive) {
                NotificationService.shared.cancelReminders(forHackathonId: hackathon.id)
                modelContext.delete(hackathon)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete '\(hackathon.title)'? This will cancel all scheduled reminders.")
        }
    }

    // MARK: - Detail Subcomponents

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hackathon.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.theme.primaryText)

                    if !hackathon.organizer.isEmpty {
                        Text(hackathon.organizer)
                            .font(.subheadline)
                            .foregroundStyle(Color.theme.secondaryText)
                    }
                }

                Spacer()

                Button {
                    withAnimation {
                        hackathon.isAttendedOrCompleted.toggle()
                        try? modelContext.save()
                        if hackathon.isAttendedOrCompleted {
                            NotificationService.shared.cancelReminders(forHackathonId: hackathon.id)
                        } else {
                            NotificationService.shared.scheduleReminders(for: hackathon)
                        }
                    }
                } label: {
                    Image(systemName: hackathon.isAttendedOrCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(hackathon.isAttendedOrCompleted ? Color.theme.primaryAccent : Color.theme.secondaryText)
                }
                .buttonStyle(.plain)
            }

            Divider()
                .background(Color.theme.divider)

            HStack(spacing: 8) {
                // Mode
                Label(hackathon.mode.rawValue, systemImage: hackathon.mode.iconName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.theme.secondarySurface)
                    .foregroundStyle(Color.theme.primaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                // Participation Status
                if let part = hackathon.participationStatus, !part.isEmpty {
                    Label(part, systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.theme.softAccentSurface)
                        .foregroundStyle(Color.theme.primaryAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Spacer()

                // Event Status Badge
                let status = hackathon.status()
                Text(status.rawValue)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(status == .regClosingSoon ? Color.theme.warningSurface : Color.theme.secondarySurface)
                    .foregroundStyle(status == .regClosingSoon ? Color.theme.warning : Color.theme.primaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(14)
        .themeCard()
    }

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Description & Tracks", systemImage: "text.alignleft")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.theme.primaryText)

            Text(hackathon.eventDescription)
                .font(.subheadline)
                .foregroundStyle(Color.theme.secondaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .themeCard()
    }

    private var deadlinesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Important Schedule & Deadlines", systemImage: "calendar.badge.clock")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.theme.primaryText)

            VStack(spacing: 8) {
                if let reg = hackathon.registrationDeadline {
                    dateRow(
                        title: "Registration Deadline",
                        date: reg,
                        icon: "clock.badge.exclamationmark",
                        color: Color.theme.warning
                    )
                }

                if let sub = hackathon.submissionDeadline {
                    dateRow(
                        title: "Project / Round Submission",
                        date: sub,
                        icon: "tray.and.arrow.up.fill",
                        color: Color.theme.exam
                    )
                }

                if let start = hackathon.startDate {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "calendar")
                            .font(.body)
                            .foregroundStyle(Color.theme.primaryAccent)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Event Schedule")
                                .font(.caption)
                                .foregroundStyle(Color.theme.secondaryText)

                            if let end = hackathon.endDate {
                                Text("\(start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.theme.primaryText)
                            } else {
                                Text(start.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.theme.primaryText)
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(14)
        .themeCard()
    }

    private func dateRow(title: String, date: Date, icon: String, color: Color) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color.theme.secondaryText)
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.theme.primaryText)
            }
            Spacer()
        }
    }

    private var logisticsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Venue & Format", systemImage: "mappin.circle")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.theme.primaryText)

            HStack(spacing: 8) {
                Text("Format:")
                    .font(.caption)
                    .foregroundStyle(Color.theme.secondaryText)
                Text(hackathon.mode.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.theme.primaryText)
            }

            if !hackathon.location.isEmpty {
                HStack(spacing: 8) {
                    Text("Location:")
                        .font(.caption)
                        .foregroundStyle(Color.theme.secondaryText)
                    Text(hackathon.location)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.theme.primaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .themeCard()
    }

    private func websiteCard(url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Image(systemName: "arrow.up.right.square")
                    .font(.body)
                Text("Open Official Event Website")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Color.theme.secondaryText)
            }
            .foregroundStyle(Color.theme.primaryAccent)
            .padding(14)
            .themeCard()
        }
    }

    private var actionsFooter: some View {
        VStack(spacing: 10) {
            Button(role: .destructive) {
                isShowingDeleteAlert = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Event")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.theme.overdueSurface)
                .foregroundStyle(Color.theme.overdue)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Event Form Editor

/// Form for creating or editing a hackathon or competition event.
struct HackathonEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var hackathonToEdit: Hackathon?

    @State private var title: String = ""
    @State private var organizer: String = ""
    @State private var mode: HackathonMode = .online
    @State private var location: String = ""
    @State private var websiteUrl: String = ""
    @State private var eventDescription: String = ""

    @State private var hasRegDeadline: Bool = false
    @State private var registrationDeadline: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    @State private var hasSubmissionDeadline: Bool = false
    @State private var submissionDeadline: Date = Calendar.current.date(byAdding: .day, value: 10, to: Date()) ?? Date()

    @State private var hasStartDate: Bool = false
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()

    @State private var hasEndDate: Bool = false
    @State private var endDate: Date = Calendar.current.date(byAdding: .day, value: 16, to: Date()) ?? Date()

    @State private var participationStatus: String = "Registered"
    @State private var isAttendedOrCompleted: Bool = false

    private var isEditing: Bool {
        hackathonToEdit != nil
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isUrlValid: Bool {
        let trimmed = websiteUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            return scheme == "http" || scheme == "https"
        }
        return false
    }

    init(hackathonToEdit: Hackathon? = nil) {
        self.hackathonToEdit = hackathonToEdit
        if let item = hackathonToEdit {
            _title = State(initialValue: item.title)
            _organizer = State(initialValue: item.organizer)
            _mode = State(initialValue: item.mode)
            _location = State(initialValue: item.location)
            _websiteUrl = State(initialValue: item.websiteUrl)
            _eventDescription = State(initialValue: item.eventDescription)
            _participationStatus = State(initialValue: item.participationStatus ?? "Registered")
            _isAttendedOrCompleted = State(initialValue: item.isAttendedOrCompleted)

            if let reg = item.registrationDeadline {
                _hasRegDeadline = State(initialValue: true)
                _registrationDeadline = State(initialValue: reg)
            }
            if let sub = item.submissionDeadline {
                _hasSubmissionDeadline = State(initialValue: true)
                _submissionDeadline = State(initialValue: sub)
            }
            if let start = item.startDate {
                _hasStartDate = State(initialValue: true)
                _startDate = State(initialValue: start)
            }
            if let end = item.endDate {
                _hasEndDate = State(initialValue: true)
                _endDate = State(initialValue: end)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event Information") {
                    TextField("Event Name (e.g. HackMIT, Smart India Hackathon)", text: $title)
                    TextField("Organizer / University (Optional)", text: $organizer)

                    Picker("Mode", selection: $mode) {
                        ForEach(HackathonMode.allCases) { m in
                            Label(m.rawValue, systemImage: m.iconName).tag(m)
                        }
                    }

                    if mode != .online {
                        TextField("Location / Campus (e.g. New Delhi, In-Person)", text: $location)
                    }
                }

                Section("Links & Details") {
                    TextField("Website or Registration URL (Optional)", text: $websiteUrl)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    if !isUrlValid {
                        Text("Please enter a valid web URL starting with https:// or http://")
                            .font(.caption2)
                            .foregroundStyle(Color.theme.overdue)
                    }

                    TextField("Description, tracks, prize pool, etc.", text: $eventDescription, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Registration Deadline") {
                    Toggle("Set Registration Deadline", isOn: $hasRegDeadline)
                    if hasRegDeadline {
                        DatePicker("Deadline", selection: $registrationDeadline, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("Project / Round Submission Deadline") {
                    Toggle("Set Submission Deadline", isOn: $hasSubmissionDeadline)
                    if hasSubmissionDeadline {
                        DatePicker("Submission Due", selection: $submissionDeadline, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("Event Dates") {
                    Toggle("Set Start Date", isOn: $hasStartDate)
                    if hasStartDate {
                        DatePicker("Start Date", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    }

                    Toggle("Set End Date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("End Date", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("Participation Status") {
                    TextField("Status (e.g. Registered, Shortlisted, Submitted)", text: $participationStatus)
                }

                if isEditing {
                    Section("Status") {
                        Toggle("Mark as Attended / Completed", isOn: $isAttendedOrCompleted)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Hackathon" : "New Hackathon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!isValid || !isUrlValid)
                    .fontWeight(.bold)
                }
            }
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanOrganizer = organizer.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUrl = websiteUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDesc = eventDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = hackathonToEdit {
            existing.title = cleanTitle
            existing.organizer = cleanOrganizer
            existing.mode = mode
            existing.location = cleanLocation
            existing.websiteUrl = cleanUrl
            existing.eventDescription = cleanDesc
            existing.registrationDeadline = hasRegDeadline ? registrationDeadline : nil
            existing.submissionDeadline = hasSubmissionDeadline ? submissionDeadline : nil
            existing.startDate = hasStartDate ? startDate : nil
            existing.endDate = hasEndDate ? endDate : nil
            existing.participationStatus = participationStatus.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.isAttendedOrCompleted = isAttendedOrCompleted
            existing.isManuallyEdited = true
            NotificationService.shared.scheduleReminders(for: existing)
        } else {
            let newHackathon = Hackathon(
                title: cleanTitle,
                organizer: cleanOrganizer,
                startDate: hasStartDate ? startDate : nil,
                registrationDeadline: hasRegDeadline ? registrationDeadline : nil,
                submissionDeadline: hasSubmissionDeadline ? submissionDeadline : nil,
                endDate: hasEndDate ? endDate : nil,
                mode: mode,
                location: cleanLocation,
                websiteUrl: cleanUrl,
                eventDescription: cleanDesc,
                source: "local",
                participationStatus: participationStatus.trimmingCharacters(in: .whitespacesAndNewlines),
                isAttendedOrCompleted: isAttendedOrCompleted,
                importSource: "manual",
                importedAt: Date(),
                isManuallyEdited: true
            )
            modelContext.insert(newHackathon)
            NotificationService.shared.scheduleReminders(for: newHackathon)
        }

        try? modelContext.save()
        dismiss()
    }
}
