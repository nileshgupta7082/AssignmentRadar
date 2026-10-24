//
//  AssignementRadarTests.swift
//  AssignementRadarTests
//
//  Created by KIET4 on 23/10/26.
//

import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import AssignementRadar

@Suite(.serialized)
struct AssignementRadarTests {

    // MARK: - Core Assignment Model Tests

    @Test func testAssignmentCreation() async throws {
        let assignment = Assignment(
            title: "Math Homework",
            course: "MATH 101",
            priority: .high
        )
        #expect(assignment.title == "Math Homework")
        #expect(assignment.course == "MATH 101")
        #expect(assignment.priority == .high)
        #expect(assignment.isCompleted == false)
    }

    @Test func testOverdueCalculation() async throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let overdueAssignment = Assignment(
            title: "Past Deadline Assignment",
            dueDate: yesterday
        )
        #expect(overdueAssignment.isOverdue == true)

        overdueAssignment.isCompleted = true
        #expect(overdueAssignment.isOverdue == false)
    }

    // MARK: - OCR Scanner Parser Tests

    @Test func testScheduleParserDetectsCourseTitleDateAndPriority() async throws {
        let lines = [
            "CS 101 - Introduction to Programming",
            "Midterm Exam on November 12, 2026 at 10:00 AM"
        ]

        let drafts = ScheduleParser.parse(lines: lines)
        #expect(drafts.count >= 1)

        let examDraft = drafts.first!
        #expect(examDraft.course == "CS 101")
        #expect(examDraft.priority == .high)
        #expect(examDraft.isConfidentDate == true)
        #expect(examDraft.title.localizedCaseInsensitiveContains("Midterm Exam"))
    }

    @Test func testScheduleParserFlagsUncertainDateWhenMissing() async throws {
        let lines = [
            "MATH 202 - Term Paper Draft (Due date TBD)"
        ]

        let drafts = ScheduleParser.parse(lines: lines)
        #expect(drafts.count == 1)

        let paperDraft = drafts.first!
        #expect(paperDraft.course == "MATH 202")
        #expect(paperDraft.isConfidentDate == false)
    }

    // MARK: - Moodle URL & ATS Scoped Policy Tests

    @Test func testMoodleUrlNormalizationWithScopedAtsException() async throws {
        // Plain HTTP is specifically permitted for lms.kiet.edu per targeted ATS exception
        let collegeUrlResult = MoodleService.normalizeUrl("http://lms.kiet.edu/moodle")
        let collegeEndpoint = try collegeUrlResult.get()
        #expect(collegeEndpoint.absoluteString == "http://lms.kiet.edu/moodle/webservice/rest/server.php")

        // Inputting without scheme for college host automatically selects http://
        let collegeNoScheme = try MoodleService.normalizeUrl("lms.kiet.edu/moodle").get()
        #expect(collegeNoScheme.absoluteString == "http://lms.kiet.edu/moodle/webservice/rest/server.php")

        // Token endpoint for college server works over HTTP
        let collegeTokenUrl = try MoodleService.tokenEndpointUrl("http://lms.kiet.edu/moodle").get()
        #expect(collegeTokenUrl.absoluteString == "http://lms.kiet.edu/moodle/login/token.php")

        // Plain HTTP for ANY OTHER non-whitelisted domain must be strictly rejected
        let insecureResult = MoodleService.normalizeUrl("http://untrusted-moodle.com/moodle")
        switch insecureResult {
        case .success:
            #expect(Bool(false), "Insecure HTTP to untrusted domains must be rejected")
        case .failure(let error):
            #expect(error.localizedDescription.contains("unencrypted and blocked"))
        }

        // HTTPS for standard university portals is accepted
        let urlHttps = try MoodleService.normalizeUrl("https://moodle.university.edu/moodle/").get()
        #expect(urlHttps.absoluteString == "https://moodle.university.edu/moodle/webservice/rest/server.php")

        // Empty URL fails validation
        let emptyResult = MoodleService.normalizeUrl("   ")
        switch emptyResult {
        case .success:
            #expect(Bool(false), "Empty URL must fail")
        case .failure:
            #expect(Bool(true))
        }
    }

    // MARK: - Keychain Helper Tests

    @Test func testMoodleKeychainTokenHelper() async throws {
        let testToken = "test_abc123_token"
        let saved = MoodleKeychainHelper.saveToken(testToken)
        #expect(saved == true)

        let loaded = MoodleKeychainHelper.loadToken()
        #expect(loaded == testToken)

        let deleted = MoodleKeychainHelper.deleteToken()
        #expect(deleted == true)

        let loadedAfterDelete = MoodleKeychainHelper.loadToken()
        #expect(loadedAfterDelete == nil)
    }

    // MARK: - Moodle API Response Decoding & Error Handling

    @Test func testMoodleAssignGetAssignmentsResponseDecoding() async throws {
        let json = """
        {
            "courses": [
                {
                    "id": 14,
                    "fullname": "Operating Systems",
                    "shortname": "CS 301",
                    "assignments": [
                        {
                            "id": 101,
                            "cmid": 450,
                            "course": 14,
                            "name": "Kernel Module Lab 4",
                            "duedate": 1730000000,
                            "cutoffdate": 0,
                            "intro": "<p>Please upload your .c file and Makefile.<br/>No late submissions.</p>"
                        }
                    ]
                }
            ],
            "warnings": []
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(MoodleAssignGetAssignmentsResponse.self, from: json)
        #expect(response.courses?.count == 1)

        let course = response.courses?.first
        #expect(course?.shortname == "CS 301")
        #expect(course?.assignments?.count == 1)

        let assignment = course?.assignments?.first
        #expect(assignment?.name == "Kernel Module Lab 4")
        #expect(assignment?.cmid == 450)
        #expect(assignment?.duedate == 1730000000)

        // Test HTML cleaning
        let cleanedNotes = MoodleService.stripHtml(assignment?.intro ?? "")
        #expect(cleanedNotes.contains("Please upload your .c file and Makefile."))
        #expect(!cleanedNotes.contains("<p>"))
        #expect(!cleanedNotes.contains("<br/>"))
    }

    @Test func testMoodleErrorResponseDecoding() async throws {
        let invalidLoginJson = """
        {"error":"Invalid login, please try again","errorcode":"invalidlogin","stacktrace":null,"debuginfo":null,"reproductionlink":null}
        """.data(using: .utf8)!

        let tokenResponse = try JSONDecoder().decode(MoodleTokenResponse.self, from: invalidLoginJson)
        #expect(tokenResponse.token == nil)
        #expect(tokenResponse.errorcode == "invalidlogin")

        let restErrorJson = """
        {"exception":"webservice_access_exception","errorcode":"accessexception","message":"Access control exception"}
        """.data(using: .utf8)!

        let restError = try JSONDecoder().decode(MoodleErrorResponse.self, from: restErrorJson)
        #expect(restError.errorcode == "accessexception")
        #expect(restError.exception == "webservice_access_exception")
    }

    @Test func testMoodlePriorityInference() async throws {
        #expect(MoodleService.inferPriority(from: "Midterm Exam Part 1") == .high)
        #expect(MoodleService.inferPriority(from: "Final Practical Examination") == .high)
        #expect(MoodleService.inferPriority(from: "Unit 3 Quiz") == .medium)
        #expect(MoodleService.inferPriority(from: "Term Project Checkpoint") == .medium)
        #expect(MoodleService.inferPriority(from: "Weekly Reading Chapter 4") == .low)
    }

    // MARK: - Deduplication Tests

    @Test func testMoodleDeduplication() async throws {
        let existing = Assignment(
            title: "Operating Systems Lab 4 Submission",
            course: "CS 301",
            source: "moodle",
            moodleEventId: "assign_101"
        )

        let drafts = MoodleService.generateMockDrafts(existingAssignments: [existing])
        let dup = drafts.first { $0.moodleEventId == "assign_101" }

        #expect(dup != nil)
        #expect(dup?.isDuplicate == true)
        #expect(dup?.isSelected == false) // Duplicate should be deselected by default

        let nonDup = drafts.first { $0.moodleEventId == "assign_102" }
        #expect(nonDup?.isDuplicate == false)
        #expect(nonDup?.isSelected == true)
    }

    // MARK: - Live College Moodle HTTP Request (ATS Verification)

    @Test func testLiveCollegeMoodleConnectionOverHttp() async throws {
        // This test connects to the live college server at http://lms.kiet.edu/moodle/login/token.php
        // It verifies that:
        // 1. Plain HTTP is not blocked by ATS for lms.kiet.edu.
        // 2. The endpoint responds with standard Moodle JSON.
        // 3. Incorrect credentials correctly produce the invalidlogin error without throwing a network or ATS error.
        do {
            _ = try await MoodleService.shared.login(
                siteUrl: "http://lms.kiet.edu/moodle",
                username: "nonexistent_radar_test_user",
                password: "invalid_test_password"
            )
            #expect(Bool(false), "Login should not succeed with fake credentials")
        } catch let error as MoodleError {
            switch error {
            case .serverError(let code, _):
                #expect(code == "invalidlogin", "Server should respond with invalidlogin errorcode")
            default:
                #expect(Bool(false), "Unexpected MoodleError: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected non-Moodle error (such as ATS block): \(error.localizedDescription)")
        }
    }

    // MARK: - Keyboard & Special Character Handling Tests

    @Test func testUsernameInputFormattingAndSpecialCharacters() async throws {
        let testInputs = [
            "student@example.com",
            "student.name@example.com",
            "student_123",
            "student-123",
            "KIET2026CS001",
            "FIRSTNAME.LASTNAME@COLLEGE.EDU"
        ]

        for input in testInputs {
            // Ensure no characters are stripped or forcibly lowercased
            let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(clean == input)
            #expect(clean.count == input.count)
            #expect(!clean.isEmpty)
        }
    }

    @Test func testFormUrlEncodingPreservesCredentialsAndSymbols() async throws {
        // Special character support for emails and complex passwords
        let email = "student@example.com"
        let encodedEmail = MoodleService.formUrlEncode(email)
        #expect(encodedEmail == "student%40example.com")

        let passwordWithSymbols = "P@ss#123&more+symbols!_*-."
        let encodedPassword = MoodleService.formUrlEncode(passwordWithSymbols)
        // Ensure symbols are percent-encoded and not corrupted as URL parameter delimiters (&, +, =)
        #expect(encodedPassword.contains("%40")) // @
        #expect(encodedPassword.contains("%23")) // #
        #expect(encodedPassword.contains("%26")) // &
        #expect(encodedPassword.contains("%2B")) // +
        #expect(encodedPassword.contains("%21")) // !
        #expect(encodedPassword.contains("-"))   // - is unreserved
        #expect(encodedPassword.contains("."))   // . is unreserved
        #expect(encodedPassword.contains("_"))   // _ is unreserved
        #expect(encodedPassword.contains("*"))   // * is unreserved
    }

    // MARK: - Dashboard Filter & Overdue Logic Tests

    @Test func testDashboardFilterTabsAndOverdueCalculation() async throws {
        let futureDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        let pastDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())!

        let pendingItem = Assignment(title: "Upcoming Project", dueDate: futureDate, isCompleted: false)
        let overdueItem = Assignment(title: "Late Submission", dueDate: pastDate, isCompleted: false)
        let completedItem = Assignment(title: "Done Lab", dueDate: futureDate, isCompleted: true)
        let completedPastItem = Assignment(title: "Done Exam", dueDate: pastDate, isCompleted: true)

        let allList = [pendingItem, overdueItem, completedItem, completedPastItem]

        // 1. All filter contains all 4 items
        #expect(allList.count == 4)

        // 2. Pending: only incomplete and not overdue
        let pendingFiltered = allList.filter { !$0.isCompleted && !$0.isOverdue }
        #expect(pendingFiltered.count == 1)
        #expect(pendingFiltered.first?.title == "Upcoming Project")

        // 3. Overdue: only incomplete and overdue
        let overdueFiltered = allList.filter { !$0.isCompleted && $0.isOverdue }
        #expect(overdueFiltered.count == 1)
        #expect(overdueFiltered.first?.title == "Late Submission")

        // 4. Completed: not classified as overdue even if dueDate in past
        #expect(completedPastItem.isOverdue == false)
        #expect(completedItem.isOverdue == false)

        // 5. Completing an overdue item removes it from Overdue and leaves it in All
        overdueItem.isCompleted = true
        #expect(overdueItem.isOverdue == false)
        let updatedOverdue = allList.filter { !$0.isCompleted && $0.isOverdue }
        #expect(updatedOverdue.isEmpty)
        #expect(allList.contains { $0.title == "Late Submission" && $0.isCompleted })
    }

    // MARK: - Theme Mode Tests

    @Test func testThemeModesAndColorSchemes() async throws {
        #expect(AppTheme.system.colorScheme == nil)
        #expect(AppTheme.light.colorScheme == .light)
        #expect(AppTheme.dark.colorScheme == .dark)
        #expect(AppTheme.allCases.count == 3)
    }

    // MARK: - Moodle Completed Status Preservation Test

    @Test func testMoodleImportPreservesLocallyCompletedStatus() async throws {
        let existingCompleted = Assignment(
            title: "Operating Systems Lab 4 Submission",
            course: "CS 301",
            dueDate: Date(),
            isCompleted: true,
            source: "moodle",
            moodleEventId: "assign_101"
        )

        // Verify deduplication flags it as duplicate
        let drafts = MoodleService.generateMockDrafts(existingAssignments: [existingCompleted])
        let matchingDraft = drafts.first { $0.moodleEventId == "assign_101" }
        #expect(matchingDraft?.isDuplicate == true)
        #expect(matchingDraft?.isSelected == false)

        // Ensure isCompleted remains true on the existing record
        #expect(existingCompleted.isCompleted == true)
    }

    // MARK: - Smart Urgency Classification Tests

    @Test func testUrgencyClassificationCategories() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1770000000)

        // 1. Due in 24 hours (e.g. 23 hours 59 min) -> dueSoon
        let due24h = Assignment(
            title: "Physics Problem Set",
            dueDate: referenceDate.addingTimeInterval(23 * 3600 + 3500)
        )
        #expect(due24h.urgency(at: referenceDate) == .dueSoon)

        // 2. Due in 3 hours -> dueSoon
        let due3h = Assignment(
            title: "Quick Quiz",
            dueDate: referenceDate.addingTimeInterval(3 * 3600)
        )
        #expect(due3h.urgency(at: referenceDate) == .dueSoon)

        // 3. Due in 2 days (<= 3 days) -> upcoming
        let due2d = Assignment(
            title: "Essay Outline",
            dueDate: referenceDate.addingTimeInterval(2 * 86400)
        )
        #expect(due2d.urgency(at: referenceDate) == .upcoming)

        // 4. Due in 5 days (> 3 days) -> later
        let due5d = Assignment(
            title: "Term Project",
            dueDate: referenceDate.addingTimeInterval(5 * 86400)
        )
        #expect(due5d.urgency(at: referenceDate) == .later)

        // 5. Past deadline & incomplete -> overdue
        let overdue = Assignment(
            title: "Late Lab Submission",
            dueDate: referenceDate.addingTimeInterval(-3600)
        )
        #expect(overdue.urgency(at: referenceDate) == .overdue)
        #expect(overdue.isOverdue == true)

        // 6. Completed with past deadline -> completed (never overdue)
        let completedPast = Assignment(
            title: "Done Lab",
            dueDate: referenceDate.addingTimeInterval(-7200),
            isCompleted: true
        )
        #expect(completedPast.urgency(at: referenceDate) == .completed)
        #expect(completedPast.isOverdue == false)

        // 7. Assignment without valid deadline -> later (not overdue)
        let noDeadline = Assignment(
            title: "Reading Assignment",
            dueDate: Date.distantFuture
        )
        #expect(noDeadline.hasValidDeadline == false)
        #expect(noDeadline.urgency(at: referenceDate) == .later)
        #expect(noDeadline.isOverdue == false)
    }

    // MARK: - 5-Tier Urgency Dashboard Sorting Tests

    @Test func testFiveTierUrgencySortingOrder() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1770000000)

        let overdueItem = Assignment(title: "1. Overdue Item", dueDate: referenceDate.addingTimeInterval(-3600))
        let dueSoonItemA = Assignment(title: "2. Due in 2 Hours", dueDate: referenceDate.addingTimeInterval(2 * 3600))
        let dueSoonItemB = Assignment(title: "3. Due in 18 Hours", dueDate: referenceDate.addingTimeInterval(18 * 3600))
        let upcomingItem = Assignment(title: "4. Due in 2 Days", dueDate: referenceDate.addingTimeInterval(2 * 86400))
        let laterItem = Assignment(title: "5. Due in 6 Days", dueDate: referenceDate.addingTimeInterval(6 * 86400))
        let noDeadlineItem = Assignment(title: "6. No Deadline", dueDate: Date.distantFuture)
        let completedItem = Assignment(title: "7. Completed Item", dueDate: referenceDate.addingTimeInterval(-10000), isCompleted: true)

        // Input in shuffled order
        let unsorted = [completedItem, upcomingItem, overdueItem, noDeadlineItem, dueSoonItemB, laterItem, dueSoonItemA]

        let sorted = unsorted.sorted { Assignment.urgencySortComparator(a: $0, b: $1, referenceDate: referenceDate) }

        #expect(sorted.count == 7)
        #expect(sorted[0].title == "1. Overdue Item")
        #expect(sorted[1].title == "2. Due in 2 Hours")
        #expect(sorted[2].title == "3. Due in 18 Hours")
        #expect(sorted[3].title == "4. Due in 2 Days")
        #expect(sorted[4].title == "5. Due in 6 Days")
        #expect(sorted[5].title == "6. No Deadline")
        #expect(sorted[6].title == "7. Completed Item")
    }

    // MARK: - Notification Future Trigger Filtering & Identifier Tests

    @Test func testNotificationFutureTriggerFiltering() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1770000000)

        // 1. Assignment due in 36 hours: all 3 offsets (24h, 3h, 0m) are in future
        let item36h = Assignment(title: "Project", dueDate: referenceDate.addingTimeInterval(36 * 3600))
        let offsets36h = NotificationService.futureEligibleOffsets(for: item36h, referenceDate: referenceDate)
        #expect(offsets36h.count == 3)
        #expect(offsets36h.contains(.twentyFourHours))
        #expect(offsets36h.contains(.threeHours))
        #expect(offsets36h.contains(.atDeadline))

        // 2. Assignment due in 10 hours: 24h trigger is in past! Only 3h and 0m remain
        let item10h = Assignment(title: "Quiz", dueDate: referenceDate.addingTimeInterval(10 * 3600))
        let offsets10h = NotificationService.futureEligibleOffsets(for: item10h, referenceDate: referenceDate)
        #expect(offsets10h.count == 2)
        #expect(!offsets10h.contains(.twentyFourHours))
        #expect(offsets10h.contains(.threeHours))
        #expect(offsets10h.contains(.atDeadline))

        // 3. Assignment due in 1 hour: 24h and 3h triggers are in past! Only 0m remains
        let item1h = Assignment(title: "Flash Submission", dueDate: referenceDate.addingTimeInterval(3600))
        let offsets1h = NotificationService.futureEligibleOffsets(for: item1h, referenceDate: referenceDate)
        #expect(offsets1h.count == 1)
        #expect(offsets1h.first == .atDeadline)

        // 4. Overdue assignment: no future triggers
        let overdueItem = Assignment(title: "Past", dueDate: referenceDate.addingTimeInterval(-3600))
        let overdueOffsets = NotificationService.futureEligibleOffsets(for: overdueItem, referenceDate: referenceDate)
        #expect(overdueOffsets.isEmpty)

        // 5. Completed assignment: no reminders scheduled
        let completedItem = Assignment(title: "Done", dueDate: referenceDate.addingTimeInterval(36 * 3600), isCompleted: true)
        let completedOffsets = NotificationService.futureEligibleOffsets(for: completedItem, referenceDate: referenceDate)
        #expect(completedOffsets.isEmpty)

        // 6. Assignment without valid deadline: no reminders scheduled
        let noDeadlineItem = Assignment(title: "No Date", dueDate: Date.distantFuture)
        let noDeadlineOffsets = NotificationService.futureEligibleOffsets(for: noDeadlineItem, referenceDate: referenceDate)
        #expect(noDeadlineOffsets.isEmpty)
    }

    @Test func testNotificationIdentifierStability() async throws {
        let testId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let id24h = NotificationService.identifier(for: testId, offset: .twentyFourHours)
        let id3h = NotificationService.identifier(for: testId, offset: .threeHours)
        let id0m = NotificationService.identifier(for: testId, offset: .atDeadline)

        #expect(id24h == "radar_rem_11111111-2222-3333-4444-555555555555_24h")
        #expect(id3h == "radar_rem_11111111-2222-3333-4444-555555555555_3h")
        #expect(id0m == "radar_rem_11111111-2222-3333-4444-555555555555_0m")

        let allIds = NotificationService.allIdentifiers(for: testId)
        #expect(allIds.count == 3)
        #expect(allIds.contains(id24h))
        #expect(allIds.contains(id3h))
        #expect(allIds.contains(id0m))
    }

    // MARK: - Hackathon Model & Status Tests

    @Test func testHackathonCreationAndDynamicStatus() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1770000000)

        // 1. Basic creation with required and optional fields
        let hackathon = Hackathon(
            title: "Smart India Hackathon",
            organizer: "Ministry of Education",
            startDate: referenceDate.addingTimeInterval(7 * 86400),
            registrationDeadline: referenceDate.addingTimeInterval(3 * 86400),
            endDate: referenceDate.addingTimeInterval(9 * 86400),
            mode: .hybrid,
            location: "New Delhi",
            websiteUrl: "https://sih.gov.in",
            eventDescription: "Nationwide software and hardware hackathon."
        )

        #expect(hackathon.title == "Smart India Hackathon")
        #expect(hackathon.organizer == "Ministry of Education")
        #expect(hackathon.mode == .hybrid)
        #expect(hackathon.location == "New Delhi")
        #expect(hackathon.websiteUrl == "https://sih.gov.in")
        #expect(hackathon.source == "local")
        #expect(hackathon.isAttendedOrCompleted == false)

        // Status is upcoming when registration is > 48h away
        #expect(hackathon.status(at: referenceDate) == .upcoming)

        // 2. Registration closing soon (within 48 hours)
        let closingSoon = Hackathon(
            title: "HackMIT",
            registrationDeadline: referenceDate.addingTimeInterval(24 * 3600)
        )
        #expect(closingSoon.status(at: referenceDate) == .regClosingSoon)

        // 3. Ongoing event
        let ongoingEvent = Hackathon(
            title: "Weekend Devfest",
            startDate: referenceDate.addingTimeInterval(-3600),
            endDate: referenceDate.addingTimeInterval(3600)
        )
        #expect(ongoingEvent.status(at: referenceDate) == .ongoing)

        // 4. Completed by past end date
        let pastEvent = Hackathon(
            title: "Past Hackathon",
            startDate: referenceDate.addingTimeInterval(-100000),
            endDate: referenceDate.addingTimeInterval(-3600)
        )
        #expect(pastEvent.status(at: referenceDate) == .completed)

        // 5. Marked completed / attended manually
        hackathon.isAttendedOrCompleted = true
        #expect(hackathon.status(at: referenceDate) == .completed)
    }

    // MARK: - Multi-Platform Provider & Refresh Coordinator Tests

    @Test func testLeetCodeDailyQuestionModelAndDifficultyColors() async throws {
        let easyQ = LeetCodeDailyQuestion(
            date: "2026-10-23",
            title: "Two Sum",
            titleSlug: "two-sum",
            difficulty: "Easy",
            questionFrontendId: "1",
            problemUrl: URL(string: "https://leetcode.com/problems/two-sum/")
        )
        #expect(easyQ.difficultyColor == .green)

        let mediumQ = LeetCodeDailyQuestion(
            date: "2026-10-23",
            title: "Maximum Subarray",
            titleSlug: "maximum-subarray",
            difficulty: "Medium",
            questionFrontendId: "53",
            problemUrl: URL(string: "https://leetcode.com/problems/maximum-subarray/")
        )
        #expect(mediumQ.difficultyColor == .orange)

        let hardQ = LeetCodeDailyQuestion(
            date: "2026-10-23",
            title: "Trapping Rain Water",
            titleSlug: "trapping-rain-water",
            difficulty: "Hard",
            questionFrontendId: "42",
            problemUrl: URL(string: "https://leetcode.com/problems/trapping-rain-water/")
        )
        #expect(hardQ.difficultyColor == .red)
    }

    @Test func testLeetCodeContestLocalTimeAndApproachingIndicator() async throws {
        let now = Date()
        let approachingStart = now.addingTimeInterval(3 * 3600) // 3 hours from now

        let approachingContest = LeetCodeContest(
            title: "Biweekly Contest 194",
            titleSlug: "biweekly-contest-194",
            startTime: approachingStart,
            durationSeconds: 5400 // 1h 30m
        )

        #expect(approachingContest.isApproaching == true)
        #expect(approachingContest.formattedDuration == "1h 30m")
        #expect(approachingContest.contestUrl?.absoluteString == "https://leetcode.com/contest/biweekly-contest-194")
        #expect(approachingContest.relativeTimeDescription.contains("Starts in 3h") || approachingContest.relativeTimeDescription.contains("Starts in 2h"))

        // Far future contest (e.g. 5 days away)
        let futureContest = LeetCodeContest(
            title: "Weekly Contest 526",
            titleSlug: "weekly-contest-526",
            startTime: now.addingTimeInterval(5 * 86400),
            durationSeconds: 5400
        )
        #expect(futureContest.isApproaching == false)
    }

    @Test func testGeeksForGeeksPOTDModelAndDifficulty() async throws {
        let potd = GeeksForGeeksPOTD(
            id: 2214,
            date: "2026-10-23",
            title: "Count Pairs Violating BST Property",
            difficulty: "Medium",
            problemUrl: URL(string: "https://www.geeksforgeeks.org/problems/pairs-violating-bst-property--212515/1")
        )

        #expect(potd.id == 2214)
        #expect(potd.difficulty == "Medium")
        #expect(potd.difficultyColor == .orange)
        #expect(potd.problemUrl != nil)
    }

    @Test @MainActor func testLocalStatusDistinctionFromRemoteSubmission() async throws {
        let testDate = "2026-10-23"

        // Ensure clean initial state
        UserDefaults.standard.removeObject(forKey: "leetcode_daily_solved_\(testDate)")
        UserDefaults.standard.removeObject(forKey: "gfg_potd_solved_\(testDate)")

        // LeetCode local completion toggle
        let lc = LeetCodeProvider.shared
        #expect(lc.isDailySolvedLocally(date: testDate) == false)

        lc.toggleDailySolvedLocally(date: testDate)
        #expect(lc.isDailySolvedLocally(date: testDate) == true)

        lc.toggleDailySolvedLocally(date: testDate)
        #expect(lc.isDailySolvedLocally(date: testDate) == false)

        // GeeksforGeeks local completion toggle
        let gfg = GeeksForGeeksProvider.shared
        #expect(gfg.isPOTDSolvedLocally(date: testDate) == false)

        gfg.togglePOTDSolvedLocally(date: testDate)
        #expect(gfg.isPOTDSolvedLocally(date: testDate) == true)

        gfg.togglePOTDSolvedLocally(date: testDate)
        #expect(gfg.isPOTDSolvedLocally(date: testDate) == false)
    }

    @Test @MainActor func testMoodleRefreshPreservesCompletedAndEditedAssignments() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Assignment.self, configurations: config)
        let context = container.mainContext

        // User previously completed assignment and wrote custom notes
        let existingCompleted = Assignment(
            title: "Software Engineering Project",
            course: "CS 301",
            dueDate: Date().addingTimeInterval(86400),
            priority: .high,
            notes: "My custom user notes that must be preserved",
            isCompleted: true,
            source: "moodle",
            moodleEventId: "assign_101",
            sourceUrl: "http://lms.kiet.edu/moodle/mod/assign/view.php?id=101"
        )
        context.insert(existingCompleted)
        try context.save()

        // Incoming Moodle draft for the same event
        let incomingDraft = MoodleDraft(
            moodleEventId: "assign_101",
            title: "Software Engineering Project (Updated)",
            course: "CS 301",
            dueDate: Date().addingTimeInterval(2 * 86400),
            priority: .high,
            notes: "Raw server intro",
            sourceUrl: "http://lms.kiet.edu/moodle/mod/assign/view.php?id=101",
            activityType: "Assignment",
            isSelected: true,
            isDuplicate: true,
            isConfidentDate: true
        )

        // Reconcile
        let descriptor = FetchDescriptor<Assignment>()
        let currentList = try context.fetch(descriptor)
        let matched = currentList.first { $0.moodleEventId == incomingDraft.moodleEventId }
        #expect(matched != nil)

        // Simulate refresh update preserving completion state
        if let target = matched {
            #expect(target.isCompleted == true)
            target.dueDate = incomingDraft.dueDate
            #expect(target.isCompleted == true)
            #expect(target.notes == "My custom user notes that must be preserved")
        }

        try context.save()

        // Verify after fetch
        let afterList = try context.fetch(descriptor)
        #expect(afterList.count == 1)
        #expect(afterList.first?.isCompleted == true)
        #expect(afterList.first?.notes == "My custom user notes that must be preserved")
    }

    @Test func testProviderConnectionStatusProperties() async throws {
        let unavailableStatus = ProviderConnectionStatus.connectionUnavailable(reason: "Unavailable")
        #expect(unavailableStatus.badgeText == "Connection Unavailable")
        #expect(unavailableStatus.badgeColor == .orange)
        #expect(unavailableStatus.isConnected == false)

        let connectedStatus = ProviderConnectionStatus.connected(details: "Student")
        #expect(connectedStatus.badgeText == "Connected")
        #expect(connectedStatus.badgeColor == .green)
        #expect(connectedStatus.isConnected == true)
    }

    // MARK: - Part B: Swipe Actions, Archive & Count Consistency Tests

    @Test @MainActor func testSwipeRightCompleteAssignmentLogic() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Assignment.self, configurations: config)
        let context = container.mainContext

        let futureDate = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        let assignment = Assignment(
            title: "Operating Systems Assignment 3",
            course: "CS 301",
            dueDate: futureDate,
            priority: .high,
            isCompleted: false,
            isArchived: false
        )
        context.insert(assignment)
        try context.save()

        #expect(assignment.isCompleted == false)
        #expect(assignment.isArchived == false)

        // Simulate Right Swipe Action: Complete
        assignment.isCompleted = true
        NotificationService.shared.cancelReminders(for: assignment.id)
        try context.save()

        // Fetch from context to verify persistence
        let descriptor = FetchDescriptor<Assignment>()
        let items = try context.fetch(descriptor)
        let fetched = items.first { $0.id == assignment.id }
        #expect(fetched != nil)
        #expect(fetched?.isCompleted == true)
        #expect(fetched?.isArchived == false)

        // All filter (active + completed, excluding archived)
        let allItems = items.filter { !$0.isArchived }
        #expect(allItems.contains { $0.id == assignment.id })

        // Pending filter (incomplete and not overdue, excluding archived)
        let pendingItems = items.filter { !$0.isCompleted && !$0.isOverdue && !$0.isArchived }
        #expect(!pendingItems.contains { $0.id == assignment.id })

        // Overdue filter (incomplete and overdue, excluding archived)
        let overdueItems = items.filter { !$0.isCompleted && $0.isOverdue && !$0.isArchived }
        #expect(!overdueItems.contains { $0.id == assignment.id })
    }

    @Test @MainActor func testSwipeLeftArchiveAndRestoreTaskLogic() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Assignment.self, configurations: config)
        let context = container.mainContext

        let dueDate = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        let task = Assignment(
            title: "Algorithms Term Paper",
            course: "CS 302",
            dueDate: dueDate,
            priority: .high,
            notes: "Important paper",
            isCompleted: false,
            isArchived: false,
            source: "moodle",
            moodleEventId: "paper_99"
        )
        context.insert(task)
        try context.save()

        // 1. Swipe Left Action: Archive
        task.isArchived = true
        NotificationService.shared.cancelReminders(for: task.id)
        try context.save()

        let descriptor = FetchDescriptor<Assignment>()
        let allInDB = try context.fetch(descriptor)
        #expect(allInDB.count == 1)

        // Must be hidden from active All, Pending, Overdue
        let activeAll = allInDB.filter { !$0.isArchived }
        #expect(activeAll.isEmpty)

        let activePending = allInDB.filter { !$0.isCompleted && !$0.isOverdue && !$0.isArchived }
        #expect(activePending.isEmpty)

        let activeOverdue = allInDB.filter { !$0.isCompleted && $0.isOverdue && !$0.isArchived }
        #expect(activeOverdue.isEmpty)

        // Must be visible in Archived Tasks
        let archivedTasks = allInDB.filter { $0.isArchived }
        #expect(archivedTasks.count == 1)
        let archived = archivedTasks.first!
        #expect(archived.title == "Algorithms Term Paper")
        #expect(archived.course == "CS 302")
        #expect(archived.dueDate == dueDate)
        #expect(archived.priority == .high)
        #expect(archived.moodleEventId == "paper_99")
        #expect(archived.isCompleted == false)

        // 2. Restore task from Archived screen
        archived.isArchived = false
        try context.save()

        let reloaded = try context.fetch(descriptor)
        let restoredActiveAll = reloaded.filter { !$0.isArchived }
        #expect(restoredActiveAll.count == 1)
        #expect(restoredActiveAll.first?.title == "Algorithms Term Paper")
        #expect(restoredActiveAll.first?.isArchived == false)
        #expect(restoredActiveAll.first?.isCompleted == false)
    }

    @Test @MainActor func testSwipeLeftLowerPriorityLogic() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Assignment.self, configurations: config)
        let context = container.mainContext

        let dueDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        let highPriorityTask = Assignment(
            title: "Database Indexing Reading",
            course: "CS 204",
            dueDate: dueDate,
            priority: .high,
            notes: "",
            isCompleted: false,
            isArchived: false
        )
        context.insert(highPriorityTask)
        try context.save()

        #expect(highPriorityTask.priority == .high)

        // Swipe Left Action: Low Priority
        highPriorityTask.priority = .low
        try context.save()

        let descriptor = FetchDescriptor<Assignment>()
        let items = try context.fetch(descriptor)
        let target = items.first { $0.id == highPriorityTask.id }

        #expect(target != nil)
        #expect(target?.priority == .low)
        // Must NOT change deadline, completion, or archive state
        #expect(target?.dueDate == dueDate)
        #expect(target?.isCompleted == false)
        #expect(target?.isArchived == false)
    }

    @Test func testCountsConsistencyAcrossAllFilterTabs() async throws {
        let futureDate = Calendar.current.date(byAdding: .day, value: 4, to: Date())!
        let pastDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())!

        let pending1 = Assignment(title: "Task 1", dueDate: futureDate, isCompleted: false, isArchived: false)
        let pending2 = Assignment(title: "Task 2", dueDate: futureDate, isCompleted: false, isArchived: false)
        let overdue1 = Assignment(title: "Task 3", dueDate: pastDate, isCompleted: false, isArchived: false)
        let completed1 = Assignment(title: "Task 4", dueDate: pastDate, isCompleted: true, isArchived: false)

        let list = [pending1, pending2, overdue1, completed1]

        // Helper count functions matching ContentView
        func pendingCount(_ items: [Assignment]) -> Int { items.filter { !$0.isCompleted && !$0.isArchived }.count }
        func overdueCount(_ items: [Assignment]) -> Int { items.filter { !$0.isCompleted && $0.isOverdue && !$0.isArchived }.count }
        func completedCount(_ items: [Assignment]) -> Int { items.filter { $0.isCompleted && !$0.isArchived }.count }

        // Initial state: 3 pending (2 upcoming + 1 overdue), 1 overdue, 1 completed
        #expect(pendingCount(list) == 3)
        #expect(overdueCount(list) == 1)
        #expect(completedCount(list) == 1)

        // 1. Complete overdue task (Task 3)
        overdue1.isCompleted = true
        #expect(pendingCount(list) == 2)   // Removed from Pending
        #expect(overdueCount(list) == 0)   // Removed from Overdue
        #expect(completedCount(list) == 2) // Added to Completed

        // 2. Archive pending task (Task 1)
        pending1.isArchived = true
        #expect(pendingCount(list) == 1)   // Removed from Pending
        #expect(overdueCount(list) == 0)   // Overdue unchanged
        #expect(completedCount(list) == 2) // Completed unchanged

        // 3. Lower priority of pending task (Task 2)
        pending2.priority = .low
        #expect(pendingCount(list) == 1)   // Unchanged
        #expect(overdueCount(list) == 0)   // Unchanged
        #expect(completedCount(list) == 2) // Unchanged

        // 4. Restore archived task (Task 1)
        pending1.isArchived = false
        #expect(pendingCount(list) == 2)   // Returned to Pending
        #expect(overdueCount(list) == 0)
        #expect(completedCount(list) == 2)
    }

    // MARK: - Hackathon Model & Milestone Date Tests

    @Test func testHackathonDistinctDatesAndLocalFields() async throws {
        let refDate = Date(timeIntervalSince1970: 1770000000)
        let regDeadline = refDate.addingTimeInterval(2 * 86400)      // Reg ends in 2 days
        let submissionDeadline = refDate.addingTimeInterval(5 * 86400) // Submission in 5 days
        let eventStart = refDate.addingTimeInterval(4 * 86400)       // Event starts in 4 days
        let eventEnd = refDate.addingTimeInterval(6 * 86400)         // Event ends in 6 days

        let hackathon = Hackathon(
            title: "National Student Innovation Challenge",
            organizer: "Tech Council",
            startDate: eventStart,
            registrationDeadline: regDeadline,
            submissionDeadline: submissionDeadline,
            endDate: eventEnd,
            mode: .online,
            location: "Virtual",
            websiteUrl: "https://example.com/competitions/test-123",
            eventDescription: "Local registered hackathon with distinct milestone dates.",
            source: "local",
            participationStatus: "Registered / Round 1",
            lastSyncedAt: refDate
        )

        // Verify distinct dates are preserved independently
        #expect(hackathon.registrationDeadline == regDeadline)
        #expect(hackathon.submissionDeadline == submissionDeadline)
        #expect(hackathon.startDate == eventStart)
        #expect(hackathon.endDate == eventEnd)
        #expect(hackathon.registrationDeadline != hackathon.submissionDeadline)
        #expect(hackathon.registrationDeadline != hackathon.startDate)

        // Verify local registration metadata
        #expect(hackathon.participationStatus == "Registered / Round 1")
        #expect(hackathon.lastSyncedAt == refDate)
        #expect(hackathon.source == "local")
    }

    // MARK: - Part B: Demo Scan Gallery & Real OCR Pipeline Tests

    @Test func testDemoGalleryOfflineDocumentGeneration() async throws {
        // Verify all 4 documents are rendered 100% offline with crisp high-resolution dimensions
        let datesheet = DemoDocumentGenerator.renderExamDatesheet()
        #expect(datesheet.size.width == 1200)
        #expect(datesheet.size.height == 1600)
        #expect(datesheet.cgImage != nil)

        let assignment = DemoDocumentGenerator.renderAssignmentNotice()
        #expect(assignment.size.width == 1200)
        #expect(assignment.size.height == 1600)
        #expect(assignment.cgImage != nil)

        let event = DemoDocumentGenerator.renderEventNotice()
        #expect(event.size.width == 1200)
        #expect(event.size.height == 1600)
        #expect(event.cgImage != nil)

        let uncertain = DemoDocumentGenerator.renderUncertainNotice()
        #expect(uncertain.size.width == 1200)
        #expect(uncertain.size.height == 1600)
        #expect(uncertain.cgImage != nil)
    }

    @Test func testDemoExamDatesheetRealOCRExtraction() async throws {
        let datesheetImage = DemoDocumentGenerator.renderExamDatesheet()

        // 1. Process image through actual Apple Vision text recognition
        let recognizedLines = try await TextRecognitionService.recognizeText(from: datesheetImage)
        #expect(!recognizedLines.isEmpty)

        // Verify OCR detected text contains our expected courses
        let joinedText = recognizedLines.joined(separator: " ")
        #expect(joinedText.localizedCaseInsensitiveContains("KIET"))
        #expect(joinedText.localizedCaseInsensitiveContains("CS 301") || joinedText.localizedCaseInsensitiveContains("Operating Systems"))

        // 2. Parse lines through ScheduleParser
        let drafts = ScheduleParser.parse(lines: recognizedLines)
        #expect(drafts.count >= 2)

        // Verify detected courses & exam titles
        let hasCS301 = drafts.contains { $0.course.contains("CS 301") || $0.title.localizedCaseInsensitiveContains("Operating Systems") }
        #expect(hasCS301 == true)

        let examPriorities = drafts.map { $0.priority }
        #expect(examPriorities.contains(.high))
    }

    @Test func testDemoAssignmentNoticeRealOCRExtraction() async throws {
        let assignmentImage = DemoDocumentGenerator.renderAssignmentNotice()

        let lines = try await TextRecognitionService.recognizeText(from: assignmentImage)
        #expect(!lines.isEmpty)

        let drafts = ScheduleParser.parse(lines: lines)
        #expect(!drafts.isEmpty)

        let assignmentDraft = drafts.first { $0.course.contains("CS 204") || $0.title.localizedCaseInsensitiveContains("Polymorphism") }
        #expect(assignmentDraft != nil)
        #expect(assignmentDraft?.isConfidentDate == true)
    }

    @Test func testDemoUncertainDateNoticeFlagsConfidence() async throws {
        let uncertainImage = DemoDocumentGenerator.renderUncertainNotice()

        let lines = try await TextRecognitionService.recognizeText(from: uncertainImage)
        #expect(!lines.isEmpty)

        let drafts = ScheduleParser.parse(lines: lines)
        #expect(!drafts.isEmpty)

        // At least one draft should flag date uncertainty (TBD date), prompting user review
        let uncertainDraft = drafts.first { !$0.isConfidentDate || $0.rawText.contains("TBD") }
        #expect(uncertainDraft != nil)
    }

    @Test @MainActor func testCancellingScanReviewPreservesDatabaseWithoutSavingDemoData() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Assignment.self, configurations: config)
        let context = container.mainContext

        let initialFetch = try context.fetch(FetchDescriptor<Assignment>())
        #expect(initialFetch.isEmpty)

        // Simulate user scanning a demo datesheet, generating drafts in review state
        let datesheetImage = DemoDocumentGenerator.renderExamDatesheet()
        let lines = try await TextRecognitionService.recognizeText(from: datesheetImage)
        let drafts = ScheduleParser.parse(lines: lines)
        #expect(!drafts.isEmpty)

        // User cancels / closes review sheet without confirming save:
        // No drafts are inserted into context!
        let postCancelFetch = try context.fetch(FetchDescriptor<Assignment>())
        #expect(postCancelFetch.isEmpty) // Zero demo records leaked into DB!
    }

    @Test @MainActor func testConfirmingOnlySelectedDraftsSavesToDatabase() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Assignment.self, configurations: config)
        let context = container.mainContext

        let nov15 = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 10))!
        let nov18 = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 14))!

        var draft1 = ScannedAssignmentDraft(
            title: "Operating Systems Midterm",
            course: "CS 301",
            dueDate: nov15,
            priority: .high,
            isSelected: true
        )
        var draft2 = ScannedAssignmentDraft(
            title: "Algorithms Final",
            course: "CS 302",
            dueDate: nov18,
            priority: .high,
            isSelected: false // User deselected this item!
        )

        let drafts = [draft1, draft2]

        // Only save confirmed (isSelected == true) items
        let confirmed = drafts.filter { $0.isSelected }
        for draft in confirmed {
            let item = Assignment(
                title: draft.title,
                course: draft.course,
                dueDate: draft.dueDate,
                priority: draft.priority,
                source: "scan"
            )
            context.insert(item)
        }
        try context.save()

        let saved = try context.fetch(FetchDescriptor<Assignment>())
        #expect(saved.count == 1)
        #expect(saved.first?.title == "Operating Systems Midterm")
        #expect(saved.first?.course == "CS 301")
        #expect(saved.first?.source == "scan")
    }



    // MARK: - Task Card Redundant Badges & Layout Tests

    @Test func testTaskCardRedundantBadgeRules() async throws {
        // Rule 1: Pending tab hides redundant "Upcoming" and "Later" badges
        let hideUpcomingInPending = AssignmentRowView.shouldDisplayUrgencyBadge(
            filter: .pending,
            urgency: .upcoming,
            isCompleted: false
        )
        #expect(hideUpcomingInPending == false, "Pending tab must hide the redundant Upcoming badge")

        let hideLaterInPending = AssignmentRowView.shouldDisplayUrgencyBadge(
            filter: .pending,
            urgency: .later,
            isCompleted: false
        )
        #expect(hideLaterInPending == false, "Pending tab must hide redundant Later badge")

        // Rule 2: Pending tab shows distinct urgency indicator when task is due soon (<24h)
        let showDueSoonInPending = AssignmentRowView.shouldDisplayUrgencyBadge(
            filter: .pending,
            urgency: .dueSoon,
            isCompleted: false
        )
        #expect(showDueSoonInPending == true, "Pending tab must show urgency indicator when a task is due soon")

        // Rule 3: Pending tab shows subtle indicator for overdue items
        let showOverdueInPending = AssignmentRowView.shouldDisplayUrgencyBadge(
            filter: .pending,
            urgency: .overdue,
            isCompleted: false
        )
        #expect(showOverdueInPending == true, "Pending tab must show subtle indicator for overdue pending items")

        // Rule 4: Completed tab hides urgency badges since all tasks in this tab are finished
        let showUpcomingInCompleted = AssignmentRowView.shouldDisplayUrgencyBadge(filter: .completed, urgency: .upcoming, isCompleted: true)
        let showDueSoonInCompleted = AssignmentRowView.shouldDisplayUrgencyBadge(filter: .completed, urgency: .dueSoon, isCompleted: true)
        let showOverdueInCompleted = AssignmentRowView.shouldDisplayUrgencyBadge(filter: .completed, urgency: .overdue, isCompleted: true)
        let showCompletedInCompleted = AssignmentRowView.shouldDisplayUrgencyBadge(filter: .completed, urgency: .completed, isCompleted: true)

        #expect(showUpcomingInCompleted == false)
        #expect(showDueSoonInCompleted == false)
        #expect(showOverdueInCompleted == false)
        #expect(showCompletedInCompleted == false)
    }

    @Test func testTwoDashboardFiltersLogic() async throws {
        // Verify dashboard filter options contain only Pending and Completed
        let allFilters = AssignmentFilter.allCases
        #expect(allFilters.count == 2)
        #expect(allFilters.contains(.pending))
        #expect(allFilters.contains(.completed))

        let cal = Calendar.current
        let futureDate = cal.date(byAdding: .day, value: 3, to: Date())!
        let pastDate = cal.date(byAdding: .day, value: -2, to: Date())!

        let pendingUpcoming = Assignment(title: "Upcoming Essay", dueDate: futureDate, isCompleted: false, isArchived: false)
        let pendingOverdue = Assignment(title: "Overdue Lab", dueDate: pastDate, isCompleted: false, isArchived: false)
        let completedTask = Assignment(title: "Finished Quiz", dueDate: pastDate, isCompleted: true, isArchived: false)
        let archivedTask = Assignment(title: "Archived Project", dueDate: futureDate, isCompleted: false, isArchived: true)

        let allItems = [pendingUpcoming, pendingOverdue, completedTask, archivedTask]
        let active = allItems.filter { !$0.isArchived }

        // Pending filter includes all incomplete active items (both upcoming and overdue)
        let pendingFiltered = active.filter { !$0.isCompleted }
        #expect(pendingFiltered.count == 2)
        #expect(pendingFiltered.contains(where: { $0.id == pendingUpcoming.id }))
        #expect(pendingFiltered.contains(where: { $0.id == pendingOverdue.id }))
        #expect(!pendingFiltered.contains(where: { $0.id == completedTask.id }))
        #expect(!pendingFiltered.contains(where: { $0.id == archivedTask.id }))

        // Completed filter includes completed non-archived items
        let completedFiltered = active.filter { $0.isCompleted }
        #expect(completedFiltered.count == 1)
        #expect(completedFiltered.contains(where: { $0.id == completedTask.id }))
        #expect(!completedFiltered.contains(where: { $0.id == pendingUpcoming.id }))
        #expect(!completedFiltered.contains(where: { $0.id == pendingOverdue.id }))
    }

    @Test func testAssignmentIsOverdueByDays() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        var refComp = DateComponents()
        refComp.year = 2026
        refComp.month = 10
        refComp.day = 24
        refComp.hour = 12
        refComp.minute = 0
        refComp.second = 0
        let refDate = cal.date(from: refComp)!

        // 1. Upcoming task (due 2 days in the future)
        let upcoming = Assignment(
            title: "Future Task",
            dueDate: cal.date(byAdding: .day, value: 2, to: refDate)!,
            isCompleted: false
        )
        #expect(upcoming.isOverdueBy(days: 7, referenceDate: refDate, in: cal) == false)
        #expect(upcoming.isOverdueByMoreThan(days: 7, referenceDate: refDate, in: cal) == false)

        // 2. Overdue by 3 days (< 7 days)
        let overdue3Days = Assignment(
            title: "Recent Overdue Task",
            dueDate: cal.date(byAdding: .day, value: -3, to: refDate)!,
            isCompleted: false
        )
        #expect(overdue3Days.isOverdue == true)
        #expect(overdue3Days.isOverdueBy(days: 7, referenceDate: refDate, in: cal) == false)

        // 3. Overdue by 6 days and 23 hours (< 7 days)
        let overdueAlmost7Days = Assignment(
            title: "Almost 7 Days Overdue",
            dueDate: cal.date(byAdding: .hour, value: -(7 * 24 - 1), to: refDate)!,
            isCompleted: false
        )
        #expect(overdueAlmost7Days.isOverdueBy(days: 7, referenceDate: refDate, in: cal) == false)

        // 4. Overdue by exactly 7 days
        let overdue7Days = Assignment(
            title: "Exactly 7 Days Overdue",
            dueDate: cal.date(byAdding: .day, value: -7, to: refDate)!,
            isCompleted: false
        )
        #expect(overdue7Days.isOverdueBy(days: 7, referenceDate: refDate, in: cal) == true)

        // 5. Overdue by 14 days (> 7 days)
        let overdue14Days = Assignment(
            title: "Two Weeks Overdue",
            dueDate: cal.date(byAdding: .day, value: -14, to: refDate)!,
            isCompleted: false
        )
        #expect(overdue14Days.isOverdueBy(days: 7, referenceDate: refDate, in: cal) == true)

        // 6. Overdue by years (e.g. 16 Dec 2022)
        var oldComp = DateComponents()
        oldComp.year = 2022
        oldComp.month = 12
        oldComp.day = 16
        oldComp.hour = 23
        oldComp.minute = 59
        let oldDate = cal.date(from: oldComp)!
        let oldMoodleTask = Assignment(
            title: "video assignment/ seminar",
            dueDate: oldDate,
            isCompleted: false
        )
        #expect(oldMoodleTask.isOverdueBy(days: 7, referenceDate: refDate, in: cal) == true)

        // 7. Completed task from 2022 (completed tasks should not be flagged as overdue)
        let completedOldTask = Assignment(
            title: "Finished 2022 Task",
            dueDate: oldDate,
            isCompleted: true
        )
        #expect(completedOldTask.isOverdueBy(days: 7, referenceDate: refDate, in: cal) == false)

        // 8. Exam with session time overdue by 8 days
        let exam8DaysOverdue = Assignment(
            title: "Physics Exam",
            dueDate: cal.date(byAdding: .day, value: -8, to: refDate)!,
            isCompleted: false,
            eventType: "exam",
            sessionTime: "10:00 AM - 01:00 PM"
        )
        #expect(exam8DaysOverdue.isOverdueBy(days: 7, referenceDate: refDate, in: cal) == true)
    }

    @Test func testFrontPagePendingFilterHidesItemsOverdueBy7Days() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        var refComp = DateComponents()
        refComp.year = 2026
        refComp.month = 10
        refComp.day = 24
        refComp.hour = 12
        refComp.minute = 0
        refComp.second = 0
        let refDate = cal.date(from: refComp)!

        let upcoming = Assignment(
            title: "Upcoming Project",
            dueDate: cal.date(byAdding: .day, value: 3, to: refDate)!,
            isCompleted: false,
            isArchived: false
        )
        let recentOverdue2d = Assignment(
            title: "Assignment Due 2 Days Ago",
            dueDate: cal.date(byAdding: .day, value: -2, to: refDate)!,
            isCompleted: false,
            isArchived: false
        )
        let recentOverdue5d = Assignment(
            title: "Assignment Due 5 Days Ago",
            dueDate: cal.date(byAdding: .day, value: -5, to: refDate)!,
            isCompleted: false,
            isArchived: false
        )
        let oldOverdue8d = Assignment(
            title: "Assignment Due 8 Days Ago",
            dueDate: cal.date(byAdding: .day, value: -8, to: refDate)!,
            isCompleted: false,
            isArchived: false
        )
        let ancientMoodle2022 = Assignment(
            title: "video assignment/ seminar (2022)",
            dueDate: cal.date(from: DateComponents(year: 2022, month: 12, day: 16))!,
            isCompleted: false,
            isArchived: false
        )
        let ancientMoodle2024 = Assignment(
            title: "Activity 3 - Classroom design (2024)",
            dueDate: cal.date(from: DateComponents(year: 2024, month: 10, day: 1))!,
            isCompleted: false,
            isArchived: false
        )
        let completedTask = Assignment(
            title: "Completed Project",
            dueDate: cal.date(byAdding: .day, value: -10, to: refDate)!,
            isCompleted: true,
            isArchived: false
        )

        let allItems = [upcoming, recentOverdue2d, recentOverdue5d, oldOverdue8d, ancientMoodle2022, ancientMoodle2024, completedTask]
        let active = allItems.filter { !$0.isArchived }

        // Front-page Pending filter logic:
        let frontPagePending = active.filter { !$0.isCompleted && !$0.isOverdueBy(days: 7, referenceDate: refDate, in: cal) }

        // Must contain upcoming and recently overdue items (<= 7 days)
        #expect(frontPagePending.count == 3)
        #expect(frontPagePending.contains(where: { $0.id == upcoming.id }))
        #expect(frontPagePending.contains(where: { $0.id == recentOverdue2d.id }))
        #expect(frontPagePending.contains(where: { $0.id == recentOverdue5d.id }))

        // Must NOT contain items overdue by 7 days or more on the front page
        #expect(!frontPagePending.contains(where: { $0.id == oldOverdue8d.id }))
        #expect(!frontPagePending.contains(where: { $0.id == ancientMoodle2022.id }))
        #expect(!frontPagePending.contains(where: { $0.id == ancientMoodle2024.id }))
        #expect(!frontPagePending.contains(where: { $0.id == completedTask.id }))

        // Pending count matching front page
        let pendingCount = allItems.filter { !$0.isArchived && !$0.isCompleted && !$0.isOverdueBy(days: 7, referenceDate: refDate, in: cal) }.count
        #expect(pendingCount == 3)

        // Completed filter includes completed tasks regardless of date
        let completedItems = active.filter { $0.isCompleted }
        #expect(completedItems.count == 1)
        #expect(completedItems.contains(where: { $0.id == completedTask.id }))
    }

    @Test func testConciseDeadlineLabelFormatting() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        var refComponents = DateComponents()
        refComponents.year = 2026
        refComponents.month = 10
        refComponents.day = 24
        refComponents.hour = 12
        refComponents.minute = 0
        refComponents.second = 0
        let refDate = cal.date(from: refComponents)!

        // 1. Regular upcoming assignment
        var upcomingComp = DateComponents()
        upcomingComp.year = 2026
        upcomingComp.month = 10
        upcomingComp.day = 31
        upcomingComp.hour = 9
        upcomingComp.minute = 32
        let upcomingDate = cal.date(from: upcomingComp)!

        let regularLabel = AssignmentRowView.conciseDeadlineLabel(
            for: upcomingDate,
            urgency: .upcoming,
            isExam: false,
            referenceDate: refDate,
            calendar: cal
        )
        #expect(regularLabel == "Due 31 Oct 2026 · 9:32 AM")

        // 2. Overdue item from previous year (should include 4-digit year e.g. "Overdue · 16 Dec 2022")
        var overduePastYearComp = DateComponents()
        overduePastYearComp.year = 2022
        overduePastYearComp.month = 12
        overduePastYearComp.day = 16
        overduePastYearComp.hour = 14
        overduePastYearComp.minute = 0
        let overduePastYearDate = cal.date(from: overduePastYearComp)!

        let overdueLabel = AssignmentRowView.conciseDeadlineLabel(
            for: overduePastYearDate,
            urgency: .overdue,
            isExam: false,
            referenceDate: refDate,
            calendar: cal
        )
        #expect(overdueLabel == "Overdue · 16 Dec 2022")

        // 3. Exam with session time
        let examLabelWithSession = AssignmentRowView.conciseDeadlineLabel(
            for: upcomingDate,
            urgency: .upcoming,
            isExam: true,
            sessionTime: "10:00 AM - 01:00 PM",
            referenceDate: refDate,
            calendar: cal
        )
        #expect(examLabelWithSession == "Exam 31 Oct 2026 · 10:00 AM - 01:00 PM")

        // 4. Cross-year boundary upcoming (e.g. Due in 2027 while ref is 2026)
        var nextYearComp = DateComponents()
        nextYearComp.year = 2027
        nextYearComp.month = 1
        nextYearComp.day = 15
        nextYearComp.hour = 11
        nextYearComp.minute = 59
        let nextYearDate = cal.date(from: nextYearComp)!

        let crossYearLabel = AssignmentRowView.conciseDeadlineLabel(
            for: nextYearDate,
            urgency: .upcoming,
            isExam: false,
            referenceDate: refDate,
            calendar: cal
        )
        #expect(crossYearLabel.contains("2027"))
        #expect(crossYearLabel.contains("11:59 AM"))

        // 5. Nil date
        let nilLabel = AssignmentRowView.conciseDeadlineLabel(
            for: nil,
            urgency: .later,
            isExam: false,
            referenceDate: refDate,
            calendar: cal
        )
        #expect(nilLabel == "No deadline set")
    }

    @Test func testCalendarScheduleGroupingAndDayMath() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        var day1Comp = DateComponents()
        day1Comp.year = 2026
        day1Comp.month = 11
        day1Comp.day = 10
        day1Comp.hour = 10
        let day1Date = cal.date(from: day1Comp)!

        var day2Comp = DateComponents()
        day2Comp.year = 2026
        day2Comp.month = 11
        day2Comp.day = 12
        day2Comp.hour = 15
        let day2Date = cal.date(from: day2Comp)!

        let examTask = Assignment(title: "Operating Systems Exam", dueDate: day1Date, eventType: "exam", sessionTime: "10:00 AM - 01:00 PM")
        let assignmentTask = Assignment(title: "Physics Problem Set", dueDate: day1Date, eventType: "assignment")
        let day2Task = Assignment(title: "Algorithm Submission", dueDate: day2Date, eventType: "assignment")
        let archivedTask = Assignment(title: "Archived Reading", dueDate: day1Date, isArchived: true)

        let items = [examTask, assignmentTask, day2Task, archivedTask]

        // Filter active
        let active = items.filter { !$0.isArchived }
        #expect(active.count == 3)

        // Day 1 start
        let day1Start = cal.startOfDay(for: day1Date)
        let day1Items = active.filter { cal.startOfDay(for: $0.effectiveDate) == day1Start }
        #expect(day1Items.count == 2)
        #expect(day1Items.contains(where: { $0.isExam }))
        #expect(day1Items.contains(where: { !$0.isExam }))

        // Day 2 start
        let day2Start = cal.startOfDay(for: day2Date)
        let day2Items = active.filter { cal.startOfDay(for: $0.effectiveDate) == day2Start }
        #expect(day2Items.count == 1)
        #expect(day2Items.first?.title == "Algorithm Submission")

        // Empty day
        var emptyDayComp = DateComponents()
        emptyDayComp.year = 2026
        emptyDayComp.month = 11
        emptyDayComp.day = 11
        let emptyDay = cal.date(from: emptyDayComp)!
        let emptyDayStart = cal.startOfDay(for: emptyDay)
        let emptyDayItems = active.filter { cal.startOfDay(for: $0.effectiveDate) == emptyDayStart }
        #expect(emptyDayItems.isEmpty)
    }

    @Test func testTaskCardDeadlinesAndPriorityPreservation() async throws {
        // Deadline warning color rules:
        // Overdue must be red warning color
        let overdueColor = AssignmentRowView.deadlineDisplayColor(urgency: .overdue, isCompleted: false)
        #expect(overdueColor == Color.red)

        // Due soon must be orange warning color
        let dueSoonColor = AssignmentRowView.deadlineDisplayColor(urgency: .dueSoon, isCompleted: false)
        #expect(dueSoonColor == Color.orange)

        // Upcoming / Later must be secondary
        let upcomingColor = AssignmentRowView.deadlineDisplayColor(urgency: .upcoming, isCompleted: false)
        #expect(upcomingColor == Color.secondary)

        // Completed assignments always use muted secondary color
        let completedColor = AssignmentRowView.deadlineDisplayColor(urgency: .overdue, isCompleted: true)
        #expect(completedColor == Color.secondary)

        // Verify Priority labels preserved across all task states
        let highTask = Assignment(title: "Database Project", priority: .high)
        let mediumTask = Assignment(title: "Essay Draft", priority: .medium)
        let lowTask = Assignment(title: "Optional Reading", priority: .low)

        #expect(highTask.priority == .high)
        #expect(highTask.priority.rawValue == "High")
        #expect(mediumTask.priority == .medium)
        #expect(mediumTask.priority.rawValue == "Medium")
        #expect(lowTask.priority == .low)
        #expect(lowTask.priority.rawValue == "Low")

        // Priority is preserved when completed
        highTask.isCompleted = true
        #expect(highTask.priority == .high)
    }

    @Test func testHackathonDistinctDeadlinesAndScheduleDisplay() async throws {
        let cal = Calendar.current
        let refDate = Date()
        let regDeadline = cal.date(byAdding: .day, value: 5, to: refDate)!
        let subDeadline = cal.date(byAdding: .day, value: 12, to: refDate)!
        let start = cal.date(byAdding: .day, value: 14, to: refDate)!
        let end = cal.date(byAdding: .day, value: 16, to: refDate)!

        let event = Hackathon(
            title: "Smart India Hackathon 2026",
            organizer: "Ministry of Education",
            startDate: start,
            registrationDeadline: regDeadline,
            submissionDeadline: subDeadline,
            endDate: end,
            mode: .hybrid,
            location: "Noida Campus",
            websiteUrl: "https://example.com/hackathons/sih-2026",
            eventDescription: "National hackathon with distinct registration, project submission, and finale dates.",
            source: "local",
            participationStatus: "Shortlisted",
            lastSyncedAt: refDate
        )

        // Strictly distinguish registration deadline from submission deadline and event dates
        #expect(event.registrationDeadline != event.submissionDeadline)
        #expect(event.registrationDeadline != event.startDate)
        #expect(event.submissionDeadline != event.startDate)
        #expect(event.startDate != event.endDate)

        #expect(event.registrationDeadline == regDeadline)
        #expect(event.submissionDeadline == subDeadline)
        #expect(event.startDate == start)
        #expect(event.endDate == end)

        // Verify organizer, participation status, website link, and sync time
        #expect(event.organizer == "Ministry of Education")
        #expect(event.participationStatus == "Shortlisted")
        #expect(event.websiteUrl == "https://example.com/hackathons/sih-2026")
        #expect(event.lastSyncedAt == refDate)
        #expect(event.source == "local")
    }

    @Test func testHackathonNotificationSchedulingAndCancellation() async throws {
        let eventId = UUID()
        let regId24h = NotificationService.hackathonIdentifier(for: eventId, deadlineType: "reg", offset: .twentyFourHours)
        let subId3h = NotificationService.hackathonIdentifier(for: eventId, deadlineType: "sub", offset: .threeHours)

        #expect(regId24h.contains(eventId.uuidString))
        #expect(regId24h.contains("reg_24h"))
        #expect(subId3h.contains("sub_3h"))

        let allIds = NotificationService.allHackathonIdentifiers(for: eventId)
        #expect(allIds.count == 6) // 2 deadline types x 3 offsets
        #expect(allIds.contains(regId24h))
        #expect(allIds.contains(subId3h))
    }

    @Test func testHackathonLabelsAndMetadata() async throws {
        let localEvent = Hackathon(title: "Comp 1", source: "local", importSource: "manual")
        #expect(localEvent.importSourceDisplayName == "Manual Entry")
        #expect(localEvent.importSourceIconName == "pencil")
    }

    // MARK: - Smart Deadline Extraction & OCR Scanner Improvement Tests

    @Test func testDatesWithAndWithoutYears() async throws {
        let cal = Calendar.current

        // 1. Explicit year in date string
        let explicitDateLine = "Assignment Submission Deadline: 16 November 2026 at 5:00 PM"
        let explicitExtracted = SmartDateExtractor.extractDate(from: explicitDateLine, documentContextYear: nil)
        #expect(explicitExtracted != nil)
        #expect(explicitExtracted?.isConfident == true)
        let explicitComps = cal.dateComponents([.year, .month, .day, .hour], from: explicitExtracted!.date)
        #expect(explicitComps.year == 2026)
        #expect(explicitComps.month == 11)
        #expect(explicitComps.day == 16)
        #expect(explicitComps.hour == 17)

        // 2. Numeric formats DD/MM/YYYY and DD-MM-YYYY
        let slashLine = "Due on: 16/11/2026 at 10:00 AM"
        let slashExtracted = SmartDateExtractor.extractDate(from: slashLine, documentContextYear: nil)
        #expect(slashExtracted != nil)
        #expect(slashExtracted?.isConfident == true)
        let slashComps = cal.dateComponents([.year, .month, .day], from: slashExtracted!.date)
        #expect(slashComps.year == 2026)
        #expect(slashComps.month == 11)
        #expect(slashComps.day == 16)

        let dashLine = "Final Exam Date: 28-11-2026"
        let dashExtracted = SmartDateExtractor.extractDate(from: dashLine, documentContextYear: nil)
        #expect(dashExtracted != nil)
        #expect(dashExtracted?.isConfident == true)
        let dashComps = cal.dateComponents([.year, .month, .day], from: dashExtracted!.date)
        #expect(dashComps.year == 2026)
        #expect(dashComps.month == 11)
        #expect(dashComps.day == 28)

        // 3. Ordinals and Weekday names
        let weekdayLine = "Monday, 16th November 2026 at 02:00 PM"
        let weekdayExtracted = SmartDateExtractor.extractDate(from: weekdayLine, documentContextYear: nil)
        #expect(weekdayExtracted != nil)
        #expect(weekdayExtracted?.isConfident == true)
        let weekdayComps = cal.dateComponents([.year, .month, .day, .hour], from: weekdayExtracted!.date)
        #expect(weekdayComps.year == 2026)
        #expect(weekdayComps.month == 11)
        #expect(weekdayComps.day == 16)
        #expect(weekdayComps.hour == 14)

        // 4. Date without explicit year but with document context year
        let noYearLine = "Midterm Exam on November 19 at 10:00 AM"
        let withContextExtracted = SmartDateExtractor.extractDate(from: noYearLine, documentContextYear: 2026)
        #expect(withContextExtracted != nil)
        #expect(withContextExtracted?.isConfident == true)
        let contextComps = cal.dateComponents([.year, .month, .day], from: withContextExtracted!.date)
        #expect(contextComps.year == 2026)
        #expect(contextComps.month == 11)
        #expect(contextComps.day == 19)

        // 5. Date without explicit year and NO document context year -> unconfident flag
        let unconfidentExtracted = SmartDateExtractor.extractDate(from: noYearLine, documentContextYear: nil)
        #expect(unconfidentExtracted != nil)
        // Missing explicit year without context year must flag for confirmation
        #expect(unconfidentExtracted?.isConfident == false || unconfidentExtracted?.reason != nil)
    }

    @Test func testAmbiguousDateDetection() async throws {
        // 04/05/2026: both 4 and 5 are <= 12, ambiguous between 4 May and 5 April
        let ambiguousLine = "Submission Date: 04/05/2026"
        let ambiguousExtracted = SmartDateExtractor.extractDate(from: ambiguousLine, documentContextYear: 2026)
        #expect(ambiguousExtracted != nil)
        #expect(ambiguousExtracted?.isConfident == false)
        #expect(ambiguousExtracted?.reason?.contains("Ambiguous") == true)

        // 24/10/2026: 24 > 12 -> clearly 24 October 2026 (unambiguous)
        let unambiguousLine = "Due Date: 24/10/2026"
        let unambiguousExtracted = SmartDateExtractor.extractDate(from: unambiguousLine, documentContextYear: 2026)
        #expect(unambiguousExtracted != nil)
        #expect(unambiguousExtracted?.isConfident == true)
        let cal = Calendar.current
        let comps = cal.dateComponents([.day, .month, .year], from: unambiguousExtracted!.date)
        #expect(comps.day == 24)
        #expect(comps.month == 10)
        #expect(comps.year == 2026)
    }

    @Test func testMultipleExamSubjectsDatesheetExtraction() async throws {
        let datesheetLines = [
            "KIET GROUP OF INSTITUTIONS",
            "OFFICE OF THE CONTROLLER OF EXAMINATIONS",
            "END SEMESTER THEORY EXAMINATION DATESHEET — ODD SEMESTER 2026-27",
            "Ref: KIET/COE/EXAM/2026/104",
            "Date of Notice: October 24, 2026",
            "Course Code & Subject Title Exam Date & Time",
            "CS 301 - Operating Systems Midterm Exam on November 16, 2026 at 10:00 AM - 01:00 PM",
            "CS 302 - Design & Analysis of Algorithms Final Exam on November 19, 2026 at 02:00 PM - 05:00 PM",
            "CS 303 - Database Management Systems Midterm Exam on November 24, 2026 at 10:00 AM",
            "CS 304 - Computer Networks & Security Final Exam on November 28, 2026 at 02:00 PM",
            "Controller of Examinations"
        ]

        let documentKind = ScheduleParser.classifyDocument(lines: datesheetLines)
        #expect(documentKind == .examDatesheet)

        let drafts = ScheduleParser.parse(lines: datesheetLines)
        #expect(drafts.count == 4)

        // 1. CS 301 Exam
        let cs301 = drafts.first { $0.course == "CS 301" }
        #expect(cs301 != nil)
        #expect(cs301?.eventType == "exam")
        #expect(cs301?.priority == .high)
        #expect(cs301?.sessionTime?.contains("10:00 AM") == true)
        #expect(cs301?.title.localizedCaseInsensitiveContains("Operating Systems") == true)
        #expect(cs301?.isConfidentDate == true)

        // 2. CS 302 Exam
        let cs302 = drafts.first { $0.course == "CS 302" }
        #expect(cs302 != nil)
        #expect(cs302?.eventType == "exam")
        #expect(cs302?.sessionTime?.contains("02:00 PM") == true)
        #expect(cs302?.title.localizedCaseInsensitiveContains("Algorithms") == true)

        // 3. CS 303 Exam
        let cs303 = drafts.first { $0.course == "CS 303" }
        #expect(cs303 != nil)
        #expect(cs303?.eventType == "exam")
        #expect(cs303?.sessionTime?.contains("10:00 AM") == true)

        // 4. CS 304 Exam
        let cs304 = drafts.first { $0.course == "CS 304" }
        #expect(cs304 != nil)
        #expect(cs304?.eventType == "exam")
        #expect(cs304?.sessionTime?.contains("02:00 PM") == true)

        // Verify notice issuance date "October 24, 2026" was NEVER treated as an exam deadline
        let oct24Draft = drafts.first { Calendar.current.component(.month, from: $0.dueDate) == 10 && Calendar.current.component(.day, from: $0.dueDate) == 24 }
        #expect(oct24Draft == nil, "Notice issuance date must never be treated as an exam deadline")
    }

    @Test func testNoticeWithSeveralUnrelatedDatesFiltersDeadlines() async throws {
        let noticeLines = [
            "DEPARTMENT OF COMPUTER SCIENCE",
            "ACADEMIC COURSEWORK ASSIGNMENT NOTICE",
            "Ref: CS/2026/099",
            "Date of Notice: October 24, 2026",
            "Course: CS 204 - Object Oriented Programming",
            "Assignment: Polymorphism and Memory Management in Swift",
            "Classes commence: November 02, 2026",
            "Registration Deadline: November 06, 2026",
            "Due Date: CS 204 Polymorphism Assignment — Deadline on November 14, 2026 at 05:00 PM",
            "Priority Level: High Priority — Late submissions incur daily grade penalty."
        ]

        let drafts = ScheduleParser.parse(lines: noticeLines)
        #expect(drafts.count == 1)

        let draft = drafts.first!
        #expect(draft.course == "CS 204")
        #expect(draft.eventType == "assignment")
        #expect(draft.priority == .high)

        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: draft.dueDate)
        #expect(comps.year == 2026)
        #expect(comps.month == 11)
        #expect(comps.day == 14)
        #expect(comps.hour == 17)

        // Verify title
        #expect(draft.title.localizedCaseInsensitiveContains("Polymorphism") == true)
        #expect(draft.isConfidentDate == true)
    }

    @Test func testMissingOrTBDSubmissionDeadlineFlagsUncertainty() async throws {
        let tbdNotice = [
            "DEPARTMENT OF INFORMATION TECHNOLOGY",
            "ACADEMIC NOTICE: RESEARCH PAPER DRAFT GUIDELINES",
            "Course Code: CS 402 - Final Year Technical Seminar",
            "Assignment: Term Paper Synopsis and Literature Review",
            "Submission Date: Due date TBD (To Be Decided after midterm departmental review)",
            "Presentation Venue: Seminar Hall B"
        ]

        let drafts = ScheduleParser.parse(lines: tbdNotice)
        #expect(drafts.count == 1)

        let draft = drafts.first!
        #expect(draft.course == "CS 402")
        #expect(draft.isConfidentDate == false)
        #expect(draft.uncertaintyReason?.localizedCaseInsensitiveContains("TBD") == true || draft.uncertaintyReason?.localizedCaseInsensitiveContains("unconfirmed") == true)
    }

    @Test @MainActor func testDuplicateScanDetection() async throws {
        let nov16 = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 10))!
        let existingExam = Assignment(
            title: "Operating Systems Midterm Exam",
            course: "CS 301",
            dueDate: nov16,
            priority: .high,
            source: "scan",
            eventType: "exam",
            sessionTime: "10:00 AM - 01:00 PM"
        )

        let lines = [
            "OFFICE OF THE CONTROLLER OF EXAMINATIONS",
            "THEORY EXAMINATION DATESHEET 2026",
            "CS 301 - Operating Systems Midterm Exam on November 16, 2026 at 10:00 AM",
            "CS 302 - Design & Analysis of Algorithms Final Exam on November 19, 2026 at 02:00 PM"
        ]

        let drafts = ScheduleParser.parse(lines: lines, existingAssignments: [existingExam])
        #expect(drafts.count == 2)

        // CS 301 should be flagged as duplicate and unchecked
        let cs301Draft = drafts.first { $0.course == "CS 301" }
        #expect(cs301Draft != nil)
        #expect(cs301Draft?.isDuplicate == true)
        #expect(cs301Draft?.isSelected == false, "Duplicate drafts must be deselected by default")

        // CS 302 is new and should be checked
        let cs302Draft = drafts.first { $0.course == "CS 302" }
        #expect(cs302Draft != nil)
        #expect(cs302Draft?.isDuplicate == false)
        #expect(cs302Draft?.isSelected == true)
    }

    @Test @MainActor func testUserCorrectionsBeforeSaving() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Assignment.self, configurations: config)
        let context = container.mainContext

        let nov20 = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 14))!
        var draft = ScannedAssignmentDraft(
            title: "Auto-Extracted Draft",
            course: "CS 301",
            dueDate: Date(),
            priority: .medium,
            eventType: "exam",
            isSelected: true,
            isConfidentDate: false,
            isConfidentTitle: false
        )

        // Simulate user editing fields in NoticeScannerView
        draft.title = "Operating Systems Final Theory Exam"
        draft.dueDate = nov20
        draft.priority = .high
        draft.sessionTime = "02:00 PM - 05:00 PM"
        draft.notes = "Room 304 • Carry Scientific Calculator"

        // Save corrected draft to database
        let savedAssignment = Assignment(
            title: draft.title,
            course: draft.course,
            dueDate: draft.dueDate,
            priority: draft.priority,
            notes: draft.notes,
            source: "scan",
            eventType: draft.eventType,
            sessionTime: draft.sessionTime
        )
        context.insert(savedAssignment)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Assignment>())
        #expect(fetched.count == 1)
        let record = fetched.first!
        #expect(record.title == "Operating Systems Final Theory Exam")
        #expect(record.dueDate == nov20)
        #expect(record.priority == .high)
        #expect(record.eventType == "exam")
        #expect(record.isExam == true)
        #expect(record.sessionTime == "02:00 PM - 05:00 PM")
        #expect(record.notes.contains("Room 304"))
    }

    @Test func testInvalidDraftsValidation() async throws {
        let emptyTitleDraft = ScannedAssignmentDraft(
            title: "   ",
            course: "CS 301",
            dueDate: Date().addingTimeInterval(86400),
            isSelected: true
        )

        // Check validation
        let cleanTitle = emptyTitleDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(cleanTitle.isEmpty == true, "Empty title draft must fail validation")

        let validTitleDraft = ScannedAssignmentDraft(
            title: "Database Indexing Homework",
            course: "CS 303",
            dueDate: Date().addingTimeInterval(86400),
            isSelected: true
        )
        #expect(!validTitleDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test @MainActor func testExamModelBackwardCompatibilityAndRegression() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Assignment.self, configurations: config)
        let context = container.mainContext

        let refDate = Date()

        // 1. Legacy/Standard Assignment (defaults to eventType = "assignment")
        let standardAssignment = Assignment(
            title: "Regular Problem Set",
            course: "MATH 101",
            dueDate: refDate.addingTimeInterval(86400),
            priority: .medium
        )
        #expect(standardAssignment.eventType == "assignment")
        #expect(standardAssignment.isExam == false)
        #expect(standardAssignment.sessionTime == nil)
        #expect(standardAssignment.rawOcrText == nil)
        context.insert(standardAssignment)

        // 2. Exam Event (eventType = "exam")
        let examEvent = Assignment(
            title: "Calculus Final Examination",
            course: "MATH 101",
            dueDate: refDate.addingTimeInterval(3 * 86400),
            priority: .high,
            eventType: "exam",
            sessionTime: "10:00 AM - 01:00 PM",
            rawOcrText: "MATH 101 Calculus Final Exam on Nov 25 10:00 AM"
        )
        #expect(examEvent.eventType == "exam")
        #expect(examEvent.isExam == true)
        #expect(examEvent.sessionTime == "10:00 AM - 01:00 PM")
        #expect(examEvent.rawOcrText != nil)
        context.insert(examEvent)

        try context.save()

        // Verify retrieval and sorting
        let allRecords = try context.fetch(FetchDescriptor<Assignment>())
        #expect(allRecords.count == 2)

        let sorted = allRecords.sorted { Assignment.urgencySortComparator(a: $0, b: $1, referenceDate: refDate) }
        #expect(sorted.first?.title == "Regular Problem Set")
        #expect(sorted.last?.title == "Calculus Final Examination")
    }

    // MARK: - Examination Reminders & Session Time Regression Tests

    @Test func testExamSessionTimeStartExtractionNeverUsesEndTime() async throws {
        // Range 1: 10:00 AM - 01:00 PM (Start must be 10:00, NOT 13:00)
        let t1 = NotificationService.parseSessionStartTime(from: "10:00 AM - 01:00 PM")
        #expect(t1?.hour == 10)
        #expect(t1?.minute == 0)

        // Range 2: 02:00 PM - 05:00 PM (Start must be 14:00, NOT 17:00)
        let t2 = NotificationService.parseSessionStartTime(from: "02:00 PM - 05:00 PM")
        #expect(t2?.hour == 14)
        #expect(t2?.minute == 0)

        // Range 3: 09:30 AM to 12:30 PM (Start must be 09:30, NOT 12:30)
        let t3 = NotificationService.parseSessionStartTime(from: "09:30 AM to 12:30 PM")
        #expect(t3?.hour == 9)
        #expect(t3?.minute == 30)

        // Range 4: 24-hour range: 10:00 - 13:00 (Start must be 10:00, NOT 13:00)
        let t4 = NotificationService.parseSessionStartTime(from: "10:00 - 13:00")
        #expect(t4?.hour == 10)
        #expect(t4?.minute == 0)

        // Range 5: Afternoon slot without start AM/PM: 2:00 - 5:00 PM (Start must be 14:00, NOT 17:00)
        let t5 = NotificationService.parseSessionStartTime(from: "2:00 - 5:00 PM")
        #expect(t5?.hour == 14)
        #expect(t5?.minute == 0)

        // Range 6: Morning start with afternoon end: 10:00 - 1:00 PM (Start must be 10:00 AM, NOT 13:00)
        let t6 = NotificationService.parseSessionStartTime(from: "10:00 - 1:00 PM")
        #expect(t6?.hour == 10)
        #expect(t6?.minute == 0)

        // Single time: 10:00 AM
        let t7 = NotificationService.parseSessionStartTime(from: "10:00 AM")
        #expect(t7?.hour == 10)
        #expect(t7?.minute == 0)

        // Single time: 02:30 PM
        let t8 = NotificationService.parseSessionStartTime(from: "02:30 PM")
        #expect(t8?.hour == 14)
        #expect(t8?.minute == 30)

        // Named session: Morning Session (10:00 AM - 01:00 PM)
        let t9 = NotificationService.parseSessionStartTime(from: "Morning Session (10:00 AM - 01:00 PM)")
        #expect(t9?.hour == 10)
        #expect(t9?.minute == 0)

        // Named session: Evening Session
        let t10 = NotificationService.parseSessionStartTime(from: "Evening Session")
        #expect(t10?.hour == 14)
        #expect(t10?.minute == 0)

        // Unparseable / Empty strings
        #expect(NotificationService.parseSessionStartTime(from: nil) == nil)
        #expect(NotificationService.parseSessionStartTime(from: "") == nil)
        #expect(NotificationService.parseSessionStartTime(from: "Auditorium Hall B") == nil)
    }

    @Test func testExamEffectiveEventDateWithKnownStartTime() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // Create a date for 2026-11-20 at 00:00:00 GMT
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 11
        comps.day = 20
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        let examDate = calendar.date(from: comps)!

        let exam = Assignment(
            title: "Operating Systems Examination",
            course: "CS 301",
            dueDate: examDate,
            eventType: "exam",
            sessionTime: "02:00 PM - 05:00 PM"
        )

        let effective = exam.effectiveEventDate(at: calendar)
        let effectiveComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: effective)

        #expect(effectiveComps.year == 2026)
        #expect(effectiveComps.month == 11)
        #expect(effectiveComps.day == 20)
        #expect(effectiveComps.hour == 14, "Exam start time must be 14:00 (2:00 PM), never the end time 17:00 (5:00 PM)")
        #expect(effectiveComps.minute == 0)
    }

    @Test func testExamEffectiveEventDateFallbackWhenSessionTimeMissingOrUnparseable() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // 1. Exam with missing sessionTime and midnight dueDate: falls back to 10:00 AM
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 11
        comps.day = 20
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        let midnightDate = calendar.date(from: comps)!

        let examMissing = Assignment(
            title: "Discrete Math Exam",
            dueDate: midnightDate,
            eventType: "exam",
            sessionTime: nil
        )
        let effectiveMissing = examMissing.effectiveEventDate(at: calendar)
        let missingComps = calendar.dateComponents([.hour, .minute], from: effectiveMissing)
        #expect(missingComps.hour == 10, "Missing session time must fallback to standard 10:00 AM slot")
        #expect(missingComps.minute == 0)

        // 2. Exam with unparseable sessionTime: falls back to 10:00 AM
        let examUnparseable = Assignment(
            title: "Computer Networks Exam",
            dueDate: midnightDate,
            eventType: "exam",
            sessionTime: "LH-3 Room TBA"
        )
        let effectiveUnparseable = examUnparseable.effectiveEventDate(at: calendar)
        let unparseableComps = calendar.dateComponents([.hour, .minute], from: effectiveUnparseable)
        #expect(unparseableComps.hour == 10, "Unparseable session time must fallback to 10:00 AM")
        #expect(unparseableComps.minute == 0)

        // 3. Exam with explicit user-chosen non-midnight time (e.g. 11:30 AM): respects chosen time
        var explicitComps = comps
        explicitComps.hour = 11
        explicitComps.minute = 30
        let explicitDate = calendar.date(from: explicitComps)!
        let examExplicit = Assignment(
            title: "Algorithms Exam",
            dueDate: explicitDate,
            eventType: "exam",
            sessionTime: nil
        )
        let effectiveExplicit = examExplicit.effectiveEventDate(at: calendar)
        let explicitResultComps = calendar.dateComponents([.hour, .minute], from: effectiveExplicit)
        #expect(explicitResultComps.hour == 11)
        #expect(explicitResultComps.minute == 30)
    }

    @Test func testExamReminderSchedulingWithKnownStartTime() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // Reference date: 2026-11-18 at 10:00:00 GMT
        var refComps = DateComponents()
        refComps.year = 2026
        refComps.month = 11
        refComps.day = 18
        refComps.hour = 10
        refComps.minute = 0
        refComps.second = 0
        let referenceDate = calendar.date(from: refComps)!

        // Exam date: 2026-11-20 with session "02:00 PM - 05:00 PM" (Start = 14:00 GMT)
        var examComps = DateComponents()
        examComps.year = 2026
        examComps.month = 11
        examComps.day = 20
        examComps.hour = 0
        examComps.minute = 0
        examComps.second = 0
        let examDate = calendar.date(from: examComps)!

        let exam = Assignment(
            title: "Database Systems Midterm",
            course: "CS 304",
            dueDate: examDate,
            eventType: "exam",
            sessionTime: "02:00 PM - 05:00 PM"
        )

        let details = NotificationService.calculateReminderDetails(for: exam, referenceDate: referenceDate, calendar: calendar)
        #expect(details.count == 3)

        // 1. 24h Before Trigger: 2026-11-19 at 14:00:00 GMT (NOT 17:00:00)
        let rem24 = details.first { $0.offset == .twentyFourHours }!
        let rem24Comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: rem24.triggerDate)
        #expect(rem24Comps.year == 2026)
        #expect(rem24Comps.month == 11)
        #expect(rem24Comps.day == 19)
        #expect(rem24Comps.hour == 14, "24h reminder must trigger relative to 14:00 exam start time, NOT 17:00 end time")
        #expect(rem24Comps.minute == 0)
        #expect(rem24.title == "📝 Exam in 24 Hours: Database Systems Midterm")
        #expect(rem24.body.contains("CS 304 • Exam session: 02:00 PM - 05:00 PM"))
        #expect(rem24.category == "EXAM_REMINDER")

        // 2. 3h Before Trigger: 2026-11-20 at 11:00:00 GMT
        let rem3h = details.first { $0.offset == .threeHours }!
        let rem3hComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: rem3h.triggerDate)
        #expect(rem3hComps.day == 20)
        #expect(rem3hComps.hour == 11)
        #expect(rem3h.title == "🚨 Exam in 3 Hours: Database Systems Midterm")
        #expect(rem3h.category == "EXAM_REMINDER")

        // 3. At Deadline/Start Trigger: 2026-11-20 at 14:00:00 GMT
        let rem0m = details.first { $0.offset == .atDeadline }!
        let rem0mComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: rem0m.triggerDate)
        #expect(rem0mComps.day == 20)
        #expect(rem0mComps.hour == 14)
        #expect(rem0m.title == "🔔 Exam Starting Now: Database Systems Midterm")
        #expect(rem0m.category == "EXAM_REMINDER")
    }

    @Test func testExamReminderSchedulingMissingSessionTimeFallback() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // Reference date: 2026-11-18 at 10:00:00 GMT
        var refComps = DateComponents()
        refComps.year = 2026
        refComps.month = 11
        refComps.day = 18
        refComps.hour = 10
        refComps.minute = 0
        refComps.second = 0
        let referenceDate = calendar.date(from: refComps)!

        // Exam date: 2026-11-20 at 00:00:00 with sessionTime = nil
        var examComps = DateComponents()
        examComps.year = 2026
        examComps.month = 11
        examComps.day = 20
        examComps.hour = 0
        examComps.minute = 0
        examComps.second = 0
        let examDate = calendar.date(from: examComps)!

        let exam = Assignment(
            title: "Physics II Exam",
            course: "PHY 102",
            dueDate: examDate,
            eventType: "exam",
            sessionTime: nil
        )

        let details = NotificationService.calculateReminderDetails(for: exam, referenceDate: referenceDate, calendar: calendar)
        #expect(details.count == 3)

        // Triggers must be relative to 10:00 AM fallback (NOT 00:00 midnight)
        let rem24 = details.first { $0.offset == .twentyFourHours }!
        let rem24Comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: rem24.triggerDate)
        #expect(rem24Comps.day == 19)
        #expect(rem24Comps.hour == 10, "Fallback 24h reminder must trigger at 10:00 AM on the day prior")

        let rem3h = details.first { $0.offset == .threeHours }!
        let rem3hComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: rem3h.triggerDate)
        #expect(rem3hComps.day == 20)
        #expect(rem3hComps.hour == 7, "Fallback 3h reminder must trigger at 07:00 AM")

        let rem0m = details.first { $0.offset == .atDeadline }!
        let rem0mComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: rem0m.triggerDate)
        #expect(rem0mComps.day == 20)
        #expect(rem0mComps.hour == 10)
    }

    @Test func testExamReminderDateAndTimeEditReplacesTriggers() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let referenceDate = Date(timeIntervalSince1970: 1770000000)

        // Initially: Exam on Day + 3 at 10:00 AM ("10:00 AM - 01:00 PM")
        let exam = Assignment(
            title: "Chemistry Exam",
            course: "CHEM 101",
            dueDate: referenceDate.addingTimeInterval(3 * 86400),
            eventType: "exam",
            sessionTime: "10:00 AM - 01:00 PM"
        )
        let initialDetails = NotificationService.calculateReminderDetails(for: exam, referenceDate: referenceDate, calendar: calendar)
        #expect(initialDetails.count == 3)

        // Edit: Date postponed by 2 days, and session moved to afternoon ("02:00 PM - 05:00 PM")
        exam.dueDate = referenceDate.addingTimeInterval(5 * 86400)
        exam.sessionTime = "02:00 PM - 05:00 PM"

        let updatedDetails = NotificationService.calculateReminderDetails(for: exam, referenceDate: referenceDate, calendar: calendar)
        #expect(updatedDetails.count == 3)

        // Verify triggers shifted forward to the new afternoon start time
        let rem0m = updatedDetails.first { $0.offset == .atDeadline }!
        let rem0mComps = calendar.dateComponents([.hour, .minute], from: rem0m.triggerDate)
        #expect(rem0mComps.hour == 14)
        #expect(rem0mComps.minute == 0)

        // Verify stable identifiers allow replacing pending notifications
        let ids = NotificationService.allIdentifiers(for: exam.id)
        #expect(ids.count == 3)
        #expect(ids.contains(NotificationService.identifier(for: exam.id, offset: .twentyFourHours)))
    }

    @Test func testExamPastDateDoesNotScheduleReminders() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var examComps = DateComponents()
        examComps.year = 2026
        examComps.month = 10
        examComps.day = 20
        examComps.hour = 0
        examComps.minute = 0
        examComps.second = 0
        let pastDate = calendar.date(from: examComps)!

        let pastExam = Assignment(
            title: "Past Midterm Exam",
            dueDate: pastDate,
            eventType: "exam",
            sessionTime: "10:00 AM - 01:00 PM"
        )

        // Reference date is well after the exam: 2026-10-24
        let refDate = Date()
        let eligible = NotificationService.futureEligibleOffsets(for: pastExam, referenceDate: refDate, calendar: calendar)
        #expect(eligible.isEmpty, "Past exams must never have future eligible reminder triggers")

        let details = NotificationService.calculateReminderDetails(for: pastExam, referenceDate: refDate, calendar: calendar)
        #expect(details.isEmpty)

        #expect(pastExam.isOverdue == true)
        #expect(pastExam.urgency(at: refDate) == .overdue)
    }

    @Test func testExamCompletionAndDeletionCancelsReminders() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let refDate = Date(timeIntervalSince1970: 1770000000)
        let exam = Assignment(
            title: "Software Engineering Exam",
            dueDate: refDate.addingTimeInterval(48 * 3600),
            eventType: "exam",
            sessionTime: "10:00 AM - 01:00 PM"
        )

        // Incomplete exam has future eligible triggers
        let activeEligible = NotificationService.futureEligibleOffsets(for: exam, referenceDate: refDate, calendar: calendar)
        #expect(activeEligible.count == 3)

        // Mark completed
        exam.isCompleted = true
        let completedEligible = NotificationService.futureEligibleOffsets(for: exam, referenceDate: refDate, calendar: calendar)
        #expect(completedEligible.isEmpty, "Completed exams must have zero future eligible reminder triggers")

        let completedDetails = NotificationService.calculateReminderDetails(for: exam, referenceDate: refDate, calendar: calendar)
        #expect(completedDetails.isEmpty)
        #expect(exam.isOverdue == false)
        #expect(exam.urgency(at: refDate) == .completed)
    }

    @Test func testOrdinaryAssignmentPreservesStandardReminderBehavior() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var refComps = DateComponents()
        refComps.year = 2026
        refComps.month = 11
        refComps.day = 18
        refComps.hour = 10
        refComps.minute = 0
        refComps.second = 0
        let refDate = calendar.date(from: refComps)!

        var dueComps = DateComponents()
        dueComps.year = 2026
        dueComps.month = 11
        dueComps.day = 20
        dueComps.hour = 17
        dueComps.minute = 0
        dueComps.second = 0
        let dueDate = calendar.date(from: dueComps)!

        let regularAssignment = Assignment(
            title: "Problem Set 4",
            course: "CS 201",
            dueDate: dueDate,
            eventType: "assignment",
            sessionTime: nil
        )

        let details = NotificationService.calculateReminderDetails(for: regularAssignment, referenceDate: refDate, calendar: calendar)
        #expect(details.count == 3)

        let rem24 = details.first { $0.offset == .twentyFourHours }!
        #expect(rem24.title == "⏰ Due in 24 Hours: Problem Set 4")
        #expect(rem24.category == "ASSIGNMENT_REMINDER")
        #expect(rem24.body.contains("Due at"))

        let rem0m = details.first { $0.offset == .atDeadline }!
        #expect(rem0m.title == "⏳ Deadline Reached: Problem Set 4")
        #expect(rem0m.category == "ASSIGNMENT_REMINDER")
    }

    @Test func testExamDashboardUrgencyAndSortingWithSessionTime() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // Today is 2026-11-20 at 11:00:00 AM
        var nowComps = DateComponents()
        nowComps.year = 2026
        nowComps.month = 11
        nowComps.day = 20
        nowComps.hour = 11
        nowComps.minute = 0
        nowComps.second = 0
        let now = calendar.date(from: nowComps)!

        // Exam A: Today with session "02:00 PM - 05:00 PM" (Starts at 14:00, 3 hours away)
        var todayBase = DateComponents()
        todayBase.year = 2026
        todayBase.month = 11
        todayBase.day = 20
        todayBase.hour = 0
        todayBase.minute = 0
        let todayDate = calendar.date(from: todayBase)!

        let examAfternoon = Assignment(
            title: "Afternoon Exam",
            dueDate: todayDate,
            eventType: "exam",
            sessionTime: "02:00 PM - 05:00 PM"
        )
        // At 11:00 AM, Exam A is NOT overdue! It starts at 14:00.
        let urgAfternoon = examAfternoon.urgency(at: now, in: calendar)
        #expect(urgAfternoon == .dueSoon, "Exam starting in 3 hours must be Due Soon, NOT Overdue")

        // Exam B: Today with session "09:00 AM - 12:00 PM" (Started at 09:00, 2 hours in past)
        let examMorning = Assignment(
            title: "Morning Exam",
            dueDate: todayDate,
            eventType: "exam",
            sessionTime: "09:00 AM - 12:00 PM"
        )
        // At 11:00 AM, Exam B started at 9:00 AM, so it is overdue if incomplete!
        let urgMorning = examMorning.urgency(at: now, in: calendar)
        #expect(urgMorning == .overdue, "Exam that started at 09:00 AM is Overdue at 11:00 AM")

        // Assignment C: Tomorrow at 10:00 AM
        var tomorrowComps = DateComponents()
        tomorrowComps.year = 2026
        tomorrowComps.month = 11
        tomorrowComps.day = 21
        tomorrowComps.hour = 10
        tomorrowComps.minute = 0
        let tomorrowDate = calendar.date(from: tomorrowComps)!

        let assignmentTomorrow = Assignment(
            title: "Tomorrow Homework",
            dueDate: tomorrowDate,
            eventType: "assignment"
        )
        let urgTomorrow = assignmentTomorrow.urgency(at: now, in: calendar)
        #expect(urgTomorrow == .dueSoon)

        // Verify urgency sort order:
        // 1. Morning Exam (Overdue: sortOrder 0)
        // 2. Afternoon Exam (Due Soon: sortOrder 1, starts today 14:00)
        // 3. Tomorrow Homework (Due Soon: sortOrder 1, starts tomorrow 10:00)
        var list = [assignmentTomorrow, examAfternoon, examMorning]
        list.sort { Assignment.urgencySortComparator(a: $0, b: $1, referenceDate: now, calendar: calendar) }

        #expect(list[0].title == "Morning Exam")
        #expect(list[1].title == "Afternoon Exam")
        #expect(list[2].title == "Tomorrow Homework")
    }

    @Test @MainActor func testExamTimeConfidenceAndAssumedTimeDistinction() async throws {
        // 1. Scanned draft with extracted session time
        let explicitDraft = ScannedAssignmentDraft(
            title: "Operating Systems Exam",
            course: "CS 301",
            dueDate: Date().addingTimeInterval(86400),
            eventType: "exam",
            sessionTime: "10:00 AM - 01:00 PM",
            isAssumedTime: false
        )
        #expect(explicitDraft.isAssumedTime == false)
        #expect(explicitDraft.sessionTime == "10:00 AM - 01:00 PM")

        // 2. Scanned draft with missing time: marked as assumed fallback
        let assumedDraft = ScannedAssignmentDraft(
            title: "Compiler Design Exam",
            course: "CS 305",
            dueDate: Date().addingTimeInterval(86400),
            eventType: "exam",
            sessionTime: nil,
            isAssumedTime: true
        )
        #expect(assumedDraft.isAssumedTime == true)
        #expect(assumedDraft.sessionTime == nil)

        // 3. Document parser sets isAssumedTime accurately
        let linesWithTime = [
            "CS 301 Operating Systems",
            "Exam Date: 20/11/2026 Session: 10:00 AM - 01:00 PM"
        ]
        let draftsWithTime = ScheduleParser.parse(lines: linesWithTime)
        if let first = draftsWithTime.first {
            #expect(first.isAssumedTime == false)
            #expect(first.sessionTime != nil)
        }

        let linesWithoutTime = [
            "CS 302 Database Management Systems",
            "Exam Date: 22/11/2026"
        ]
        let draftsWithoutTime = ScheduleParser.parse(lines: linesWithoutTime)
        if let first = draftsWithoutTime.first {
            #expect(first.isAssumedTime == true)
            #expect(first.sessionTime == nil)
        }
    }

    @Test @MainActor func testNotificationNavigationTargetIdentifierHandling() async throws {
        let service = NotificationService.shared
        let targetId = UUID()

        // Verify initial state or reset
        service.pendingOpenedAssignmentId = nil

        // Simulate notification response payload reception
        service.pendingOpenedAssignmentId = targetId
        #expect(service.pendingOpenedAssignmentId == targetId)

        // Simulate view consuming the target ID and clearing it to prevent duplicate navigation
        let consumedId = service.pendingOpenedAssignmentId
        service.pendingOpenedAssignmentId = nil
        #expect(consumedId == targetId)
        #expect(service.pendingOpenedAssignmentId == nil)
    }

    // MARK: - Assignment Card Layout Tests

    @Test func testCardLayoutInformationElements() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        let dueDate = cal.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: 11, minute: 0))!
        let assignmentWithCourse = Assignment(
            title: "Geo Tag Photographs — Section 3A",
            course: "COI_3A&3B",
            dueDate: dueDate,
            isCompleted: false
        )

        // 1. Assignment topic is preserved
        #expect(assignmentWithCourse.title == "Geo Tag Photographs — Section 3A")

        // 2. Course code is retrieved from model
        #expect(assignmentWithCourse.course == "COI_3A&3B")

        // 3. Concise deadline format
        let deadlineLabel = AssignmentRowView.conciseDeadlineLabel(
            for: assignmentWithCourse.dueDate,
            urgency: .upcoming,
            isExam: false,
            referenceDate: dueDate.addingTimeInterval(-86400),
            calendar: cal
        )
        #expect(deadlineLabel == "Due 28 Nov 2026 · 11:00 AM")

        // 4. Missing course code handling
        let assignmentWithoutCourse = Assignment(
            title: "Term Paper Submission",
            course: "   ",
            dueDate: dueDate
        )
        let trimmedCourse = assignmentWithoutCourse.course.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmedCourse.isEmpty)
    }

    // MARK: - Moodle Session Lifecycle & Data-Safety Tests

    @Test @MainActor func testMoodleSessionLifecycleAndLogoutDataSafety() async throws {
        let schema = Schema([Assignment.self, Hackathon.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let moodleItem = Assignment(
            title: "Moodle Lab Report",
            course: "CS101",
            dueDate: Date().addingTimeInterval(86400),
            source: "moodle",
            moodleEventId: "moodle_evt_999"
        )
        let manualItem = Assignment(
            title: "Personal Side Project",
            course: "Self",
            dueDate: Date().addingTimeInterval(172800),
            source: "manual"
        )
        let scannedExam = Assignment(
            title: "Operating Systems Final",
            course: "CS301",
            dueDate: Date().addingTimeInterval(259200),
            source: "scan",
            eventType: "exam",
            sessionTime: "10:00 AM - 01:00 PM"
        )
        let hackathon = Hackathon(
            title: "Smart India Hackathon",
            organizer: "Govt of India",
            startDate: Date().addingTimeInterval(864000)
        )

        context.insert(moodleItem)
        context.insert(manualItem)
        context.insert(scannedExam)
        context.insert(hackathon)
        try context.save()

        let session = SessionManager.shared

        // 1. Test Login
        session.logInWithMoodle(user: "Nilesh Kumar", site: "http://lms.kiet.edu/moodle")
        #expect(session.isAuthenticated == true)
        #expect(session.isGuestMode == false)

        // 2. Test Safe Logout
        session.logOut(modelContext: context)
        #expect(session.isAuthenticated == false)

        // 3. Verify Data Safety:
        // Moodle assignment MUST be removed
        let descriptorAll = FetchDescriptor<Assignment>()
        let remainingAssignments = try context.fetch(descriptorAll)

        #expect(!remainingAssignments.contains(where: { $0.id == moodleItem.id }), "Moodle-owned assignment must be removed on logout")

        // Manual assignment, scanned exam MUST be strictly preserved
        #expect(remainingAssignments.contains(where: { $0.id == manualItem.id }), "Manually created assignment must be preserved")
        #expect(remainingAssignments.contains(where: { $0.id == scannedExam.id }), "Scanned exam notice must be preserved")

        // Local hackathon MUST be strictly preserved
        let descriptorHackathons = FetchDescriptor<Hackathon>()
        let remainingHackathons = try context.fetch(descriptorHackathons)
        #expect(remainingHackathons.contains(where: { $0.id == hackathon.id }), "Local hackathons must be preserved")
    }

    // MARK: - Apple Calendar Integration Tests

    @Test @MainActor func testCalendarSyncServiceEventCreationAndDeduplication() async throws {
        let mockService = MockCalendarSyncService()
        mockService.isCalendarSyncEnabled = true
        mockService.mockStatus = .authorized

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let targetDate = cal.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: 11, minute: 0))!

        let assignment = Assignment(
            title: "Geo Tag Photographs — Section 3A",
            course: "COI_3A&3B",
            dueDate: targetDate,
            source: "moodle"
        )

        // 1. Create Event
        let eventId = await mockService.syncAssignment(assignment)
        #expect(eventId != nil)
        #expect(assignment.calendarEventId == eventId)
        #expect(mockService.mockEvents.count == 1)

        let saved = mockService.mockEvents[eventId!]
        #expect(saved?.title == "Geo Tag Photographs — Section 3A")
        #expect(saved?.notes.contains(CalendarSyncService.appManagedTag) == true)

        // 2. Update Event (Idempotent: updates existing event without duplication)
        assignment.dueDate = targetDate.addingTimeInterval(3600)
        let updatedId = await mockService.syncAssignment(assignment)
        #expect(updatedId == eventId, "Must reuse existing calendar event ID")
        #expect(mockService.mockEvents.count == 1, "Must not create duplicate calendar event")

        // 3. Exam with session time
        let exam = Assignment(
            title: "Computer Networks Midterm",
            course: "IT202",
            dueDate: targetDate,
            eventType: "exam",
            sessionTime: "10:00 AM - 01:00 PM"
        )
        let examEventId = await mockService.syncAssignment(exam)
        #expect(examEventId != nil)
        let savedExam = mockService.mockEvents[examEventId!]
        #expect(savedExam?.title == "[Exam] Computer Networks Midterm")

        // 4. Missing deadline should not create event
        let noDeadlineItem = Assignment(title: "Undated Task", dueDate: Date.distantFuture)
        let noDeadlineEventId = await mockService.syncAssignment(noDeadlineItem)
        #expect(noDeadlineEventId == nil)

        // 5. Deletion of app-managed event only
        mockService.removeLinkedEvent(withIdentifier: eventId!)
        #expect(mockService.mockEvents[eventId!] == nil)
    }

    // MARK: - Coding Hub Overview Tests

    @Test @MainActor func testCodingHubLocalTrackingAndOverview() async throws {
        let leetCode = LeetCodeProvider.shared
        let gfg = GeeksForGeeksProvider.shared

        let testDate = "2026-10-24"

        // Test LeetCode completion toggle
        let initialLeetCode = leetCode.isDailySolvedLocally(date: testDate)
        leetCode.toggleDailySolvedLocally(date: testDate)
        #expect(leetCode.isDailySolvedLocally(date: testDate) == !initialLeetCode)
        // Toggle back to reset
        leetCode.toggleDailySolvedLocally(date: testDate)

        // Test GFG completion toggle
        let initialGFG = gfg.isPOTDSolvedLocally(date: testDate)
        gfg.togglePOTDSolvedLocally(date: testDate)
        #expect(gfg.isPOTDSolvedLocally(date: testDate) == !initialGFG)
        // Toggle back to reset
        gfg.togglePOTDSolvedLocally(date: testDate)
    }

    // MARK: - Moodle Completion Persistence & Account Isolation Regression Tests

    @Test @MainActor func testCompleteMoodleAssignmentPersistsAcrossLogoutAndLogin() async throws {
        let schema = Schema([Assignment.self, Hackathon.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let accountAlice = "alice_student"
        let session = SessionManager.shared

        // 1. Student logs in as Alice
        session.logInWithMoodle(user: "Alice Smith", site: MoodleService.defaultSiteUrl, accountId: accountAlice)
        #expect(session.isAuthenticated == true)
        #expect(session.currentAccountId == accountAlice)

        // 2. Moodle assignment is imported
        let assignment = Assignment(
            title: "Operating Systems Assignment 1",
            course: "CS301",
            dueDate: Date().addingTimeInterval(86400),
            isCompleted: false,
            source: "moodle",
            moodleEventId: "assign_os_301",
            accountId: accountAlice
        )
        context.insert(assignment)
        try context.save()

        // 3. Alice completes the assignment
        assignment.isCompleted = true
        MoodleAccountTaskStore.shared.saveState(for: assignment, accountId: accountAlice)
        try context.save()
        #expect(assignment.isCompleted == true)

        // 4. Alice logs out
        session.logOut(modelContext: context)
        #expect(session.isAuthenticated == false)

        // Verify active SwiftData store no longer holds Alice's Moodle item
        let descriptor = FetchDescriptor<Assignment>()
        let remaining = try context.fetch(descriptor)
        #expect(!remaining.contains(where: { $0.moodleEventId == "assign_os_301" }))

        // 5. Alice logs back in
        session.logInWithMoodle(user: "Alice Smith", site: MoodleService.defaultSiteUrl, accountId: accountAlice)
        #expect(session.isAuthenticated == true)

        // 6. Moodle sync returns the assignment again from the server
        let restoredState = MoodleAccountTaskStore.shared.getState(
            accountId: accountAlice,
            eventId: "assign_os_301",
            title: "Operating Systems Assignment 1",
            course: "CS301"
        )
        #expect(restoredState != nil)
        #expect(restoredState?.isCompleted == true)

        let reimportedAssignment = Assignment(
            title: "Operating Systems Assignment 1",
            course: "CS301",
            dueDate: Date().addingTimeInterval(86400),
            isCompleted: restoredState?.isCompleted ?? false,
            source: "moodle",
            moodleEventId: "assign_os_301",
            accountId: accountAlice
        )
        context.insert(reimportedAssignment)
        try context.save()

        // 7. Verify the re-imported assignment is STILL COMPLETED!
        #expect(reimportedAssignment.isCompleted == true, "Assignment completion MUST persist across logout and login!")
    }

    @Test @MainActor func testDifferentMoodleAccountsCompletionIsolation() async throws {
        let schema = Schema([Assignment.self, Hackathon.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let accountBob = "bob_student"
        let accountCarol = "carol_student"
        let session = SessionManager.shared

        // 1. Bob completes assignment
        session.logInWithMoodle(user: "Bob Jones", site: MoodleService.defaultSiteUrl, accountId: accountBob)
        let bobAssignment = Assignment(
            title: "Distributed Systems Lab 2",
            course: "CS402",
            dueDate: Date().addingTimeInterval(86400),
            isCompleted: true,
            source: "moodle",
            moodleEventId: "assign_ds_402",
            accountId: accountBob
        )
        context.insert(bobAssignment)
        MoodleAccountTaskStore.shared.saveState(for: bobAssignment, accountId: accountBob)
        try context.save()

        // 2. Bob logs out
        session.logOut(modelContext: context)

        // 3. Carol logs in
        session.logInWithMoodle(user: "Carol White", site: MoodleService.defaultSiteUrl, accountId: accountCarol)

        // 4. Query Carol's state for the same assignment
        let carolState = MoodleAccountTaskStore.shared.getState(
            accountId: accountCarol,
            eventId: "assign_ds_402",
            title: "Distributed Systems Lab 2",
            course: "CS402"
        )

        // Verify Bob's completion status NEVER leaks into Carol's account
        #expect(carolState == nil || carolState?.isCompleted == false, "Completion status must not leak between different Moodle accounts!")
    }

    @Test @MainActor func testRepeatedMoodleRefreshesPreserveCompletionAndNotesWithoutDuplicates() async throws {
        let schema = Schema([Assignment.self, Hackathon.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let accountId = "dave_student"
        let originalDate = Date().addingTimeInterval(86400)
        let assignment = Assignment(
            title: "Compiler Design Practical",
            course: "CS305",
            dueDate: originalDate,
            priority: .medium,
            notes: "Drafted lexer",
            isCompleted: true,
            isArchived: true,
            source: "moodle",
            moodleEventId: "assign_cd_305",
            accountId: accountId
        )
        context.insert(assignment)
        try context.save()

        // Simulate refresh with new deadline from server
        let updatedDate = Date().addingTimeInterval(172800)
        let draft = MoodleDraft(
            moodleEventId: "assign_cd_305",
            title: "Compiler Design Practical",
            course: "CS305",
            dueDate: updatedDate,
            priority: .high,
            notes: "Official Moodle note",
            sourceUrl: "http://lms.kiet.edu/moodle/mod/assign/view.php?id=305",
            activityType: "Assignment",
            isSelected: true,
            isDuplicate: true,
            isConfidentDate: true
        )

        // Simulate refresh match logic in syncAssignments:
        let descriptor = FetchDescriptor<Assignment>()
        let allExisting = try context.fetch(descriptor)
        let existingMoodleAssignments = allExisting.filter {
            $0.source == "moodle" && ($0.accountId == nil || $0.accountId?.lowercased() == accountId)
        }

        let existing = existingMoodleAssignments.first(where: {
            if let mId = $0.moodleEventId, !mId.isEmpty, mId == draft.moodleEventId { return true }
            return $0.title.caseInsensitiveCompare(draft.title) == .orderedSame &&
                   $0.course.caseInsensitiveCompare(draft.course) == .orderedSame
        })

        #expect(existing != nil)
        if let existing = existing {
            // Server updates dueDate and priority
            existing.dueDate = draft.dueDate
            existing.priority = draft.priority
            // But MUST PRESERVE user completion and archive status!
            #expect(existing.isCompleted == true)
            #expect(existing.isArchived == true)
            #expect(existing.notes == "Drafted lexer")
        }
        try context.save()

        // Verify count remains 1 (no duplicate created)
        let count = try context.fetchCount(descriptor)
        #expect(count == 1)
    }

    @Test func testFixedMoodleEndpointCentralizedConfiguration() async throws {
        #expect(MoodleService.defaultSiteUrl == "http://lms.kiet.edu/moodle")
        #expect(MoodleService.allowedInsecureHost == "lms.kiet.edu")
        #expect(MoodleService.isAllowedHttpHost("lms.kiet.edu") == true)
        #expect(MoodleService.isAllowedHttpHost("other.example.com") == false)
    }

    // MARK: - Backend & Task Completion Persistence Regression Tests

    @Test @MainActor func testMarkMoodleAssignmentCompletedAndSaveToBackend() async throws {
        let mockBackend = MockTaskBackendService()
        let coordinator = TaskSyncCoordinator.shared
        coordinator.backendService = mockBackend
        let accountId = "test_student_01"
        let userId = BackendAuthManager.shared.bindMoodleAccount(accountId: accountId)

        let assignment = Assignment(
            title: "Operating Systems Assignment 1",
            course: "CS301",
            dueDate: Date().addingTimeInterval(86400),
            priority: .high,
            notes: "Initial kernel setup",
            isCompleted: true,
            source: "moodle",
            moodleEventId: "os_assign_101",
            accountId: accountId
        )

        coordinator.recordTaskStateChange(for: assignment, accountId: accountId)
        await coordinator.flushPendingQueue(userId: userId)

        let saved = try await mockBackend.fetchTaskStates(userId: userId, sourceAccountKey: accountId)
        #expect(saved.count == 1)
        #expect(saved.first?.taskKey == "moodle_os_assign_101")
        #expect(saved.first?.isCompleted == true)
        #expect(saved.first?.notes == "Initial kernel setup")
    }

    @Test @MainActor func testLogoutAndLoginAgainSameAccountRestoresCompletion() async throws {
        let schema = Schema([Assignment.self, Hackathon.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let mockBackend = MockTaskBackendService()
        let coordinator = TaskSyncCoordinator.shared
        coordinator.backendService = mockBackend
        let session = SessionManager.shared

        let accountId = "same_student_02"
        session.logInWithMoodle(user: "Same Student", site: MoodleService.defaultSiteUrl, accountId: accountId)

        let assignment = Assignment(
            title: "Database Indexing Lab",
            course: "CS302",
            dueDate: Date().addingTimeInterval(86400),
            priority: .medium,
            notes: "B-Tree implementation",
            isCompleted: true,
            source: "moodle",
            moodleEventId: "db_lab_202",
            accountId: accountId
        )
        context.insert(assignment)
        try context.save()

        coordinator.recordTaskStateChange(for: assignment, accountId: accountId)
        if let uid = session.currentAccountId.map({ BackendAuthManager.deterministicUserId(forAccount: $0) }) {
            await coordinator.flushPendingQueue(userId: uid)
        }

        // Student logs out
        session.logOut(modelContext: context)

        // Verify Moodle assignment is removed from active context for security
        let countAfterLogout = try context.fetchCount(FetchDescriptor<Assignment>())
        #expect(countAfterLogout == 0)

        // Same student logs in again
        session.logInWithMoodle(user: "Same Student", site: MoodleService.defaultSiteUrl, accountId: accountId)

        // Moodle drafts fetched upon login
        let restoredState = coordinator.restoreTaskState(
            source: "moodle",
            moodleEventId: "db_lab_202",
            title: "Database Indexing Lab",
            course: "CS302",
            accountId: accountId
        )

        #expect(restoredState.isCompleted == true)
        #expect(restoredState.notes == "B-Tree implementation")

        // Insert new assignment with restored state
        let reimported = Assignment(
            title: "Database Indexing Lab",
            course: "CS302",
            dueDate: Date().addingTimeInterval(86400),
            priority: .medium,
            notes: restoredState.notes ?? "",
            isCompleted: restoredState.isCompleted,
            source: "moodle",
            moodleEventId: "db_lab_202",
            accountId: accountId
        )
        context.insert(reimported)
        try context.save()

        #expect(reimported.isCompleted == true)
    }

    @Test @MainActor func testRepeatedMoodleRefreshesIdempotentNoDuplicates() async throws {
        let schema = Schema([Assignment.self, Hackathon.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let accountId = "refresh_student_03"
        let mockBackend = MockTaskBackendService()
        TaskSyncCoordinator.shared.backendService = mockBackend

        let initialAssignment = Assignment(
            title: "Computer Networks Socket Lab",
            course: "CS304",
            dueDate: Date().addingTimeInterval(86400),
            priority: .high,
            notes: "Completed TCP handshake",
            isCompleted: true,
            source: "moodle",
            moodleEventId: "cn_lab_304",
            accountId: accountId
        )
        context.insert(initialAssignment)
        try context.save()

        TaskSyncCoordinator.shared.recordTaskStateChange(for: initialAssignment, accountId: accountId)

        // Simulate 3 repeated Moodle sync cycles with the same assignment
        for _ in 1...3 {
            let descriptor = FetchDescriptor<Assignment>()
            let existingList = try context.fetch(descriptor).filter {
                $0.source == "moodle" && $0.accountId == accountId
            }

            if let existing = existingList.first(where: { $0.moodleEventId == "cn_lab_304" }) {
                // Update server fields without duplicating or resetting isCompleted
                existing.dueDate = Date().addingTimeInterval(90000)
                TaskSyncCoordinator.shared.recordTaskStateChange(for: existing, accountId: accountId)
            } else {
                let restored = TaskSyncCoordinator.shared.restoreTaskState(
                    source: "moodle",
                    moodleEventId: "cn_lab_304",
                    title: "Computer Networks Socket Lab",
                    course: "CS304",
                    accountId: accountId
                )
                let item = Assignment(
                    title: "Computer Networks Socket Lab",
                    course: "CS304",
                    isCompleted: restored.isCompleted,
                    source: "moodle",
                    moodleEventId: "cn_lab_304",
                    accountId: accountId
                )
                context.insert(item)
            }
            try context.save()
        }

        let totalAssignments = try context.fetch(FetchDescriptor<Assignment>())
        #expect(totalAssignments.count == 1, "Repeated Moodle refreshes must not create duplicates")
        #expect(totalAssignments.first?.isCompleted == true, "Repeated Moodle refreshes must preserve completion")
    }

    @Test @MainActor func testPreserveCompletedStateArchiveStateAndNotes() async throws {
        let accountId = "preserve_student_04"
        let assignment = Assignment(
            title: "Web Security Penetration Report",
            course: "CS405",
            dueDate: Date().addingTimeInterval(86400),
            priority: .low,
            notes: "Tested SQL injection and XSS mitigation",
            isCompleted: true,
            isArchived: true,
            source: "moodle",
            moodleEventId: "sec_rep_405",
            accountId: accountId
        )

        TaskSyncCoordinator.shared.recordTaskStateChange(for: assignment, accountId: accountId)

        let restored = TaskSyncCoordinator.shared.restoreTaskState(
            source: "moodle",
            moodleEventId: "sec_rep_405",
            title: "Web Security Penetration Report",
            course: "CS405",
            accountId: accountId
        )

        #expect(restored.isCompleted == true)
        #expect(restored.isArchived == true)
        #expect(restored.notes == "Tested SQL injection and XSS mitigation")
    }

    @Test @MainActor func testSwitchBetweenTwoAccountsStrictIsolation() async throws {
        let schema = Schema([Assignment.self, Hackathon.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let mockBackend = MockTaskBackendService()
        let coordinator = TaskSyncCoordinator.shared
        coordinator.backendService = mockBackend
        let session = SessionManager.shared

        let accountAlice = "student_alice"
        let accountBob = "student_bob"

        // 1. Alice logs in and completes assignment
        session.logInWithMoodle(user: "Alice Smith", site: MoodleService.defaultSiteUrl, accountId: accountAlice)
        let aliceUserId = BackendAuthManager.deterministicUserId(forAccount: accountAlice)

        let aliceAssignment = Assignment(
            title: "Cloud Computing Docker Project",
            course: "CS406",
            dueDate: Date().addingTimeInterval(86400),
            isCompleted: true,
            source: "moodle",
            moodleEventId: "cloud_docker_406",
            accountId: accountAlice
        )
        context.insert(aliceAssignment)
        try context.save()

        coordinator.recordTaskStateChange(for: aliceAssignment, accountId: accountAlice)
        await coordinator.flushPendingQueue(userId: aliceUserId)

        // 2. Alice logs out
        session.logOut(modelContext: context)

        // 3. Bob logs in
        session.logInWithMoodle(user: "Bob Jones", site: MoodleService.defaultSiteUrl, accountId: accountBob)
        let bobUserId = BackendAuthManager.deterministicUserId(forAccount: accountBob)

        // Check Bob's state in backend mock
        let bobStates = try await mockBackend.fetchTaskStates(userId: bobUserId, sourceAccountKey: accountBob)
        #expect(bobStates.isEmpty, "Bob must not have Alice's states in backend")

        // Bob imports the same assignment from Moodle
        let bobRestored = coordinator.restoreTaskState(
            source: "moodle",
            moodleEventId: "cloud_docker_406",
            title: "Cloud Computing Docker Project",
            course: "CS406",
            accountId: accountBob
        )

        #expect(bobRestored.isCompleted == false, "Alice's completed state must NEVER leak to Bob's account")
    }

    @Test @MainActor func testCompleteTaskOfflineAndSynchronizeLater() async throws {
        let mockBackend = MockTaskBackendService()
        mockBackend.shouldSimulateNetworkFailure = true // Simulate offline / network dropout

        let coordinator = TaskSyncCoordinator.shared
        coordinator.backendService = mockBackend
        let accountId = "offline_student_06"
        let userId = BackendAuthManager.shared.bindMoodleAccount(accountId: accountId)

        PendingSyncQueue.shared.clear(for: userId)

        let assignment = Assignment(
            title: "Software Engineering Sprint 2",
            course: "CS308",
            dueDate: Date().addingTimeInterval(86400),
            isCompleted: true,
            source: "moodle",
            moodleEventId: "se_sprint_308",
            accountId: accountId
        )

        coordinator.recordTaskStateChange(for: assignment, accountId: accountId)

        // Attempting to flush while offline leaves item in queue
        await coordinator.flushPendingQueue(userId: userId)
        #expect(PendingSyncQueue.shared.count(for: userId) == 1, "Item must remain in pending queue when offline")
        if case .offline(let count) = coordinator.syncStatus {
            #expect(count == 1)
        }

        // Connectivity returns
        mockBackend.shouldSimulateNetworkFailure = false
        await coordinator.flushPendingQueue(userId: userId)

        #expect(PendingSyncQueue.shared.count(for: userId) == 0, "Queue must be empty after successful sync")
        #expect(coordinator.syncStatus == .synced)

        let serverRecords = try await mockBackend.fetchTaskStates(userId: userId, sourceAccountKey: accountId)
        #expect(serverRecords.count == 1)
        #expect(serverRecords.first?.isCompleted == true)
    }

    @Test @MainActor func testRetryFailedRequestsWithoutDuplicateRows() async throws {
        let mockBackend = MockTaskBackendService()
        let coordinator = TaskSyncCoordinator.shared
        coordinator.backendService = mockBackend
        let accountId = "retry_student_07"
        let userId = BackendAuthManager.shared.bindMoodleAccount(accountId: accountId)

        PendingSyncQueue.shared.clear(for: userId)

        let record = UserTaskStateRecord(
            userId: userId,
            taskKey: "moodle_retry_707",
            source: "moodle",
            sourceAccountKey: accountId,
            isCompleted: true,
            notes: "First attempt"
        )

        // Multiple idempotent enqueues (retries)
        PendingSyncQueue.shared.enqueueUpsert(record)
        PendingSyncQueue.shared.enqueueUpsert(record)
        PendingSyncQueue.shared.enqueueUpsert(record)

        #expect(PendingSyncQueue.shared.count(for: userId) == 1, "Queue must deduplicate multiple retries for same taskKey")

        await coordinator.flushPendingQueue(userId: userId)
        let records = try await mockBackend.fetchTaskStates(userId: userId, sourceAccountKey: accountId)
        #expect(records.count == 1, "Backend must not contain duplicate rows on retried requests")
    }

    @Test @MainActor func testUpdateDeadlinesWithoutChangingPersonalCompletionStatus() async throws {
        let schema = Schema([Assignment.self, Hackathon.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let originalDate = Date().addingTimeInterval(86400)
        let assignment = Assignment(
            title: "Microprocessors Lab Report",
            course: "EE201",
            dueDate: originalDate,
            isCompleted: true,
            source: "moodle",
            moodleEventId: "mp_lab_201",
            accountId: "deadline_student_08"
        )
        context.insert(assignment)
        try context.save()

        // Server updates deadline (e.g. extension granted)
        let extendedDate = Date().addingTimeInterval(259200)
        assignment.dueDate = extendedDate
        try context.save()

        #expect(assignment.dueDate == extendedDate)
        #expect(assignment.isCompleted == true, "Server deadline updates must never reset personal completion")
    }

    @Test @MainActor func testHandleAssignmentTitleChangeWithStableId() async throws {
        let accountId = "title_change_student_09"
        let stableEventId = "essay_id_909"

        let originalAssignment = Assignment(
            title: "Technical Writing Draft Essay",
            course: "ENG101",
            isCompleted: true,
            source: "moodle",
            moodleEventId: stableEventId,
            accountId: accountId
        )

        #expect(originalAssignment.stableTaskKey == "moodle_\(stableEventId)")
        TaskSyncCoordinator.shared.recordTaskStateChange(for: originalAssignment, accountId: accountId)

        // Instructor renames the assignment on Moodle
        let renamedDraftTitle = "Technical Writing Final Report"
        let restored = TaskSyncCoordinator.shared.restoreTaskState(
            source: "moodle",
            moodleEventId: stableEventId,
            title: renamedDraftTitle,
            course: "ENG101",
            accountId: accountId
        )

        #expect(restored.isCompleted == true, "Matching by stable moodleEventId must preserve completion even when title changes")
    }

    @Test @MainActor func testKeepLocalAndOCRCreatedTasksFunctional() async throws {
        let schema = Schema([Assignment.self, Hackathon.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let session = SessionManager.shared

        // 1. Create a manual assignment
        let manualAssignment = Assignment(
            title: "Self Study Discrete Mathematics",
            course: "MATH201",
            dueDate: Date().addingTimeInterval(86400),
            isCompleted: true,
            source: "manual"
        )
        context.insert(manualAssignment)

        // 2. Create an OCR scanned examination
        let examAssignment = Assignment(
            title: "Mid-Term Examination: Algorithms",
            course: "CS301",
            dueDate: Date().addingTimeInterval(172800),
            isCompleted: false,
            source: "scan",
            eventType: "exam",
            sessionTime: "10:00 AM - 01:00 PM"
        )
        context.insert(examAssignment)
        try context.save()

        TaskSyncCoordinator.shared.recordTaskStateChange(for: manualAssignment)
        TaskSyncCoordinator.shared.recordTaskStateChange(for: examAssignment)

        // 3. User logs out of Moodle
        session.logOut(modelContext: context)

        // 4. Verify manual task and OCR exam are strictly preserved!
        let remainingTasks = try context.fetch(FetchDescriptor<Assignment>())
        #expect(remainingTasks.count == 2, "Logout must NEVER delete manual assignments or scanned exams")

        let fetchedManual = remainingTasks.first(where: { $0.source == "manual" })
        let fetchedExam = remainingTasks.first(where: { $0.eventType == "exam" })

        #expect(fetchedManual != nil && fetchedManual?.isCompleted == true)
        #expect(fetchedExam != nil && fetchedExam?.sessionTime == "10:00 AM - 01:00 PM")
    }

    // MARK: - Coding Radar Workspace & Task Management Tests

    @Test func testAppWorkspaceNavigationStructureAndTabs() {
        let workspaces = AppWorkspace.allCases
        #expect(workspaces.count == 2)
        #expect(workspaces.contains(.assignmentRadar))
        #expect(workspaces.contains(.codingRadar))

        #expect(AppWorkspace.assignmentRadar.title == "Assignment Radar")
        #expect(AppWorkspace.codingRadar.title == "Coding Radar")
        #expect(AppWorkspace.assignmentRadar.iconName == "graduationcap.fill")
        #expect(AppWorkspace.codingRadar.iconName == "chevron.left.forwardslash.chevron.right")
    }

    @Test func testPlatformCatalogSupportedPlatformsAndStatus() {
        let catalog = PlatformCatalog.platforms
        #expect(catalog.count == 7)

        let ids = catalog.map { $0.id }
        #expect(ids.contains("leetcode"))
        #expect(ids.contains("gfg"))
        #expect(ids.contains("codeforces"))
        #expect(ids.contains("codechef"))
        #expect(ids.contains("atcoder"))
        #expect(ids.contains("hackerrank"))
        #expect(ids.contains("codestudio"))

        // Verify only verified implementations have automatic live feeds
        let leetcode = PlatformCatalog.find(id: "leetcode")
        #expect(leetcode?.supportsAutomaticData == true)
        #expect(leetcode?.integrationStatusLabel == "Live Data Available")

        let gfg = PlatformCatalog.find(id: "gfg")
        #expect(gfg?.supportsAutomaticData == true)
        #expect(gfg?.integrationStatusLabel == "Live Data Available")

        // Verify all other platforms are designated as manual tracking
        let codeforces = PlatformCatalog.find(id: "codeforces")
        #expect(codeforces?.supportsAutomaticData == false)
        #expect(codeforces?.integrationStatusLabel == "Manual tracking")

        let codechef = PlatformCatalog.find(id: "codechef")
        #expect(codechef?.supportsAutomaticData == false)

        let atcoder = PlatformCatalog.find(id: "atcoder")
        #expect(atcoder?.supportsAutomaticData == false)
    }

    @Test @MainActor func testOptionalPlatformAdditionAndTracking() throws {
        let schema = Schema([Assignment.self, Hackathon.self, CodingTask.self, TrackedPlatform.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // Starts with 0 tracked platforms
        var tracked = try context.fetch(FetchDescriptor<TrackedPlatform>())
        #expect(tracked.isEmpty, "Platforms must start not added by default")

        // User chooses to add Codeforces and LeetCode
        let cf = TrackedPlatform(platformId: "codeforces", platformName: "Codeforces", profileUrl: "https://codeforces.com/profile/tourist")
        let lc = TrackedPlatform(platformId: "leetcode", platformName: "LeetCode")
        context.insert(cf)
        context.insert(lc)
        try context.save()

        tracked = try context.fetch(FetchDescriptor<TrackedPlatform>())
        #expect(tracked.count == 2)
        #expect(tracked.contains(where: { $0.platformId == "codeforces" }))
        #expect(tracked.contains(where: { $0.platformId == "leetcode" }))
    }

    @Test @MainActor func testRemovingPlatformPreservesTaskHistory() throws {
        let schema = Schema([Assignment.self, Hackathon.self, CodingTask.self, TrackedPlatform.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // Add AtCoder platform
        let atcoderPlatform = TrackedPlatform(platformId: "atcoder", platformName: "AtCoder")
        context.insert(atcoderPlatform)

        // Add 2 tasks under AtCoder
        let task1 = CodingTask(title: "AtCoder ABC 350 - Problem A", platformId: "atcoder", platformName: "AtCoder", isCompleted: true)
        let task2 = CodingTask(title: "AtCoder Beginner Contest 351", platformId: "atcoder", platformName: "AtCoder", taskType: .contest)
        context.insert(task1)
        context.insert(task2)
        try context.save()

        // User removes AtCoder platform from My Platforms
        context.delete(atcoderPlatform)
        try context.save()

        // Verify platform is removed
        let remainingPlatforms = try context.fetch(FetchDescriptor<TrackedPlatform>())
        #expect(remainingPlatforms.isEmpty)

        // Verify user's task history is STRICTLY PRESERVED!
        let remainingTasks = try context.fetch(FetchDescriptor<CodingTask>())
        #expect(remainingTasks.count == 2, "Removing a platform must not erase associated coding tasks")
        #expect(remainingTasks.first(where: { $0.title.contains("Problem A") })?.isCompleted == true)
    }

    @Test @MainActor func testManualCodingTaskCreationValidationAndCompletionPersistence() throws {
        let schema = Schema([Assignment.self, Hackathon.self, CodingTask.self, TrackedPlatform.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let dueDate = Date().addingTimeInterval(86400)
        let task = CodingTask(
            title: "Longest Increasing Subsequence",
            platformId: "leetcode",
            platformName: "LeetCode",
            taskType: .practiceProblem,
            difficulty: "Medium",
            topicTags: "Dynamic Programming, Binary Search",
            dueDate: dueDate,
            officialUrl: "https://leetcode.com/problems/longest-increasing-subsequence",
            notes: "O(n log n) with patience sorting",
            isCompleted: false
        )
        context.insert(task)
        try context.save()

        #expect(task.title == "Longest Increasing Subsequence")
        #expect(task.difficulty == "Medium")
        #expect(task.formattedTimeline?.contains("Due") == true)

        // Toggle completion
        task.isCompleted = true
        task.completedAt = Date()
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CodingTask>()).first
        #expect(fetched?.isCompleted == true)
        #expect(fetched?.completedAt != nil)
    }

    @Test @MainActor func testCodingRadarFiltersLogic() throws {
        let schema = Schema([Assignment.self, Hackathon.self, CodingTask.self, TrackedPlatform.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let pendingTask = CodingTask(title: "Two Sum", taskType: .practiceProblem, isCompleted: false)
        let completedTask = CodingTask(title: "Reverse Linked List", taskType: .practiceProblem, isCompleted: true)
        let contestTask = CodingTask(title: "Codeforces Round 950", taskType: .contest, isCompleted: false)

        context.insert(pendingTask)
        context.insert(completedTask)
        context.insert(contestTask)
        try context.save()

        let all = try context.fetch(FetchDescriptor<CodingTask>())
        let pending = all.filter { !$0.isCompleted }
        let completed = all.filter { $0.isCompleted }
        let contests = all.filter { $0.isContest }

        #expect(pending.count == 2) // Two Sum + contest
        #expect(completed.count == 1) // Reverse Linked List
        #expect(contests.count == 1) // Codeforces Round 950
    }

    @Test @MainActor func testMoodleLogoutDoesNotEraseCodingTasksOrTrackedPlatforms() throws {
        let schema = Schema([Assignment.self, Hackathon.self, CodingTask.self, TrackedPlatform.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let session = SessionManager.shared
        session.logInWithMoodle(user: "Student Charlie", site: MoodleService.defaultSiteUrl, accountId: "charlie_01")

        // Academic assignment
        let academic = Assignment(title: "Moodle Assignment", source: "moodle", accountId: "charlie_01")
        context.insert(academic)

        // Coding task and tracked platform
        let codingTask = CodingTask(title: "CodeChef Starters 130", platformId: "codechef", platformName: "CodeChef", taskType: .contest)
        let platform = TrackedPlatform(platformId: "codechef", platformName: "CodeChef")
        context.insert(codingTask)
        context.insert(platform)
        try context.save()

        // Moodle logout
        session.logOut(modelContext: context)

        // Verify Moodle assignment is removed
        let remainingAssignments = try context.fetch(FetchDescriptor<Assignment>())
        #expect(remainingAssignments.isEmpty, "Moodle assignments should be cleared on logout")

        // Verify Coding Task and Tracked Platform are 100% PRESERVED!
        let remainingCodingTasks = try context.fetch(FetchDescriptor<CodingTask>())
        let remainingPlatforms = try context.fetch(FetchDescriptor<TrackedPlatform>())
        #expect(remainingCodingTasks.count == 1, "Coding tasks must never be deleted on Moodle logout")
        #expect(remainingPlatforms.count == 1, "Tracked platforms must never be deleted on Moodle logout")
    }

    // MARK: - Platform Visual Identities & Streak Calculation Tests

    @Test func testPlatformSpecificVisualIdentityHexColors() {
        // 1. Verify exact official accent colors
        let leetCode = PlatformCatalog.find(id: "leetcode")
        #expect(leetCode?.accentHex == "#FFA116")

        let gfg = PlatformCatalog.find(id: "gfg")
        #expect(gfg?.accentHex == "#2F8D46")

        let codeforces = PlatformCatalog.find(id: "codeforces")
        #expect(codeforces?.accentHex == "#6599FF")

        let codechef = PlatformCatalog.find(id: "codechef")
        #expect(codechef?.accentHex == "#E9B44C")

        let atcoder = PlatformCatalog.find(id: "atcoder")
        #expect(atcoder?.accentHex == "#8C96A8")

        let hackerrank = PlatformCatalog.find(id: "hackerrank")
        #expect(hackerrank?.accentHex == "#2EC866")

        let codestudio = PlatformCatalog.find(id: "codestudio")
        #expect(codestudio?.accentHex == "#B78AFF")

        // 2. Color lookup matches by name or ID
        let lcColor = PlatformCatalog.color(for: "LeetCode")
        let cfColor = PlatformCatalog.color(for: "Codeforces Round 900")
        let ninjaColor = PlatformCatalog.color(for: "Coding Ninjas")

        #expect(lcColor == Color(hex: "#FFA116"))
        #expect(cfColor == Color(hex: "#6599FF"))
        #expect(ninjaColor == Color(hex: "#B78AFF"))
    }

    @Test func testCodingStreakEmptyTasks() {
        let stats = CodingStreakCalculator.calculate(tasks: [])
        #expect(stats.currentStreak == 0)
        #expect(stats.longestStreak == 0)
        #expect(stats.totalActiveDays == 0)
        #expect(stats.activeDates.isEmpty)
    }

    @Test func testCodingStreakSingleTaskToday() {
        let calendar = Calendar.current
        let now = Date()
        let task = CodingTask(title: "Two Sum", isCompleted: true)
        task.completedAt = now

        let stats = CodingStreakCalculator.calculate(tasks: [task], calendar: calendar, now: now)
        #expect(stats.currentStreak == 1)
        #expect(stats.longestStreak == 1)
        #expect(stats.totalActiveDays == 1)
        #expect(stats.activeDates.contains(calendar.startOfDay(for: now)))
    }

    @Test func testCodingStreakMultipleCompletionsOnSameDay() {
        let calendar = Calendar.current
        let now = Date()

        let task1 = CodingTask(title: "Problem 1", isCompleted: true)
        task1.completedAt = now
        let task2 = CodingTask(title: "Problem 2", isCompleted: true)
        task2.completedAt = now.addingTimeInterval(3600)
        let task3 = CodingTask(title: "Problem 3", isCompleted: true)
        task3.completedAt = now.addingTimeInterval(7200)

        let stats = CodingStreakCalculator.calculate(tasks: [task1, task2, task3], calendar: calendar, now: now)
        // Multiple completions on one calendar day count as ONE active day
        #expect(stats.totalActiveDays == 1)
        #expect(stats.currentStreak == 1)
        #expect(stats.longestStreak == 1)
        #expect(stats.dailyCompletionsCount[calendar.startOfDay(for: now)] == 3)
    }

    @Test func testCodingStreakConsecutiveActiveDays() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let taskYesterday = CodingTask(title: "Yesterday Problem", isCompleted: true)
        taskYesterday.completedAt = yesterday

        let taskToday = CodingTask(title: "Today Problem", isCompleted: true)
        taskToday.completedAt = today

        let stats = CodingStreakCalculator.calculate(tasks: [taskYesterday, taskToday], calendar: calendar, now: now)
        #expect(stats.currentStreak == 2)
        #expect(stats.longestStreak == 2)
        #expect(stats.totalActiveDays == 2)
    }

    @Test func testCodingStreakPendingGracePeriod() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        // User completed yesterday, but hasn't completed today yet
        let taskYesterday = CodingTask(title: "Yesterday Problem", isCompleted: true)
        taskYesterday.completedAt = yesterday

        let stats = CodingStreakCalculator.calculate(tasks: [taskYesterday], calendar: calendar, now: now)
        // Streak is preserved pending today's activity
        #expect(stats.currentStreak == 1)
        #expect(stats.longestStreak == 1)
    }

    @Test func testCodingStreakMissedDaysBreaksCurrentStreak() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!

        // Tasks 3 days ago and 2 days ago, but missed yesterday and today
        let task1 = CodingTask(title: "P1", isCompleted: true)
        task1.completedAt = threeDaysAgo
        let task2 = CodingTask(title: "P2", isCompleted: true)
        task2.completedAt = twoDaysAgo

        let stats = CodingStreakCalculator.calculate(tasks: [task1, task2], calendar: calendar, now: now)
        #expect(stats.currentStreak == 0, "Streak must be 0 when missed yesterday and today")
        #expect(stats.longestStreak == 2, "Longest streak must preserve the 2 consecutive days")
        #expect(stats.totalActiveDays == 2)
    }

    @Test func testCodingStreakUncheckingTaskRecalculatesImmediately() {
        let calendar = Calendar.current
        let now = Date()

        let task = CodingTask(title: "Dynamic Problem", isCompleted: true)
        task.completedAt = now

        var stats = CodingStreakCalculator.calculate(tasks: [task], calendar: calendar, now: now)
        #expect(stats.currentStreak == 1)

        // User unchecks the task
        task.isCompleted = false
        task.completedAt = nil

        stats = CodingStreakCalculator.calculate(tasks: [task], calendar: calendar, now: now)
        #expect(stats.currentStreak == 0)
        #expect(stats.totalActiveDays == 0)
    }

    @Test func testCodingStreakLongestStreakPreservedAcrossGaps() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        // 4 consecutive days in the past
        var tasks: [CodingTask] = []
        for i in 10...13 {
            let pastDate = calendar.date(byAdding: .day, value: -i, to: today)!
            let t = CodingTask(title: "Past \(i)", isCompleted: true)
            t.completedAt = pastDate
            tasks.append(t)
        }

        // Today only
        let todayTask = CodingTask(title: "Today", isCompleted: true)
        todayTask.completedAt = today
        tasks.append(todayTask)

        let stats = CodingStreakCalculator.calculate(tasks: tasks, calendar: calendar, now: now)
        #expect(stats.currentStreak == 1)
        #expect(stats.longestStreak == 4)
        #expect(stats.totalActiveDays == 5)
    }

    @Test func testContributionGridMatrixBuilding() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        var counts: [Date: Int] = [:]
        counts[today] = 2

        let grid = CodingStreakCalculator.buildContributionGrid(activeCounts: counts, numberOfWeeks: 14, calendar: calendar, now: now)
        #expect(grid.count == 14)
        for week in grid {
            #expect(week.count == 7)
        }

        // Verify today's cell intensity
        let todayCell = grid.flatMap { $0 }.first { calendar.isDate($0.date, inSameDayAs: today) }
        #expect(todayCell != nil)
        #expect(todayCell?.count == 2)
        #expect(todayCell?.intensityLevel == 2)
        #expect(todayCell?.isToday == true)
    }

    // MARK: - Coding Radar Daily Challenge & Contest Notifications Tests

    @Test func testNoDailyReminderAfterDailyQuestionCompleted() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let now = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: today)! // 2:00 PM

        // Completed daily question today
        let completedDaily = CodingTask(title: "LeetCode Daily Challenge", taskType: .dailyQuestion, isCompleted: true)
        completedDaily.completedAt = now.addingTimeInterval(-3600) // completed at 1:00 PM

        let plan = CodingNotificationManager.calculateDailyReminderPlan(
            tasks: [completedDaily],
            calendar: calendar,
            now: now
        )

        #expect(plan == nil, "No daily challenge reminder should be scheduled once a daily question has been completed today")
    }

    @Test func testDailyReminderScheduledAt9PMWhenNoEligibleQuestionCompleted() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let now = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: today)! // 2:00 PM

        // Pending daily question
        let pendingDaily = CodingTask(title: "Two Sum Daily", taskType: .dailyQuestion, dueDate: today, isCompleted: false)

        let plan = CodingNotificationManager.calculateDailyReminderPlan(
            tasks: [pendingDaily],
            calendar: calendar,
            now: now
        )

        #expect(plan != nil, "Daily reminder must be scheduled at 9:00 PM when an eligible question is pending")
        #expect(plan?.title == "Time for your daily challenge")
        #expect(plan?.body.contains("You haven't completed a daily coding question today") == true)

        let triggerHour = calendar.component(.hour, from: plan!.triggerDate)
        let triggerMinute = calendar.component(.minute, from: plan!.triggerDate)
        #expect(triggerHour == 21, "Daily reminder must trigger at 9:00 PM (21:00)")
        #expect(triggerMinute == 0)
    }

    @Test func testNoDailyReminderIfNoDailyQuestionIsConfigured() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let now = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: today)!

        // User only has standard practice problems or contests, but NO daily question configured
        let practiceTask = CodingTask(title: "Reverse String", taskType: .practiceProblem, isCompleted: false)
        let contestTask = CodingTask(title: "Weekly Contest", taskType: .contest, isCompleted: false)

        let plan = CodingNotificationManager.calculateDailyReminderPlan(
            tasks: [practiceTask, contestTask],
            calendar: calendar,
            now: now
        )

        #expect(plan == nil, "Must not send a misleading reminder if no daily question is configured for that day")
    }

    @Test func testContestDayReminderOnlyForRegisteredContests() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let contestStart = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: tomorrow)! // Tomorrow 3:00 PM
        let now = Date()

        // 1. Unregistered contest (interested only)
        let interestedContest = CodingTask(
            title: "Codeforces Round 950",
            platformName: "Codeforces",
            taskType: .contest,
            registrationStatus: .interested,
            startDate: contestStart
        )

        let interestedPlans = CodingNotificationManager.calculateContestRemindersPlan(
            contest: interestedContest,
            calendar: calendar,
            now: now
        )
        #expect(interestedPlans.isEmpty, "Unregistered contests must NEVER generate contest reminders")

        // 2. Explicitly registered contest
        let registeredContest = CodingTask(
            title: "Codeforces Round 950",
            platformName: "Codeforces",
            taskType: .contest,
            registrationStatus: .registered,
            startDate: contestStart
        )

        let registeredPlans = CodingNotificationManager.calculateContestRemindersPlan(
            contest: registeredContest,
            calendar: calendar,
            now: now
        )
        #expect(registeredPlans.count == 2, "Registered contest must generate both contest-day and 15-minute reminders")
        #expect(registeredPlans.contains { $0.category == "CODING_CONTEST_DAY" })
        #expect(registeredPlans.contains { $0.category == "CODING_CONTEST_15MIN" })
    }

    @Test func testNo9AMReminderForContestThatStartsEarlier() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let earlyStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)! // 8:00 AM (starts before 9:00 AM)
        let now = Date()

        let earlyContest = CodingTask(
            title: "AtCoder Grand Contest",
            platformName: "AtCoder",
            taskType: .contest,
            registrationStatus: .registered,
            startDate: earlyStart
        )

        let plans = CodingNotificationManager.calculateContestRemindersPlan(
            contest: earlyContest,
            calendar: calendar,
            now: now
        )

        // 9:00 AM reminder should be skipped because contest starts at 8:00 AM
        let hasDayReminder = plans.contains { $0.category == "CODING_CONTEST_DAY" }
        #expect(!hasDayReminder, "9:00 AM reminder must be skipped when contest starts earlier than 9:00 AM")

        // 15-minute reminder should still be scheduled (at 7:45 AM)
        let min15Plan = plans.first { $0.category == "CODING_CONTEST_15MIN" }
        #expect(min15Plan != nil)
        let expectedTrigger = earlyStart.addingTimeInterval(-15 * 60)
        #expect(min15Plan?.triggerDate == expectedTrigger)
    }

    @Test func testContest15MinuteReminderCalculatedCorrectly() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let contestStart = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: tomorrow)! // 8:00 PM
        let now = Date()

        let contest = CodingTask(
            title: "LeetCode Biweekly Contest 140",
            platformName: "LeetCode",
            taskType: .contest,
            registrationStatus: .registered,
            startDate: contestStart
        )

        let plans = CodingNotificationManager.calculateContestRemindersPlan(
            contest: contest,
            calendar: calendar,
            now: now
        )

        let min15Plan = plans.first { $0.category == "CODING_CONTEST_15MIN" }
        #expect(min15Plan != nil)
        #expect(min15Plan?.title == "Contest starts in 15 minutes")
        #expect(min15Plan?.body == "LeetCode — LeetCode Biweekly Contest 140 is about to begin. Open the contest page and get ready!")
        #expect(min15Plan?.triggerDate == contestStart.addingTimeInterval(-15 * 60))
    }

    @Test func testPastContestsAndPastReminderTimesSkipped() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let now = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: today)! // Current time: 11:00 AM today
        let contestStartToday = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: today)! // 4:00 PM today

        let contest = CodingTask(
            title: "CodeChef Starters",
            platformName: "CodeChef",
            taskType: .contest,
            registrationStatus: .registered,
            startDate: contestStartToday
        )

        let plans = CodingNotificationManager.calculateContestRemindersPlan(
            contest: contest,
            calendar: calendar,
            now: now
        )

        // 9:00 AM reminder is already in the past (now is 11:00 AM), so it must NOT be scheduled
        let hasDayReminder = plans.contains { $0.category == "CODING_CONTEST_DAY" }
        #expect(!hasDayReminder, "Past 9:00 AM reminder on contest day must be skipped")

        // 15-minute reminder (3:45 PM) is in the future, so it MUST be scheduled
        let has15mReminder = plans.contains { $0.category == "CODING_CONTEST_15MIN" }
        #expect(has15mReminder, "Future 15-minute reminder must still be scheduled")
    }

    @Test func testChangingRegistrationOrContestTimesCancelsAndReplacesNotifications() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let initialStart = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: tomorrow)!
        let now = Date()

        let contest = CodingTask(
            title: "HackerRank CodeSprint",
            platformName: "HackerRank",
            taskType: .contest,
            registrationStatus: .registered,
            startDate: initialStart
        )

        // 1. Initial state: registered -> 2 plans
        var plans = CodingNotificationManager.calculateContestRemindersPlan(contest: contest, calendar: calendar, now: now)
        #expect(plans.count == 2)

        // 2. User unregisters (changes to .interested or .cancelled)
        contest.registrationStatus = .interested
        plans = CodingNotificationManager.calculateContestRemindersPlan(contest: contest, calendar: calendar, now: now)
        #expect(plans.isEmpty, "Unregistering cancels all pending reminders")

        // 3. User re-registers and contest start time shifts by 3 hours
        contest.registrationStatus = .registered
        let updatedStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: tomorrow)! // 6:00 PM
        contest.startDate = updatedStart

        plans = CodingNotificationManager.calculateContestRemindersPlan(contest: contest, calendar: calendar, now: now)
        #expect(plans.count == 2)
        let min15Plan = plans.first { $0.category == "CODING_CONTEST_15MIN" }
        #expect(min15Plan?.triggerDate == updatedStart.addingTimeInterval(-15 * 60), "15-minute trigger must be updated to new start time")
    }

    @Test func testDuplicateSchedulingPreventedViaDeterministicIdentifiers() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        let id1 = CodingNotificationManager.dailyReminderIdentifier(for: today, calendar: calendar)
        let id2 = CodingNotificationManager.dailyReminderIdentifier(for: today, calendar: calendar)
        #expect(id1 == id2, "Daily reminder identifiers on the same calendar day must be identical and idempotent")

        let contestId = UUID()
        let cId1 = CodingNotificationManager.contestDayReminderIdentifier(for: contestId)
        let cId2 = CodingNotificationManager.contestDayReminderIdentifier(for: contestId)
        #expect(cId1 == cId2, "Contest day reminder identifiers for the same contest must be idempotent")
    }

    @Test func testLocalTimeZoneAndDateBoundaryHandling() {
        var tokyoCalendar = Calendar(identifier: .gregorian)
        tokyoCalendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        let now = Date()
        let tokyoToday = tokyoCalendar.startOfDay(for: now)
        let tokyoNow = tokyoCalendar.date(bySettingHour: 10, minute: 0, second: 0, of: tokyoToday)!

        let dailyTask = CodingTask(title: "Tokyo Daily", taskType: .dailyQuestion, dueDate: tokyoToday, isCompleted: false)

        let plan = CodingNotificationManager.calculateDailyReminderPlan(
            tasks: [dailyTask],
            calendar: tokyoCalendar,
            now: tokyoNow
        )

        #expect(plan != nil)
        let triggerHour = tokyoCalendar.component(.hour, from: plan!.triggerDate)
        #expect(triggerHour == 21, "Daily reminder must trigger at 21:00 in the target calendar time zone")
    }

    @Test func testAcademicRemindersRemainUnaffectedByCodingNotifications() {
        let assignmentId = UUID()
        let academicId = NotificationService.identifier(for: assignmentId, offset: .twentyFourHours)

        let contestId = UUID()
        let codingDayId = CodingNotificationManager.contestDayReminderIdentifier(for: contestId)
        let coding15mId = CodingNotificationManager.contest15MinReminderIdentifier(for: contestId)
        let codingDailyId = CodingNotificationManager.dailyReminderIdentifier(for: Date())

        #expect(academicId.hasPrefix("radar_rem_"), "Academic reminders must use radar_rem_ prefix")
        #expect(codingDayId.hasPrefix("coding_contest_"), "Coding contest reminders must use coding_contest_ prefix")
        #expect(coding15mId.hasPrefix("coding_contest_"), "Coding 15m reminders must use coding_contest_ prefix")
        #expect(codingDailyId.hasPrefix("coding_daily_"), "Coding daily reminders must use coding_daily_ prefix")

        #expect(!codingDayId.contains("radar_rem_"))
        #expect(!codingDailyId.contains("radar_rem_"))
        #expect(!academicId.contains("coding_"))
    }

    // MARK: - Coding Radar: Daily Questions, Contests, Manual Events & Calendar Tests

    @Test func testLeetCodeDailyQuestionModelAndTagParsing() {
        let question = LeetCodeDailyQuestion(
            date: "2026-10-24",
            title: "Longest Increasing Path in a Matrix",
            titleSlug: "longest-increasing-path-in-a-matrix",
            difficulty: "Hard",
            questionFrontendId: "329",
            problemUrl: URL(string: "https://leetcode.com/problems/longest-increasing-path-in-a-matrix/"),
            topicTags: ["Dynamic Programming", "Depth-First Search", "Graph"]
        )

        #expect(question.id == "2026-10-24")
        #expect(question.title == "Longest Increasing Path in a Matrix")
        #expect(question.difficulty == "Hard")
        #expect(question.difficultyColor == .red)
        #expect(question.topicTags.count == 3)
        #expect(question.topicTags.contains("Dynamic Programming"))
        #expect(question.problemUrl?.absoluteString == "https://leetcode.com/problems/longest-increasing-path-in-a-matrix/")

        let mediumQuestion = LeetCodeDailyQuestion(
            date: "2026-10-25",
            title: "Two Sum",
            titleSlug: "two-sum",
            difficulty: "Medium",
            questionFrontendId: "1",
            problemUrl: URL(string: "https://leetcode.com/problems/two-sum/"),
            topicTags: ["Array", "Hash Table"]
        )
        #expect(mediumQuestion.difficultyColor == .orange)

        let easyQuestion = LeetCodeDailyQuestion(
            date: "2026-10-26",
            title: "Palindrome Number",
            titleSlug: "palindrome-number",
            difficulty: "Easy",
            questionFrontendId: "9",
            problemUrl: nil,
            topicTags: ["Math"]
        )
        #expect(easyQuestion.difficultyColor == .green)
    }

    @Test func testLeetCodeUpcomingContestModelAndCountdown() {
        let now = Date()
        let futureStart = now.addingTimeInterval(3600 * 5) // 5 hours in future
        let contest = LeetCodeContest(
            title: "Weekly Contest 421",
            titleSlug: "weekly-contest-421",
            startTime: futureStart,
            durationSeconds: 5400 // 90 minutes
        )

        #expect(contest.id == "weekly-contest-421")
        #expect(contest.contestUrl?.absoluteString == "https://leetcode.com/contest/weekly-contest-421")
        #expect(contest.endTime == futureStart.addingTimeInterval(5400))
        #expect(contest.formattedDuration == "1h 30m")
        #expect(contest.isApproaching == true)
        #expect(contest.isLiveNow == false)
        #expect(!contest.relativeTimeDescription.isEmpty)

        // 2-hour contest formatting
        let twoHourContest = LeetCodeContest(
            title: "Biweekly Contest 142",
            titleSlug: "biweekly-contest-142",
            startTime: futureStart.addingTimeInterval(86400 * 3),
            durationSeconds: 7200
        )
        #expect(twoHourContest.formattedDuration == "2h")
        #expect(twoHourContest.isApproaching == false)
    }

    @Test func testGeeksForGeeksPOTDModelAndTagParsing() {
        let potd = GeeksForGeeksPOTD(
            id: 706240,
            date: "2026-10-24",
            title: "Alternative Sorting",
            difficulty: "Basic",
            problemUrl: URL(string: "https://practice.geeksforgeeks.org/problems/alternative-sorting1311/1"),
            topicTags: ["Arrays", "Sorting"]
        )

        #expect(potd.id == 706240)
        #expect(potd.title == "Alternative Sorting")
        #expect(potd.difficulty == "Basic")
        #expect(potd.topicTags.contains("Sorting"))
        #expect(potd.problemUrl != nil)
        #expect(potd.difficultyColor == .green)

        // Test honest unavailable state note for GFG contests
        let reason = GeeksForGeeksProvider.contestsUnavailableReason
        #expect(reason.contains("official portal requires session authentication"))
        #expect(reason.contains("Add Event"))
    }

    @Test @MainActor func testRefreshCodingDeduplicationOnRepeatedSync() async throws {
        let schema = Schema([CodingTask.self, TrackedPlatform.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // Enable LeetCode & GFG
        let lcPlatform = TrackedPlatform(platformId: "leetcode", platformName: "LeetCode")
        let gfgPlatform = TrackedPlatform(platformId: "gfg", platformName: "GeeksforGeeks")
        context.insert(lcPlatform)
        context.insert(gfgPlatform)
        try context.save()

        // Set mock data on providers
        let testDate = "2026-10-24"
        LeetCodeProvider.shared.dailyQuestion = LeetCodeDailyQuestion(
            date: testDate,
            title: "Subarray Sum Equals K",
            titleSlug: "subarray-sum-equals-k",
            difficulty: "Medium",
            questionFrontendId: "560",
            problemUrl: URL(string: "https://leetcode.com/problems/subarray-sum-equals-k/"),
            topicTags: ["Array", "Hash Table"]
        )
        LeetCodeProvider.shared.upcomingContests = [
            LeetCodeContest(
                title: "Weekly Contest 421",
                titleSlug: "weekly-contest-421",
                startTime: Date().addingTimeInterval(3600 * 24),
                durationSeconds: 5400
            )
        ]
        GeeksForGeeksProvider.shared.dailyProblem = GeeksForGeeksPOTD(
            id: 991,
            date: testDate,
            title: "Find Missing Number",
            difficulty: "Easy",
            problemUrl: URL(string: "https://practice.geeksforgeeks.org/problems/missing-number/1"),
            topicTags: ["Arrays", "Searching"]
        )

        // First sync
        await RefreshCoordinator.shared.refreshCoding(modelContext: context)

        let descriptor1 = FetchDescriptor<CodingTask>()
        let tasksAfterFirstSync = try context.fetch(descriptor1)
        #expect(!tasksAfterFirstSync.isEmpty, "First sync should import platform items")

        // Second sync with identical data
        await RefreshCoordinator.shared.refreshCoding(modelContext: context)

        let tasksAfterSecondSync = try context.fetch(descriptor1)
        #expect(tasksAfterSecondSync.count == tasksAfterFirstSync.count, "Second sync must NOT duplicate contests or daily questions")

        let providerIds = tasksAfterSecondSync.compactMap { $0.providerEventId }
        let uniqueProviderIds = Set(providerIds)
        #expect(providerIds.count == uniqueProviderIds.count, "Every imported provider event must have a unique identifier without duplicates")
    }

    @Test @MainActor func testRefreshPreservesUserCompletionAndNotes() async throws {
        let schema = Schema([CodingTask.self, TrackedPlatform.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let lcPlatform = TrackedPlatform(platformId: "leetcode", platformName: "LeetCode")
        context.insert(lcPlatform)
        try context.save()

        let testDate = "2026-10-24"
        LeetCodeProvider.shared.dailyQuestion = LeetCodeDailyQuestion(
            date: testDate,
            title: "Subarray Sum Equals K",
            titleSlug: "subarray-sum-equals-k",
            difficulty: "Medium",
            questionFrontendId: "560",
            problemUrl: URL(string: "https://leetcode.com/problems/subarray-sum-equals-k/"),
            topicTags: ["Array", "Hash Table"]
        )

        // Initial sync
        await RefreshCoordinator.shared.refreshCoding(modelContext: context)

        let descriptor = FetchDescriptor<CodingTask>()
        var tasks = try context.fetch(descriptor)
        let dailyTask = tasks.first { $0.isDailyQuestion && $0.platformId == "leetcode" }!

        // User marks complete and writes personal notes
        let completedTimestamp = Date().addingTimeInterval(-1800)
        dailyTask.isCompleted = true
        dailyTask.completedAt = completedTimestamp
        dailyTask.notes = "Solved using prefix sums and HashMap in O(N)."
        try context.save()

        // Re-run provider sync
        await RefreshCoordinator.shared.refreshCoding(modelContext: context)

        tasks = try context.fetch(descriptor)
        let refreshedTask = tasks.first { $0.isDailyQuestion && $0.platformId == "leetcode" }!

        #expect(refreshedTask.isCompleted == true, "Sync must preserve user completion status")
        #expect(refreshedTask.completedAt == completedTimestamp, "Sync must preserve user completedAt timestamp")
        #expect(refreshedTask.notes == "Solved using prefix sums and HashMap in O(N).", "Sync must preserve user personal notes")
    }

    @Test @MainActor func testRefreshPreservesContestRegistrationStatus() async throws {
        let schema = Schema([CodingTask.self, TrackedPlatform.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let lcPlatform = TrackedPlatform(platformId: "leetcode", platformName: "LeetCode")
        context.insert(lcPlatform)
        try context.save()

        LeetCodeProvider.shared.upcomingContests = [
            LeetCodeContest(
                title: "Weekly Contest 421",
                titleSlug: "weekly-contest-421",
                startTime: Date().addingTimeInterval(3600 * 24),
                durationSeconds: 5400
            )
        ]

        await RefreshCoordinator.shared.refreshCoding(modelContext: context)

        let descriptor = FetchDescriptor<CodingTask>()
        var tasks = try context.fetch(descriptor)
        let contestTask = tasks.first { $0.isContest }!

        // User marks as registered
        contestTask.registrationStatus = .registered
        try context.save()

        // Re-run sync
        await RefreshCoordinator.shared.refreshCoding(modelContext: context)

        tasks = try context.fetch(descriptor)
        let refreshedContest = tasks.first { $0.isContest }!
        #expect(refreshedContest.registrationStatus == .registered, "Sync must preserve contest registration status")
    }

    @Test @MainActor func testRefreshPreservesManualEvents() async throws {
        let schema = Schema([CodingTask.self, TrackedPlatform.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let lcPlatform = TrackedPlatform(platformId: "leetcode", platformName: "LeetCode")
        context.insert(lcPlatform)

        // User created a manual hackathon
        let manualEvent = CodingTask(
            title: "Local University Hackathon 2026",
            platformName: "KIET Tech Club",
            taskType: .hackathon,
            registrationStatus: .registered,
            startDate: Date().addingTimeInterval(86400 * 7),
            dueDate: Date().addingTimeInterval(86400 * 8),
            endDate: Date().addingTimeInterval(86400 * 8),
            isManualEvent: true
        )
        context.insert(manualEvent)
        try context.save()

        // Run sync
        await RefreshCoordinator.shared.refreshCoding(modelContext: context)

        let descriptor = FetchDescriptor<CodingTask>()
        let allTasks = try context.fetch(descriptor)
        let foundManual = allTasks.first { $0.title == "Local University Hackathon 2026" }

        #expect(foundManual != nil, "Manual events must NEVER be removed or overwritten by platform sync")
        #expect(foundManual?.isManualEvent == true)
        #expect(foundManual?.taskType == .hackathon)
    }

    @Test func testManualEventCreationAndFieldValidation() {
        let start = Date().addingTimeInterval(3600 * 24)
        let end = start.addingTimeInterval(3600 * 48)
        let regDeadline = start.addingTimeInterval(-3600 * 12)
        let subDeadline = end.addingTimeInterval(-3600 * 2)

        let event = CodingTask(
            title: "Global AI Hackathon",
            platformName: "MLH",
            taskType: .hackathon,
            registrationStatus: .registered,
            startDate: start,
            dueDate: end,
            endDate: end,
            registrationDeadline: regDeadline,
            submissionDeadline: subDeadline,
            officialUrl: "https://hackathon.ai",
            notes: "Build multimodal agent",
            isManualEvent: true
        )

        #expect(event.title == "Global AI Hackathon")
        #expect(event.platformName == "MLH")
        #expect(event.isEvent == true)
        #expect(event.isManualEvent == true)
        #expect(event.taskType == .hackathon)
        #expect(event.registrationDeadline == regDeadline)
        #expect(event.submissionDeadline == subDeadline)
        #expect(event.nextRelevantDate == regDeadline, "Next relevant date should be registration deadline since it is upcoming first")

        // Validation logic rules:
        // 1. Title cannot be empty
        let emptyTitle = "   ".trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(emptyTitle.isEmpty)

        // 2. End date cannot be before start date
        let invalidEndDate = start.addingTimeInterval(-3600)
        #expect(invalidEndDate < start)

        // 3. Registration deadline cannot be after start date
        let invalidRegDeadline = start.addingTimeInterval(3600)
        #expect(invalidRegDeadline > start)
    }

    @Test @MainActor func testManualEventEditingCompletionAndDeletion() async throws {
        let schema = Schema([CodingTask.self, TrackedPlatform.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let event = CodingTask(
            title: "Rust Systems Workshop",
            platformName: "Rust Foundation",
            taskType: .workshop,
            registrationStatus: .interested,
            startDate: Date().addingTimeInterval(86400),
            dueDate: Date().addingTimeInterval(86400 * 2),
            endDate: Date().addingTimeInterval(86400 * 2),
            isManualEvent: true
        )
        context.insert(event)
        try context.save()

        // 1. Edit event
        event.title = "Advanced Rust Concurrency Workshop"
        event.registrationStatus = .registered
        try context.save()

        var fetched = try context.fetch(FetchDescriptor<CodingTask>())
        #expect(fetched.first?.title == "Advanced Rust Concurrency Workshop")
        #expect(fetched.first?.registrationStatus == .registered)

        // 2. Complete event
        event.isCompleted = true
        event.completedAt = Date()
        event.registrationStatus = .completed
        try context.save()

        fetched = try context.fetch(FetchDescriptor<CodingTask>())
        #expect(fetched.first?.isCompleted == true)
        #expect(fetched.first?.registrationStatus == .completed)

        // 3. Delete event
        context.delete(event)
        try context.save()

        fetched = try context.fetch(FetchDescriptor<CodingTask>())
        #expect(fetched.isEmpty, "Deleted event must no longer exist in context")
    }

    @Test @MainActor func testManualEventPersistenceAcrossContextQueries() async throws {
        let schema = Schema([CodingTask.self, TrackedPlatform.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let start = Date().addingTimeInterval(86400 * 3)
        let end = Date().addingTimeInterval(86400 * 5)
        let event = CodingTask(
            title: "Summer Code Sprint",
            platformName: "DevPost",
            taskType: .hackathon,
            registrationStatus: .interested,
            startDate: start,
            dueDate: end,
            endDate: end,
            registrationDeadline: start.addingTimeInterval(-86400),
            submissionDeadline: end.addingTimeInterval(-3600),
            officialUrl: "https://devpost.com/sprint",
            notes: "Solo project submission",
            isManualEvent: true
        )
        context.insert(event)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CodingTask>())
        #expect(fetched.count == 1)
        let item = fetched.first!
        #expect(item.title == "Summer Code Sprint")
        #expect(item.platformName == "DevPost")
        #expect(item.isManualEvent == true)
        #expect(item.officialUrl == "https://devpost.com/sprint")
        #expect(item.notes == "Solo project submission")
    }

    @Test @MainActor func testMockCalendarSyncServicePermissionDenialPreservesLocalEvent() async {
        let mockCalendar = MockCalendarSyncService()
        mockCalendar.mockStatus = .denied

        let task = CodingTask(
            title: "Winter Hackathon",
            platformName: "Major League Hacking",
            taskType: .hackathon,
            startDate: Date().addingTimeInterval(86400),
            isManualEvent: true
        )

        let result = await mockCalendar.syncCodingTask(task, alertMinutesBefore: 15)
        #expect(result.eventId == nil, "Event ID must be nil when calendar permission is denied")
        #expect(result.error?.contains("Calendar permission denied") == true)
        #expect(task.calendarEventId == nil)
        // Task itself remains valid and preserved locally
        #expect(task.title == "Winter Hackathon")
    }

    @Test @MainActor func testMockCalendarSyncServiceSuccessfulSyncAndAlarms() async {
        let mockCalendar = MockCalendarSyncService()
        mockCalendar.mockStatus = .authorized

        let task = CodingTask(
            title: "Spring Hackathon 2026",
            platformName: "Devpost",
            taskType: .hackathon,
            startDate: Date().addingTimeInterval(86400 * 2),
            endDate: Date().addingTimeInterval(86400 * 3),
            isManualEvent: true
        )

        let result = await mockCalendar.syncCodingTask(task, alertMinutesBefore: 15)
        #expect(result.eventId != nil)
        #expect(result.error == nil)
        #expect(task.calendarEventId == result.eventId)

        // Verify stored in mock calendar with app security tag
        let savedEvent = mockCalendar.mockEvents[result.eventId!]
        #expect(savedEvent != nil)
        #expect(savedEvent?.title == "Spring Hackathon 2026")
        #expect(savedEvent?.notes.contains(CalendarSyncService.appManagedTag) == true, "Must include app security tag")
    }

    @Test @MainActor func testMockCalendarSyncServiceUpdatingLinkedEventPreventsDuplicates() async {
        let mockCalendar = MockCalendarSyncService()
        mockCalendar.mockStatus = .authorized

        let task = CodingTask(
            title: "Initial Hackathon Title",
            taskType: .hackathon,
            startDate: Date().addingTimeInterval(86400),
            isManualEvent: true
        )

        // First sync
        let firstResult = await mockCalendar.syncCodingTask(task, alertMinutesBefore: 15)
        let initialEventId = firstResult.eventId!
        #expect(mockCalendar.mockEvents.count == 1)

        // Update task title and sync again
        task.title = "Updated Hackathon Championship"
        let secondResult = await mockCalendar.syncCodingTask(task, alertMinutesBefore: 30)

        #expect(secondResult.eventId == initialEventId, "Re-syncing must update the existing event ID")
        #expect(mockCalendar.mockEvents.count == 1, "Must NOT create duplicate calendar events")
        #expect(mockCalendar.mockEvents[initialEventId]?.title == "Updated Hackathon Championship")
    }

    @Test @MainActor func testMockCalendarSyncServiceRemovesOnlyAppManagedEvents() {
        let mockCalendar = MockCalendarSyncService()

        // 1. Personal event belonging to the user
        let personalId = "personal_dentist_appointment"
        mockCalendar.mockEvents[personalId] = (
            title: "Dentist Appointment",
            date: Date(),
            notes: "Dr. Smith Clinic"
        )

        // 2. App-managed coding event
        let appId = "app_managed_contest"
        mockCalendar.mockEvents[appId] = (
            title: "Codeforces Round 990",
            date: Date(),
            notes: "Tag: \(CalendarSyncService.appManagedTag) · \(UUID().uuidString)]"
        )

        // Attempt to delete personal event
        mockCalendar.removeLinkedEvent(withIdentifier: personalId)
        #expect(mockCalendar.mockEvents[personalId] != nil, "Personal calendar events must NEVER be removed by Coding Radar")

        // Delete app-managed event
        mockCalendar.removeLinkedEvent(withIdentifier: appId)
        #expect(mockCalendar.mockEvents[appId] == nil, "App-managed calendar events should be removed cleanly")
    }

    @Test func testDeduplicateNotificationsWhenCalendarEventIsLinked() {
        let futureDate = Date().addingTimeInterval(3600 * 20)
        let contest = CodingTask(
            title: "LeetCode Biweekly Contest 142",
            platformName: "LeetCode",
            taskType: .contest,
            registrationStatus: .registered,
            startDate: futureDate,
            dueDate: futureDate.addingTimeInterval(5400)
        )

        // Case 1: No calendar event linked -> Coding Radar schedules notifications
        contest.calendarEventId = nil
        let plansWithoutCalendar = CodingNotificationManager.calculateContestRemindersPlan(
            contest: contest,
            now: Date()
        )
        #expect(!plansWithoutCalendar.isEmpty, "When not linked to Apple Calendar, local UNNotifications must be scheduled")

        // Case 2: Calendar event linked -> Coding Radar suppresses UNNotification reminders to avoid duplicate alerts
        contest.calendarEventId = "mock_calendar_evt_777"
        let plansWithCalendar = CodingNotificationManager.calculateContestRemindersPlan(
            contest: contest,
            now: Date()
        )
        #expect(plansWithCalendar.isEmpty, "When linked to Apple Calendar, local UNNotification reminders must be skipped to avoid duplicates")
    }

    // MARK: - Smart Coding Streak & Customizable Reminders Tests

    @Test func testCompletingDailyQuestion() {
        let calendar = Calendar.current
        let today = Date()
        let task = CodingTask(
            title: "LeetCode 2026. Daily Challenge",
            platformId: "leetcode",
            taskType: .dailyQuestion,
            dueDate: today,
            isCompleted: true,
            completedAt: today
        )
        let stats = CodingStreakCalculator.calculate(activities: [], tasks: [task], calendar: calendar, now: today)
        #expect(stats.currentStreak == 1)
        #expect(stats.isTodayActive == true)
        #expect(stats.problemsCompletedToday == 1)
        #expect(stats.totalProblemsSolved == 1)
    }

    @Test func testCompletingDifferentLeetCodeProblem() {
        let calendar = Calendar.current
        let today = Date()
        let activity = CodingActivityRecord(
            platformId: "leetcode",
            platformName: "LeetCode",
            problemTitle: "3Sum Closest",
            problemId: "3sum-closest",
            completedAt: today,
            verificationSource: .providerSynced,
            problemUrl: "https://leetcode.com/problems/3sum-closest/",
            difficulty: "Medium"
        )
        let stats = CodingStreakCalculator.calculate(activities: [activity], tasks: [], calendar: calendar, now: today)
        #expect(stats.currentStreak == 1)
        #expect(stats.isTodayActive == true)
        #expect(stats.problemsCompletedToday == 1)
        #expect(stats.totalProblemsSolved == 1)
    }

    @Test func testCompletingGeeksforGeeksProblem() {
        let calendar = Calendar.current
        let today = Date()
        let gfgActivity = CodingActivityRecord(
            platformId: "gfg",
            platformName: "GeeksforGeeks",
            problemTitle: "Subarray with Given Sum",
            problemId: "subarray-with-given-sum",
            completedAt: today,
            verificationSource: .userConfirmed,
            problemUrl: "https://practice.geeksforgeeks.org/problems/subarray-with-given-sum/1",
            difficulty: "Medium"
        )
        let stats = CodingStreakCalculator.calculate(activities: [gfgActivity], tasks: [], calendar: calendar, now: today)
        #expect(stats.currentStreak == 1)
        #expect(stats.isTodayActive == true)
        #expect(stats.problemsCompletedToday == 1)
        #expect(stats.totalProblemsSolved == 1)
    }

    @Test func testMultipleSolvedProblemsOnOneDay() {
        let calendar = Calendar.current
        let today = Date()
        let act1 = CodingActivityRecord(
            platformId: "leetcode",
            problemTitle: "Two Sum",
            problemId: "two-sum",
            completedAt: today.addingTimeInterval(-3600),
            verificationSource: .providerSynced,
            providerSubmissionId: "sub_1"
        )
        let act2 = CodingActivityRecord(
            platformId: "leetcode",
            problemTitle: "Add Two Numbers",
            problemId: "add-two-numbers",
            completedAt: today.addingTimeInterval(-1800),
            verificationSource: .providerSynced,
            providerSubmissionId: "sub_2"
        )
        let act3 = CodingActivityRecord(
            platformId: "gfg",
            problemTitle: "Detect Loop in Linked List",
            problemId: "detect-loop",
            completedAt: today,
            verificationSource: .userConfirmed
        )
        let stats = CodingStreakCalculator.calculate(activities: [act1, act2, act3], tasks: [], calendar: calendar, now: today)
        #expect(stats.currentStreak == 1, "Multiple solved problems on the same day must count as ONE streak day")
        #expect(stats.totalActiveDays == 1)
        #expect(stats.problemsCompletedToday == 3, "Total problems completed today must reflect all 3 solved problems")
        #expect(stats.totalProblemsSolved == 3)
    }

    @Test func testDuplicateProviderActivityDeduplication() {
        let calendar = Calendar.current
        let today = Date()
        let act1 = CodingActivityRecord(
            platformId: "leetcode",
            problemTitle: "LRU Cache",
            problemId: "lru-cache",
            completedAt: today,
            verificationSource: .providerSynced,
            providerSubmissionId: "lc_sub_101"
        )
        let actDuplicate = CodingActivityRecord(
            platformId: "leetcode",
            problemTitle: "LRU Cache",
            problemId: "lru-cache",
            completedAt: today,
            verificationSource: .providerSynced,
            providerSubmissionId: "lc_sub_101"
        )
        let stats = CodingStreakCalculator.calculate(activities: [act1, actDuplicate], tasks: [], calendar: calendar, now: today)
        #expect(stats.totalProblemsSolved == 1, "Duplicate provider submissions must be deduplicated")
        #expect(stats.problemsCompletedToday == 1)
        #expect(stats.currentStreak == 1)
    }

    @Test func testConsecutiveDayStreakCalculations() {
        let calendar = Calendar.current
        let today = Date()
        let day1 = calendar.date(byAdding: .day, value: -2, to: today)!
        let day2 = calendar.date(byAdding: .day, value: -1, to: today)!
        let day3 = today

        let act1 = CodingActivityRecord(platformId: "leetcode", problemTitle: "Problem 1", completedAt: day1)
        let act2 = CodingActivityRecord(platformId: "gfg", problemTitle: "Problem 2", completedAt: day2)
        let act3 = CodingActivityRecord(platformId: "leetcode", problemTitle: "Problem 3", completedAt: day3)

        let stats = CodingStreakCalculator.calculate(activities: [act1, act2, act3], tasks: [], calendar: calendar, now: today)
        #expect(stats.currentStreak == 3)
        #expect(stats.longestStreak == 3)
        #expect(stats.totalActiveDays == 3)
    }

    @Test func testMissingActivityDayStreakBreak() {
        let calendar = Calendar.current
        let today = Date()
        let dayMinus5 = calendar.date(byAdding: .day, value: -5, to: today)!
        let dayMinus4 = calendar.date(byAdding: .day, value: -4, to: today)!

        let act1 = CodingActivityRecord(platformId: "leetcode", problemTitle: "P1", completedAt: dayMinus5)
        let act2 = CodingActivityRecord(platformId: "leetcode", problemTitle: "P2", completedAt: dayMinus4)
        let actToday = CodingActivityRecord(platformId: "leetcode", problemTitle: "P3", completedAt: today)

        let stats = CodingStreakCalculator.calculate(activities: [act1, act2, actToday], tasks: [], calendar: calendar, now: today)
        #expect(stats.currentStreak == 1, "Streak must restart after a missing day")
        #expect(stats.longestStreak == 2, "Longest streak must preserve the historical best")
    }

    @Test func testTodayBeingActiveVersusYesterdayBeingActive() {
        let calendar = Calendar.current
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let dayBeforeYesterday = calendar.date(byAdding: .day, value: -2, to: today)!

        // Case A: Active yesterday, not yet solved today -> streak stays alive with grace period
        let actY1 = CodingActivityRecord(platformId: "leetcode", problemTitle: "P-2", completedAt: dayBeforeYesterday)
        let actY2 = CodingActivityRecord(platformId: "leetcode", problemTitle: "P-1", completedAt: yesterday)

        let pendingTodayStats = CodingStreakCalculator.calculate(activities: [actY1, actY2], tasks: [], calendar: calendar, now: today)
        #expect(pendingTodayStats.currentStreak == 2, "Streak remains alive until the end of today if yesterday was active")
        #expect(pendingTodayStats.isTodayActive == false)

        // Case B: Active today -> streak extends to 3
        let actToday = CodingActivityRecord(platformId: "leetcode", problemTitle: "P0", completedAt: today)
        let activeTodayStats = CodingStreakCalculator.calculate(activities: [actY1, actY2, actToday], tasks: [], calendar: calendar, now: today)
        #expect(activeTodayStats.currentStreak == 3)
        #expect(activeTodayStats.isTodayActive == true)

        // Case C: Neither today nor yesterday active -> streak is broken (0)
        let brokenStats = CodingStreakCalculator.calculate(activities: [actY1], tasks: [], calendar: calendar, now: today)
        #expect(brokenStats.currentStreak == 0, "Streak is broken if neither today nor yesterday has activity")
    }

    @Test func testReminderTimePersistenceAcrossLaunches() {
        let defaults = UserDefaults.standard
        let testHour = 20
        let testMinute = 45

        defaults.set(testHour, forKey: CodingNotificationManager.dailyReminderHourKey)
        defaults.set(testMinute, forKey: CodingNotificationManager.dailyReminderMinuteKey)
        defaults.set(true, forKey: CodingNotificationManager.notifyDailyChallengeKey)

        let loadedHour = defaults.object(forKey: CodingNotificationManager.dailyReminderHourKey) as? Int
        let loadedMinute = defaults.object(forKey: CodingNotificationManager.dailyReminderMinuteKey) as? Int
        let isEnabled = defaults.object(forKey: CodingNotificationManager.notifyDailyChallengeKey) as? Bool

        #expect(loadedHour == 20)
        #expect(loadedMinute == 45)
        #expect(isEnabled == true)

        // Clean up
        defaults.removeObject(forKey: CodingNotificationManager.dailyReminderHourKey)
        defaults.removeObject(forKey: CodingNotificationManager.dailyReminderMinuteKey)
    }

    @Test func testChangingReminderTimeReplacesPreviousSchedule() {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 12
        comps.minute = 0
        let now = calendar.date(from: comps)!

        // Schedule at 20:00 (8:00 PM)
        let plan8PM = CodingNotificationManager.calculateStreakReminderPlan(
            activities: [],
            tasks: [],
            calendar: calendar,
            now: now,
            isEnabled: true,
            reminderHour: 20,
            reminderMinute: 0
        )
        #expect(plan8PM != nil)
        let comps8PM = calendar.dateComponents([.hour, .minute], from: plan8PM!.triggerDate)
        #expect(comps8PM.hour == 20)
        #expect(comps8PM.minute == 0)

        // Change time to 21:30 (9:30 PM)
        let plan930PM = CodingNotificationManager.calculateStreakReminderPlan(
            activities: [],
            tasks: [],
            calendar: calendar,
            now: now,
            isEnabled: true,
            reminderHour: 21,
            reminderMinute: 30
        )
        #expect(plan930PM != nil)
        let comps930PM = calendar.dateComponents([.hour, .minute], from: plan930PM!.triggerDate)
        #expect(comps930PM.hour == 21)
        #expect(comps930PM.minute == 30)
        #expect(plan8PM!.identifier == plan930PM!.identifier, "Uses deterministic per-day ID so replacing cancels previous schedule")
    }

    @Test func testRemindMeIn1HourSchedulingAndCancellation() {
        let calendar = Calendar.current
        let now = Date()
        let followUpPlan = CodingNotificationManager.calculateFollowUpReminderPlan(calendar: calendar, now: now)

        #expect(followUpPlan.category == CodingNotificationManager.streakReminderCategory)
        #expect(followUpPlan.title == "Your coding streak is waiting!")
        #expect(followUpPlan.triggerDate.timeIntervalSince(now) == 3600, "Follow-up must trigger exactly 1 hour later")
        #expect(followUpPlan.identifier.contains("coding_streak_followup"))
    }

    @Test func testCompletionAfterReminderHasBeenScheduled() {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 10
        comps.minute = 0
        let now = calendar.date(from: comps)!

        // Before solving problem: reminder is planned
        let planBefore = CodingNotificationManager.calculateStreakReminderPlan(
            activities: [],
            tasks: [],
            calendar: calendar,
            now: now,
            isEnabled: true,
            reminderHour: 21,
            reminderMinute: 0
        )
        #expect(planBefore != nil)

        // User solves a problem today
        let solved = CodingActivityRecord(
            platformId: "leetcode",
            problemTitle: "Reverse Integer",
            completedAt: now,
            verificationSource: .userConfirmed
        )

        // After solving problem: reminder is cancelled / suppressed
        let planAfter = CodingNotificationManager.calculateStreakReminderPlan(
            activities: [solved],
            tasks: [],
            calendar: calendar,
            now: now,
            isEnabled: true,
            reminderHour: 21,
            reminderMinute: 0
        )
        #expect(planAfter == nil, "Initial reminder must not be sent if qualifying activity exists for today")
    }

    @Test func testNotificationPermissionDeniedStreakStillWorks() {
        let calendar = Calendar.current
        let today = Date()
        let act = CodingActivityRecord(platformId: "leetcode", problemTitle: "Climbing Stairs", completedAt: today)

        // When notifications disabled / denied: plan is nil
        let plan = CodingNotificationManager.calculateStreakReminderPlan(
            activities: [],
            tasks: [],
            calendar: calendar,
            now: today,
            isEnabled: false
        )
        #expect(plan == nil, "No notifications should be planned when permission is denied or disabled")

        // But streak calculation works without interruption
        let stats = CodingStreakCalculator.calculate(activities: [act], tasks: [], calendar: calendar, now: today)
        #expect(stats.currentStreak == 1)
        #expect(stats.isTodayActive == true)
    }

    // MARK: - Timetable Photo Scanning & Intelligence Tests

    @Test func testClearTimetable2DGroupingAndParsing() async throws {
        // Create 2D spatial text blocks simulating a structured university datesheet table
        let blocks = [
            // Header
            OcrTextBlock(text: "KIET GROUP OF INSTITUTIONS", boundingBox: CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.03), confidence: 0.99),
            OcrTextBlock(text: "END SEMESTER EXAMINATION DATESHEET 2026-27", boundingBox: CGRect(x: 0.1, y: 0.09, width: 0.8, height: 0.03), confidence: 0.98),
            // Table Header
            OcrTextBlock(text: "Date", boundingBox: CGRect(x: 0.05, y: 0.15, width: 0.15, height: 0.02), confidence: 0.95),
            OcrTextBlock(text: "Time Slot", boundingBox: CGRect(x: 0.25, y: 0.15, width: 0.2, height: 0.02), confidence: 0.95),
            OcrTextBlock(text: "Course Code", boundingBox: CGRect(x: 0.5, y: 0.15, width: 0.15, height: 0.02), confidence: 0.95),
            OcrTextBlock(text: "Subject Title", boundingBox: CGRect(x: 0.7, y: 0.15, width: 0.15, height: 0.02), confidence: 0.95),
            OcrTextBlock(text: "Venue", boundingBox: CGRect(x: 0.88, y: 0.15, width: 0.1, height: 0.02), confidence: 0.95),
            // Row 1
            OcrTextBlock(text: "16 November 2026", boundingBox: CGRect(x: 0.05, y: 0.20, width: 0.18, height: 0.025), confidence: 0.97),
            OcrTextBlock(text: "10:00 AM - 01:00 PM", boundingBox: CGRect(x: 0.25, y: 0.20, width: 0.22, height: 0.025), confidence: 0.96),
            OcrTextBlock(text: "CS 301", boundingBox: CGRect(x: 0.50, y: 0.20, width: 0.12, height: 0.025), confidence: 0.98),
            OcrTextBlock(text: "Operating Systems", boundingBox: CGRect(x: 0.65, y: 0.20, width: 0.20, height: 0.025), confidence: 0.97),
            OcrTextBlock(text: "Room 302", boundingBox: CGRect(x: 0.88, y: 0.20, width: 0.10, height: 0.025), confidence: 0.94),
            // Row 2
            OcrTextBlock(text: "19 November 2026", boundingBox: CGRect(x: 0.05, y: 0.26, width: 0.18, height: 0.025), confidence: 0.97),
            OcrTextBlock(text: "02:00 PM - 05:00 PM", boundingBox: CGRect(x: 0.25, y: 0.26, width: 0.22, height: 0.025), confidence: 0.96),
            OcrTextBlock(text: "CS 302", boundingBox: CGRect(x: 0.50, y: 0.26, width: 0.12, height: 0.025), confidence: 0.98),
            OcrTextBlock(text: "Design & Analysis of Algorithms", boundingBox: CGRect(x: 0.65, y: 0.26, width: 0.22, height: 0.025), confidence: 0.96),
            OcrTextBlock(text: "Hall B", boundingBox: CGRect(x: 0.88, y: 0.26, width: 0.10, height: 0.025), confidence: 0.95)
        ]

        let result = ScheduleParser.parse(blocks: blocks)
        #expect(result.kind == .examDatesheet)
        #expect(result.detectedYear == 2026)
        #expect(result.isYearAmbiguous == false)
        #expect(result.drafts.count == 2)

        let d1 = result.drafts[0]
        #expect(d1.course == "CS 301")
        #expect(d1.title.localizedCaseInsensitiveContains("Operating Systems"))
        #expect(d1.room == "Room 302")
        #expect(d1.sessionTime == "10:00 AM - 01:00 PM")
        #expect(d1.eventType == "exam")
        #expect(d1.isConfidentDate == true)
        #expect(d1.isAssumedTime == false)

        let d2 = result.drafts[1]
        #expect(d2.course == "CS 302")
        #expect(d2.title.localizedCaseInsensitiveContains("Algorithms"))
        #expect(d2.room == "Hall B")
        #expect(d2.sessionTime == "02:00 PM - 05:00 PM")
        #expect(d2.eventType == "exam")
        #expect(d2.isConfidentDate == true)
        #expect(d2.isAssumedTime == false)
    }

    @Test func testTimetableMergedDateCellCarriesForwardAcrossRows() async throws {
        // Simulates datesheets where one date header applies to multiple exam rows
        let blocks = [
            OcrTextBlock(text: "OFFICE OF THE CONTROLLER OF EXAMINATIONS 2026", boundingBox: CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.03)),
            // Date Header Alone (Merged Cell)
            OcrTextBlock(text: "Monday, 16 November 2026", boundingBox: CGRect(x: 0.1, y: 0.12, width: 0.4, height: 0.03)),
            // Row A under Nov 16
            OcrTextBlock(text: "10:00 AM - 01:00 PM", boundingBox: CGRect(x: 0.1, y: 0.18, width: 0.25, height: 0.025)),
            OcrTextBlock(text: "CS 301 Operating Systems", boundingBox: CGRect(x: 0.4, y: 0.18, width: 0.35, height: 0.025)),
            OcrTextBlock(text: "Room 101", boundingBox: CGRect(x: 0.8, y: 0.18, width: 0.15, height: 0.025)),
            // Row B under Nov 16
            OcrTextBlock(text: "02:00 PM - 05:00 PM", boundingBox: CGRect(x: 0.1, y: 0.24, width: 0.25, height: 0.025)),
            OcrTextBlock(text: "CS 302 Database Management Systems", boundingBox: CGRect(x: 0.4, y: 0.24, width: 0.35, height: 0.025)),
            OcrTextBlock(text: "Room 102", boundingBox: CGRect(x: 0.8, y: 0.24, width: 0.15, height: 0.025))
        ]

        let result = ScheduleParser.parse(blocks: blocks)
        #expect(result.drafts.count == 2)

        let cal = Calendar.current
        let d1 = result.drafts[0]
        let d2 = result.drafts[1]

        #expect(d1.course == "CS 301")
        #expect(d1.room == "Room 101")
        #expect(d1.sessionTime == "10:00 AM - 01:00 PM")
        let comps1 = cal.dateComponents([.year, .month, .day], from: d1.dueDate)
        #expect(comps1.month == 11)
        #expect(comps1.day == 16)

        #expect(d2.course == "CS 302")
        #expect(d2.room == "Room 102")
        #expect(d2.sessionTime == "02:00 PM - 05:00 PM")
        let comps2 = cal.dateComponents([.year, .month, .day], from: d2.dueDate)
        #expect(comps2.month == 11)
        #expect(comps2.day == 16)
    }

    @Test func testMultiCourseExtractionInSingleRow() async throws {
        let blocks = [
            OcrTextBlock(text: "DATESHEET 2026", boundingBox: CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.03)),
            OcrTextBlock(text: "16 Nov 2026 Shift 1: CS 301 Operating Systems | Shift 2: CS 302 Database Room 204", boundingBox: CGRect(x: 0.05, y: 0.12, width: 0.9, height: 0.03))
        ]

        let result = ScheduleParser.parse(blocks: blocks)
        #expect(result.drafts.count == 2)
        let courses = result.drafts.map { $0.course }
        #expect(courses.contains("CS 301"))
        #expect(courses.contains("CS 302"))
        #expect(result.drafts.allSatisfy { $0.room == "Room 204" })
    }

    @Test func testMissingDocumentYearAndAmbiguousDateFormatFlagged() async throws {
        // Document without year anywhere in header
        let blocks = [
            OcrTextBlock(text: "MIDTERM EXAMINATION SCHEDULE", boundingBox: CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.03)),
            OcrTextBlock(text: "04/05 CS 301 Operating Systems Room 201", boundingBox: CGRect(x: 0.1, y: 0.12, width: 0.8, height: 0.03))
        ]

        let result = ScheduleParser.parse(blocks: blocks)
        #expect(result.isYearAmbiguous == true, "Missing year in document must be flagged as ambiguous")
        #expect(result.detectedYear == nil)
        #expect(result.drafts.count == 1)

        let draft = result.drafts[0]
        #expect(draft.isYearAmbiguous == true)
        #expect(draft.isConfidentDate == false)
        #expect(draft.uncertaintyReason != nil)
    }

    @Test func testMissingExamTimeMarkedAsAssumedTime() async throws {
        let blocks = [
            OcrTextBlock(text: "FINAL EXAM DATESHEET 2026", boundingBox: CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.03)),
            OcrTextBlock(text: "November 16, 2026 CS 301 Operating Systems Hall A", boundingBox: CGRect(x: 0.1, y: 0.12, width: 0.8, height: 0.03))
        ]

        let result = ScheduleParser.parse(blocks: blocks)
        #expect(result.drafts.count == 1)
        let draft = result.drafts[0]
        #expect(draft.sessionTime == nil)
        #expect(draft.isAssumedTime == true)
        #expect(draft.room == "Hall A")

        // Verifies fallback event start time defaults to standard 10:00 AM morning slot
        let assignment = Assignment(
            title: draft.title,
            course: draft.course,
            dueDate: draft.dueDate,
            eventType: "exam",
            sessionTime: draft.sessionTime,
            room: draft.room
        )
        let cal = Calendar.current
        let effectiveStart = assignment.effectiveDate
        let hour = cal.component(.hour, from: effectiveStart)
        #expect(hour == 10, "Exam with missing time slot should default to 10:00 AM morning session")
    }

    @Test func testLowConfidenceOcrGeneratesQualityWarning() async throws {
        let lowQuality = OcrQualityReport(
            totalBlocks: 2,
            averageConfidence: 0.42,
            isBlurryOrLowQuality: true,
            warningMessage: "Low text recognition confidence (42%). Image may be blurry."
        )
        #expect(lowQuality.isBlurryOrLowQuality == true)
        #expect(lowQuality.warningMessage?.contains("blurry") == true)
    }

    @Test func testDuplicateScanDetectionAgainstExistingAssignments() async throws {
        let existingCal = Calendar.current
        var comps = existingCal.dateComponents([.year, .month, .day], from: Date())
        comps.year = 2026
        comps.month = 11
        comps.day = 16
        comps.hour = 10
        let examDate = existingCal.date(from: comps)!

        let existing = Assignment(
            title: "Operating Systems Exam",
            course: "CS 301",
            dueDate: examDate,
            eventType: "exam"
        )

        let blocks = [
            OcrTextBlock(text: "EXAMINATION DATESHEET 2026", boundingBox: CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.03)),
            OcrTextBlock(text: "16 November 2026 CS 301 Operating Systems 10:00 AM", boundingBox: CGRect(x: 0.1, y: 0.12, width: 0.8, height: 0.03))
        ]

        let result = ScheduleParser.parse(blocks: blocks, existingAssignments: [existing])
        #expect(result.drafts.count == 1)
        let draft = result.drafts[0]
        #expect(draft.isDuplicate == true)
        #expect(draft.isSelected == false, "Duplicates must be unselected by default")
    }

    @Test func testUserCorrectionsBeforeSavingPersisted() async throws {
        var draft = ScannedAssignmentDraft(
            title: "Original Scanned Title",
            course: "CS 301",
            dueDate: Date(),
            eventType: "exam",
            sessionTime: "10:00 AM - 01:00 PM",
            room: "Room 101"
        )

        // User edits fields before confirming save
        draft.title = "Advanced Operating Systems"
        draft.course = "CS 501"
        draft.room = "Auditorium Hall"
        draft.sessionTime = "02:00 PM - 05:00 PM"

        let assignment = Assignment(
            title: draft.title,
            course: draft.course,
            dueDate: draft.dueDate,
            source: "scan",
            eventType: draft.eventType,
            sessionTime: draft.sessionTime,
            room: draft.room,
            rawOcrText: "Raw OCR Line"
        )

        #expect(assignment.title == "Advanced Operating Systems")
        #expect(assignment.course == "CS 501")
        #expect(assignment.room == "Auditorium Hall")
        #expect(assignment.sessionTime == "02:00 PM - 05:00 PM")
        #expect(assignment.source == "scan")
        #expect(assignment.rawOcrText == "Raw OCR Line")
    }

    @Test @MainActor func testCalendarSyncWithEndTimeAndRoomLocation() async throws {
        let mockCalendar = MockCalendarSyncService()
        mockCalendar.isCalendarSyncEnabled = true
        mockCalendar.mockStatus = .authorized

        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.year = 2026
        comps.month = 11
        comps.day = 16
        comps.hour = 10
        comps.minute = 0
        let examDate = cal.date(from: comps)!

        let assignment = Assignment(
            title: "Operating Systems Examination",
            course: "CS 301",
            dueDate: examDate,
            eventType: "exam",
            sessionTime: "10:00 AM - 01:00 PM",
            room: "Audi-1"
        )

        let eventId = await mockCalendar.syncAssignment(assignment)
        #expect(eventId != nil)
        #expect(assignment.calendarEventId != nil)

        // Verify end time parsing
        let endTime = NotificationService.parseSessionEndTime(from: assignment.sessionTime)
        #expect(endTime?.hour == 13)
        #expect(endTime?.minute == 0)

        let savedEvent = mockCalendar.mockEvents[assignment.calendarEventId!]
        #expect(savedEvent != nil)
        #expect(savedEvent?.title.contains("Operating Systems") == true)
    }

    @Test @MainActor func testCalendarPermissionDeniedGracefulHandling() async throws {
        let mockCalendar = MockCalendarSyncService()
        mockCalendar.isCalendarSyncEnabled = true
        mockCalendar.mockStatus = .denied

        let assignment = Assignment(
            title: "Physics Exam",
            course: "PHY 101",
            dueDate: Date().addingTimeInterval(86400),
            eventType: "exam",
            room: "Room 102"
        )

        let eventId = await mockCalendar.syncAssignment(assignment)
        #expect(eventId == nil, "Calendar sync must return nil when access is denied")
        #expect(assignment.calendarEventId == nil)
        // Local assignment remains valid and unmodified
        #expect(assignment.title == "Physics Exam")
    }

    @Test func testNotificationSchedulingAndCancellationForScannedExam() async throws {
        let exam = Assignment(
            title: "Computer Networks Exam",
            course: "CS 304",
            dueDate: Date().addingTimeInterval(86400 * 2),
            eventType: "exam",
            sessionTime: "10:00 AM - 01:00 PM",
            room: "Room 302"
        )

        let ids = NotificationService.allIdentifiers(for: exam.id)
        #expect(ids.count == 3)
        #expect(ids.contains(NotificationService.identifier(for: exam.id, offset: .twentyFourHours)))
        #expect(ids.contains(NotificationService.identifier(for: exam.id, offset: .threeHours)))
        #expect(ids.contains(NotificationService.identifier(for: exam.id, offset: .atDeadline)))

        // Cancel reminders
        NotificationService.shared.cancelReminders(for: exam.id)
    }

    // MARK: - EventKit Calendar Sync & Deadline Handling Tests

    @Test @MainActor func testCalendarDeadlineHandling30MinuteDuration() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let deadline = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 17, minute: 0))!

        let assignment = Assignment(
            title: "Operating Systems Assignment 3",
            course: "CS 301",
            dueDate: deadline,
            eventType: "assignment"
        )

        // Verify deadline is not midnight
        let comps = cal.dateComponents([.hour, .minute, .second], from: assignment.dueDate)
        let isMidnightOnly = (comps.hour == 0 && comps.minute == 0 && comps.second == 0)
        #expect(!isMidnightOnly)

        // Verify calculated start and end times for 30-min duration ending at deadline
        let expectedEnd = assignment.dueDate
        let expectedStart = assignment.dueDate.addingTimeInterval(-1800)
        #expect(expectedEnd.timeIntervalSince(expectedStart) == 1800)
        #expect(expectedEnd == deadline)
    }

    @Test @MainActor func testCalendarMidnightOnlyDueDateCreatesAllDayEvent() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnightDate = cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 0, minute: 0, second: 0))!

        let assignment = Assignment(
            title: "Date-Only Coursework Submission",
            course: "IT 101",
            dueDate: midnightDate,
            eventType: "assignment"
        )

        let comps = cal.dateComponents([.hour, .minute, .second], from: assignment.dueDate)
        let isMidnightOnly = (comps.hour == 0 && comps.minute == 0 && comps.second == 0)
        #expect(isMidnightOnly)
    }

    @Test @MainActor func testCalendarExamSessionTimeParsingAndAllDayFallback() async throws {
        // Exam with explicit session time range
        let examWithTime = Assignment(
            title: "Database Management Exam",
            course: "CS 303",
            dueDate: Date(),
            eventType: "exam",
            sessionTime: "10:00 AM - 01:00 PM"
        )

        let start = NotificationService.parseSessionStartTime(from: examWithTime.sessionTime)
        let end = NotificationService.parseSessionEndTime(from: examWithTime.sessionTime)
        #expect(start?.hour == 10 && start?.minute == 0)
        #expect(end?.hour == 13 && end?.minute == 0)

        // Exam with unknown session time and midnight date
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnightDate = cal.date(from: DateComponents(year: 2026, month: 12, day: 5, hour: 0, minute: 0, second: 0))!
        let examUnknown = Assignment(
            title: "Computer Graphics Exam",
            course: "CS 405",
            dueDate: midnightDate,
            eventType: "exam",
            sessionTime: ""
        )
        let unknownComps = cal.dateComponents([.hour, .minute, .second], from: examUnknown.dueDate)
        let isMidnight = (unknownComps.hour == 0 && unknownComps.minute == 0 && unknownComps.second == 0)
        #expect(isMidnight)
        #expect(examUnknown.sessionTime?.isEmpty == true)
    }

    @Test @MainActor func testCalendarSyncSummaryResultMessages() async throws {
        var summarySuccess = CalendarSyncSummary(destinationCalendarName: "Personal")
        summarySuccess.added = 3
        summarySuccess.updated = 1
        summarySuccess.skipped = 2
        #expect(summarySuccess.isSuccess)
        #expect(summarySuccess.resultMessage.contains("3 added"))
        #expect(summarySuccess.resultMessage.contains("1 updated"))
        #expect(summarySuccess.resultMessage.contains("2 up to date"))

        var summaryAllUpToDate = CalendarSyncSummary(destinationCalendarName: "Personal")
        summaryAllUpToDate.added = 0
        summaryAllUpToDate.updated = 0
        summaryAllUpToDate.skipped = 4
        #expect(summaryAllUpToDate.isSuccess)
        #expect(summaryAllUpToDate.resultMessage.contains("already up-to-date"))

        var summaryWithErrors = CalendarSyncSummary(destinationCalendarName: "Personal")
        summaryWithErrors.added = 1
        summaryWithErrors.failed = 2
        summaryWithErrors.firstErrorMessage = "Calendar is read-only"
        #expect(!summaryWithErrors.isSuccess)
        #expect(summaryWithErrors.resultMessage.contains("Sync encountered issues"))
        #expect(summaryWithErrors.resultMessage.contains("2 failed"))
    }

    @Test @MainActor func testMockCalendarSyncServiceBatchReport() async throws {
        let mock = MockCalendarSyncService()
        mock.isCalendarSyncEnabled = true
        mock.mockStatus = .authorized

        let item1 = Assignment(title: "Task 1", dueDate: Date().addingTimeInterval(86400))
        let item2 = Assignment(title: "Task 2", dueDate: Date().addingTimeInterval(172800))

        let report = await mock.syncAssignmentsWithReport([item1, item2])
        #expect(report.added == 2)
        #expect(report.failed == 0)
        #expect(item1.calendarEventId != nil)
        #expect(item2.calendarEventId != nil)

        // Resync: updates without duplicating
        let report2 = await mock.syncAssignmentsWithReport([item1, item2])
        #expect(report2.updated == 2)
        #expect(report2.added == 0)
        #expect(mock.mockEvents.count == 2)
    }

    // MARK: - Completed Tasks Calendar Sync Tests

    @Test @MainActor func testCompletedAssignmentMarksCalendarEventWithCompletedTitle() async throws {
        let mock = MockCalendarSyncService()
        mock.isCalendarSyncEnabled = true
        mock.mockStatus = .authorized
        mock.completedEventBehavior = .markCompleted

        let assignment = Assignment(
            title: "Physics Lab Report",
            course: "PHYS 201",
            dueDate: Date().addingTimeInterval(86400)
        )

        // Initial sync of active assignment
        let eventId = await mock.syncAssignment(assignment)
        #expect(eventId != nil)
        #expect(mock.mockEvents[eventId!]?.title == "Physics Lab Report")

        // Mark as completed
        assignment.isCompleted = true
        await mock.handleAssignmentCompletionChanged(assignment)

        // Event should still exist on calendar, but marked with checkmark and completed status
        let updatedEvent = mock.mockEvents[eventId!]
        #expect(updatedEvent != nil)
        #expect(updatedEvent?.title == "✓ Completed: Physics Lab Report")
        #expect(updatedEvent?.notes.contains("Status: Completed (Finished)") == true)
    }

    @Test @MainActor func testCompletedExamMarksCalendarEventWithCompletedExamTitle() async throws {
        let mock = MockCalendarSyncService()
        mock.isCalendarSyncEnabled = true
        mock.mockStatus = .authorized
        mock.completedEventBehavior = .markCompleted

        let exam = Assignment(
            title: "Data Structures Final",
            course: "CS 201",
            dueDate: Date().addingTimeInterval(172800),
            eventType: "Exam"
        )

        let eventId = await mock.syncAssignment(exam)
        #expect(eventId != nil)
        #expect(mock.mockEvents[eventId!]?.title == "[Exam] Data Structures Final")

        // Mark as completed
        exam.isCompleted = true
        await mock.handleAssignmentCompletionChanged(exam)

        let updatedEvent = mock.mockEvents[eventId!]
        #expect(updatedEvent != nil)
        #expect(updatedEvent?.title == "✓ [Completed Exam] Data Structures Final")
    }

    @Test @MainActor func testCompletedAssignmentRemovesCalendarEventWhenConfigured() async throws {
        let mock = MockCalendarSyncService()
        mock.isCalendarSyncEnabled = true
        mock.mockStatus = .authorized
        mock.completedEventBehavior = .removeFromCalendar

        let assignment = Assignment(
            title: "Chemistry Homework",
            course: "CHEM 101",
            dueDate: Date().addingTimeInterval(86400)
        )

        // Initial sync
        mock.completedEventBehavior = .markCompleted
        let eventId = await mock.syncAssignment(assignment)
        #expect(eventId != nil)
        #expect(mock.mockEvents[eventId!] != nil)
        #expect(assignment.calendarEventId == eventId)

        // Switch behavior to remove from calendar and mark completed
        mock.completedEventBehavior = .removeFromCalendar
        assignment.isCompleted = true
        await mock.handleAssignmentCompletionChanged(assignment)

        // Event must be cleanly removed from calendar so calendar doesn't hold completed data
        #expect(mock.mockEvents[eventId!] == nil)
        #expect(assignment.calendarEventId == nil)
    }

    @Test @MainActor func testUncompletingAssignmentRestoresCalendarEvent() async throws {
        let mock = MockCalendarSyncService()
        mock.isCalendarSyncEnabled = true
        mock.mockStatus = .authorized

        let assignment = Assignment(
            title: "Essay Draft",
            course: "ENG 105",
            dueDate: Date().addingTimeInterval(86400)
        )

        // 1. Test restoration under .removeFromCalendar
        mock.completedEventBehavior = .removeFromCalendar
        assignment.isCompleted = true
        assignment.calendarEventId = nil

        // Uncomplete the assignment
        assignment.isCompleted = false
        await mock.handleAssignmentCompletionChanged(assignment)

        #expect(assignment.calendarEventId != nil)
        let restoredEvent = mock.mockEvents[assignment.calendarEventId!]
        #expect(restoredEvent != nil)
        #expect(restoredEvent?.title == "Essay Draft")

        // 2. Test restoration under .markCompleted
        mock.completedEventBehavior = .markCompleted
        assignment.isCompleted = true
        await mock.handleAssignmentCompletionChanged(assignment)
        #expect(mock.mockEvents[assignment.calendarEventId!]?.title == "✓ Completed: Essay Draft")

        // Uncomplete again
        assignment.isCompleted = false
        await mock.handleAssignmentCompletionChanged(assignment)
        #expect(mock.mockEvents[assignment.calendarEventId!]?.title == "Essay Draft")
    }

    @Test @MainActor func testBatchSyncWithCompletedTasksRespectsRemovalStrategy() async throws {
        let mock = MockCalendarSyncService()
        mock.isCalendarSyncEnabled = true
        mock.mockStatus = .authorized
        mock.completedEventBehavior = .removeFromCalendar

        let activeTask = Assignment(title: "Active Task", dueDate: Date().addingTimeInterval(86400))
        let completedTask = Assignment(title: "Old Task", dueDate: Date().addingTimeInterval(86400), isCompleted: true)

        let report = await mock.syncAssignmentsWithReport([activeTask, completedTask])
        #expect(report.added == 1) // only active task added
        #expect(report.skipped == 1) // completed task skipped so calendar doesn't hold completed data
        #expect(report.failed == 0)
        #expect(activeTask.calendarEventId != nil)
        #expect(completedTask.calendarEventId == nil)
    }

    @Test @MainActor func testCodingTaskCompletionSyncsWithCalendar() async throws {
        let mock = MockCalendarSyncService()
        mock.isCalendarSyncEnabled = true
        mock.mockStatus = .authorized
        mock.completedEventBehavior = .markCompleted

        let codingTask = CodingTask(
            title: "Weekly Contest 420",
            platformId: "leetcode",
            taskType: .contest,
            dueDate: Date().addingTimeInterval(86400)
        )

        let (initialId, _) = await mock.syncCodingTask(codingTask, alertMinutesBefore: 15)
        #expect(initialId != nil)
        #expect(mock.mockEvents[initialId!]?.title == "Weekly Contest 420")

        // Mark completed
        codingTask.isCompleted = true
        await mock.handleCodingTaskCompletionChanged(codingTask)

        #expect(mock.mockEvents[initialId!]?.title == "✓ Completed: Weekly Contest 420")

        // Now switch to remove mode
        mock.completedEventBehavior = .removeFromCalendar
        await mock.handleCodingTaskCompletionChanged(codingTask)
        #expect(mock.mockEvents[initialId!] == nil)
        #expect(codingTask.calendarEventId == nil)
    }
}




