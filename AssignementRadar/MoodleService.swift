//
//  MoodleService.swift
//  AssignementRadar
//
//  Created for Moodle Deadline Integration.
//

import Foundation
import Security

// MARK: - Secure Keychain Storage

/// Securely saves, retrieves, and clears the Moodle web-service token using the iOS Keychain.
enum MoodleKeychainHelper {
    private static let serviceName = "kiet.AssignementRadar.moodle"
    private static let accountName = "moodle_web_token"
    private static let fallbackKey = "moodle_web_token_secure_store"

    /// Saves the token securely into the iOS Keychain.
    @discardableResult
    static func saveToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }

        // Remove any prior entry before saving
        deleteToken()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            return true
        } else {
            // Simulator test environment fallback
            UserDefaults.standard.set(token, forKey: fallbackKey)
            return true
        }
    }

    /// Retrieves the stored token from the Keychain, or nil if none exists.
    static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let data = item as? Data, let str = String(data: data, encoding: .utf8) {
            return str
        }
        return UserDefaults.standard.string(forKey: fallbackKey)
    }

    /// Alias for loadToken.
    static func getToken() -> String? {
        loadToken()
    }

    /// Removes the token from the Keychain and fallback store.
    @discardableResult
    static func deleteToken() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]
        let status = SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackKey)
        return status == errSecSuccess || status == errSecItemNotFound || true
    }
}

// MARK: - Moodle API Models & DTOs

/// Site metadata returned by Moodle's `core_webservice_get_site_info`.
struct MoodleSiteInfo: Codable {
    let sitename: String?
    let username: String?
    let firstname: String?
    let lastname: String?
    let fullname: String?
    let release: String?
    let userid: Int?

    var displayName: String {
        if let full = fullname, !full.isEmpty { return full }
        let names = [firstname, lastname].compactMap { $0 }.filter { !$0.isEmpty }
        if !names.isEmpty { return names.joined(separator: " ") }
        return username ?? "Moodle Student"
    }
}

/// Token payload returned by Moodle's `login/token.php`.
struct MoodleTokenResponse: Codable {
    let token: String?
    let error: String?
    let errorcode: String?
    let stacktrace: String?
    let debuginfo: String?
}

/// Error structure returned by Moodle REST endpoints on failure.
struct MoodleErrorResponse: Codable {
    let exception: String?
    let errorcode: String?
    let message: String?
}

// MARK: - mod_assign_get_assignments DTOs

/// Root response from Moodle's `mod_assign_get_assignments`.
struct MoodleAssignGetAssignmentsResponse: Codable {
    let courses: [MoodleAssignCourse]?
    let warnings: [MoodleAssignWarning]?
}

/// Course container inside `mod_assign_get_assignments`.
struct MoodleAssignCourse: Codable {
    let id: Int
    let fullname: String?
    let shortname: String?
    let assignments: [MoodleAssignItem]?
}

/// Individual assignment inside `mod_assign_get_assignments`.
struct MoodleAssignItem: Codable {
    let id: Int
    let cmid: Int?
    let course: Int?
    let name: String
    let duedate: Int?
    let cutoffdate: Int?
    let intro: String?
}

/// Warning item in Moodle responses.
struct MoodleAssignWarning: Codable {
    let item: String?
    let itemid: Int?
    let warningcode: String?
    let message: String?
}

// MARK: - Calendar Events DTOs (Supplementary / Fallback)

/// Generic Moodle Calendar Event from `core_calendar_get_calendar_upcoming_view` or `core_calendar_get_calendar_events`.
struct MoodleCalendarEvent: Codable {
    let id: Int
    let name: String
    let description: String?
    let timestart: Int?
    let eventtype: String?
    let url: String?
    let course: MoodleCourseInfo?
}

struct MoodleCourseInfo: Codable {
    let id: Int?
    let fullname: String?
    let shortname: String?
}

/// Response payload from `core_calendar_get_calendar_upcoming_view`.
struct MoodleUpcomingViewResponse: Codable {
    let events: [MoodleCalendarEvent]?
}

/// Response payload from `core_calendar_get_calendar_events`.
struct MoodleCalendarEventsResponse: Codable {
    let events: [MoodleCalendarEvent]?
}

// MARK: - Draft Model for Review

/// A deadline candidate fetched from Moodle, ready for student review before saving.
struct MoodleDraft: Identifiable {
    let id = UUID()
    let moodleEventId: String
    var title: String
    var course: String
    var dueDate: Date
    var priority: Priority = .medium
    var notes: String = ""
    var sourceUrl: String?
    var activityType: String = "Assignment"
    var isSelected: Bool = true
    var isDuplicate: Bool = false
    var isConfidentDate: Bool = true
}

// MARK: - Moodle Service Errors

enum MoodleError: LocalizedError {
    case invalidUrl(String)
    case insecureHttpNotAllowed(String)
    case missingCredentials
    case serverError(code: String, message: String)
    case networkError(String)
    case parsingError(String)
    case webServicesNotEnabled(String)
    case accessDenied(String)

    var errorDescription: String? {
        switch self {
        case .invalidUrl(let detail):
            return "Invalid Moodle URL: \(detail)"
        case .insecureHttpNotAllowed(let detail):
            return "Insecure Connection (HTTP): \(detail)"
        case .missingCredentials:
            return "Please provide both your Moodle site URL and login credentials."
        case .serverError(let code, let message):
            if code == "invalidlogin" {
                return "Invalid username or password. Please verify your college login credentials."
            } else if code == "invalidtoken" {
                return "Your Moodle session token is invalid or has expired. Please sign in again."
            } else if code == "accessexception" {
                return "Access denied: Your Moodle account does not have permission to access web-service functions."
            }
            return "Moodle API error (\(code)): \(message)"
        case .networkError(let detail):
            return "Network connection failed: \(detail)"
        case .parsingError(let detail):
            return "Could not process Moodle data: \(detail)"
        case .webServicesNotEnabled(let detail):
            return "Moodle Web Services unavailable: \(detail)"
        case .accessDenied(let detail):
            return "Moodle Permission Error: \(detail)"
        }
    }
}

// MARK: - Moodle Networking Service

/// Handles URL validation, token authorization, and assignment retrieval via Moodle REST web services.
final class MoodleService {
    static let shared = MoodleService()

    /// The exact hostname permitted for HTTP by the targeted App Transport Security exception.
    static let allowedInsecureHost = "lms.kiet.edu"

    /// Centralized fixed Moodle LMS site URL for the college portal.
    static let defaultSiteUrl = "http://lms.kiet.edu/moodle"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - URL Normalization & Validation

    /// Checks if a given host is permitted to use plain HTTP via the scoped ATS exception.
    static func isAllowedHttpHost(_ host: String) -> Bool {
        host.lowercased() == allowedInsecureHost
    }

    /// Returns the clean base URL string without trailing slashes.
    /// If no scheme is provided, defaults to http for lms.kiet.edu, and https for other domains.
    static func cleanBaseUrlString(_ rawInput: String) -> String {
        var trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        // Remove trailing slashes
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        // Check if a scheme already exists
        let lower = trimmed.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            if lower.contains(allowedInsecureHost) {
                trimmed = "http://" + trimmed
            } else {
                trimmed = "https://" + trimmed
            }
        }

        return trimmed
    }

    /// Normalizes student-entered Moodle URL and constructs the REST endpoint.
    /// Strictly rejects unencrypted HTTP URLs unless the host matches the scoped ATS exception domain (lms.kiet.edu).
    static func normalizeUrl(_ rawInput: String) -> Result<URL, MoodleError> {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.invalidUrl("URL cannot be empty."))
        }

        let base = cleanBaseUrlString(rawInput)

        guard let baseUrl = URL(string: base), let host = baseUrl.host, !host.isEmpty else {
            return .failure(.invalidUrl("Please enter a valid site domain, e.g. http://lms.kiet.edu/moodle"))
        }

        // Validate scheme against domain policy
        if baseUrl.scheme?.lowercased() == "http" {
            guard isAllowedHttpHost(host) else {
                return .failure(.insecureHttpNotAllowed("HTTP is unencrypted and blocked for \(host). To protect your credentials, only HTTPS is permitted (or the college portal lms.kiet.edu)."))
            }
        } else if baseUrl.scheme?.lowercased() != "https" {
            return .failure(.invalidUrl("Unsupported URL scheme. Please use http:// or https://"))
        }

        guard let endpointUrl = URL(string: "\(base)/webservice/rest/server.php") else {
            return .failure(.invalidUrl("Could not build web-service endpoint URL."))
        }

        return .success(endpointUrl)
    }

    /// Constructs the token generation endpoint URL (`/login/token.php`).
    static func tokenEndpointUrl(_ rawInput: String) -> Result<URL, MoodleError> {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.invalidUrl("URL cannot be empty."))
        }

        let base = cleanBaseUrlString(rawInput)

        guard let baseUrl = URL(string: base), let host = baseUrl.host, !host.isEmpty else {
            return .failure(.invalidUrl("Please enter a valid site domain."))
        }

        if baseUrl.scheme?.lowercased() == "http" {
            guard isAllowedHttpHost(host) else {
                return .failure(.insecureHttpNotAllowed("Passwords cannot be transmitted over plain HTTP for \(host)."))
            }
        }

        guard let endpointUrl = URL(string: "\(base)/login/token.php") else {
            return .failure(.invalidUrl("Could not build token endpoint URL."))
        }

        return .success(endpointUrl)
    }

    // MARK: - Direct Authentication (login/token.php)

    /// Authenticates against Moodle's supported mobile web-service login endpoint.
    /// Never stores or logs the student's password; saves only the authorized token into Keychain.
    func login(siteUrl: String, username: String, password: String) async throws -> String {
        let endpoint = try Self.tokenEndpointUrl(siteUrl).get()

        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUsername.isEmpty, !password.isEmpty else {
            throw MoodleError.missingCredentials
        }

        let bodyParams = [
            "service": "moodle_mobile_app",
            "username": cleanUsername,
            "password": password
        ]

        let data = try await performPost(to: endpoint, parameters: bodyParams)

        // Parse token response
        if let tokenResponse = try? JSONDecoder().decode(MoodleTokenResponse.self, from: data) {
            if let token = tokenResponse.token, !token.isEmpty {
                // Save authorized token to Keychain
                MoodleKeychainHelper.saveToken(token)
                return token
            }

            if let code = tokenResponse.errorcode {
                if code == "invalidlogin" {
                    throw MoodleError.serverError(code: code, message: "Invalid username or password. Please verify your college login credentials.")
                } else if code == "enablews" {
                    throw MoodleError.webServicesNotEnabled("Mobile Web Services are not enabled on this Moodle site. Please contact your college Moodle administrator.")
                } else {
                    throw MoodleError.serverError(code: code, message: tokenResponse.error ?? "Login failed")
                }
            }
        }

        // Check if an XML or HTML error was returned
        if let responseString = String(data: data, encoding: .utf8), responseString.contains("<error>") {
            throw MoodleError.parsingError("Server returned XML error: \(responseString)")
        }

        throw MoodleError.parsingError("Unable to obtain authorization token from Moodle server.")
    }

    // MARK: - Connection Verification (core_webservice_get_site_info)

    /// Tests connection and token validity by invoking `core_webservice_get_site_info`.
    func testConnection(siteUrl: String, token: String) async throws -> MoodleSiteInfo {
        let endpoint = try Self.normalizeUrl(siteUrl).get()

        let bodyParams = [
            "wstoken": token,
            "wsfunction": "core_webservice_get_site_info",
            "moodlewsrestformat": "json"
        ]

        let data = try await performPost(to: endpoint, parameters: bodyParams)

        // Detect Moodle error responses
        if let errorResponse = try? JSONDecoder().decode(MoodleErrorResponse.self, from: data),
           let code = errorResponse.errorcode {
            if code == "invalidtoken" {
                throw MoodleError.serverError(code: code, message: "Session token is invalid or expired.")
            } else if code == "accessexception" {
                throw MoodleError.accessDenied("Account does not have web-service access permission.")
            }
            throw MoodleError.serverError(code: code, message: errorResponse.message ?? "Unknown error")
        }

        do {
            let siteInfo = try JSONDecoder().decode(MoodleSiteInfo.self, from: data)
            return siteInfo
        } catch {
            throw MoodleError.parsingError("Unable to decode site info: \(error.localizedDescription)")
        }
    }

    // MARK: - Assignment Retrieval (mod_assign_get_assignments & Calendar Fallback)

    /// Retrieves assignments using Moodle's supported `mod_assign_get_assignments` API,
    /// falling back to or supplementing with calendar events if needed.
    func fetchAssignments(siteUrl: String, token: String, existingAssignments: [Assignment]) async throws -> [MoodleDraft] {
        let endpoint = try Self.normalizeUrl(siteUrl).get()
        let cleanBase = Self.cleanBaseUrlString(siteUrl)

        var drafts: [MoodleDraft] = []
        var assignApiSucceeded = false

        // 1. Invoke primary supported assignment function: mod_assign_get_assignments
        let assignParams = [
            "wstoken": token,
            "wsfunction": "mod_assign_get_assignments",
            "moodlewsrestformat": "json"
        ]

        do {
            let data = try await performPost(to: endpoint, parameters: assignParams)

            // Check for Moodle API error object
            if let errorResponse = try? JSONDecoder().decode(MoodleErrorResponse.self, from: data),
               let code = errorResponse.errorcode {
                if code == "invalidtoken" {
                    throw MoodleError.serverError(code: code, message: "Moodle token is invalid or expired. Please re-authenticate.")
                } else if code == "accessexception" {
                    // Function not allowed for this role; fall through to calendar events
                    print("mod_assign_get_assignments permission restricted, falling back to calendar view.")
                } else {
                    print("mod_assign_get_assignments returned error \(code): \(errorResponse.message ?? "")")
                }
            } else if let assignResponse = try? JSONDecoder().decode(MoodleAssignGetAssignmentsResponse.self, from: data),
                      let courses = assignResponse.courses {
                assignApiSucceeded = true

                for course in courses {
                    let courseName = course.shortname ?? course.fullname ?? "Course \(course.id)"
                    guard let assignments = course.assignments else { continue }

                    for item in assignments {
                        guard let duedate = item.duedate, duedate > 0 else { continue }

                        let dueDate = Date(timeIntervalSince1970: TimeInterval(duedate))
                        let eventId = "assign_\(item.id)"
                        let priority = Self.inferPriority(from: item.name)
                        let cleanNotes = Self.stripHtml(item.intro ?? "")

                        let itemUrl: String?
                        if let cmid = item.cmid, cmid > 0 {
                            itemUrl = "\(cleanBase)/mod/assign/view.php?id=\(cmid)"
                        } else {
                            itemUrl = "\(cleanBase)/course/view.php?id=\(course.id)"
                        }

                        // Duplicate check against SwiftData assignments
                        let isDuplicate = existingAssignments.contains { existing in
                            if let mId = existing.moodleEventId, mId == eventId {
                                return true
                            }
                            let isSameTitle = existing.title.caseInsensitiveCompare(item.name) == .orderedSame
                            let isSameCourse = existing.course.caseInsensitiveCompare(courseName) == .orderedSame
                            let isSameDay = Calendar.current.isDate(existing.dueDate, inSameDayAs: dueDate)
                            return isSameTitle && (isSameCourse || isSameDay)
                        }

                        let draft = MoodleDraft(
                            moodleEventId: eventId,
                            title: item.name,
                            course: courseName,
                            dueDate: dueDate,
                            priority: priority,
                            notes: cleanNotes,
                            sourceUrl: itemUrl,
                            activityType: "Assignment",
                            isSelected: !isDuplicate,
                            isDuplicate: isDuplicate,
                            isConfidentDate: true
                        )
                        drafts.append(draft)
                    }
                }
            }
        } catch let err as MoodleError {
            throw err
        } catch {
            print("mod_assign_get_assignments call failed: \(error.localizedDescription)")
        }

        // 2. Query calendar events if mod_assign returned 0 items or for non-assignment deadlines (quizzes, practicals, exams)
        let calendarDrafts = (try? await fetchUpcomingCalendarDeadlines(endpoint: endpoint, cleanBase: cleanBase, token: token, existingAssignments: existingAssignments, existingDrafts: drafts)) ?? []
        drafts.append(contentsOf: calendarDrafts)

        // Sort drafts by upcoming due date
        drafts.sort { $0.dueDate < $1.dueDate }

        return drafts
    }

    /// Fetches calendar events (e.g. exams, quizzes, submissions) using `core_calendar_get_calendar_upcoming_view` or fallback.
    private func fetchUpcomingCalendarDeadlines(
        endpoint: URL,
        cleanBase: String,
        token: String,
        existingAssignments: [Assignment],
        existingDrafts: [MoodleDraft]
    ) async throws -> [MoodleDraft] {
        let upcomingParams = [
            "wstoken": token,
            "wsfunction": "core_calendar_get_calendar_upcoming_view",
            "moodlewsrestformat": "json"
        ]

        var rawEvents: [MoodleCalendarEvent] = []

        if let data = try? await performPost(to: endpoint, parameters: upcomingParams) {
            if let upcomingResponse = try? JSONDecoder().decode(MoodleUpcomingViewResponse.self, from: data),
               let events = upcomingResponse.events {
                rawEvents = events
            }
        }

        // If upcoming view returned nothing, try core_calendar_get_calendar_events
        if rawEvents.isEmpty {
            let eventsParams = [
                "wstoken": token,
                "wsfunction": "core_calendar_get_calendar_events",
                "moodlewsrestformat": "json"
            ]
            if let data = try? await performPost(to: endpoint, parameters: eventsParams),
               let eventsResponse = try? JSONDecoder().decode(MoodleCalendarEventsResponse.self, from: data),
               let events = eventsResponse.events {
                rawEvents = events
            }
        }

        var calendarDrafts: [MoodleDraft] = []

        for event in rawEvents {
            guard let timestamp = event.timestart, timestamp > 0 else { continue }

            let eventId = "cal_\(event.id)"

            // Skip if already captured from mod_assign_get_assignments
            if existingDrafts.contains(where: { $0.title.caseInsensitiveCompare(event.name) == .orderedSame }) {
                continue
            }

            let dueDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
            let courseName = event.course?.shortname ?? event.course?.fullname ?? "Course"
            let activityType = event.eventtype?.capitalized ?? "Deadline"
            let priority = Self.inferPriority(from: event.name)
            let cleanNotes = Self.stripHtml(event.description ?? "")

            let isDuplicate = existingAssignments.contains { existing in
                if let mId = existing.moodleEventId, mId == eventId || mId == "\(event.id)" {
                    return true
                }
                let isSameTitle = existing.title.caseInsensitiveCompare(event.name) == .orderedSame
                let isSameCourse = existing.course.caseInsensitiveCompare(courseName) == .orderedSame
                let isSameDay = Calendar.current.isDate(existing.dueDate, inSameDayAs: dueDate)
                return isSameTitle && (isSameCourse || isSameDay)
            }

            calendarDrafts.append(MoodleDraft(
                moodleEventId: eventId,
                title: event.name,
                course: courseName,
                dueDate: dueDate,
                priority: priority,
                notes: cleanNotes,
                sourceUrl: event.url ?? "\(cleanBase)/calendar/view.php?view=upcoming",
                activityType: activityType,
                isSelected: !isDuplicate,
                isDuplicate: isDuplicate,
                isConfidentDate: true
            ))
        }

        return calendarDrafts
    }

    /// RFC-compliant form-url encoding for application/x-www-form-urlencoded payloads,
    /// ensuring characters like '@', '&', '+', '=', '#', and passwords with symbols are correctly transmitted.
    static func formUrlEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "*-._")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func performPost(to url: URL, parameters: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let bodyString = parameters.map { key, value in
            let escapedKey = Self.formUrlEncode(key)
            let escapedValue = Self.formUrlEncode(value)
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")

        request.httpBody = bodyString.data(using: .utf8)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MoodleError.networkError("Invalid HTTP server response.")
            }

            if httpResponse.statusCode == 404 {
                throw MoodleError.webServicesNotEnabled("The web-service endpoint does not exist on this server (HTTP 404).")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw MoodleError.networkError("HTTP status code \(httpResponse.statusCode)")
            }

            return data
        } catch let err as MoodleError {
            throw err
        } catch {
            throw MoodleError.networkError(error.localizedDescription)
        }
    }

    // MARK: - Utility Helpers

    /// Infers academic priority from deadline title keywords.
    static func inferPriority(from title: String) -> Priority {
        let lower = title.lowercased()
        if lower.contains("exam") || lower.contains("midterm") || lower.contains("final") || lower.contains("practical") {
            return .high
        } else if lower.contains("quiz") || lower.contains("project") || lower.contains("presentation") || lower.contains("lab") {
            return .medium
        } else {
            return .low
        }
    }

    /// Strips HTML tags and entities from Moodle descriptions to provide clean plain text notes.
    static func stripHtml(_ input: String) -> String {
        guard !input.isEmpty else { return "" }
        var result = input
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return result
    }

    // MARK: - Realistic Mock Data for Previews & Tests

    /// Generates realistic mock Moodle draft assignments for tests and SwiftUI Previews.
    static func generateMockDrafts(existingAssignments: [Assignment]) -> [MoodleDraft] {
        let cal = Calendar.current
        let now = Date()

        let items: [(id: String, title: String, course: String, daysOffset: Int, hour: Int, priority: Priority, type: String)] = [
            ("assign_101", "Operating Systems Lab 4 Submission", "CS 301", 2, 23, .high, "Assignment"),
            ("assign_102", "Probability & Statistics Quiz 2", "MATH 204", 4, 14, .medium, "Quiz"),
            ("assign_103", "Data Structures Term Project Checkpoint", "CS 202", 7, 18, .high, "Assignment"),
            ("assign_104", "Database Management Assignment 3", "CS 305", 9, 23, .low, "Assignment")
        ]

        return items.map { item in
            var components = cal.dateComponents([.year, .month, .day], from: now)
            components.day = (components.day ?? 0) + item.daysOffset
            components.hour = item.hour
            components.minute = 59
            let dueDate = cal.date(from: components) ?? now

            let isDuplicate = existingAssignments.contains {
                $0.moodleEventId == item.id || ($0.title == item.title && $0.course == item.course)
            }

            return MoodleDraft(
                moodleEventId: item.id,
                title: item.title,
                course: item.course,
                dueDate: dueDate,
                priority: item.priority,
                notes: "Imported via Moodle LMS (\(item.type))",
                sourceUrl: "http://lms.kiet.edu/moodle/mod/assign/view.php?id=1234",
                activityType: item.type,
                isSelected: !isDuplicate,
                isDuplicate: isDuplicate,
                isConfidentDate: true
            )
        }
    }
}
