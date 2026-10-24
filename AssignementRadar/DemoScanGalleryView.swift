//
//  DemoScanGalleryView.swift
//  AssignementRadar
//
//  Created for Assignment Radar Built-in Scan Demo Gallery.
//

import SwiftUI
import UIKit

// MARK: - Demo Document Model

struct DemoDocument: Identifiable {
    let id: String
    let title: String
    let category: String
    let summary: String
    let highlights: [String]
    let badgeText: String
    let getImage: () -> UIImage
}

// MARK: - Document Image Generator (100% Offline & High-Resolution)

enum DemoDocumentGenerator {
    private static var cachedExamDatesheet: UIImage?
    private static var cachedAssignmentNotice: UIImage?
    private static var cachedEventNotice: UIImage?
    private static var cachedUncertainNotice: UIImage?

    // MARK: - 1. Exam Datesheet
    static func renderExamDatesheet() -> UIImage {
        if let cached = cachedExamDatesheet { return cached }

        let size = CGSize(width: 1200, height: 1600)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            // Clean Paper Background
            UIColor(red: 0.98, green: 0.98, blue: 0.97, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Outer Frame
            let borderRect = CGRect(x: 40, y: 40, width: 1120, height: 1520)
            let borderPath = UIBezierPath(rect: borderRect)
            borderPath.lineWidth = 4
            UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0).setStroke()
            borderPath.stroke()

            // Header Box
            let headerRect = CGRect(x: 40, y: 40, width: 1120, height: 260)
            UIColor(red: 0.92, green: 0.94, blue: 0.97, alpha: 1.0).setFill()
            ctx.fill(headerRect)
            let linePath = UIBezierPath()
            linePath.move(to: CGPoint(x: 40, y: 300))
            linePath.addLine(to: CGPoint(x: 1160, y: 300))
            linePath.lineWidth = 2
            UIColor.darkGray.setStroke()
            linePath.stroke()

            let centerStyle = NSMutableParagraphStyle()
            centerStyle.alignment = .center

            let instAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 34),
                .foregroundColor: UIColor.black,
                .paragraphStyle: centerStyle
            ]
            ("KIET GROUP OF INSTITUTIONS" as NSString).draw(in: CGRect(x: 60, y: 65, width: 1080, height: 45), withAttributes: instAttrs)

            let deptAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .semibold),
                .foregroundColor: UIColor(red: 0.2, green: 0.2, blue: 0.3, alpha: 1.0),
                .paragraphStyle: centerStyle
            ]
            ("OFFICE OF THE CONTROLLER OF EXAMINATIONS" as NSString).draw(in: CGRect(x: 60, y: 115, width: 1080, height: 35), withAttributes: deptAttrs)

            let noticeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 26),
                .foregroundColor: UIColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1.0),
                .paragraphStyle: centerStyle
            ]
            ("END SEMESTER THEORY EXAMINATION DATESHEET — ODD SEMESTER 2026-27" as NSString).draw(in: CGRect(x: 60, y: 160, width: 1080, height: 40), withAttributes: noticeAttrs)

            // DEMO NOTICE Stamp
            let demoStampAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor(red: 0.8, green: 0.3, blue: 0.0, alpha: 1.0),
                .paragraphStyle: centerStyle
            ]
            ("★ OFFICIAL DEMO DOCUMENT — FOR OCR TEXT RECOGNITION TESTING ★" as NSString).draw(in: CGRect(x: 60, y: 220, width: 1080, height: 30), withAttributes: demoStampAttrs)

            // Date & Ref
            let bodyStyle = NSMutableParagraphStyle()
            bodyStyle.alignment = .left

            let refAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .medium),
                .foregroundColor: UIColor.darkGray,
                .paragraphStyle: bodyStyle
            ]
            ("Ref: KIET/COE/EXAM/2026/104" as NSString).draw(in: CGRect(x: 80, y: 325, width: 500, height: 30), withAttributes: refAttrs)
            ("Date of Notice: October 24, 2026" as NSString).draw(in: CGRect(x: 750, y: 325, width: 350, height: 30), withAttributes: refAttrs)

            let introText = "All enrolled B.Tech (Computer Science & Information Technology) students are hereby informed of the theory examination datesheet as detailed below:"
            let introAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22),
                .foregroundColor: UIColor.black,
                .paragraphStyle: bodyStyle
            ]
            (introText as NSString).draw(in: CGRect(x: 80, y: 375, width: 1040, height: 70), withAttributes: introAttrs)

            // Table Header Box
            let tableHeaderRect = CGRect(x: 80, y: 460, width: 1040, height: 50)
            UIColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1.0).setFill()
            ctx.fill(tableHeaderRect)

            let tableHeadAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.white,
                .paragraphStyle: bodyStyle
            ]
            ("  Course Code & Subject Title" as NSString).draw(in: CGRect(x: 90, y: 472, width: 500, height: 35), withAttributes: tableHeadAttrs)
            ("Exam Date & Time" as NSString).draw(in: CGRect(x: 680, y: 472, width: 420, height: 35), withAttributes: tableHeadAttrs)

            // Schedule Rows
            let scheduleItems: [(code: String, name: String, date: String)] = [
                ("CS 301", "Operating Systems", "Midterm Exam on November 16, 2026 at 10:00 AM"),
                ("CS 302", "Design & Analysis of Algorithms", "Final Exam on November 19, 2026 at 02:00 PM"),
                ("CS 303", "Database Management Systems", "Midterm Exam on November 24, 2026 at 10:00 AM"),
                ("CS 304", "Computer Networks & Security", "Final Exam on November 28, 2026 at 02:00 PM")
            ]

            var currentY: CGFloat = 525
            for (idx, item) in scheduleItems.enumerated() {
                let rowRect = CGRect(x: 80, y: currentY, width: 1040, height: 110)
                if idx % 2 == 1 {
                    UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1.0).setFill()
                    ctx.fill(rowRect)
                }

                let sep = UIBezierPath()
                sep.move(to: CGPoint(x: 80, y: currentY + 110))
                sep.addLine(to: CGPoint(x: 1120, y: currentY + 110))
                sep.lineWidth = 1
                UIColor.lightGray.setStroke()
                sep.stroke()

                let courseAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 26),
                    .foregroundColor: UIColor(red: 0.1, green: 0.2, blue: 0.6, alpha: 1.0),
                    .paragraphStyle: bodyStyle
                ]
                ("\(item.code) - \(item.name)" as NSString).draw(in: CGRect(x: 100, y: currentY + 18, width: 550, height: 38), withAttributes: courseAttrs)

                let examDetailAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 22),
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: bodyStyle
                ]
                (item.date as NSString).draw(in: CGRect(x: 680, y: currentY + 22, width: 430, height: 75), withAttributes: examDetailAttrs)

                currentY += 125
            }

            // Note below table
            let noteAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .medium),
                .foregroundColor: UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0),
                .paragraphStyle: bodyStyle
            ]
            let notesText = "Important Instructions:\n1. Students must carry their College ID cards to the exam hall.\n2. Entry into examination hall closes exactly 10 minutes prior to exam start.\n3. Electronic devices and smartwatches are strictly prohibited."
            (notesText as NSString).draw(in: CGRect(x: 80, y: currentY + 40, width: 1040, height: 160), withAttributes: noteAttrs)

            // Controller Signature Block
            let sigAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.black,
                .paragraphStyle: bodyStyle
            ]
            ("Controller of Examinations\nKIET Group of Institutions" as NSString).draw(in: CGRect(x: 750, y: 1420, width: 350, height: 70), withAttributes: sigAttrs)
        }

        cachedExamDatesheet = image
        return image
    }

    // MARK: - 2. Assignment Submission Notice
    static func renderAssignmentNotice() -> UIImage {
        if let cached = cachedAssignmentNotice { return cached }

        let size = CGSize(width: 1200, height: 1600)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            // Background
            UIColor(red: 0.98, green: 0.99, blue: 0.98, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Border
            let borderRect = CGRect(x: 40, y: 40, width: 1120, height: 1520)
            let borderPath = UIBezierPath(rect: borderRect)
            borderPath.lineWidth = 4
            UIColor(red: 0.15, green: 0.3, blue: 0.2, alpha: 1.0).setStroke()
            borderPath.stroke()

            // Header Box
            let headerRect = CGRect(x: 40, y: 40, width: 1120, height: 250)
            UIColor(red: 0.92, green: 0.96, blue: 0.93, alpha: 1.0).setFill()
            ctx.fill(headerRect)

            let centerStyle = NSMutableParagraphStyle()
            centerStyle.alignment = .center

            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 34),
                .foregroundColor: UIColor.black,
                .paragraphStyle: centerStyle
            ]
            ("DEPARTMENT OF COMPUTER SCIENCE & ENGINEERING" as NSString).draw(in: CGRect(x: 60, y: 70, width: 1080, height: 45), withAttributes: headerAttrs)

            let noticeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 26),
                .foregroundColor: UIColor(red: 0.1, green: 0.5, blue: 0.2, alpha: 1.0),
                .paragraphStyle: centerStyle
            ]
            ("ACADEMIC COURSEWORK ASSIGNMENT NOTICE" as NSString).draw(in: CGRect(x: 60, y: 125, width: 1080, height: 35), withAttributes: noticeAttrs)

            let demoStampAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor(red: 0.8, green: 0.3, blue: 0.0, alpha: 1.0),
                .paragraphStyle: centerStyle
            ]
            ("★ OFFICIAL DEMO DOCUMENT — FOR OCR TEXT RECOGNITION TESTING ★" as NSString).draw(in: CGRect(x: 60, y: 185, width: 1080, height: 30), withAttributes: demoStampAttrs)

            let bodyStyle = NSMutableParagraphStyle()
            bodyStyle.alignment = .left

            // Key Course Info Box
            let infoBoxRect = CGRect(x: 80, y: 340, width: 1040, height: 460)
            UIColor(red: 0.95, green: 0.97, blue: 0.95, alpha: 1.0).setFill()
            ctx.fill(infoBoxRect)
            let boxBorder = UIBezierPath(roundedRect: infoBoxRect, cornerRadius: 12)
            boxBorder.lineWidth = 2
            UIColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 1.0).setStroke()
            boxBorder.stroke()

            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 26),
                .foregroundColor: UIColor.black,
                .paragraphStyle: bodyStyle
            ]
            let valAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .regular),
                .foregroundColor: UIColor(red: 0.1, green: 0.2, blue: 0.4, alpha: 1.0),
                .paragraphStyle: bodyStyle
            ]

            ("Course: CS 204 - Object Oriented Programming" as NSString).draw(in: CGRect(x: 120, y: 380, width: 960, height: 40), withAttributes: labelAttrs)

            ("Assignment: Polymorphism and Memory Management in Swift" as NSString).draw(in: CGRect(x: 120, y: 440, width: 960, height: 40), withAttributes: labelAttrs)

            let deadlineLabelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 26),
                .foregroundColor: UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1.0),
                .paragraphStyle: bodyStyle
            ]
            ("Due Date: CS 204 Polymorphism Assignment — Deadline on November 14, 2026 at 05:00 PM" as NSString).draw(in: CGRect(x: 120, y: 505, width: 960, height: 40), withAttributes: deadlineLabelAttrs)

            ("Submission Mode: Source code archive via Moodle LMS" as NSString).draw(in: CGRect(x: 120, y: 575, width: 960, height: 40), withAttributes: valAttrs)

            ("Priority Level: High Priority — Late submissions incur daily grade penalty." as NSString).draw(in: CGRect(x: 120, y: 640, width: 960, height: 40), withAttributes: valAttrs)

            // Problem statement
            let probTitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 26),
                .foregroundColor: UIColor.black,
                .paragraphStyle: bodyStyle
            ]
            ("Assignment Problem Outline:" as NSString).draw(in: CGRect(x: 80, y: 840, width: 1040, height: 35), withAttributes: probTitleAttrs)

            let descText = """
            1. Implement generic collection protocols conforming to Swift standard library semantics.
            2. Build an efficient reference counting graph detector that avoids cyclic retain cycles with weak delegates.
            3. Include full unit test coverage and benchmark memory usage across 100,000 node allocations.
            4. Upload your completed project archive to the college Moodle portal before the due date.
            """
            let descAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22),
                .foregroundColor: UIColor.darkGray,
                .paragraphStyle: bodyStyle
            ]
            (descText as NSString).draw(in: CGRect(x: 80, y: 890, width: 1040, height: 260), withAttributes: descAttrs)

            // Faculty Sign
            let sigAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.black,
                .paragraphStyle: bodyStyle
            ]
            ("Dr. A. Verma\nCourse Faculty & Coordinator, CS 204\nDepartment of Computer Science" as NSString).draw(in: CGRect(x: 720, y: 1400, width: 400, height: 90), withAttributes: sigAttrs)
        }

        cachedAssignmentNotice = image
        return image
    }

    // MARK: - 3. Event & Hackathon Notice
    static func renderEventNotice() -> UIImage {
        if let cached = cachedEventNotice { return cached }

        let size = CGSize(width: 1200, height: 1600)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            // Background
            UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Border
            let borderRect = CGRect(x: 40, y: 40, width: 1120, height: 1520)
            let borderPath = UIBezierPath(rect: borderRect)
            borderPath.lineWidth = 4
            UIColor(red: 0.1, green: 0.25, blue: 0.55, alpha: 1.0).setStroke()
            borderPath.stroke()

            // Header Box
            let headerRect = CGRect(x: 40, y: 40, width: 1120, height: 260)
            UIColor(red: 0.9, green: 0.93, blue: 0.98, alpha: 1.0).setFill()
            ctx.fill(headerRect)

            let centerStyle = NSMutableParagraphStyle()
            centerStyle.alignment = .center

            let instAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 34),
                .foregroundColor: UIColor.black,
                .paragraphStyle: centerStyle
            ]
            ("INSTITUTE INNOVATION COUNCIL (IIC)" as NSString).draw(in: CGRect(x: 60, y: 65, width: 1080, height: 45), withAttributes: instAttrs)

            let deptAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .semibold),
                .foregroundColor: UIColor(red: 0.2, green: 0.3, blue: 0.6, alpha: 1.0),
                .paragraphStyle: centerStyle
            ]
            ("STUDENT TECHNICAL SOCIETY & HACKATHON COMMITTEE" as NSString).draw(in: CGRect(x: 60, y: 115, width: 1080, height: 35), withAttributes: deptAttrs)

            let noticeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 26),
                .foregroundColor: UIColor(red: 0.0, green: 0.3, blue: 0.7, alpha: 1.0),
                .paragraphStyle: centerStyle
            ]
            ("HACKRADAR 2026: NATIONAL STUDENT INNOVATION CHALLENGE" as NSString).draw(in: CGRect(x: 60, y: 160, width: 1080, height: 40), withAttributes: noticeAttrs)

            // DEMO Stamp
            let demoStampAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor(red: 0.8, green: 0.3, blue: 0.0, alpha: 1.0),
                .paragraphStyle: centerStyle
            ]
            ("★ OFFICIAL DEMO DOCUMENT — FOR OCR TEXT RECOGNITION TESTING ★" as NSString).draw(in: CGRect(x: 60, y: 220, width: 1080, height: 30), withAttributes: demoStampAttrs)

            let bodyStyle = NSMutableParagraphStyle()
            bodyStyle.alignment = .left

            // Event Details Box
            let infoBoxRect = CGRect(x: 80, y: 340, width: 1040, height: 500)
            UIColor(red: 0.94, green: 0.96, blue: 0.99, alpha: 1.0).setFill()
            ctx.fill(infoBoxRect)
            let boxBorder = UIBezierPath(roundedRect: infoBoxRect, cornerRadius: 12)
            boxBorder.lineWidth = 2
            UIColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1.0).setStroke()
            boxBorder.stroke()

            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 26),
                .foregroundColor: UIColor.black,
                .paragraphStyle: bodyStyle
            ]
            let valAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .regular),
                .foregroundColor: UIColor(red: 0.1, green: 0.2, blue: 0.4, alpha: 1.0),
                .paragraphStyle: bodyStyle
            ]

            ("Event Title:" as NSString).draw(in: CGRect(x: 120, y: 380, width: 250, height: 35), withAttributes: labelAttrs)
            ("HackRadar National Innovation Conclave 2026" as NSString).draw(in: CGRect(x: 420, y: 380, width: 660, height: 35), withAttributes: valAttrs)

            let regAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 26),
                .foregroundColor: UIColor(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0),
                .paragraphStyle: bodyStyle
            ]
            ("Registration Deadline:" as NSString).draw(in: CGRect(x: 120, y: 445, width: 280, height: 35), withAttributes: regAttrs)
            ("Registration Deadline on November 06, 2026 at 11:59 PM" as NSString).draw(in: CGRect(x: 420, y: 445, width: 660, height: 35), withAttributes: regAttrs)

            ("Event Presentation:" as NSString).draw(in: CGRect(x: 120, y: 515, width: 280, height: 35), withAttributes: labelAttrs)
            ("Project Presentation on November 20, 2026 at 09:00 AM" as NSString).draw(in: CGRect(x: 420, y: 515, width: 660, height: 35), withAttributes: valAttrs)

            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 26),
                .foregroundColor: UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1.0),
                .paragraphStyle: bodyStyle
            ]
            ("Submission Deadline:" as NSString).draw(in: CGRect(x: 120, y: 585, width: 280, height: 35), withAttributes: subAttrs)
            ("Final Submission Deadline on November 21, 2026 at 06:00 PM" as NSString).draw(in: CGRect(x: 420, y: 585, width: 660, height: 35), withAttributes: subAttrs)

            ("Venue & Mode:" as NSString).draw(in: CGRect(x: 120, y: 655, width: 280, height: 35), withAttributes: labelAttrs)
            ("Central Innovation Center & Auditorium (Hybrid)" as NSString).draw(in: CGRect(x: 420, y: 655, width: 660, height: 35), withAttributes: valAttrs)

            ("Eligibility:" as NSString).draw(in: CGRect(x: 120, y: 720, width: 280, height: 35), withAttributes: labelAttrs)
            ("Open to all undergraduate students (teams of 2-4 members)" as NSString).draw(in: CGRect(x: 420, y: 720, width: 660, height: 35), withAttributes: valAttrs)

            // Themes
            let themeTitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 26),
                .foregroundColor: UIColor.black,
                .paragraphStyle: bodyStyle
            ]
            ("Hackathon Track Themes:" as NSString).draw(in: CGRect(x: 80, y: 880, width: 1040, height: 35), withAttributes: themeTitleAttrs)

            let themesText = """
            Track 1: Smart Academic Tools & Campus Productivity
            Track 2: Sustainable Smart Cities, Clean Energy & IoT
            Track 3: Generative AI, Computer Vision & Healthcare Diagnostics
            Track 4: Open Innovation & Fintech Accessibility
            """
            let themesAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22),
                .foregroundColor: UIColor.darkGray,
                .paragraphStyle: bodyStyle
            ]
            (themesText as NSString).draw(in: CGRect(x: 80, y: 930, width: 1040, height: 220), withAttributes: themesAttrs)

            // Convener Sign
            let sigAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.black,
                .paragraphStyle: bodyStyle
            ]
            ("Dr. S. Gupta\nFaculty Convener, Hackathon Committee\nInstitute Innovation Council" as NSString).draw(in: CGRect(x: 700, y: 1400, width: 420, height: 90), withAttributes: sigAttrs)
        }

        cachedEventNotice = image
        return image
    }

    // MARK: - 4. Notice with Uncertain Deadline (Manual Correction Edge Case)
    static func renderUncertainNotice() -> UIImage {
        if let cached = cachedUncertainNotice { return cached }

        let size = CGSize(width: 1200, height: 1600)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            // Background
            UIColor(red: 0.99, green: 0.98, blue: 0.97, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Border
            let borderRect = CGRect(x: 40, y: 40, width: 1120, height: 1520)
            let borderPath = UIBezierPath(rect: borderRect)
            borderPath.lineWidth = 4
            UIColor(red: 0.4, green: 0.3, blue: 0.2, alpha: 1.0).setStroke()
            borderPath.stroke()

            let centerStyle = NSMutableParagraphStyle()
            centerStyle.alignment = .center

            // Header Box
            let headerRect = CGRect(x: 40, y: 40, width: 1120, height: 240)
            UIColor(red: 0.98, green: 0.94, blue: 0.9, alpha: 1.0).setFill()
            ctx.fill(headerRect)

            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 34),
                .foregroundColor: UIColor.black,
                .paragraphStyle: centerStyle
            ]
            ("DEPARTMENT OF INFORMATION TECHNOLOGY" as NSString).draw(in: CGRect(x: 60, y: 70, width: 1080, height: 45), withAttributes: headerAttrs)

            let noticeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 26),
                .foregroundColor: UIColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 1.0),
                .paragraphStyle: centerStyle
            ]
            ("ACADEMIC NOTICE: RESEARCH PAPER DRAFT GUIDELINES" as NSString).draw(in: CGRect(x: 60, y: 125, width: 1080, height: 35), withAttributes: noticeAttrs)

            let demoStampAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor(red: 0.8, green: 0.3, blue: 0.0, alpha: 1.0),
                .paragraphStyle: centerStyle
            ]
            ("★ OFFICIAL DEMO DOCUMENT — TESTING UNCERTAIN DATE DETECTION ★" as NSString).draw(in: CGRect(x: 60, y: 185, width: 1080, height: 30), withAttributes: demoStampAttrs)

            let bodyStyle = NSMutableParagraphStyle()
            bodyStyle.alignment = .left

            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 26),
                .foregroundColor: UIColor.black,
                .paragraphStyle: bodyStyle
            ]
            let valAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .regular),
                .foregroundColor: UIColor(red: 0.2, green: 0.2, blue: 0.3, alpha: 1.0),
                .paragraphStyle: bodyStyle
            ]

            let infoBoxRect = CGRect(x: 80, y: 340, width: 1040, height: 420)
            UIColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0).setFill()
            ctx.fill(infoBoxRect)
            let boxBorder = UIBezierPath(roundedRect: infoBoxRect, cornerRadius: 12)
            boxBorder.lineWidth = 2
            UIColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1.0).setStroke()
            boxBorder.stroke()

            ("Course Code:" as NSString).draw(in: CGRect(x: 120, y: 380, width: 250, height: 35), withAttributes: labelAttrs)
            ("CS 402 - Final Year Technical Seminar" as NSString).draw(in: CGRect(x: 400, y: 380, width: 680, height: 35), withAttributes: valAttrs)

            ("Assignment:" as NSString).draw(in: CGRect(x: 120, y: 440, width: 250, height: 35), withAttributes: labelAttrs)
            ("Term Paper Synopsis and Literature Review" as NSString).draw(in: CGRect(x: 400, y: 440, width: 680, height: 35), withAttributes: valAttrs)

            let warnAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 26),
                .foregroundColor: UIColor(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0),
                .paragraphStyle: bodyStyle
            ]
            ("Submission Date:" as NSString).draw(in: CGRect(x: 120, y: 510, width: 250, height: 35), withAttributes: warnAttrs)
            ("Due date TBD (To Be Decided after midterm departmental review)" as NSString).draw(in: CGRect(x: 400, y: 510, width: 680, height: 35), withAttributes: warnAttrs)

            ("Presentation Venue:" as NSString).draw(in: CGRect(x: 120, y: 580, width: 250, height: 35), withAttributes: labelAttrs)
            ("Seminar Hall B (Panel allocation will be posted later)" as NSString).draw(in: CGRect(x: 400, y: 580, width: 680, height: 35), withAttributes: valAttrs)

            let descText = """
            Notice Guidelines:
            1. All registered students must submit a preliminary synopsis of 5-8 pages.
            2. The exact evaluation schedule is tentative and will be confirmed after internal review.
            3. When scanned in Assignment Radar, this notice tests the unconfirmed-date warning, allowing students to set an explicit target date manually.
            """
            let descAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22),
                .foregroundColor: UIColor.darkGray,
                .paragraphStyle: bodyStyle
            ]
            (descText as NSString).draw(in: CGRect(x: 80, y: 820, width: 1040, height: 260), withAttributes: descAttrs)

            let sigAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.black,
                .paragraphStyle: bodyStyle
            ]
            ("Head of Department\nDepartment of Information Technology" as NSString).draw(in: CGRect(x: 700, y: 1400, width: 420, height: 90), withAttributes: sigAttrs)
        }

        cachedUncertainNotice = image
        return image
    }
}

// MARK: - Demo Scan Gallery View

struct DemoScanGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelectImage: (UIImage) -> Void

    @State private var selectedDocumentForPreview: DemoDocument? = nil

    private let demoDocuments: [DemoDocument] = [
        DemoDocument(
            id: "exam_datesheet",
            title: "End-Semester Examination Datesheet",
            category: "Exam Datesheet",
            summary: "Multi-subject examination datesheet featuring CS 301, CS 302, CS 303, and CS 304 with exam dates and start times.",
            highlights: [
                "CS 301 Operating Systems — Nov 16, 10:00 AM",
                "CS 302 Algorithms — Nov 19, 02:00 PM",
                "CS 303 Database Systems — Nov 24, 10:00 AM",
                "CS 304 Computer Networks — Nov 28, 02:00 PM"
            ],
            badgeText: "DEMO DATESHEET",
            getImage: { DemoDocumentGenerator.renderExamDatesheet() }
        ),
        DemoDocument(
            id: "assignment_notice",
            title: "Coursework Assignment Notice",
            category: "Assignment Notice",
            summary: "Official academic assignment submission notice for CS 204 with project title, instructions, and hard deadline.",
            highlights: [
                "Course: CS 204 Object Oriented Programming",
                "Assignment: Polymorphism & Memory Management",
                "Due Date: Nov 14, 2026 at 05:00 PM",
                "Priority: High Priority Submission"
            ],
            badgeText: "DEMO ASSIGNMENT",
            getImage: { DemoDocumentGenerator.renderAssignmentNotice() }
        ),
        DemoDocument(
            id: "event_hackathon",
            title: "Hackathon & Innovation Conclave",
            category: "Event Schedule",
            summary: "Annual university technical challenge notice with distinct registration deadline and project submission dates.",
            highlights: [
                "Event: HackRadar National Innovation Challenge",
                "Registration Deadline: Nov 06, 2026 at 11:59 PM",
                "Presentation: Nov 20, 2026 at 09:00 AM",
                "Submission Deadline: Nov 21, 2026 at 06:00 PM"
            ],
            badgeText: "DEMO EVENT",
            getImage: { DemoDocumentGenerator.renderEventNotice() }
        ),
        DemoDocument(
            id: "uncertain_date",
            title: "Seminar Synopsis Guidelines",
            category: "Uncertain Date Edge Case",
            summary: "Demonstrates edge-case handling when a notice specifies a course but has a TBD deadline, prompting manual user correction.",
            highlights: [
                "Course: CS 402 Technical Seminar",
                "Deadline: Date TBD (Unconfirmed)",
                "Tests uncertainty flag and manual date picker prompt"
            ],
            badgeText: "DEMO EDGE CASE",
            getImage: { DemoDocumentGenerator.renderUncertainNotice() }
        )
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                            Text("Built-in Demonstration Gallery")
                                .font(.headline)
                        }

                        Text("Select an example academic document to test Apple's Vision on-device OCR and Assignment Radar's deadline extraction pipeline without requiring access to your computer photo library.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text("100% Offline • High Resolution • Zero Internet Required")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Available Demo Notices (\(demoDocuments.count))") {
                    ForEach(demoDocuments) { doc in
                        demoDocumentRow(doc)
                    }
                }
            }
            .navigationTitle("Try Demo Scans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedDocumentForPreview) { doc in
                DemoDocumentPreviewView(
                    document: doc,
                    onScan: { image in
                        selectedDocumentForPreview = nil
                        dismiss()
                        onSelectImage(image)
                    }
                )
            }
        }
    }

    private func demoDocumentRow(_ doc: DemoDocument) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                // Document Thumbnail Preview
                Image(uiImage: doc.getImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 70, height: 95)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(doc.badgeText)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())

                        Text(doc.category)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(doc.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(doc.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            // Highlights
            VStack(alignment: .leading, spacing: 2) {
                ForEach(doc.highlights.prefix(2), id: \.self) { highlight in
                    HStack(alignment: .top, spacing: 5) {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Text(highlight)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            // Action Buttons
            HStack(spacing: 12) {
                Button {
                    selectedDocumentForPreview = doc
                } label: {
                    Label("Preview Notice", systemImage: "eye.fill")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)

                Button {
                    dismiss()
                    onSelectImage(doc.getImage())
                } label: {
                    Label("Scan This Example", systemImage: "doc.viewfinder.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Document Full Screen Preview & Scan

struct DemoDocumentPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let document: DemoDocument
    let onScan: (UIImage) -> Void

    @State private var documentImage: UIImage? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Document Scrollable Image
                ScrollView([.horizontal, .vertical]) {
                    if let img = documentImage {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                    } else {
                        ProgressView("Rendering high-resolution document...")
                            .frame(maxWidth: .infinity, minHeight: 300)
                    }
                }
                .background(Color(.systemGroupedBackground))

                // Bottom Action Bar
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.title)
                                .font(.headline)
                            Text(document.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    Button {
                        if let img = documentImage {
                            onScan(img)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "doc.viewfinder.fill")
                            Text("Scan This Example with OCR")
                                .fontWeight(.bold)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
            }
            .navigationTitle("Document Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                documentImage = document.getImage()
            }
        }
    }
}
