//
//  NoticeScannerView.swift
//  AssignementRadar
//
//  Created for Assignment Radar Scanning Feature & Timetable Intelligence.
//

import SwiftUI
import PhotosUI
import SwiftData
import UIKit

/// Camera capture view representable using UIImagePickerController.
struct CameraCapturePickerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onImageCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCapturePickerView

        init(_ parent: CameraCapturePickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImageCaptured(image)
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

/// The complete on-device scanning view: camera/photo selection, Vision OCR processing,
/// structured timetable row grouping, editable review screen, SwiftData persistence, and Apple Calendar sync.
struct NoticeScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Existing assignments for deduplication
    @Query private var existingAssignments: [Assignment]

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String? = nil

    // Extracted drafts under review
    @State private var drafts: [ScannedAssignmentDraft] = []
    @State private var rawExtractedLines: [String] = []
    @State private var documentKind: ScannedDocumentKind = .generalNotice
    @State private var ocrQualityReport: OcrQualityReport? = nil
    @State private var detectedYear: Int? = nil
    @State private var isYearAmbiguous: Bool = false
    @State private var selectedYearForOverride: Int = Calendar.current.component(.year, from: Date())

    // UI state sheets & alerts
    @State private var isShowingCamera: Bool = false
    @State private var isShowingRawText: Bool = false
    @State private var isShowingManualEditor: Bool = false
    @State private var isShowingDemoGallery: Bool = false
    @State private var isShowingYearPicker: Bool = false
    @State private var syncToAppleCalendar: Bool = true

    // Validation & Reporting Alert State
    @State private var validationErrorMessage: String? = nil
    @State private var isShowingValidationAlert: Bool = false
    @State private var calendarNoticeMessage: String? = nil
    @State private var isShowingCalendarNotice: Bool = false

    private var selectedDraftsCount: Int {
        drafts.filter { $0.isSelected }.count
    }

    private var hasUncertainDeadlines: Bool {
        drafts.contains { $0.isSelected && (!$0.isConfidentDate || !$0.isConfidentTitle) }
    }

    private var hasDuplicates: Bool {
        drafts.contains { $0.isDuplicate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isProcessing {
                    processingView
                } else if !drafts.isEmpty {
                    reviewView
                } else {
                    initialPickerView
                }
            }
            .background(Color.theme.mainBackground)
            .navigationTitle(drafts.isEmpty ? "Scan Notice" : "Review Deadlines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                if !drafts.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save (\(selectedDraftsCount))") {
                            saveConfirmedDrafts()
                        }
                        .disabled(selectedDraftsCount == 0)
                        .fontWeight(.bold)
                    }
                }
            }
            .alert("Incomplete Information", isPresented: $isShowingValidationAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationErrorMessage ?? "Please verify all required fields.")
            }
            .alert("Calendar Notice", isPresented: $isShowingCalendarNotice) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text(calendarNoticeMessage ?? "Events were saved to Radar.")
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraCapturePickerView(isPresented: $isShowingCamera) { captured in
                    scanImage(captured)
                }
            }
            .sheet(isPresented: $isShowingYearPicker) {
                yearConfirmationSheet
            }
            .sheet(isPresented: $isShowingManualEditor) {
                AssignmentEditorView()
            }
            .sheet(isPresented: $isShowingDemoGallery) {
                DemoScanGalleryView { demoImage in
                    scanImage(demoImage)
                }
            }
        }
    }

    // MARK: - Initial Picker View

    private var initialPickerView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 58))
                .foregroundStyle(Color.theme.primaryAccent)

            VStack(spacing: 8) {
                Text("Scan University Timetable")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.theme.primaryText)

                Text("Take a photo of your exam datesheet, syllabus, or lecture schedule. Text is recognized and clustered on-device into structured, editable events.")
                    .font(.subheadline)
                    .foregroundStyle(Color.theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let error = errorMessage {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.theme.warning)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(Color.theme.primaryText)
                    }
                    .padding(12)
                    .background(Color.theme.warningSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)

                    Button("Enter Deadline Manually") {
                        isShowingManualEditor = true
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.theme.primaryAccent)
                }
            }

            VStack(spacing: 12) {
                // Primary Action: Camera Capture
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        isShowingCamera = true
                    } else {
                        errorMessage = "Camera is not available on this simulator. Please use photo library or demo scans."
                    }
                } label: {
                    Label("Take Photo with Camera", systemImage: "camera.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.theme.primaryAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Secondary Action: PhotosPicker
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Choose Photo from Library", systemImage: "photo.on.rectangle")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.theme.cardBackground)
                        .foregroundStyle(Color.theme.primaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.theme.divider, lineWidth: 1)
                        )
                }
                .onChange(of: selectedPhotoItem) { _, newItem in
                    handlePhotoSelection(newItem)
                }

                // Demo Gallery Button
                Button {
                    isShowingDemoGallery = true
                } label: {
                    Label("Try Demo Scans", systemImage: "sparkles.rectangle.stack.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.theme.cardBackground.opacity(0.8))
                        .foregroundStyle(Color.theme.secondaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            // Manual Fallback Link
            Button {
                isShowingManualEditor = true
            } label: {
                Text("Can't scan? Enter deadline manually")
                    .font(.footnote)
                    .foregroundStyle(Color.theme.secondaryText)
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Processing State

    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(Color.theme.primaryAccent)
            Text("Analyzing timetable & grouping rows...")
                .font(.headline)
                .foregroundStyle(Color.theme.primaryText)
            Text("Vision OCR is clustering bounding boxes into structured dates, sessions, courses, and exam venues.")
                .font(.subheadline)
                .foregroundStyle(Color.theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding()
    }

    // MARK: - Editable Review Screen

    private var reviewView: some View {
        List {
            // Quality Warning Banner
            if let quality = ocrQualityReport, quality.isBlurryOrLowQuality {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.theme.warning)
                            Text("Image Quality Notice")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.theme.primaryText)
                        }
                        Text(quality.warningMessage ?? "Photo appears blurry or poorly lit. Please verify extracted fields carefully.")
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)

                        HStack {
                            Button("Rescan Photo") {
                                drafts.removeAll()
                            }
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.theme.primaryAccent)
                        }
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.theme.warningSurface)
            }

            // Year Ambiguity Confirmation Banner
            if isYearAmbiguous {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .foregroundStyle(Color.theme.warning)
                            Text("Document Year Missing / Ambiguous")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.theme.primaryText)
                        }
                        Text("The datesheet did not specify an explicit 4-digit academic year. Dates are currently set to \(selectedYearForOverride). Please confirm or choose the correct year.")
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)

                        HStack(spacing: 12) {
                            Button("Confirm \(selectedYearForOverride)") {
                                applyYearOverride(selectedYearForOverride)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(Color.theme.primaryAccent)

                            Button("Change Year") {
                                isShowingYearPicker = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.theme.cardBackground)
            }

            // Document Classification Header Banner
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: bannerIcon)
                            .font(.body)
                            .foregroundStyle(bannerColor)

                        Text(bannerTitle)
                            .font(.headline)
                            .foregroundStyle(Color.theme.primaryText)
                    }

                    Text(bannerDescription)
                        .font(.caption)
                        .foregroundStyle(Color.theme.secondaryText)

                    if hasDuplicates {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.theme.primaryAccent)
                            Text("Some events match existing items in Radar and are deselected to prevent duplicates.")
                                .font(.caption2)
                                .foregroundStyle(Color.theme.secondaryText)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.theme.cardBackground)

            // Apple Calendar Option Toggle
            Section {
                Toggle(isOn: $syncToAppleCalendar) {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .foregroundStyle(Color.theme.primaryAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sync Confirmed to Apple Calendar")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.theme.primaryText)
                            Text("Creates events with venue, duration, and alarms in Apple Calendar.")
                                .font(.caption2)
                                .foregroundStyle(Color.theme.secondaryText)
                        }
                    }
                }
                .tint(Color.theme.primaryAccent)
            }
            .listRowBackground(Color.theme.cardBackground)

            // Extracted Timetable Rows
            Section("Extracted Items (\(selectedDraftsCount) of \(drafts.count) selected)") {
                ForEach($drafts) { $draft in
                    draftRow(draft: $draft)
                }
            }
            .listRowBackground(Color.theme.cardBackground)

            // Actions & Inspector Section
            Section {
                Button {
                    let newDraft = ScannedAssignmentDraft(
                        title: documentKind == .examDatesheet ? "New Exam" : "New Assignment",
                        course: "",
                        dueDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date(),
                        priority: documentKind == .examDatesheet ? .high : .medium,
                        eventType: documentKind == .examDatesheet ? "exam" : "assignment",
                        sessionTime: documentKind == .examDatesheet ? "10:00 AM - 01:00 PM" : nil,
                        room: "",
                        isSelected: true,
                        isConfidentDate: true,
                        isConfidentTitle: true,
                        isConfidentTime: true
                    )
                    drafts.append(newDraft)
                } label: {
                    Label(documentKind == .examDatesheet ? "Add Another Exam" : "Add Another Item", systemImage: "plus.circle")
                        .foregroundStyle(Color.theme.primaryAccent)
                }

                Button(role: .destructive) {
                    drafts.removeAll()
                } label: {
                    Label("Rescan / Choose Different Photo", systemImage: "arrow.counterclockwise")
                }

                // Raw OCR text inspector
                DisclosureGroup("View Raw Extracted Text (\(rawExtractedLines.count) lines)", isExpanded: $isShowingRawText) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(rawExtractedLines.indices, id: \.self) { idx in
                            Text("\(idx + 1). \(rawExtractedLines[idx])")
                                .font(.caption2)
                                .foregroundStyle(Color.theme.secondaryText)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listRowBackground(Color.theme.cardBackground)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.theme.mainBackground)
    }

    private var bannerTitle: String {
        switch documentKind {
        case .examDatesheet:
            return "Examination Datesheet Detected"
        case .assignmentNotice:
            return hasUncertainDeadlines ? "Assignment Notice • Review Required" : "Assignment Notice Detected"
        case .generalNotice:
            return hasUncertainDeadlines ? "Notice • Review Required" : "Academic Schedule Extracted"
        }
    }

    private var bannerIcon: String {
        switch documentKind {
        case .examDatesheet:
            return "graduationcap.circle.fill"
        case .assignmentNotice, .generalNotice:
            return hasUncertainDeadlines ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"
        }
    }

    private var bannerColor: Color {
        switch documentKind {
        case .examDatesheet:
            return Color.theme.exam
        case .assignmentNotice, .generalNotice:
            return hasUncertainDeadlines ? Color.theme.warning : Color.theme.success
        }
    }

    private var bannerDescription: String {
        switch documentKind {
        case .examDatesheet:
            return "Extracted \(drafts.count) examination rows with subjects, times, and venues. Unchecked items will not be saved."
        case .assignmentNotice:
            return hasUncertainDeadlines
                ? "Extracted assignment details with unconfirmed deadline. Please verify the submission deadline before saving."
                : "Coursework assignment and submission deadline extracted. Unchecked items will be ignored."
        case .generalNotice:
            return hasUncertainDeadlines
                ? "Items with verification badges have unconfirmed dates or titles. Please adjust before saving."
                : "Verify the extracted academic deadlines below. Unchecked items will be ignored."
        }
    }

    // MARK: - Draft Row Editor

    private func draftRow(draft: Binding<ScannedAssignmentDraft>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Checkbox, Event Type Badge, and delete action
            HStack {
                Button {
                    draft.wrappedValue.isSelected.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: draft.wrappedValue.isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(draft.wrappedValue.isSelected ? Color.theme.primaryAccent : Color.theme.secondaryText)
                        Text(draft.wrappedValue.isSelected ? "Include in Radar" : "Skip")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(draft.wrappedValue.isSelected ? Color.theme.primaryText : Color.theme.secondaryText)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Event Type Picker (Exam, Assignment, Class)
                Picker("", selection: draft.eventType) {
                    Text("Exam").tag("exam")
                    Text("Assignment").tag("assignment")
                    Text("Class").tag("class")
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Button(role: .destructive) {
                    if let index = drafts.firstIndex(where: { $0.id == draft.wrappedValue.id }) {
                        drafts.remove(at: index)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(Color.theme.overdue)
                }
                .buttonStyle(.plain)
            }

            // Compact Status / Warning Indicators
            HStack(spacing: 6) {
                if draft.wrappedValue.isDuplicate {
                    HStack(spacing: 3) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("Duplicate")
                    }
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.theme.secondarySurface)
                    .foregroundStyle(Color.theme.secondaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                if !draft.wrappedValue.isConfidentDate {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(draft.wrappedValue.uncertaintyReason ?? "Verify date")
                    }
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.theme.warningSurface)
                    .foregroundStyle(Color.theme.warning)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                if draft.wrappedValue.eventType == "exam" {
                    if let session = draft.wrappedValue.sessionTime, !session.isEmpty, !draft.wrappedValue.isAssumedTime {
                        HStack(spacing: 3) {
                            Image(systemName: "clock.badge.checkmark")
                            Text(session)
                        }
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.theme.softAccentSurface)
                        .foregroundStyle(Color.theme.primaryAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "clock.badge.questionmark")
                            Text("Assumed 10:00 AM")
                        }
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.theme.warningSurface)
                        .foregroundStyle(Color.theme.warning)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            // Editable Title
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(draft.wrappedValue.eventType == "exam" ? "Subject / Examination" : "Assignment Title")
                        .font(.caption2)
                        .foregroundStyle(Color.theme.secondaryText)
                    if draft.wrappedValue.isSelected && draft.wrappedValue.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("• Required")
                            .font(.caption2)
                            .foregroundStyle(Color.theme.overdue)
                    }
                }
                TextField("Title", text: draft.title)
                    .textFieldStyle(.roundedBorder)
            }

            // Editable Course & Venue/Room
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Course Code")
                        .font(.caption2)
                        .foregroundStyle(Color.theme.secondaryText)
                    TextField("e.g. CS 301", text: draft.course)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Room / Venue")
                        .font(.caption2)
                        .foregroundStyle(Color.theme.secondaryText)
                    TextField("e.g. Room 302, Hall A", text: draft.room)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Editable Date
            DatePicker(
                draft.wrappedValue.eventType == "exam" ? "Date" : "Due Date",
                selection: draft.dueDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(.subheadline)

            // Examination Session / Time Slot (if applicable)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Session / Time Slot")
                        .font(.caption2)
                        .foregroundStyle(Color.theme.secondaryText)
                    if draft.wrappedValue.isAssumedTime {
                        Text("(Assumed 10:00 AM — tap to edit)")
                            .font(.caption2)
                            .foregroundStyle(Color.theme.warning)
                    }
                }
                TextField(
                    "e.g. 10:00 AM - 01:00 PM (or 02:00 PM)",
                    text: Binding(
                        get: { draft.wrappedValue.sessionTime ?? "" },
                        set: { newValue in
                            let clean = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            draft.wrappedValue.sessionTime = clean.isEmpty ? nil : clean
                            draft.wrappedValue.isAssumedTime = clean.isEmpty
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
            }

            // Priority Picker
            Picker("Priority", selection: draft.priority) {
                ForEach(Priority.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 6)
        .opacity(draft.wrappedValue.isSelected ? 1.0 : 0.5)
    }

    // MARK: - Year Picker Modal Sheet

    private var yearConfirmationSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Select Academic Year")
                    .font(.headline)
                    .padding(.top)

                Text("Choose the year for these timetable entries. All ambiguous dates will be updated accordingly.")
                    .font(.subheadline)
                    .foregroundStyle(Color.theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Picker("Year", selection: $selectedYearForOverride) {
                    ForEach(2024...2030, id: \.self) { y in
                        Text("\(y)").tag(y)
                    }
                }
                .pickerStyle(.wheel)

                Button("Apply Year to All Items") {
                    applyYearOverride(selectedYearForOverride)
                    isShowingYearPicker = false
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.theme.primaryAccent)
                .padding(.bottom)

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss") {
                        isShowingYearPicker = false
                    }
                }
            }
        }
        .presentationDetents([.height(340)])
    }

    private func applyYearOverride(_ newYear: Int) {
        let calendar = Calendar.current
        for idx in drafts.indices {
            var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: drafts[idx].dueDate)
            comps.year = newYear
            if let newDate = calendar.date(from: comps) {
                drafts[idx].dueDate = newDate
                drafts[idx].isConfidentDate = true
                drafts[idx].isYearAmbiguous = false
                drafts[idx].uncertaintyReason = nil
            }
        }
        isYearAmbiguous = false
        detectedYear = newYear
    }

    // MARK: - Actions & Logic

    func scanImage(_ image: UIImage) {
        selectedImage = image
        isProcessing = true
        errorMessage = nil

        Task {
            do {
                let (blocks, quality) = try await TextRecognitionService.recognizeTextBlocks(from: image)
                await processRecognizedBlocks(blocks, quality: quality)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        isProcessing = true
        errorMessage = nil

        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        scanImage(image)
                    }
                } else {
                    await MainActor.run {
                        errorMessage = "Could not load image data from selection."
                        isProcessing = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }

    @MainActor
    private func processRecognizedBlocks(_ blocks: [OcrTextBlock], quality: OcrQualityReport) {
        let rows = TimetableParser.groupBlocksIntoRows(blocks)
        rawExtractedLines = rows.map { $0.text }
        ocrQualityReport = quality
        isProcessing = false

        if blocks.isEmpty {
            errorMessage = quality.warningMessage ?? "No readable text detected in this photo. Please try a clearer picture or enter deadlines manually."
            return
        }

        let result = ScheduleParser.parse(blocks: blocks, existingAssignments: existingAssignments, qualityReport: quality)
        documentKind = result.kind
        detectedYear = result.detectedYear
        isYearAmbiguous = result.isYearAmbiguous

        if let y = result.detectedYear {
            selectedYearForOverride = y
        }

        if result.drafts.isEmpty {
            let fallbackDraft = ScannedAssignmentDraft(
                title: rawExtractedLines.first ?? "Scanned Notice",
                course: "",
                dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
                priority: .medium,
                notes: rawExtractedLines.joined(separator: "\n"),
                eventType: "assignment",
                sessionTime: nil,
                room: "",
                isSelected: true,
                isConfidentDate: false,
                isConfidentTitle: false,
                isConfidentTime: true,
                isAssumedTime: false,
                isYearAmbiguous: result.isYearAmbiguous,
                rawText: rawExtractedLines.joined(separator: " "),
                uncertaintyReason: "No specific deadline recognized - please set manually"
            )
            drafts = [fallbackDraft]
        } else {
            drafts = result.drafts
        }
    }

    /// Validates selected drafts, inserts them into SwiftData, schedules reminders, and optionally syncs to Apple Calendar.
    private func saveConfirmedDrafts() {
        let confirmed = drafts.filter { $0.isSelected }

        for (index, draft) in confirmed.enumerated() {
            let cleanTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanTitle.isEmpty {
                let identifier = draft.course.isEmpty ? "Item \(index + 1)" : draft.course
                validationErrorMessage = "\(identifier) has an empty title. Please enter a valid title or deselect the item before saving."
                isShowingValidationAlert = true
                return
            }
        }

        for draft in confirmed {
            if draft.dueDate == Date.distantFuture || draft.dueDate == Date.distantPast || draft.dueDate.timeIntervalSince1970 < 86400 {
                validationErrorMessage = "One or more selected items have an invalid date. Please adjust the due date."
                isShowingValidationAlert = true
                return
            }
        }

        var savedAssignments: [Assignment] = []

        for draft in confirmed {
            let cleanTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanCourse = draft.course.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanNotes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanRoom = draft.room.trimmingCharacters(in: .whitespacesAndNewlines)

            let assignment = Assignment(
                title: cleanTitle.isEmpty ? (draft.eventType == "exam" ? "Examination" : "Untitled Assignment") : cleanTitle,
                course: cleanCourse,
                dueDate: draft.dueDate,
                priority: draft.priority,
                notes: cleanNotes,
                isCompleted: false,
                source: "scan",
                eventType: draft.eventType,
                sessionTime: draft.sessionTime,
                room: cleanRoom,
                rawOcrText: draft.rawText
            )
            modelContext.insert(assignment)
            NotificationService.shared.scheduleReminders(for: assignment)
            savedAssignments.append(assignment)
        }

        try? modelContext.save()

        if syncToAppleCalendar {
            Task {
                let authorized = await CalendarSyncService.shared.requestAccess()
                if authorized {
                    var syncedCount = 0
                    for item in savedAssignments {
                        if await CalendarSyncService.shared.syncAssignment(item) != nil {
                            syncedCount += 1
                        }
                    }
                    try? modelContext.save()
                    await MainActor.run {
                        dismiss()
                    }
                } else {
                    await MainActor.run {
                        calendarNoticeMessage = "Saved \(savedAssignments.count) events locally in Radar. Apple Calendar access was denied or unavailable, so Calendar events could not be created."
                        isShowingCalendarNotice = true
                    }
                }
            }
        } else {
            dismiss()
        }
    }
}
