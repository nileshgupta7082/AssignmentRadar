//
//  NoticeScannerService.swift
//  AssignementRadar
//
//  Created for Assignment Radar Scanning Feature & Timetable Intelligence.
//

import Foundation
import UIKit
import Vision
import SwiftUI

/// Errors that can occur during document scanning and text recognition.
enum ScannerError: LocalizedError {
    case invalidImage
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Unable to process the selected image."
        case .noTextFound:
            return "No readable text was detected. Please ensure the notice is well-lit and clear, or enter deadlines manually."
        }
    }
}

/// Represents an individual OCR text observation with normalized coordinates and recognition confidence.
struct OcrTextBlock: Sendable, Identifiable {
    let id: UUID
    let text: String
    /// Bounding box in normalized coordinates [0, 1] where (0,0) is TOP-LEFT.
    let boundingBox: CGRect
    let confidence: Float

    init(id: UUID = UUID(), text: String, boundingBox: CGRect, confidence: Float = 1.0) {
        self.id = id
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

/// Quality assessment of the scanned document image.
struct OcrQualityReport: Sendable {
    let totalBlocks: Int
    let averageConfidence: Float
    let isBlurryOrLowQuality: Bool
    let warningMessage: String?

    init(
        totalBlocks: Int,
        averageConfidence: Float,
        isBlurryOrLowQuality: Bool,
        warningMessage: String?
    ) {
        self.totalBlocks = totalBlocks
        self.averageConfidence = averageConfidence
        self.isBlurryOrLowQuality = isBlurryOrLowQuality
        self.warningMessage = warningMessage
    }
}

/// A horizontal visual line or row formed by 2D spatial clustering of text blocks.
struct TimetableRow: Sendable {
    let yCenter: CGFloat
    let blocks: [OcrTextBlock]

    var text: String {
        blocks.map { $0.text }.joined(separator: " ")
    }

    init(yCenter: CGFloat, blocks: [OcrTextBlock]) {
        self.yCenter = yCenter
        self.blocks = blocks
    }
}

/// Represents an editable draft of an academic deadline or examination extracted from OCR text.
struct ScannedAssignmentDraft: Identifiable, Sendable {
    let id: UUID
    var title: String
    var course: String
    var dueDate: Date
    var priority: Priority
    var notes: String
    var eventType: String // "assignment", "exam", "class"
    var sessionTime: String?
    var room: String
    var isSelected: Bool
    var isConfidentDate: Bool
    var isConfidentTitle: Bool
    var isConfidentTime: Bool
    var isAssumedTime: Bool
    var isYearAmbiguous: Bool
    var rawText: String
    var isDuplicate: Bool
    var uncertaintyReason: String?

    init(
        id: UUID = UUID(),
        title: String,
        course: String = "",
        dueDate: Date = Date(),
        priority: Priority = .medium,
        notes: String = "",
        eventType: String = "assignment",
        sessionTime: String? = nil,
        room: String = "",
        isSelected: Bool = true,
        isConfidentDate: Bool = true,
        isConfidentTitle: Bool = true,
        isConfidentTime: Bool = true,
        isAssumedTime: Bool = false,
        isYearAmbiguous: Bool = false,
        rawText: String = "",
        isDuplicate: Bool = false,
        uncertaintyReason: String? = nil
    ) {
        self.id = id
        self.title = title
        self.course = course
        self.dueDate = dueDate
        self.priority = priority
        self.notes = notes
        self.eventType = eventType
        self.sessionTime = sessionTime
        self.room = room
        self.isSelected = isSelected
        self.isConfidentDate = isConfidentDate
        self.isConfidentTitle = isConfidentTitle
        self.isConfidentTime = isConfidentTime
        self.isAssumedTime = isAssumedTime
        self.isYearAmbiguous = isYearAmbiguous
        self.rawText = rawText
        self.isDuplicate = isDuplicate
        self.uncertaintyReason = uncertaintyReason
    }
}

/// Classification of scanned academic document.
enum ScannedDocumentKind: Sendable {
    case examDatesheet
    case assignmentNotice
    case generalNotice
}

/// Result of schedule parsing containing extracted drafts, document classification, and quality metadata.
struct ScheduleParseResult: Sendable {
    let drafts: [ScannedAssignmentDraft]
    let kind: ScannedDocumentKind
    let detectedYear: Int?
    let isYearAmbiguous: Bool
    let qualityReport: OcrQualityReport?

    init(
        drafts: [ScannedAssignmentDraft],
        kind: ScannedDocumentKind,
        detectedYear: Int?,
        isYearAmbiguous: Bool,
        qualityReport: OcrQualityReport? = nil
    ) {
        self.drafts = drafts
        self.kind = kind
        self.detectedYear = detectedYear
        self.isYearAmbiguous = isYearAmbiguous
        self.qualityReport = qualityReport
    }
}

// MARK: - On-Device Text Recognition Service

/// On-device text recognition using Apple's Vision framework with bounding box and quality preservation.
final class TextRecognitionService {

    /// Preprocesses the image to normalize orientation and ensure optimal Vision performance.
    static func preprocessImage(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up {
            return image
        }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return normalized
    }

    /// Performs accurate on-device text recognition, preserving text content, bounding boxes, and confidence.
    static func recognizeTextBlocks(from image: UIImage) async throws -> (blocks: [OcrTextBlock], quality: OcrQualityReport) {
        let processedImage = preprocessImage(image)
        guard let cgImage = processedImage.cgImage else {
            throw ScannerError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                    let emptyQuality = OcrQualityReport(
                        totalBlocks: 0,
                        averageConfidence: 0.0,
                        isBlurryOrLowQuality: true,
                        warningMessage: "No readable text detected. Please ensure the document is well-lit and clearly photographed."
                    )
                    continuation.resume(returning: ([], emptyQuality))
                    return
                }

                var textBlocks: [OcrTextBlock] = []
                var confidenceSum: Float = 0.0

                for obs in observations {
                    guard let top = obs.topCandidates(1).first else { continue }
                    let cleaned = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleaned.isEmpty else { continue }

                    // Vision normalized coordinates: (0,0) is bottom-left.
                    // Convert to standard UI coordinates: (0,0) is top-left.
                    let topY = 1.0 - (obs.boundingBox.origin.y + obs.boundingBox.height)
                    let convertedBox = CGRect(
                        x: obs.boundingBox.origin.x,
                        y: topY,
                        width: obs.boundingBox.width,
                        height: obs.boundingBox.height
                    )

                    let block = OcrTextBlock(
                        text: cleaned,
                        boundingBox: convertedBox,
                        confidence: top.confidence
                    )
                    textBlocks.append(block)
                    confidenceSum += top.confidence
                }

                let totalCount = textBlocks.count
                let avgConfidence = totalCount > 0 ? (confidenceSum / Float(totalCount)) : 0.0

                var isLowQuality = false
                var warning: String? = nil

                if totalCount < 4 {
                    isLowQuality = true
                    warning = "Very little readable text found (\(totalCount) fragments). Please check if the photo is cropped or poorly lit."
                } else if avgConfidence < 0.65 {
                    isLowQuality = true
                    warning = "Low text recognition confidence (\(Int(avgConfidence * 100))%). The image may be blurry or out of focus. Please review all fields carefully."
                }

                let quality = OcrQualityReport(
                    totalBlocks: totalCount,
                    averageConfidence: avgConfidence,
                    isBlurryOrLowQuality: isLowQuality,
                    warningMessage: warning
                )

                continuation.resume(returning: (textBlocks, quality))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Backward-compatible text recognition returning sorted lines.
    static func recognizeText(from image: UIImage) async throws -> [String] {
        let (blocks, _) = try await recognizeTextBlocks(from: image)
        let rows = TimetableParser.groupBlocksIntoRows(blocks)
        return rows.map { $0.text }
    }
}

// MARK: - Timetable 2D Spatial Parser

/// Converts 2D spatial text blocks into structured timetable rows, extracting columns, codes, dates, sessions, and rooms.
struct TimetableParser {

    /// Groups recognized text blocks into visual rows based on vertical alignment and line overlap.
    static func groupBlocksIntoRows(_ blocks: [OcrTextBlock]) -> [TimetableRow] {
        guard !blocks.isEmpty else { return [] }

        // Sort primarily by vertical position (boundingBox.midY)
        let sortedBlocks = blocks.sorted {
            if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.005 {
                return $0.boundingBox.midY < $1.boundingBox.midY
            }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }

        struct RowCluster {
            var minY: CGFloat
            var maxY: CGFloat
            var yCenter: CGFloat
            var blocks: [OcrTextBlock]

            var height: CGFloat { max(0.01, maxY - minY) }
        }

        var clusters: [RowCluster] = []

        for block in sortedBlocks {
            let bMinY = block.boundingBox.minY
            let bMaxY = block.boundingBox.maxY
            let bMidY = block.boundingBox.midY
            let bHeight = max(0.01, block.boundingBox.height)

            var bestClusterIndex: Int? = nil
            var bestDistance: CGFloat = .greatestFiniteMagnitude

            for (idx, cluster) in clusters.enumerated() {
                let overlapMin = max(bMinY, cluster.minY)
                let overlapMax = min(bMaxY, cluster.maxY)
                let overlap = max(0, overlapMax - overlapMin)
                let minH = min(bHeight, cluster.height)
                let overlapRatio = overlap / minH
                let verticalDist = abs(bMidY - cluster.yCenter)

                // Significant overlap or center close relative to line height
                if overlapRatio >= 0.35 || verticalDist <= (max(bHeight, cluster.height) * 0.45) {
                    if verticalDist < bestDistance {
                        bestDistance = verticalDist
                        bestClusterIndex = idx
                    }
                }
            }

            if let matchedIdx = bestClusterIndex {
                clusters[matchedIdx].blocks.append(block)
                clusters[matchedIdx].minY = min(clusters[matchedIdx].minY, bMinY)
                clusters[matchedIdx].maxY = max(clusters[matchedIdx].maxY, bMaxY)
                clusters[matchedIdx].yCenter = (clusters[matchedIdx].minY + clusters[matchedIdx].maxY) / 2.0
            } else {
                let newCluster = RowCluster(
                    minY: bMinY,
                    maxY: bMaxY,
                    yCenter: bMidY,
                    blocks: [block]
                )
                clusters.append(newCluster)
            }
        }

        // Sort each cluster's blocks left-to-right (minX ascending)
        // And sort clusters top-to-bottom (yCenter ascending)
        return clusters
            .sorted { $0.yCenter < $1.yCenter }
            .map { cluster in
                let sortedBlocks = cluster.blocks.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                return TimetableRow(yCenter: cluster.yCenter, blocks: sortedBlocks)
            }
    }

    /// Extracts examination room or venue (e.g., "Room 302", "Hall A", "LH-02", "Audi-1").
    static func extractRoom(from text: String) -> String? {
        let patterns = [
            #"\b(?:Room|Rm\.?)\s*([A-Za-z0-9\-]+)\b"#,
            #"\b(?:Lecture\s*Hall|LH)\s*[-:]?\s*([A-Za-z0-9\-]+)\b"#,
            #"\b(?:Lecture\s*Theatre|LT)\s*[-:]?\s*([A-Za-z0-9\-]+)\b"#,
            #"\b(?:Exam\s*Hall|Hall)\s*[-:]?\s*([A-Za-z0-9\-]+)\b"#,
            #"\b(?:Auditorium|Audi)\s*[-:]?\s*([A-Za-z0-9\-]+)?\b"#,
            #"\b(?:Lab)\s*[-:]?\s*([A-Za-z0-9\-]+)\b"#,
            #"\b(?:Venue)\s*[:\-]?\s*([A-Za-z0-9\s\-]+?)(?=\s*[|,•]|$)"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let nsRange = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, range: nsRange),
                   let fullRange = Range(match.range, in: text) {
                    let candidate = String(text[fullRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty && candidate.count < 30 {
                        return candidate
                    }
                }
            }
        }
        return nil
    }

    /// Extracts all course codes found in a string (e.g., "CS 301", "MATH 202").
    static func extractAllCourses(from text: String) -> [String] {
        guard let regex = ScheduleParser.courseRegex else { return [] }

        // Remove room if present so "Room 302", "Room 101", etc. are never mistaken for course codes
        var cleanedText = text
        if let room = extractRoom(from: text) {
            cleanedText = cleanedText.replacingOccurrences(of: room, with: " ", options: .caseInsensitive)
        }

        // Strip dates (e.g., "16 Nov 2026", "Nov 16, 2026", "16/11/2026", "2026-11-16")
        let monthWord = #"(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)"#
        let datePattern = #"\b(?:\d{1,2}(?:st|nd|rd|th)?\s+"# + monthWord + #"(?:,?\s*\d{2,4})?|"# + monthWord + #"\s+\d{1,2}(?:st|nd|rd|th)?(?:,?\s*\d{2,4})?|\d{1,2}[\/\-\.]\d{1,2}(?:[\/\-\.]\d{2,4})?|\d{4}[\/\-\.]\d{1,2}[\/\-\.]\d{1,2})\b"#
        if let dateRegex = try? NSRegularExpression(pattern: datePattern, options: .caseInsensitive) {
            cleanedText = dateRegex.stringByReplacingMatches(in: cleanedText, options: [], range: NSRange(cleanedText.startIndex..., in: cleanedText), withTemplate: " ")
        }

        let nsRange = NSRange(cleanedText.startIndex..., in: cleanedText)
        let matches = regex.matches(in: cleanedText, options: [], range: nsRange)
        var courses: [String] = []

        for match in matches {
            guard let range = Range(match.range, in: cleanedText) else { continue }
            let candidate = String(cleanedText[range])

            if range.upperBound < cleanedText.endIndex && cleanedText[range.upperBound] == ":" {
                continue
            }
            let prefix = candidate.prefix(while: { $0.isLetter }).uppercased()
            if ScheduleParser.courseStopWords.contains(prefix) {
                continue
            }
            let upper = candidate.uppercased()
            if !courses.contains(upper) {
                courses.append(upper)
            }
        }
        return courses
    }

    /// Cleans the subject title by removing course code, date, room, and session times.
    static func extractExamSubjectTitle(
        from text: String,
        course: String,
        room: String? = nil,
        sessionTime: String? = nil
    ) -> String {
        var cleaned = text

        // Remove course code
        if !course.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: course, with: "", options: .caseInsensitive)
        }
        // Remove room
        if let room = room, !room.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: room, with: "", options: .caseInsensitive)
        }
        // Remove session time
        if let session = sessionTime, !session.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: session, with: "", options: .caseInsensitive)
        }

        // Remove times like "10:00 AM", "02:00 PM", "10:00 to 01:00"
        let timeRegex = try? NSRegularExpression(
            pattern: #"\b\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)?(?:\s*(?:to|[-–])\s*\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)?)?\b"#,
            options: .caseInsensitive
        )
        cleaned = timeRegex?.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: " ") ?? cleaned

        // Remove day names (Monday, Tuesday, etc.)
        let dayRegex = try? NSRegularExpression(
            pattern: #"\b(?:Mon|Monday|Tue|Tuesday|Wed|Wednesday|Thu|Thursday|Fri|Friday|Sat|Saturday|Sun|Sunday)\b"#,
            options: .caseInsensitive
        )
        cleaned = dayRegex?.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: " ") ?? cleaned

        // Remove dates (Nov 16, 2026, 16/11/2026, etc.)
        let dateRegex = try? NSRegularExpression(
            pattern: #"\b(?:\d{1,2}(?:st|nd|rd|th)?\s+[A-Za-z]{3,12}(?:,?\s*\d{4})?|[A-Za-z]{3,12}\s+\d{1,2}(?:st|nd|rd|th)?(?:,?\s*\d{4})?|\d{1,2}[\/\-\.]\d{1,2}(?:[\/\-\.]\d{2,4})?)\b"#,
            options: .caseInsensitive
        )
        cleaned = dateRegex?.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: " ") ?? cleaned

        // Remove common table header labels if caught in text
        let labelsRegex = try? NSRegularExpression(
            pattern: #"\b(?:Course\s*Code|Subject\s*Title|Exam\s*Date|Date\s*&?\s*Time|Shift|Slot|Session|Venue|Room)\b"#,
            options: .caseInsensitive
        )
        cleaned = labelsRegex?.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: " ") ?? cleaned

        // Remove punctuation & separators
        cleaned = cleaned.replacingOccurrences(of: #"[|:\-_•*]+"#, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        var trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove trailing or leading prepositions
        for word in ["on", "at", "due", "by", "in", "for", "and", "&"] {
            if trimmed.lowercased().hasSuffix(" " + word) {
                trimmed = String(trimmed.dropLast(word.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if trimmed.lowercased().hasPrefix(word + " ") {
                trimmed = String(trimmed.dropFirst(word.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if trimmed.isEmpty {
            return course.isEmpty ? "Theory Examination" : "\(course) Examination"
        }
        if !trimmed.lowercased().contains("exam") && !trimmed.lowercased().contains("midterm") && !trimmed.lowercased().contains("final") {
            trimmed += " Exam"
        }
        return trimmed
    }

    /// Parses rows of text from an exam datesheet table into individual drafts, handling merged date cells and multi-subject rows.
    static func parseTimetable(
        rows: [TimetableRow],
        contextYear: Int?,
        explicitYear: Int?
    ) -> [ScannedAssignmentDraft] {
        var drafts: [ScannedAssignmentDraft] = []
        var activeDate: Date? = nil
        var activeSessionTime: String? = nil
        var activeDateIsConfident: Bool = (explicitYear != nil)
        var activeDateReason: String? = (explicitYear != nil) ? nil : "Year missing in datesheet — please confirm year"
        var activeRoom: String? = nil

        for row in rows {
            let line = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            // Skip header notice date (e.g. "Date of Notice: October 24, 2026")
            if SmartDateExtractor.isNoticeHeaderDateLine(line) {
                continue
            }

            // Check if this row contains a room
            let rowRoom = extractRoom(from: line)
            if let r = rowRoom {
                activeRoom = r
            }

            // Check if this row contains session time
            let timeInfo = SmartDateExtractor.extractTimeAndSession(from: line)
            if let t = timeInfo {
                activeSessionTime = t.sessionTime
            }

            // Check if this row contains a date
            let dateExtracted = SmartDateExtractor.extractDate(
                from: line,
                documentContextYear: contextYear,
                defaultHour: timeInfo?.hour ?? 10,
                defaultMinute: timeInfo?.minute ?? 0
            )

            if let d = dateExtracted {
                activeDate = d.date
                activeDateIsConfident = d.isConfident && (explicitYear != nil)
                activeDateReason = d.reason ?? ((explicitYear == nil) ? "Year missing in datesheet — please confirm year" : nil)
                if let session = d.sessionTime {
                    activeSessionTime = session
                }
            }

            // Check for courses in this row
            let courses = extractAllCourses(from: line)

            if !courses.isEmpty {
                // If there are multiple courses in this row, process each course
                for courseCode in courses {
                    let currentSession = timeInfo?.sessionTime ?? activeSessionTime
                    let currentRoom = rowRoom ?? activeRoom ?? ""

                    let subjectTitle = extractExamSubjectTitle(
                        from: line,
                        course: courseCode,
                        room: rowRoom ?? activeRoom,
                        sessionTime: currentSession
                    )

                    let effectiveDate = dateExtracted?.date ?? activeDate ?? ScheduleParser.defaultFallbackDate(hour: 10)
                    let isDateConfident = (dateExtracted != nil || activeDate != nil) && activeDateIsConfident
                    let dateReason = isDateConfident ? nil : (dateExtracted?.reason ?? activeDateReason ?? "Exam date unconfirmed in datesheet")

                    var notes = "Theory Examination"
                    if let s = currentSession {
                        notes = "Exam Session: \(s)"
                    }
                    if !currentRoom.isEmpty {
                        notes += " • Venue: \(currentRoom)"
                    }

                    let draft = ScannedAssignmentDraft(
                        title: subjectTitle,
                        course: courseCode,
                        dueDate: effectiveDate,
                        priority: .high,
                        notes: notes,
                        eventType: "exam",
                        sessionTime: currentSession,
                        room: currentRoom,
                        isSelected: true,
                        isConfidentDate: isDateConfident,
                        isConfidentTitle: !subjectTitle.isEmpty,
                        isConfidentTime: (currentSession != nil),
                        isAssumedTime: (currentSession == nil),
                        isYearAmbiguous: (explicitYear == nil),
                        rawText: line,
                        isDuplicate: false,
                        uncertaintyReason: dateReason
                    )
                    drafts.append(draft)
                }
            }
        }

        return drafts
    }
}

// MARK: - Smart Date Extractor

/// Helper for extracting and parsing dates, times, sessions, and document context.
struct SmartDateExtractor {
    static let monthMap: [String: Int] = [
        "jan": 1, "january": 1,
        "feb": 2, "february": 2,
        "mar": 3, "march": 3,
        "apr": 4, "april": 4,
        "may": 5,
        "jun": 6, "june": 6,
        "jul": 7, "july": 7,
        "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10,
        "nov": 11, "november": 11,
        "dec": 12, "december": 12
    ]

    private static let dateDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    }()

    /// Extracts explicit 4-digit academic session year or calendar year from document header.
    /// Returns nil if the year is truly absent or ambiguous.
    static func extractExplicitDocumentYear(from lines: [String]) -> Int? {
        // 1. Check header lines for academic sessions like "2026-27", "2026-2027", "2026/27"
        let sessionRegex = try? NSRegularExpression(pattern: #"\b(202[4-9]|203[0-9])\s*[-/]\s*(?:20)?(\d{2})\b"#)
        for line in lines.prefix(15) {
            let nsRange = NSRange(line.startIndex..., in: line)
            if let match = sessionRegex?.firstMatch(in: line, range: nsRange),
               let r1 = Range(match.range(at: 1), in: line),
               let y1 = Int(line[r1]) {
                return y1
            }
        }

        // 2. Check for explicit 4-digit years in header lines
        let yearRegex = try? NSRegularExpression(pattern: #"\b(202[4-9]|203[0-9])\b"#)
        for line in lines.prefix(15) {
            let nsRange = NSRange(line.startIndex..., in: line)
            if let match = yearRegex?.firstMatch(in: line, range: nsRange),
               let r1 = Range(match.range(at: 1), in: line),
               let y = Int(line[r1]) {
                return y
            }
        }

        return nil
    }

    /// Extracts the academic/calendar year from the document header, defaulting to current year.
    static func extractDocumentContextYear(from lines: [String]) -> Int? {
        extractExplicitDocumentYear(from: lines) ?? Calendar.current.component(.year, from: Date())
    }

    /// Checks if a line is a notice publication/issuance/reference line rather than an actionable deadline.
    static func isNoticeHeaderDateLine(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let headerPrefixes = [
            "date of notice", "notice date", "notice issued", "date of issue",
            "issue date", "ref:", "ref.", "ref no", "dated:", "published on",
            "printed on", "notification no"
        ]
        return headerPrefixes.contains { lower.contains($0) }
    }

    /// Checks if a date in notice is marked as TBD / tentative / unconfirmed.
    static func isTentativeOrTBD(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("tbd") ||
               lower.contains("to be decided") ||
               lower.contains("to be announced") ||
               lower.contains("tba") ||
               lower.contains("tentative") ||
               lower.contains("unconfirmed")
    }

    /// Extracts time or examination session slot (e.g., "10:00 AM - 01:00 PM" or "10:00 AM").
    static func extractTimeAndSession(from text: String) -> (hour: Int, minute: Int, sessionTime: String)? {
        // Pattern 1: Time range: 10:00 AM - 01:00 PM or 10:00 AM to 01:00 PM
        let rangePattern = #"\b(\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)?)\s*(?:to|[-–])\s*(\d{1,2}:\d{2}\s*(?:AM|PM|am|pm))\b"#
        if let regex = try? NSRegularExpression(pattern: rangePattern, options: .caseInsensitive) {
            let nsRange = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: nsRange),
               let r1 = Range(match.range(at: 1), in: text),
               let r2 = Range(match.range(at: 2), in: text) {
                let startStr = String(text[r1]).trimmingCharacters(in: .whitespaces)
                let endStr = String(text[r2]).trimmingCharacters(in: .whitespaces)
                let fullSession = "\(startStr) - \(endStr)"
                let (h, m) = parseHourAndMinute(from: startStr)
                return (h, m, fullSession)
            }
        }

        // Pattern 2: Single time: "10:00 AM", "02:00 PM", "11:59 PM", "14:00"
        let singlePattern = #"\b(?:at\s+)?(\d{1,2}:\d{2})\s*(AM|PM|am|pm)?\b"#
        if let regex = try? NSRegularExpression(pattern: singlePattern, options: .caseInsensitive) {
            let nsRange = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: nsRange),
               let r1 = Range(match.range(at: 1), in: text) {
                let timeDigits = String(text[r1])
                var meridiem = ""
                if match.range(at: 2).location != NSNotFound, let r2 = Range(match.range(at: 2), in: text) {
                    meridiem = String(text[r2]).uppercased()
                }
                let sessionStr = meridiem.isEmpty ? timeDigits : "\(timeDigits) \(meridiem)"
                let (h, m) = parseHourAndMinute(from: sessionStr)
                return (h, m, sessionStr)
            }
        }

        // Pattern 3: Named sessions
        let lower = text.lowercased()
        if lower.contains("morning session") {
            return (10, 0, "Morning Session (10:00 AM - 01:00 PM)")
        } else if lower.contains("evening session") || lower.contains("afternoon session") {
            return (14, 0, "Evening Session (02:00 PM - 05:00 PM)")
        }

        return nil
    }

    private static func parseHourAndMinute(from timeString: String) -> (hour: Int, minute: Int) {
        let parts = timeString.components(separatedBy: ":")
        guard parts.count >= 2, let rawHour = Int(parts[0].trimmingCharacters(in: .letters).trimmingCharacters(in: .whitespaces)) else {
            return (17, 0)
        }

        let minutePart = parts[1].trimmingCharacters(in: .whitespaces)
        let minDigits = minutePart.prefix(2)
        let minute = Int(minDigits) ?? 0

        var hour = rawHour
        let upper = timeString.uppercased()
        if upper.contains("PM") && hour < 12 {
            hour += 12
        } else if upper.contains("AM") && hour == 12 {
            hour = 0
        }
        return (hour, minute)
    }

    /// Extracts date, confidence, session time, and matched text range from a line of text.
    static func extractDate(
        from text: String,
        documentContextYear: Int?,
        defaultHour: Int = 17,
        defaultMinute: Int = 0
    ) -> (date: Date, isConfident: Bool, sessionTime: String?, range: NSRange?, reason: String?)? {
        let timeInfo = extractTimeAndSession(from: text)
        let hour = timeInfo?.hour ?? defaultHour
        let minute = timeInfo?.minute ?? defaultMinute
        let sessionTime = timeInfo?.sessionTime

        // If line is explicitly TBD
        if isTentativeOrTBD(text) {
            return nil
        }

        let calendar = Calendar.current
        let currentYear = documentContextYear ?? calendar.component(.year, from: Date())

        // MARK: 1. Word-based Month formats
        // Handles: "November 16, 2026", "16 November 2026", "16th Nov 2026", "Monday, 16 November 2026", "Mon, Nov 16"
        let wordMonthPattern = #"\b(?:(?:Mon|Monday|Tue|Tuesday|Wed|Wednesday|Thu|Thursday|Fri|Friday|Sat|Saturday|Sun|Sunday)[a-z]*,?\s+)?(?:on\s+)?(?:(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]{3,12})(?:,?\s*(\d{4}))?|([A-Za-z]{3,12})\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s*(\d{4}))?)\b"#
        if let regex = try? NSRegularExpression(pattern: wordMonthPattern, options: .caseInsensitive) {
            let nsRange = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: nsRange) {
                var day: Int?
                var monthStr: String?
                var year: Int?

                if match.range(at: 1).location != NSNotFound, let r1 = Range(match.range(at: 1), in: text),
                   match.range(at: 2).location != NSNotFound, let r2 = Range(match.range(at: 2), in: text) {
                    day = Int(text[r1])
                    monthStr = String(text[r2]).lowercased()
                    if match.range(at: 3).location != NSNotFound, let r3 = Range(match.range(at: 3), in: text) {
                        year = Int(text[r3])
                    }
                } else if match.range(at: 4).location != NSNotFound, let r4 = Range(match.range(at: 4), in: text),
                          match.range(at: 5).location != NSNotFound, let r5 = Range(match.range(at: 5), in: text) {
                    monthStr = String(text[r4]).lowercased()
                    day = Int(text[r5])
                    if match.range(at: 6).location != NSNotFound, let r6 = Range(match.range(at: 6), in: text) {
                        year = Int(text[r6])
                    }
                }

                if let d = day, let mStr = monthStr, let m = monthMap[mStr] {
                    let hasExplicitYear = (year != nil)
                    let finalYear = year ?? currentYear
                    let isConfident = hasExplicitYear || (documentContextYear != nil)
                    let reason = isConfident ? nil : "Year inferred from context - please verify deadline"

                    var comps = DateComponents()
                    comps.year = finalYear
                    comps.month = m
                    comps.day = d
                    comps.hour = hour
                    comps.minute = minute

                    if let constructedDate = calendar.date(from: comps) {
                        return (constructedDate, isConfident, sessionTime, match.range, reason)
                    }
                }
            }
        }

        // MARK: 2. Numeric DD/MM/YYYY, DD-MM-YYYY, DD.MM.YYYY
        let numericPattern = #"\b(\d{1,2})[\/\-\.](\d{1,2})[\/\-\.](\d{2,4})\b"#
        if let regex = try? NSRegularExpression(pattern: numericPattern) {
            let nsRange = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: nsRange),
               let r1 = Range(match.range(at: 1), in: text),
               let r2 = Range(match.range(at: 2), in: text),
               let r3 = Range(match.range(at: 3), in: text) {
                let n1 = Int(text[r1]) ?? 0
                let n2 = Int(text[r2]) ?? 0
                var y = Int(text[r3]) ?? currentYear
                if y < 100 { y += 2000 }

                var day = n1
                var month = n2
                var isConfident = true
                var reason: String? = nil

                if n1 > 12 && n2 <= 12 {
                    // Confident DD/MM/YYYY
                    day = n1
                    month = n2
                } else if n2 > 12 && n1 <= 12 {
                    // Confident MM/DD/YYYY
                    day = n2
                    month = n1
                } else if n1 <= 12 && n2 <= 12 {
                    // Ambiguous numeric date (e.g. 04/05/2026)
                    // Treat standard academic as DD/MM/YYYY, but flag for confirmation!
                    day = n1
                    month = n2
                    isConfident = false
                    reason = "Ambiguous date format (DD/MM vs MM/DD) - please confirm"
                }

                var comps = DateComponents()
                comps.year = y
                comps.month = month
                comps.day = day
                comps.hour = hour
                comps.minute = minute

                if let constructedDate = calendar.date(from: comps) {
                    return (constructedDate, isConfident, sessionTime, match.range, reason)
                }
            }
        }

        // MARK: 3. Numeric Yearless DD/MM or DD-MM (e.g. "16/11" or "24-11")
        let yearlessNumericPattern = #"(?<!\d[:\/\-])\b(\d{1,2})[\/\-](\d{1,2})\b(?!\s*[:\/\-]\d)"#
        if let regex = try? NSRegularExpression(pattern: yearlessNumericPattern) {
            let nsRange = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: nsRange),
               let r1 = Range(match.range(at: 1), in: text),
               let r2 = Range(match.range(at: 2), in: text) {
                let n1 = Int(text[r1]) ?? 0
                let n2 = Int(text[r2]) ?? 0

                if (n1 > 0 && n1 <= 31 && n2 > 0 && n2 <= 12) || (n2 > 0 && n2 <= 31 && n1 > 0 && n1 <= 12) {
                    let day = (n1 > 12) ? n1 : (n2 > 12 ? n2 : n1)
                    let month = (n1 > 12) ? n2 : (n2 > 12 ? n1 : n2)
                    let isConfident = (n1 > 12 || n2 > 12) && (documentContextYear != nil)
                    let reason = isConfident ? nil : "Yearless date - please confirm year and format"

                    var comps = DateComponents()
                    comps.year = currentYear
                    comps.month = month
                    comps.day = day
                    comps.hour = hour
                    comps.minute = minute

                    if let constructedDate = calendar.date(from: comps) {
                        return (constructedDate, isConfident, sessionTime, match.range, reason)
                    }
                }
            }
        }

        // MARK: 4. ISO YYYY-MM-DD
        let isoPattern = #"\b(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})\b"#
        if let regex = try? NSRegularExpression(pattern: isoPattern) {
            let nsRange = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: nsRange),
               let r1 = Range(match.range(at: 1), in: text),
               let r2 = Range(match.range(at: 2), in: text),
               let r3 = Range(match.range(at: 3), in: text) {
                let y = Int(text[r1]) ?? currentYear
                let m = Int(text[r2]) ?? 1
                let d = Int(text[r3]) ?? 1

                var comps = DateComponents()
                comps.year = y
                comps.month = m
                comps.day = d
                comps.hour = hour
                comps.minute = minute

                if let constructedDate = calendar.date(from: comps) {
                    return (constructedDate, true, sessionTime, match.range, nil)
                }
            }
        }

        // MARK: 5. NSDataDetector Fallback
        if let detector = dateDetector {
            let nsRange = NSRange(text.startIndex..., in: text)
            let matches = detector.matches(in: text, options: [], range: nsRange)
            for match in matches {
                guard let foundDate = match.date, let matchRange = Range(match.range, in: text) else { continue }
                let matchedText = String(text[matchRange])
                let lower = matchedText.lowercased()

                // Check if the matched substring contains an explicit month name
                let hasMonthName = monthMap.keys.contains(where: { lower.contains($0) })
                // Or numeric date format with slash/dash between digits (e.g. "16/11", "16-11", "2026-11")
                let hasNumericDatePattern = (try? NSRegularExpression(pattern: #"\b\d{1,4}[\/\-\.]\d{1,2}\b"#))?.firstMatch(in: matchedText, range: NSRange(matchedText.startIndex..., in: matchedText)) != nil

                guard hasMonthName || hasNumericDatePattern else { continue }

                var comps = calendar.dateComponents([.year, .month, .day], from: foundDate)
                let dateYear = comps.year ?? currentYear
                if dateYear < currentYear {
                    comps.year = currentYear
                }
                comps.hour = hour
                comps.minute = minute

                let finalDate = calendar.date(from: comps) ?? foundDate
                return (finalDate, true, sessionTime, match.range, nil)
            }
        }

        return nil
    }
}

// MARK: - Intelligent Schedule Parser

/// Intelligent offline parser that classifies documents and extracts structured assignment or exam drafts.
struct ScheduleParser {
    // Regex for course codes like "CS 101", "MATH-202", "CS 301", "ENG102A"
    static let courseRegex = try? NSRegularExpression(
        pattern: #"\b([A-Z]{2,5}\s?[-]?\s?\d{2,4}[A-Z]?)\b"#,
        options: .caseInsensitive
    )

    // Academic keywords indicating assignments or exams
    private static let academicKeywords = [
        "assignment", "homework", "midterm", "exam", "quiz", "test",
        "project", "paper", "presentation", "lab", "report", "pset",
        "problem set", "due", "deadline", "submission", "datesheet", "theory"
    ]

    // Prepositions, common words, and room/structure keywords that shouldn't be mistaken for course codes
    static let courseStopWords: Set<String> = [
        "AT", "ON", "IN", "TO", "BY", "PM", "AM", "NO", "OF", "OR", "IF", "IS",
        "DUE", "FOR", "THE", "ALL", "AND", "PER", "VIA",
        "ROOM", "RM", "HALL", "LAB", "AUDI", "AUDITORIUM", "VENUE", "LH", "LT",
        "SEC", "SECTION", "BATCH", "SEM", "SEMESTER", "YEAR", "DATE", "TIME",
        "SHIFT", "SLOT", "DAY", "PAGE", "REF", "CODE", "TOTAL",
        "JAN", "JANUARY", "FEB", "FEBRUARY", "MAR", "MARCH", "APR", "APRIL",
        "MAY", "JUN", "JUNE", "JUL", "JULY", "AUG", "AUGUST", "SEP", "SEPT",
        "SEPTEMBER", "OCT", "OCTOBER", "NOV", "NOVEMBER", "DEC", "DECEMBER",
        "MON", "MONDAY", "TUE", "TUESDAY", "WED", "WEDNESDAY", "THU", "THURSDAY",
        "FRI", "FRIDAY", "SAT", "SATURDAY", "SUN", "SUNDAY"
    ]

    /// Classifies the overall document type based on header signals and vocabulary.
    static func classifyDocument(lines: [String]) -> ScannedDocumentKind {
        let joined = lines.joined(separator: " ").lowercased()
        if joined.contains("datesheet") ||
           joined.contains("date sheet") ||
           joined.contains("theory exam") ||
           joined.contains("controller of examinations") ||
           (joined.contains("examination") && (joined.contains("schedule") || joined.contains("odd semester") || joined.contains("even semester"))) {
            return .examDatesheet
        }

        if joined.contains("academic coursework") ||
           joined.contains("assignment notice") ||
           joined.contains("homework") ||
           joined.contains("problem set") ||
           joined.contains("lab assignment") ||
           joined.contains("research paper") ||
           joined.contains("term paper") ||
           lines.contains(where: { $0.lowercased().hasPrefix("assignment:") }) {
            return .assignmentNotice
        }

        return .generalNotice
    }

    /// Primary 2D spatial entry point: parses OCR text blocks into structured drafts with duplicate detection.
    static func parse(
        blocks: [OcrTextBlock],
        existingAssignments: [Assignment] = [],
        qualityReport: OcrQualityReport? = nil
    ) -> ScheduleParseResult {
        let rows = TimetableParser.groupBlocksIntoRows(blocks)
        let lines = rows.map { $0.text }
        let trimmedLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        guard !trimmedLines.isEmpty else {
            return ScheduleParseResult(
                drafts: [],
                kind: .generalNotice,
                detectedYear: nil,
                isYearAmbiguous: false,
                qualityReport: qualityReport
            )
        }

        let documentKind = classifyDocument(lines: trimmedLines)
        let explicitYear = SmartDateExtractor.extractExplicitDocumentYear(from: trimmedLines)
        let contextYear = explicitYear ?? Calendar.current.component(.year, from: Date())
        let isYearAmbiguous = (explicitYear == nil)

        var drafts: [ScannedAssignmentDraft] = []

        switch documentKind {
        case .examDatesheet:
            drafts = TimetableParser.parseTimetable(rows: rows, contextYear: contextYear, explicitYear: explicitYear)
            if drafts.isEmpty {
                // Fallback to legacy line-by-line if table parser found no courses
                drafts = parseExamDatesheet(lines: trimmedLines, contextYear: contextYear)
            }
        case .assignmentNotice:
            drafts = parseAssignmentNotice(lines: trimmedLines, contextYear: contextYear)
        case .generalNotice:
            drafts = parseGeneralNotice(lines: trimmedLines, contextYear: contextYear)
        }

        // Apply deduplication against existing database assignments
        for idx in drafts.indices {
            if isDuplicate(draft: drafts[idx], existing: existingAssignments) {
                drafts[idx].isDuplicate = true
                drafts[idx].isSelected = false // Default unchecked to prevent duplicates
            }
            if isYearAmbiguous {
                drafts[idx].isYearAmbiguous = true
            }
        }

        return ScheduleParseResult(
            drafts: drafts,
            kind: documentKind,
            detectedYear: explicitYear,
            isYearAmbiguous: isYearAmbiguous,
            qualityReport: qualityReport
        )
    }

    /// Backward-compatible line-based entry point.
    static func parse(lines: [String], existingAssignments: [Assignment] = []) -> [ScannedAssignmentDraft] {
        let trimmedLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !trimmedLines.isEmpty else { return [] }

        // Convert strings to simulated OCR text blocks with sequential vertical positions
        let blocks = trimmedLines.enumerated().map { idx, line in
            let y = CGFloat(idx) * 0.05
            return OcrTextBlock(
                text: line,
                boundingBox: CGRect(x: 0.1, y: y, width: 0.8, height: 0.04),
                confidence: 1.0
            )
        }

        let result = parse(blocks: blocks, existingAssignments: existingAssignments)
        return result.drafts
    }

    // MARK: - 1. Examination Datesheet Parser (Line-by-line Fallback)

    private static func parseExamDatesheet(lines: [String], contextYear: Int?) -> [ScannedAssignmentDraft] {
        var drafts: [ScannedAssignmentDraft] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Skip notice issuance date headers
            if SmartDateExtractor.isNoticeHeaderDateLine(line) {
                i += 1
                continue
            }

            // Check if line mentions a course code
            if let courseCode = extractCourse(from: line) {
                let subjectLine = line
                var combinedRawText = line
                let rowRoom = TimetableParser.extractRoom(from: line) ?? ""

                // Check if date is on this line or the immediate next line
                var dateExtraction = SmartDateExtractor.extractDate(
                    from: line,
                    documentContextYear: contextYear,
                    defaultHour: 10,
                    defaultMinute: 0
                )

                if dateExtraction == nil && (i + 1) < lines.count {
                    let nextLine = lines[i + 1]
                    if !SmartDateExtractor.isNoticeHeaderDateLine(nextLine),
                       let nextDate = SmartDateExtractor.extractDate(from: nextLine, documentContextYear: contextYear, defaultHour: 10, defaultMinute: 0) {
                        dateExtraction = nextDate
                        combinedRawText = "\(line) • \(nextLine)"
                        i += 1 // Advance consumed line
                    }
                }

                if let extracted = dateExtraction {
                    let subjectTitle = extractExamSubjectTitle(from: subjectLine, course: courseCode)
                    let fullTitle = subjectTitle.isEmpty ? "\(courseCode) Examination" : subjectTitle

                    let draft = ScannedAssignmentDraft(
                        title: fullTitle,
                        course: courseCode,
                        dueDate: extracted.date,
                        priority: .high,
                        notes: extracted.sessionTime.map { "Exam Session: \($0)" } ?? "Theory Examination",
                        eventType: "exam",
                        sessionTime: extracted.sessionTime,
                        room: rowRoom,
                        isSelected: true,
                        isConfidentDate: extracted.isConfident,
                        isConfidentTitle: !subjectTitle.isEmpty,
                        isConfidentTime: (extracted.sessionTime != nil),
                        isAssumedTime: (extracted.sessionTime == nil),
                        rawText: combinedRawText,
                        uncertaintyReason: extracted.reason
                    )
                    drafts.append(draft)
                } else if containsAcademicKeyword(line) {
                    let subjectTitle = extractExamSubjectTitle(from: line, course: courseCode)
                    let fallbackDate = defaultFallbackDate(hour: 10)

                    let draft = ScannedAssignmentDraft(
                        title: subjectTitle.isEmpty ? "\(courseCode) Exam" : subjectTitle,
                        course: courseCode,
                        dueDate: fallbackDate,
                        priority: .high,
                        notes: "Scanned from datesheet: \"\(line)\"",
                        eventType: "exam",
                        sessionTime: nil,
                        room: rowRoom,
                        isSelected: true,
                        isConfidentDate: false,
                        isConfidentTitle: !subjectTitle.isEmpty,
                        isConfidentTime: false,
                        isAssumedTime: true,
                        rawText: line,
                        uncertaintyReason: "Exam date unconfirmed in datesheet"
                    )
                    drafts.append(draft)
                }
            }

            i += 1
        }

        return drafts
    }

    // MARK: - 2. Academic Assignment Notice Parser

    private static func parseAssignmentNotice(lines: [String], contextYear: Int?) -> [ScannedAssignmentDraft] {
        var detectedCourse = ""
        var assignmentTitle = ""
        var deadlineDate: Date? = nil
        var isConfidentDate = true
        var uncertaintyReason: String? = nil
        var priority: Priority = .medium
        var notesAccumulator: [String] = []
        var rawTextAccumulator: [String] = []

        for line in lines {
            if SmartDateExtractor.isNoticeHeaderDateLine(line) {
                continue
            }

            let lower = line.lowercased()

            // 1. Course Code & Name
            if detectedCourse.isEmpty, let code = extractCourse(from: line) {
                detectedCourse = code
            }

            // 2. Assignment Topic / Title
            if assignmentTitle.isEmpty {
                if lower.contains("assignment:") || lower.contains("topic:") || lower.contains("title:") {
                    let parts = line.components(separatedBy: ":")
                    if parts.count >= 2 {
                        let candidate = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                        if !candidate.isEmpty && !candidate.lowercased().contains("deadline") {
                            assignmentTitle = candidate
                        }
                    }
                }
            }

            // 3. True Submission Deadline
            if deadlineDate == nil {
                let isRegistration = lower.contains("registration deadline") ||
                                     lower.contains("registration closes") ||
                                     lower.contains("register by")

                let isDeadlineLine = !isRegistration && (
                    lower.contains("submission deadline") ||
                    lower.contains("due date") ||
                    lower.contains("submission date") ||
                    lower.contains("submit by") ||
                    lower.contains("due on") ||
                    (lower.contains("deadline") && !isRegistration)
                )

                if isDeadlineLine {
                    if SmartDateExtractor.isTentativeOrTBD(line) {
                        deadlineDate = defaultFallbackDate()
                        isConfidentDate = false
                        uncertaintyReason = "Submission deadline is TBD in notice - please set manually"
                    } else if let extracted = SmartDateExtractor.extractDate(from: line, documentContextYear: contextYear) {
                        deadlineDate = extracted.date
                        isConfidentDate = extracted.isConfident
                        uncertaintyReason = extracted.reason
                    }
                }
            }

            // 4. Priority Inference
            if lower.contains("high priority") || lower.contains("penalty") || lower.contains("mandatory") {
                priority = .high
            } else if lower.contains("low priority") || lower.contains("optional") {
                priority = .low
            }

            // 5. Notes & instructions
            if lower.contains("submission mode:") || lower.contains("instructions:") || lower.contains("moodle") {
                notesAccumulator.append(line)
            }
            rawTextAccumulator.append(line)
        }

        // Fallbacks if not explicitly tagged
        if assignmentTitle.isEmpty {
            for line in lines {
                if !SmartDateExtractor.isNoticeHeaderDateLine(line),
                   line.lowercased().contains("assignment") && !line.lowercased().contains("notice") && !line.lowercased().contains("deadline") {
                    assignmentTitle = line
                    break
                }
            }
        }

        let finalTitle = assignmentTitle.isEmpty ? (detectedCourse.isEmpty ? "Academic Coursework Assignment" : "\(detectedCourse) Coursework Assignment") : assignmentTitle
        let finalDueDate = deadlineDate ?? defaultFallbackDate()
        if deadlineDate == nil {
            isConfidentDate = false
            if uncertaintyReason == nil {
                uncertaintyReason = "No submission deadline found in notice - please verify"
            }
        }

        let draft = ScannedAssignmentDraft(
            title: finalTitle,
            course: detectedCourse,
            dueDate: finalDueDate,
            priority: priority,
            notes: notesAccumulator.joined(separator: "\n"),
            eventType: "assignment",
            sessionTime: nil,
            room: "",
            isSelected: true,
            isConfidentDate: isConfidentDate,
            isConfidentTitle: !assignmentTitle.isEmpty,
            isConfidentTime: true,
            isAssumedTime: false,
            rawText: rawTextAccumulator.prefix(6).joined(separator: " • "),
            uncertaintyReason: uncertaintyReason
        )

        return [draft]
    }

    // MARK: - 3. General Academic Notice / Multiple Dates Parser

    private static func parseGeneralNotice(lines: [String], contextYear: Int?) -> [ScannedAssignmentDraft] {
        var drafts: [ScannedAssignmentDraft] = []
        var currentCourse = ""

        // Check for course code in the first few lines
        for line in lines.prefix(5) {
            if let c = extractCourse(from: line) {
                currentCourse = c
                break
            }
        }

        for line in lines {
            if SmartDateExtractor.isNoticeHeaderDateLine(line) {
                continue
            }

            let lower = line.lowercased()

            if let c = extractCourse(from: line) {
                currentCourse = c
            }

            let isActionable = lower.contains("deadline") ||
                               lower.contains("due date") ||
                               lower.contains("submission") ||
                               lower.contains("registration deadline") ||
                               lower.contains("exam") ||
                               lower.contains("midterm")

            if isActionable {
                let isTBD = SmartDateExtractor.isTentativeOrTBD(line)
                let extracted = isTBD ? nil : SmartDateExtractor.extractDate(from: line, documentContextYear: contextYear)
                let dueDate = extracted?.date ?? defaultFallbackDate()
                let isConfidentDate = !isTBD && (extracted != nil) && (extracted?.isConfident ?? false)
                let isExam = lower.contains("exam") || lower.contains("datesheet")
                let reason = isTBD ? "Deadline is tentative / TBD in notice - please verify deadline" : (extracted?.reason ?? (isConfidentDate ? nil : "Please confirm deadline"))

                let (cleanTitle, isConfidentTitle) = extractTitle(from: line, course: currentCourse, dateRange: extracted?.range)
                let priority = inferPriority(from: line)
                let rowRoom = TimetableParser.extractRoom(from: line) ?? ""

                let draft = ScannedAssignmentDraft(
                    title: cleanTitle.isEmpty ? "Academic Deadline" : cleanTitle,
                    course: currentCourse,
                    dueDate: dueDate,
                    priority: priority,
                    notes: "Scanned notice: \"\(line)\"",
                    eventType: isExam ? "exam" : "assignment",
                    sessionTime: extracted?.sessionTime,
                    room: rowRoom,
                    isSelected: true,
                    isConfidentDate: isConfidentDate,
                    isConfidentTitle: isConfidentTitle && !cleanTitle.isEmpty,
                    isConfidentTime: (extracted?.sessionTime != nil || !isExam),
                    isAssumedTime: (isExam && extracted?.sessionTime == nil),
                    rawText: line,
                    uncertaintyReason: reason
                )
                drafts.append(draft)
            }
        }

        return drafts
    }

    // MARK: - Deduplication & Comparison Helpers

    /// Checks whether an extracted draft matches an existing assignment in the user's database.
    static func isDuplicate(draft: ScannedAssignmentDraft, existing: [Assignment]) -> Bool {
        existing.contains { item in
            let sameCourse = !draft.course.isEmpty &&
                             !item.course.isEmpty &&
                             item.course.localizedCaseInsensitiveCompare(draft.course) == .orderedSame

            let closeDates = abs(item.dueDate.timeIntervalSince(draft.dueDate)) < (24 * 3600)

            // If same course and on the exact same day -> duplicate!
            if sameCourse && closeDates {
                return true
            }

            // If exact matching title
            let exactTitleMatch = item.title.localizedCaseInsensitiveCompare(draft.title) == .orderedSame

            // If same course and title overlap
            let titleOverlap = item.title.localizedCaseInsensitiveContains(draft.title) ||
                               draft.title.localizedCaseInsensitiveContains(item.title)

            // Shared subject words (e.g. "Operating Systems" in both titles)
            let itemWords = Set(item.title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 4 && !["exam", "midterm", "final", "test", "assignment"].contains($0) })
            let draftWords = Set(draft.title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 4 && !["exam", "midterm", "final", "test", "assignment"].contains($0) })
            let hasSubjectWordMatch = !itemWords.isDisjoint(with: draftWords)

            if exactTitleMatch && (sameCourse || closeDates) {
                return true
            }

            if (sameCourse || hasSubjectWordMatch) && closeDates {
                return true
            }

            if sameCourse && (titleOverlap || hasSubjectWordMatch) {
                return true
            }

            return false
        }
    }

    // MARK: - Helper Methods

    static func extractCourse(from text: String) -> String? {
        guard let regex = courseRegex else { return nil }

        var cleanedText = text
        if let room = TimetableParser.extractRoom(from: text) {
            cleanedText = cleanedText.replacingOccurrences(of: room, with: " ", options: .caseInsensitive)
        }
        let monthWord = #"(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)"#
        let datePattern = #"\b(?:\d{1,2}(?:st|nd|rd|th)?\s+"# + monthWord + #"(?:,?\s*\d{2,4})?|"# + monthWord + #"\s+\d{1,2}(?:st|nd|rd|th)?(?:,?\s*\d{2,4})?|\d{1,2}[\/\-\.]\d{1,2}(?:[\/\-\.]\d{2,4})?|\d{4}[\/\-\.]\d{1,2}[\/\-\.]\d{1,2})\b"#
        if let dateRegex = try? NSRegularExpression(pattern: datePattern, options: .caseInsensitive) {
            cleanedText = dateRegex.stringByReplacingMatches(in: cleanedText, options: [], range: NSRange(cleanedText.startIndex..., in: cleanedText), withTemplate: " ")
        }

        let nsRange = NSRange(cleanedText.startIndex..., in: cleanedText)
        let matches = regex.matches(in: cleanedText, options: [], range: nsRange)

        for match in matches {
            guard let range = Range(match.range, in: cleanedText) else { continue }
            let candidate = String(cleanedText[range])

            if range.upperBound < cleanedText.endIndex && cleanedText[range.upperBound] == ":" {
                continue
            }

            let prefix = candidate.prefix(while: { $0.isLetter }).uppercased()
            if courseStopWords.contains(prefix) {
                continue
            }

            return candidate.uppercased()
        }
        return nil
    }

    private static func containsAcademicKeyword(_ text: String) -> Bool {
        let lower = text.lowercased()
        return academicKeywords.contains { lower.contains($0) }
    }

    private static func extractExamSubjectTitle(from text: String, course: String) -> String {
        TimetableParser.extractExamSubjectTitle(from: text, course: course)
    }

    private static func extractTitle(from text: String, course: String, dateRange: NSRange?) -> (title: String, isConfident: Bool) {
        var cleaned = text

        if let dRange = dateRange, let swiftRange = Range(dRange, in: text) {
            cleaned.removeSubrange(swiftRange)
        }

        if !course.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: course, with: "", options: .caseInsensitive)
        }

        var trimmed = cleaned
            .replacingOccurrences(of: #"[|:\-_]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for preposition in [" on", " at", " due", " by", " in", " for"] {
            if trimmed.lowercased().hasSuffix(preposition) {
                trimmed = String(trimmed.dropLast(preposition.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if trimmed.isEmpty {
            return ("Scheduled Deadline", false)
        }

        let isConfident = trimmed.count >= 4 && containsAcademicKeyword(text)
        return (trimmed, isConfident)
    }

    private static func inferPriority(from text: String) -> Priority {
        let lower = text.lowercased()
        if lower.contains("exam") || lower.contains("final") || lower.contains("midterm") || lower.contains("test") || lower.contains("high priority") {
            return .high
        } else if lower.contains("quiz") || lower.contains("project") || lower.contains("paper") {
            return .medium
        } else {
            return .low
        }
    }

    static func defaultFallbackDate(hour: Int = 17) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.day = (components.day ?? 0) + 1
        components.hour = hour
        components.minute = 0
        return calendar.date(from: components) ?? Date()
    }
}
