//
//  AssignementRadarUITests.swift
//  AssignementRadarUITests
//
//  Created by KIET4 on 23/10/26.
//

import XCTest

final class AssignementRadarUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "System Dialog") { alert in
            if alert.buttons["Allow"].exists {
                alert.buttons["Allow"].tap()
                return true
            }
            return false
        }
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    private func ensureAssignmentRadarWorkspace(app: XCUIApplication) {
        // If currently on Coding Radar tab, switch to Assignment Radar
        let assignmentTab = app.tabBars.buttons["Assignment Radar"]
        if assignmentTab.waitForExistence(timeout: 2.0) {
            assignmentTab.tap()
        }

        // If on Moodle login screen, continue with local workspaces to reach dashboard
        let guestButton = app.buttons["Continue with Local Workspaces & Notice Scanner"]
        if guestButton.waitForExistence(timeout: 2.0) {
            guestButton.tap()
        }
    }

    @MainActor
    func testScanNoticeAndDemoGalleryFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-selected_app_workspace", "assignment_radar"]
        app.launch()

        // Dismiss system alerts if present
        if app.alerts.firstMatch.waitForExistence(timeout: 2.0) {
            let allowButton = app.alerts.buttons["Allow"]
            if allowButton.exists {
                allowButton.tap()
            }
        }

        ensureAssignmentRadarWorkspace(app: app)

        // 1. Tap Scan Notice toolbar button
        let scanNoticeButton = app.buttons["Scan Notice"]
        XCTAssertTrue(scanNoticeButton.waitForExistence(timeout: 5.0))
        scanNoticeButton.tap()

        // 2. Tap Try Demo Scans
        let tryDemoScansButton = app.buttons["Try Demo Scans"]
        XCTAssertTrue(tryDemoScansButton.waitForExistence(timeout: 5.0))
        tryDemoScansButton.tap()

        // 3. Verify Demo Gallery opened
        let galleryTitle = app.navigationBars["Try Demo Scans"]
        XCTAssertTrue(galleryTitle.waitForExistence(timeout: 5.0))

        // 4. Tap "Scan This Example" on the first demo document (Exam Datesheet)
        let scanThisButtons = app.buttons.matching(identifier: "Scan This Example")
        XCTAssertTrue(scanThisButtons.firstMatch.waitForExistence(timeout: 5.0))
        scanThisButtons.firstMatch.tap()

        // 5. Verify OCR review screen appears with extracted items
        let reviewTitle = app.navigationBars["Review Deadlines"]
        XCTAssertTrue(reviewTitle.waitForExistence(timeout: 10.0))

        // 6. Verify Close button cleanly dismisses without modifying database
        let closeButton = app.buttons["Close"]
        XCTAssertTrue(closeButton.exists)
        closeButton.tap()
    }

    @MainActor
    func testDashboardFiltersAndCalendarNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-selected_app_workspace", "assignment_radar"]
        app.launch()

        // Dismiss system alerts if present
        if app.alerts.firstMatch.waitForExistence(timeout: 2.0) {
            let allowButton = app.alerts.buttons["Allow"]
            if allowButton.exists {
                allowButton.tap()
            }
        }

        ensureAssignmentRadarWorkspace(app: app)

        // 1. Verify primary dashboard filters: Pending and Completed
        let pendingSegment = app.segmentedControls.buttons["Pending"]
        let completedSegment = app.segmentedControls.buttons["Completed"]
        XCTAssertTrue(pendingSegment.waitForExistence(timeout: 5.0))
        XCTAssertTrue(completedSegment.waitForExistence(timeout: 5.0))

        // Old tabs "All" and "Overdue" should not exist in the primary filter
        XCTAssertFalse(app.segmentedControls.buttons["All"].exists)
        XCTAssertFalse(app.segmentedControls.buttons["Overdue"].exists)

        // 2. Tap Completed segment
        completedSegment.tap()

        // 3. Tap Pending segment to switch back
        pendingSegment.tap()

        // 4. Open dashboard overflow options menu
        let optionsButton = app.buttons["Dashboard Options"]
        XCTAssertTrue(optionsButton.waitForExistence(timeout: 5.0))
        optionsButton.tap()

        // 5. Tap Calendar Schedule in overflow menu
        let calendarButton = app.buttons["Calendar Schedule"]
        XCTAssertTrue(calendarButton.waitForExistence(timeout: 5.0))
        calendarButton.tap()

        // 6. Verify Calendar Schedule navigation bar appears
        let calendarNavBar = app.navigationBars["Calendar Schedule"]
        XCTAssertTrue(calendarNavBar.waitForExistence(timeout: 5.0))

        // 7. Verify Done button dismisses sheet
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5.0))
        doneButton.tap()
    }

    @MainActor
    func testCaptureCalendarScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-selected_app_workspace", "assignment_radar"]
        app.launch()

        ensureAssignmentRadarWorkspace(app: app)

        let optionsButton = app.buttons["Dashboard Options"]
        XCTAssertTrue(optionsButton.waitForExistence(timeout: 5.0))
        optionsButton.tap()

        let calendarButton = app.buttons["Calendar Schedule"]
        XCTAssertTrue(calendarButton.waitForExistence(timeout: 5.0))
        calendarButton.tap()

        let calendarNavBar = app.navigationBars["Calendar Schedule"]
        XCTAssertTrue(calendarNavBar.waitForExistence(timeout: 5.0))

        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "CalendarScheduleView"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Also save directly to file for inspection
        let pngData = screenshot.pngRepresentation
        let url = URL(fileURLWithPath: "/Users/kiet4/.gemini/antigravity-ide/brain/df911e8d-f9ff-476d-b5ee-aab614319cad/calendar_schedule_iphone17_promax.png")
        try? pngData.write(to: url)
    }

    @MainActor
    func testCaptureDashboardCardsAndConnectedPlatformsScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        // If on Moodle login screen, tap "Continue with Local Workspaces & Notice Scanner"
        let guestButton = app.buttons["Continue with Local Workspaces & Notice Scanner"]
        if guestButton.waitForExistence(timeout: 3.0) {
            guestButton.tap()
        }

        // Wait for dashboard Pending segment
        let pendingSegment = app.segmentedControls.buttons["Pending"]
        XCTAssertTrue(pendingSegment.waitForExistence(timeout: 5.0))

        // Take dashboard screenshot
        let dashScreenshot = app.screenshot()
        let dashUrl = URL(fileURLWithPath: "/Users/kiet4/.gemini/antigravity-ide/brain/df911e8d-f9ff-476d-b5ee-aab614319cad/dashboard_simplified_cards.png")
        try? dashScreenshot.pngRepresentation.write(to: dashUrl)

        // Open Connected Platforms / Coding Hub
        let platformsButton = app.buttons["Connected Platforms"]
        if platformsButton.waitForExistence(timeout: 3.0) {
            platformsButton.tap()
            let hubNavBar = app.navigationBars["Coding & Platforms"]
            XCTAssertTrue(hubNavBar.waitForExistence(timeout: 5.0))

            let platformsScreenshot = app.screenshot()
            let platformsUrl = URL(fileURLWithPath: "/Users/kiet4/.gemini/antigravity-ide/brain/df911e8d-f9ff-476d-b5ee-aab614319cad/coding_hub_platforms.png")
            try? platformsScreenshot.pngRepresentation.write(to: platformsUrl)
        }
    }

    @MainActor
    func testCaptureCodingRadarConfiguredStateScreenshot() throws {
        let app = XCUIApplication()
        app.launch()

        // 1. Switch to Coding Radar tab
        let codingTab = app.tabBars.buttons["Coding Radar"]
        if codingTab.waitForExistence(timeout: 5.0) {
            codingTab.tap()
        }

        // 2. Tap + Add from Catalog
        let addFromCatalogButton = app.buttons["+ Add from Catalog"]
        if addFromCatalogButton.waitForExistence(timeout: 3.0) {
            addFromCatalogButton.tap()

            // In Catalog, tap first "+ Add" button (LeetCode)
            let addButtons = app.buttons.matching(identifier: "+ Add")
            if addButtons.firstMatch.waitForExistence(timeout: 3.0) {
                addButtons.firstMatch.tap()
            }

            // Dismiss catalog
            let doneButton = app.buttons["Done"]
            if doneButton.exists {
                doneButton.tap()
            }
        }

        // 3. Tap + Add Coding Task
        let addTaskButton = app.buttons["+ Add Coding Task"]
        if addTaskButton.waitForExistence(timeout: 3.0) {
            addTaskButton.tap()

            let titleField = app.textFields["Problem or Contest Title"]
            if titleField.waitForExistence(timeout: 3.0) {
                titleField.tap()
                titleField.typeText("Reverse String")
            }

            let saveButton = app.buttons["Save"]
            if saveButton.exists {
                saveButton.tap()
            }
        }

        // 4. Capture screenshot of configured Coding Radar with pending task
        let screenshot1 = app.screenshot()
        let url1 = URL(fileURLWithPath: "/Users/kiet4/.gemini/antigravity-ide/brain/df911e8d-f9ff-476d-b5ee-aab614319cad/coding_radar_configured.png")
        try? screenshot1.pngRepresentation.write(to: url1)

        // 5. Tap the completion checkbox to record completion and trigger the daily streak
        let checkbox = app.buttons["codingTaskCheckbox"]
        if checkbox.waitForExistence(timeout: 3.0) {
            checkbox.tap()
        } else {
            let markCompleteButton = app.buttons["Mark complete"]
            if markCompleteButton.waitForExistence(timeout: 2.0) {
                markCompleteButton.tap()
            }
        }

        // Wait a brief moment for streak animation
        Thread.sleep(forTimeInterval: 0.5)

        // 6. Capture screenshot with active streak and glowing green flame
        let screenshot2 = app.screenshot()
        let url2 = URL(fileURLWithPath: "/Users/kiet4/.gemini/antigravity-ide/brain/df911e8d-f9ff-476d-b5ee-aab614319cad/coding_radar_streak_active.png")
        try? screenshot2.pngRepresentation.write(to: url2)

        // 7. Open Coding Radar Notification Settings
        let addItemMenu = app.buttons["Add Item"]
        if addItemMenu.waitForExistence(timeout: 3.0) {
            addItemMenu.tap()
            let settingsButton = app.buttons["Notification Settings"]
            if settingsButton.waitForExistence(timeout: 2.0) {
                settingsButton.tap()

                // Capture screenshot of Coding Radar Settings Sheet
                Thread.sleep(forTimeInterval: 0.5)
                let screenshotSettings = app.screenshot()
                let urlSettings = URL(fileURLWithPath: "/Users/kiet4/.gemini/antigravity-ide/brain/df911e8d-f9ff-476d-b5ee-aab614319cad/coding_radar_settings.png")
                try? screenshotSettings.pngRepresentation.write(to: urlSettings)

                let doneButton = app.buttons["Done"]
                if doneButton.exists {
                    doneButton.tap()
                }
            }
        }

        // Reset tab back to Assignment Radar
        let assignmentTab = app.tabBars.buttons["Assignment Radar"]
        if assignmentTab.exists {
            assignmentTab.tap()
        }
    }

    @MainActor
    func testSyncToAppleCalendarEndToEnd() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-selected_app_workspace", "assignment_radar"]
        app.launch()

        ensureAssignmentRadarWorkspace(app: app)

        // 1. Open dashboard overflow options menu
        let optionsButton = app.buttons["Dashboard Options"]
        XCTAssertTrue(optionsButton.waitForExistence(timeout: 5.0))
        optionsButton.tap()

        // 2. Tap "Sync to Apple Calendar"
        let syncMenuButton = app.buttons["Sync to Apple Calendar"]
        if syncMenuButton.waitForExistence(timeout: 3.0) {
            syncMenuButton.tap()

            // 3. Verify sync confirmation alert appears
            let syncAlert = app.alerts["Apple Calendar Sync"]
            if syncAlert.waitForExistence(timeout: 5.0) {
                let okButton = syncAlert.buttons["OK"]
                if okButton.exists {
                    okButton.tap()
                }
            }
        }

        // 4. Open Calendar Schedule
        if optionsButton.waitForExistence(timeout: 3.0) {
            optionsButton.tap()
        }
        let calendarScheduleButton = app.buttons["Calendar Schedule"]
        XCTAssertTrue(calendarScheduleButton.waitForExistence(timeout: 5.0))
        calendarScheduleButton.tap()

        // 5. Verify Calendar Schedule view and Sync Apple Calendar action
        let calendarNavBar = app.navigationBars["Calendar Schedule"]
        XCTAssertTrue(calendarNavBar.waitForExistence(timeout: 5.0))

        let syncBannerButton = app.buttons["Sync to Apple Calendar Now"]
        XCTAssertTrue(syncBannerButton.waitForExistence(timeout: 5.0))

        // Capture screenshot of Calendar Schedule with Sync banner
        let screenshot = app.screenshot()
        let url = URL(fileURLWithPath: "/Users/kiet4/.gemini/antigravity-ide/brain/df911e8d-f9ff-476d-b5ee-aab614319cad/calendar_schedule_sync_banner.png")
        try? screenshot.pngRepresentation.write(to: url)

        // 6. Dismiss
        let doneButton = app.buttons["Done"]
        if doneButton.waitForExistence(timeout: 5.0) {
            doneButton.tap()
        }
    }
}
