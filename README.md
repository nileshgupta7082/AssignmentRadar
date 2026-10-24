# Assignment Radar 🎯

An iOS application built with SwiftUI, SwiftData, and EventKit for tracking academic assignment deadlines, examinations, timetable schedules, and competitive programming milestones.

---

## 🌟 Key Features

### 📅 Assignment & Exam Radar
- **Automated Deadline Organization**: Categorizes tasks by urgency (Overdue, Due Soon, Upcoming) with visual indicators.
- **Moodle LMS Integration**: Syncs coursework deadlines and submission statuses directly with university learning portals.
- **OCR Timetable Scanner**: Parses scanned document timetables into structured course schedules, exam dates, session intervals, and room locations.
- **Completed Tasks Catalog**: Archival view for finished assignments with the ability to review history or restore uncompleted items.

### 🗓️ Apple Calendar Integration (EventKit)
- **Seamless System Sync**: Directly writes deadlines and exams to your chosen iOS Calendar account.
- **Smart Completion Handling**:
  - **Mark as Completed (✓)**: Updates calendar titles to `✓ Completed: [Title]` and silences all alert alarms.
  - **Remove from Calendar**: Automatically deletes calendar events when assignments are marked complete, keeping calendars clutter-free.
  - **Live Restoration**: Re-enables calendar events and scheduled alerts whenever tasks are unchecked.
- **Deduplication Engine**: Uses app ownership tags and UUID keys to prevent duplicate calendar events.

### 💻 Coding Radar
- **Multi-Platform Support**: Track contest schedules and daily coding challenges from platforms like LeetCode, Codeforces, and GeeksforGeeks.
- **Streak & Consistency Tracker**: Visualizes solved problems, active streak days, and contest registration statuses.
- **Calendar Reminders**: Configurable 15-minute or custom pre-contest Apple Calendar notifications.

---

## 🛠️ Technology Stack
- **Framework**: SwiftUI (iOS 17+)
- **Persistence**: SwiftData (`Assignment`, `CodingTask`, `PlatformSettings`)
- **Calendar**: EventKit (`EKEventStore`)
- **Computer Vision**: VisionKit & Vision OCR (`VNRecognizeTextRequest`)
- **Cloud Backend**: Supabase PostgreSQL synchronization
- **Testing**: Swift Testing framework (`@Suite`, `@Test`) with comprehensive unit & integration test coverage.

---

## 🚀 Getting Started

1. **Clone the repository**:
   ```bash
   git clone https://github.com/nileshgupta7082/AssignmentRadar.git
   cd AssignmentRadar
   ```

2. **Open in Xcode**:
   ```bash
   open AssignementRadar.xcodeproj
   ```

3. **Run the App**:
   - Select an iOS 17+ Simulator or connected physical device.
   - Press **Cmd + R** to build and run.

4. **Run Unit Tests**:
   - Press **Cmd + U** to run the complete test suite.

---

## 🔒 Permissions & Privacy
- **Calendars**: `NSCalendarsWriteOnlyAccessUsageDescription` allows Assignment Radar to create and update only its managed events without accessing personal calendar data.
- **Camera**: `NSCameraUsageDescription` enables document capture for timetable and exam schedule parsing.
- **Notifications**: Requires user authorization for local scheduled deadline reminders.
