import Foundation
import XCTest
@testable import FocusSessionCore

final class SessionServiceTests: XCTestCase {
    func testCustomSessionStartUsesThreeSecondCountdown() {
        XCTAssertEqual(
            CustomSessionStartCountdown.ticks,
            [3, 2, 1]
        )
    }

    func testDefaultSessionUsesAbsoluteFourHourEnd() throws {
        let service = try makeService()
        let start = Date(timeIntervalSince1970: 1_000_000)

        let state = try service.startSession(
            preset: .fourHours,
            now: start
        )

        XCTAssertEqual(
            state.scheduledEndAt,
            start.addingTimeInterval(4 * 60 * 60)
        )
        XCTAssertEqual(state.phase, .focusing)
        XCTAssertTrue(state.shouldBlockRestrictedServices)
        XCTAssertEqual(state.focusDurationSeconds, 55 * 60)
        XCTAssertEqual(state.breakDurationSeconds, 5 * 60)
        XCTAssertFalse(state.usageObservationEnabled)
        XCTAssertTrue(state.historyEnabled)
        XCTAssertFalse(
            try service.snapshot(now: start).settings
                .distractionSuggestionsEnabled
        )
    }

    func testPublicStateReportsOverallSessionProgress() throws {
        let service = try makeService()
        let start = Date(timeIntervalSince1970: 1_250_000)
        let end = start.addingTimeInterval(4 * 60 * 60)

        let initial = try service.startSession(
            endingAt: end,
            now: start
        )
        XCTAssertEqual(
            initial.sessionElapsedFraction,
            0,
            accuracy: 0.000_001
        )

        let midpoint = try service.publicState(
            now: start.addingTimeInterval(2 * 60 * 60)
        )
        XCTAssertEqual(
            midpoint.sessionElapsedFraction,
            0.5,
            accuracy: 0.000_001
        )
    }

    func testNoBreakSessionStaysFocusedAndCountsIntervals() throws {
        let service = try makeService()
        let start = Date(timeIntervalSince1970: 1_500_000)
        var settings = SessionSettings()
        settings.focusDuration = 60
        settings.breakDuration = 0
        try service.updateSettings(settings, now: start)

        _ = try service.startSession(
            endingAt: start.addingTimeInterval(10 * 60),
            now: start
        )

        let afterFirstInterval = try service.publicState(
            now: start.addingTimeInterval(61)
        )
        XCTAssertEqual(afterFirstInterval.phase, .focusing)
        XCTAssertFalse(afterFirstInterval.canStartBreak)
        XCTAssertNil(afterFirstInterval.focusAvailableAt)
        XCTAssertEqual(afterFirstInterval.breakDurationSeconds, 0)
        XCTAssertTrue(afterFirstInterval.shouldBlockRestrictedServices)

        XCTAssertThrowsError(
            try service.startBreak(now: start.addingTimeInterval(61))
        ) { error in
            XCTAssertEqual(
                error as? SessionServiceError,
                .breakNotAvailable
            )
        }

        let snapshot = try service.snapshot(
            now: start.addingTimeInterval(181)
        )
        XCTAssertEqual(
            snapshot.activeSession?.counters.completedFocusIntervals,
            3
        )
    }

    func testInactivePublicStateAlwaysExportsPrivacySwitches() throws {
        let service = try makeService()
        var settings = SessionSettings()
        settings.usageObservationEnabled = false
        settings.historyEnabled = false
        try service.updateSettings(settings)

        let state = try service.publicState()
        XCTAssertEqual(state.phase, .inactive)
        XCTAssertFalse(state.usageObservationEnabled)
        XCTAssertFalse(state.historyEnabled)
    }

    func testPendingBreakDoesNotAccumulate() throws {
        let service = try makeService()
        let start = Date(timeIntervalSince1970: 2_000_000)
        _ = try service.startSession(preset: .fourHours, now: start)

        var state = try service.publicState(
            now: start.addingTimeInterval(55 * 60)
        )
        XCTAssertEqual(state.phase, .breakAvailable)
        XCTAssertTrue(state.canStartBreak)

        state = try service.publicState(
            now: start.addingTimeInterval(2 * 60 * 60)
        )
        XCTAssertEqual(state.phase, .breakAvailable)

        var snapshot = try service.snapshot(
            now: start.addingTimeInterval(2 * 60 * 60)
        )
        XCTAssertEqual(
            snapshot.activeSession?.counters.completedFocusIntervals,
            1
        )

        let breakStart = start.addingTimeInterval(2 * 60 * 60)
        _ = try service.startBreak(now: breakStart)
        state = try service.publicState(
            now: breakStart.addingTimeInterval(5 * 60)
        )
        XCTAssertEqual(state.phase, .focusing)

        state = try service.publicState(
            now: breakStart.addingTimeInterval(60 * 60)
        )
        XCTAssertEqual(state.phase, .breakAvailable)
        snapshot = try service.snapshot(
            now: breakStart.addingTimeInterval(60 * 60)
        )
        XCTAssertEqual(
            snapshot.activeSession?.counters.completedFocusIntervals,
            2
        )
    }

    func testShotClockExtensionOnlyUnlocksInLastTenSecondsAndRepeats() throws {
        let service = try makeService()
        let start = Date(timeIntervalSince1970: 3_000_000)
        var settings = SessionSettings()
        settings.focusDuration = 60
        try service.updateSettings(settings, now: start)
        _ = try service.startSession(
            endingAt: start.addingTimeInterval(30 * 60),
            now: start
        )

        let breakStart = start.addingTimeInterval(60)
        _ = try service.startBreak(now: breakStart)
        let originalEnd = breakStart.addingTimeInterval(5 * 60)

        XCTAssertThrowsError(
            try service.extendBreak(
                now: originalEnd.addingTimeInterval(-11)
            )
        ) { error in
            XCTAssertEqual(
                error as? SessionServiceError,
                .extensionNotAvailable
            )
        }

        var state = try service.extendBreak(
            now: originalEnd.addingTimeInterval(-10)
        )
        XCTAssertEqual(
            state.breakEndsAt,
            originalEnd.addingTimeInterval(30)
        )
        XCTAssertFalse(state.canExtendBreak)

        state = try service.extendBreak(
            now: originalEnd.addingTimeInterval(20)
        )
        XCTAssertEqual(
            state.breakEndsAt,
            originalEnd.addingTimeInterval(60)
        )

        _ = try service.publicState(
            now: originalEnd.addingTimeInterval(60)
        )
        let snapshot = try service.snapshot(
            now: originalEnd.addingTimeInterval(60)
        )
        XCTAssertEqual(snapshot.activeSession?.counters.breakExtensions, 2)
        let counters = try XCTUnwrap(snapshot.activeSession?.counters)
        XCTAssertEqual(
            counters.breakOvertimeSeconds,
            60,
            accuracy: 0.001
        )
        XCTAssertEqual(
            counters.breakSecondsUsed,
            6 * 60,
            accuracy: 0.001
        )
    }

    func testExtensionNeverMovesScheduledSessionEnd() throws {
        let service = try makeService()
        let start = Date(timeIntervalSince1970: 4_000_000)
        var settings = SessionSettings()
        settings.focusDuration = 60
        try service.updateSettings(settings, now: start)
        let scheduledEnd = start.addingTimeInterval(6 * 60 + 20)
        _ = try service.startSession(
            endingAt: scheduledEnd,
            now: start
        )
        let breakStart = start.addingTimeInterval(60)
        _ = try service.startBreak(now: breakStart)

        let initialBreakEnd = breakStart.addingTimeInterval(5 * 60)
        var state = try service.extendBreak(
            now: initialBreakEnd.addingTimeInterval(-5)
        )
        XCTAssertEqual(state.breakEndsAt, scheduledEnd)
        XCTAssertFalse(state.canExtendBreak)

        XCTAssertThrowsError(
            try service.extendBreak(
                now: scheduledEnd.addingTimeInterval(-5)
            )
        ) { error in
            XCTAssertEqual(error as? SessionServiceError, .sessionEnding)
        }

        state = try service.publicState(now: scheduledEnd)
        XCTAssertEqual(state.phase, .inactive)
        let record = try XCTUnwrap(service.snapshot(now: scheduledEnd).history.last)
        XCTAssertEqual(record.actualEndAt, scheduledEnd)
        XCTAssertEqual(record.counters.breakOvertimeSeconds, 20, accuracy: 0.001)
        XCTAssertEqual(record.counters.breakSecondsUsed, 5 * 60 + 20, accuracy: 0.001)
    }

    func testEarlyEndAccruesPartialBreakAndSetsWorkFocusCleanup() throws {
        let service = try makeService()
        let start = Date(timeIntervalSince1970: 5_000_000)
        var settings = SessionSettings()
        settings.focusDuration = 60
        try service.updateSettings(settings, now: start)
        _ = try service.startSession(
            endingAt: start.addingTimeInterval(60 * 60),
            now: start,
            workFocusManaged: true
        )
        _ = try service.startBreak(now: start.addingTimeInterval(60))

        let end = start.addingTimeInterval(180)
        _ = try service.endSessionEarly(now: end)

        var snapshot = try service.snapshot(now: end)
        let record = try XCTUnwrap(snapshot.history.last)
        XCTAssertEqual(record.endReason, .endedEarly)
        XCTAssertEqual(record.counters.breakSecondsUsed, 120, accuracy: 0.001)
        XCTAssertTrue(snapshot.workFocusCleanupPending)

        try service.acknowledgeWorkFocusCleanup()
        snapshot = try service.snapshot(now: end)
        XCTAssertFalse(snapshot.workFocusCleanupPending)
    }

    func testRestartReconcilesExpiredAbsoluteSession() throws {
        let root = makeTemporaryDirectory()
        let start = Date(timeIntervalSince1970: 6_000_000)
        let first = SessionService(
            repository: try LocalStateRepository(rootDirectory: root)
        )
        _ = try first.startSession(
            endingAt: start.addingTimeInterval(2 * 60 * 60),
            now: start
        )

        let restarted = SessionService(
            repository: try LocalStateRepository(rootDirectory: root)
        )
        let state = try restarted.publicState(
            now: start.addingTimeInterval(3 * 60 * 60)
        )

        XCTAssertEqual(state.phase, .inactive)
        let snapshot = try restarted.snapshot(
            now: start.addingTimeInterval(3 * 60 * 60)
        )
        XCTAssertNil(snapshot.activeSession)
        XCTAssertEqual(snapshot.history.count, 1)
        XCTAssertEqual(
            snapshot.history[0].actualEndAt,
            start.addingTimeInterval(2 * 60 * 60)
        )
    }

    func testCompletionCountsFocusIntervalEvenWithoutIntermediatePoll() throws {
        let service = try makeService()
        let start = Date(timeIntervalSince1970: 7_000_000)
        _ = try service.startSession(
            endingAt: start.addingTimeInterval(60 * 60),
            now: start
        )

        _ = try service.publicState(
            now: start.addingTimeInterval(2 * 60 * 60)
        )
        let record = try XCTUnwrap(
            service.snapshot(
                now: start.addingTimeInterval(2 * 60 * 60)
            ).history.last
        )
        XCTAssertEqual(record.counters.completedFocusIntervals, 1)
    }

    func testDomainAndHistoryDataAreReducedToAggregateDomains() throws {
        let service = try makeService()
        let now = Date(timeIntervalSince1970: 8_000_000)
        var settings = SessionSettings()
        settings.usageObservationEnabled = true
        try service.updateSettings(settings, now: now)

        try service.importHistorySummary(
            [
                HistorySummaryEntry(
                    domain: "https://www.reddit.com/r/swift?secret=value",
                    visitCount: 12,
                    lastVisitAt: now.addingTimeInterval(-100)
                ),
                HistorySummaryEntry(
                    domain: "subdomain.example.co.uk/private/path",
                    visitCount: 4,
                    lastVisitAt: now
                )
            ],
            now: now
        )

        let snapshot = try service.snapshot(now: now)
        XCTAssertEqual(snapshot.usage.domains["reddit.com"]?.visitCount, 12)
        XCTAssertEqual(snapshot.usage.domains["example.co.uk"]?.visitCount, 4)
        XCTAssertNil(snapshot.usage.domains["www.reddit.com"])
        XCTAssertFalse(
            snapshot.usage.domains.keys.contains { $0.contains("/") }
        )
        XCTAssertFalse(
            snapshot.usage.domains.keys.contains { $0.contains("?") }
        )
    }

    func testNativeMessageFailureStillIncludesCurrentState() throws {
        let service = try makeService()
        let processor = NativeMessageProcessor(service: service)
        let now = Date(timeIntervalSince1970: 9_000_000)

        let response = processor.process(
            NativeMessageRequest(type: .recordBlockedAttempt),
            now: now
        )

        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.state.phase, .inactive)
        XCTAssertEqual(response.error?.code, "missingField.service")
    }

    func testNativeMessageAggregatesBlockedAttemptCount() throws {
        let service = try makeService()
        let processor = NativeMessageProcessor(service: service)
        let now = Date(timeIntervalSince1970: 9_500_000)
        let started = try service.startSession(preset: .oneHour, now: now)
        let sessionID = try XCTUnwrap(started.sessionID)

        let response = processor.process(
            NativeMessageRequest(
                type: .recordBlockedAttempt,
                service: "reddit",
                attemptCount: 37,
                sessionID: sessionID,
                wasOnBreak: false,
                historyEnabledAtObservation: true
            ),
            now: now.addingTimeInterval(1)
        )

        XCTAssertTrue(response.ok)
        let snapshot = try service.snapshot(
            now: now.addingTimeInterval(1)
        )
        XCTAssertEqual(
            snapshot.activeSession?.counters.blockedAttempts["reddit"],
            37
        )
    }

    func testDelayedBreakActivityUsesObservationContextNotCurrentPhase() throws {
        let service = try makeService()
        let start = Date(timeIntervalSince1970: 9_600_000)
        var settings = SessionSettings()
        settings.focusDuration = 60
        settings.breakDuration = 60
        settings.blockedDomains = ["reddit.com"]
        settings.usageObservationEnabled = true
        try service.updateSettings(settings, now: start)

        let started = try service.startSession(
            endingAt: start.addingTimeInterval(20 * 60),
            now: start
        )
        let sessionID = try XCTUnwrap(started.sessionID)
        _ = try service.startBreak(now: start.addingTimeInterval(60))

        let afterBreak = start.addingTimeInterval(121)
        XCTAssertEqual(
            try service.publicState(now: afterBreak).phase,
            .focusing
        )

        try service.recordDomainActivity(
            domain: "www.reddit.com",
            activeSeconds: 50,
            sessionID: sessionID,
            wasOnBreak: true,
            historyEnabledAtObservation: true,
            now: afterBreak
        )
        try service.recordDomainActivity(
            domain: "reddit.com",
            activeSeconds: 25,
            sessionID: sessionID,
            wasOnBreak: false,
            historyEnabledAtObservation: true,
            now: afterBreak
        )

        let snapshot = try service.snapshot(now: afterBreak)
        XCTAssertEqual(
            snapshot.activeSession?.counters
                .restrictedServiceSeconds["reddit.com"],
            50
        )
        XCTAssertEqual(
            snapshot.usage.domains["reddit.com"]?.activeSeconds,
            75
        )
    }

    func testDelayedActivityCanUpdateMatchingArchivedSessionOnly() throws {
        let service = try makeService()
        let start = Date(timeIntervalSince1970: 9_700_000)
        var settings = SessionSettings()
        settings.focusDuration = 60
        settings.breakDuration = 60
        settings.blockedBundleIdentifiers = ["com.hnc.Discord"]
        settings.usageObservationEnabled = true
        try service.updateSettings(settings, now: start)

        let started = try service.startSession(
            endingAt: start.addingTimeInterval(120),
            now: start
        )
        let sessionID = try XCTUnwrap(started.sessionID)
        _ = try service.startBreak(now: start.addingTimeInterval(60))
        _ = try service.publicState(now: start.addingTimeInterval(121))

        try service.recordApplicationActivity(
            bundleIdentifier: "com.hnc.Discord",
            activeSeconds: 40,
            sessionID: sessionID,
            wasOnBreak: true,
            historyEnabledAtObservation: true,
            now: start.addingTimeInterval(130)
        )
        try service.recordApplicationActivity(
            bundleIdentifier: "com.hnc.Discord",
            activeSeconds: 30,
            sessionID: UUID(),
            wasOnBreak: true,
            historyEnabledAtObservation: true,
            now: start.addingTimeInterval(131)
        )

        let record = try XCTUnwrap(
            service.snapshot(now: start.addingTimeInterval(131)).history.last
        )
        XCTAssertEqual(
            record.counters.restrictedServiceSeconds["com.hnc.Discord"],
            40
        )
    }

    func testBlockedAttemptRejectsBreakContextAndWrongSession() throws {
        let service = try makeService()
        let start = Date(timeIntervalSince1970: 9_800_000)
        let started = try service.startSession(
            preset: .oneHour,
            now: start
        )
        let sessionID = try XCTUnwrap(started.sessionID)

        try service.recordBlockedAttempt(
            service: "reddit",
            count: 9,
            sessionID: sessionID,
            wasOnBreak: true,
            historyEnabledAtObservation: true,
            now: start.addingTimeInterval(1)
        )
        try service.recordBlockedAttempt(
            service: "reddit",
            count: 7,
            sessionID: UUID(),
            wasOnBreak: false,
            historyEnabledAtObservation: true,
            now: start.addingTimeInterval(2)
        )
        try service.recordBlockedAttempt(
            service: "reddit",
            count: 11,
            sessionID: sessionID,
            wasOnBreak: false,
            historyEnabledAtObservation: false,
            now: start.addingTimeInterval(2.5)
        )
        try service.recordBlockedAttempt(
            service: "reddit",
            count: 5,
            sessionID: sessionID,
            wasOnBreak: false,
            historyEnabledAtObservation: true,
            now: start.addingTimeInterval(3)
        )

        XCTAssertEqual(
            try service.snapshot(
                now: start.addingTimeInterval(3)
            ).activeSession?.counters.blockedAttempts["reddit"],
            5
        )
    }

    func testDisablingHistoryClearsAndStopsActiveCountersButKeepsUsage() throws {
        let service = try makeService()
        let start = Date(timeIntervalSince1970: 9_900_000)
        var settings = SessionSettings()
        settings.focusDuration = 60
        settings.breakDuration = 60
        settings.blockedDomains = ["reddit.com"]
        settings.usageObservationEnabled = true
        try service.updateSettings(settings, now: start)
        let started = try service.startSession(
            endingAt: start.addingTimeInterval(10 * 60),
            now: start
        )
        let sessionID = try XCTUnwrap(started.sessionID)
        _ = try service.publicState(now: start.addingTimeInterval(60))
        _ = try service.startBreak(now: start.addingTimeInterval(60))

        var populated = try service.snapshot(
            now: start.addingTimeInterval(61)
        )
        XCTAssertEqual(
            populated.activeSession?.counters.completedFocusIntervals,
            1
        )
        XCTAssertEqual(populated.activeSession?.counters.breaksTaken, 1)

        settings.historyEnabled = false
        try service.updateSettings(
            settings,
            now: start.addingTimeInterval(62)
        )
        try service.recordDomainActivity(
            domain: "reddit.com",
            activeSeconds: 20,
            sessionID: sessionID,
            wasOnBreak: true,
            historyEnabledAtObservation: true,
            now: start.addingTimeInterval(63)
        )
        try service.recordBlockedAttempt(
            service: "reddit",
            sessionID: sessionID,
            wasOnBreak: false,
            historyEnabledAtObservation: true,
            now: start.addingTimeInterval(64)
        )

        populated = try service.snapshot(
            now: start.addingTimeInterval(64)
        )
        XCTAssertEqual(populated.activeSession?.counters, SessionCounters())
        XCTAssertEqual(
            populated.usage.domains["reddit.com"]?.activeSeconds,
            20
        )
        XCTAssertFalse(try service.publicState(
            now: start.addingTimeInterval(64)
        ).historyEnabled)
        XCTAssertTrue(try service.publicState(
            now: start.addingTimeInterval(64)
        ).usageObservationEnabled)
    }

    func testUsageObservationSwitchOnlyControlsUsageRollup() throws {
        let service = try makeService()
        let start = Date(timeIntervalSince1970: 9_950_000)
        var settings = SessionSettings()
        settings.focusDuration = 60
        settings.breakDuration = 60
        settings.blockedDomains = ["reddit.com"]
        settings.usageObservationEnabled = true
        try service.updateSettings(settings, now: start)
        let started = try service.startSession(
            endingAt: start.addingTimeInterval(10 * 60),
            now: start
        )
        let sessionID = try XCTUnwrap(started.sessionID)
        _ = try service.startBreak(now: start.addingTimeInterval(60))

        settings.usageObservationEnabled = false
        try service.updateSettings(
            settings,
            now: start.addingTimeInterval(61)
        )
        try service.recordDomainActivity(
            domain: "reddit.com",
            activeSeconds: 15,
            sessionID: sessionID,
            wasOnBreak: true,
            historyEnabledAtObservation: true,
            now: start.addingTimeInterval(62)
        )

        let snapshot = try service.snapshot(
            now: start.addingTimeInterval(62)
        )
        XCTAssertNil(snapshot.usage.domains["reddit.com"])
        XCTAssertEqual(
            snapshot.activeSession?.counters
                .restrictedServiceSeconds["reddit.com"],
            15
        )
    }

    func testStateFileUsesOwnerOnlyPermissions() throws {
        let root = makeTemporaryDirectory()
        let repository = try LocalStateRepository(rootDirectory: root)
        let service = SessionService(repository: repository)
        let now = Date(timeIntervalSince1970: 10_000_000)
        _ = try service.startSession(preset: .oneHour, now: now)

        let attributes = try FileManager.default.attributesOfItem(
            atPath: repository.stateFileURL.path
        )
        let permissions = try XCTUnwrap(
            attributes[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testClearAllHistoryAlsoClearsUsageAndSuggestionState() throws {
        let service = try makeService()
        let start = Date(timeIntervalSince1970: 11_000_000)
        try service.recordDomainActivity(
            domain: "youtube.com",
            activeSeconds: 120,
            visitCount: 20,
            now: start
        )
        _ = try service.startSession(
            endingAt: start.addingTimeInterval(60),
            now: start
        )
        _ = try service.publicState(now: start.addingTimeInterval(60))
        try service.dismissSuggestedDomain("youtube.com")

        try service.clearAllHistoryAndUsage()
        let snapshot = try service.snapshot(
            now: start.addingTimeInterval(60)
        )

        XCTAssertTrue(snapshot.history.isEmpty)
        XCTAssertTrue(snapshot.usage.domains.isEmpty)
        XCTAssertTrue(snapshot.usage.applications.isEmpty)
        XCTAssertTrue(snapshot.suggestionState.dismissedDomains.isEmpty)
        XCTAssertNil(snapshot.suggestionState.lastReviewAt)
        XCTAssertEqual(
            snapshot.settings.blockedDomains,
            SessionSettings().blockedDomains
        )
    }

    private func makeService() throws -> SessionService {
        let root = makeTemporaryDirectory()
        return SessionService(
            repository: try LocalStateRepository(rootDirectory: root)
        )
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "FocusSessionTests-\(UUID().uuidString)",
                isDirectory: true
            )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
