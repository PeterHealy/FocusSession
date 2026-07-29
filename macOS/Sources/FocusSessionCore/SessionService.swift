import Foundation

public enum SessionServiceError: LocalizedError, Equatable {
    case sessionAlreadyActive
    case noActiveSession
    case invalidEndTime
    case breakNotAvailable
    case noActiveBreak
    case extensionNotAvailable
    case sessionEnding
    case invalidService
    case invalidDomain
    case invalidActivityDuration

    public var errorDescription: String? {
        switch self {
        case .sessionAlreadyActive:
            return "A focus session is already active."
        case .noActiveSession:
            return "There is no active focus session."
        case .invalidEndTime:
            return "The session end time must be in the future."
        case .breakNotAvailable:
            return "Finish the current focus interval before starting a break."
        case .noActiveBreak:
            return "There is no active break."
        case .extensionNotAvailable:
            return "Another 30 seconds becomes available when 10 seconds or less remain."
        case .sessionEnding:
            return "The session is ending before another extension can be added."
        case .invalidService:
            return "A valid aggregate service identifier is required."
        case .invalidDomain:
            return "A valid domain is required."
        case .invalidActivityDuration:
            return "Activity duration must be greater than zero."
        }
    }
}

public final class SessionService {
    public let repository: LocalStateRepository

    public init(repository: LocalStateRepository) {
        self.repository = repository
    }

    public convenience init() throws {
        try self.init(repository: LocalStateRepository())
    }

    @discardableResult
    public func startSession(
        preset: SessionPreset,
        now: Date = Date(),
        workFocusManaged: Bool = false
    ) throws -> PublicSessionState {
        try startSession(
            endingAt: now.addingTimeInterval(preset.duration),
            now: now,
            workFocusManaged: workFocusManaged
        )
    }

    @discardableResult
    public func startSession(
        endingAt: Date,
        now: Date = Date(),
        workFocusManaged: Bool = false
    ) throws -> PublicSessionState {
        try repository.transaction { state in
            Self.reconcile(&state, now: now)
            guard state.activeSession == nil else {
                throw SessionServiceError.sessionAlreadyActive
            }
            guard endingAt > now else {
                throw SessionServiceError.invalidEndTime
            }

            state.activeSession = ActiveSession(
                startedAt: now,
                scheduledEndAt: endingAt,
                focusCycleStartedAt: now,
                workFocusManaged: workFocusManaged
            )
            if workFocusManaged {
                state.workFocusCleanupPending = false
            }
            return Self.makePublicState(from: state, now: now)
        }
    }

    @discardableResult
    public func startBreak(now: Date = Date()) throws -> PublicSessionState {
        try repository.transaction { state in
            Self.reconcile(&state, now: now)
            guard var session = state.activeSession else {
                throw SessionServiceError.noActiveSession
            }
            guard state.settings.breakDuration > 0,
                  session.activeBreak == nil,
                  session.currentFocusIntervalCounted
            else {
                throw SessionServiceError.breakNotAvailable
            }

            let proposedEnd = now.addingTimeInterval(state.settings.breakDuration)
            let breakEnd = min(proposedEnd, session.scheduledEndAt)
            guard breakEnd > now else {
                throw SessionServiceError.sessionEnding
            }

            session.activeBreak = BreakWindow(startedAt: now, endsAt: breakEnd)
            if state.settings.historyEnabled {
                session.counters.breaksTaken += 1
            }
            state.activeSession = session
            return Self.makePublicState(from: state, now: now)
        }
    }

    @discardableResult
    public func extendBreak(now: Date = Date()) throws -> PublicSessionState {
        try repository.transaction { state in
            Self.reconcile(&state, now: now)
            guard var session = state.activeSession else {
                throw SessionServiceError.noActiveSession
            }
            guard var activeBreak = session.activeBreak else {
                throw SessionServiceError.noActiveBreak
            }

            let remaining = activeBreak.endsAt.timeIntervalSince(now)
            guard remaining > 0,
                  remaining <= state.settings.extensionEligibilityWindow
            else {
                throw SessionServiceError.extensionNotAvailable
            }

            let proposedEnd = activeBreak.endsAt.addingTimeInterval(
                state.settings.breakExtensionDuration
            )
            let extendedEnd = min(proposedEnd, session.scheduledEndAt)
            let addedSeconds = extendedEnd.timeIntervalSince(activeBreak.endsAt)
            guard addedSeconds > 0 else {
                throw SessionServiceError.sessionEnding
            }

            activeBreak.endsAt = extendedEnd
            activeBreak.extensionCount += 1
            session.activeBreak = activeBreak
            if state.settings.historyEnabled {
                session.counters.breakExtensions += 1
                session.counters.breakOvertimeSeconds += addedSeconds
            }
            state.activeSession = session
            return Self.makePublicState(from: state, now: now)
        }
    }

    @discardableResult
    public func endSessionEarly(now: Date = Date()) throws -> PublicSessionState {
        try repository.transaction { state in
            Self.reconcile(&state, now: now)
            guard var session = state.activeSession else {
                throw SessionServiceError.noActiveSession
            }

            Self.finishActiveBreak(
                in: &session,
                at: now,
                recordStatistics: state.settings.historyEnabled
            )
            Self.archive(
                session,
                reason: .endedEarly,
                actualEndAt: now,
                in: &state
            )
            state.activeSession = nil
            return Self.makePublicState(from: state, now: now)
        }
    }

    public func publicState(now: Date = Date()) throws -> PublicSessionState {
        try repository.transaction { state in
            Self.reconcile(&state, now: now)
            return Self.makePublicState(from: state, now: now)
        }
    }

    public func snapshot(now: Date = Date()) throws -> PersistedState {
        try repository.transaction { state in
            Self.reconcile(&state, now: now)
            return state
        }
    }

    public func currentState(
        now: Date = Date()
    ) throws -> (snapshot: PersistedState, publicState: PublicSessionState) {
        try repository.transaction { state in
            Self.reconcile(&state, now: now)
            return (
                snapshot: state,
                publicState: Self.makePublicState(from: state, now: now)
            )
        }
    }

    public func updateSettings(
        _ settings: SessionSettings,
        now: Date = Date()
    ) throws {
        try repository.transaction { state in
            Self.reconcile(&state, now: now)
            var normalized = settings
            normalized.normalize()
            if !normalized.historyEnabled,
               var session = state.activeSession {
                session.counters = SessionCounters()
                state.activeSession = session
            }
            state.settings = normalized
        }
    }

    public func recordBlockedAttempt(
        service rawService: String,
        count: Int = 1,
        sessionID: UUID? = nil,
        wasOnBreak: Bool? = nil,
        historyEnabledAtObservation: Bool? = nil,
        now: Date = Date()
    ) throws {
        let service = try Self.aggregateServiceKey(rawService)
        let boundedCount = min(max(count, 1), 10_000)
        try repository.transaction { state in
            Self.reconcile(&state, now: now)
            guard state.settings.historyEnabled,
                  historyEnabledAtObservation == true,
                  wasOnBreak != true,
                  let sessionID
            else {
                return
            }

            Self.updateCounters(
                for: sessionID,
                in: &state
            ) { counters in
                counters.blockedAttempts[service, default: 0] +=
                    boundedCount
            }
        }
    }

    public func recordDomainActivity(
        domain rawDomain: String,
        activeSeconds: TimeInterval,
        visitCount: Int = 0,
        sessionID: UUID? = nil,
        wasOnBreak: Bool? = nil,
        historyEnabledAtObservation: Bool? = nil,
        now: Date = Date()
    ) throws {
        guard activeSeconds >= 0, activeSeconds <= 60 * 60 else {
            throw SessionServiceError.invalidActivityDuration
        }
        guard let domain = DomainSanitizer.aggregateKey(from: rawDomain) else {
            throw SessionServiceError.invalidDomain
        }

        try repository.transaction { state in
            Self.reconcile(&state, now: now)
            if state.settings.usageObservationEnabled {
                var rollup = state.usage.domains[domain] ?? UsageRollup()
                rollup.merge(
                    activeSeconds: activeSeconds,
                    visitCount: min(max(0, visitCount), 10_000),
                    lastSeenAt: now
                )
                state.usage.domains[domain] = rollup
            }

            guard state.settings.historyEnabled,
                  historyEnabledAtObservation == true,
                  wasOnBreak == true,
                  activeSeconds > 0,
                  state.settings.blocks(domain: domain),
                  let sessionID
            else {
                return
            }

            Self.updateCounters(
                for: sessionID,
                in: &state
            ) { counters in
                counters.restrictedServiceSeconds[domain, default: 0] +=
                    activeSeconds
            }
        }
    }

    public func recordApplicationActivity(
        bundleIdentifier rawBundleIdentifier: String,
        activeSeconds: TimeInterval,
        sessionID: UUID? = nil,
        wasOnBreak: Bool? = nil,
        historyEnabledAtObservation: Bool? = nil,
        now: Date = Date()
    ) throws {
        guard activeSeconds > 0, activeSeconds <= 60 * 60 else {
            throw SessionServiceError.invalidActivityDuration
        }
        let bundleIdentifier = rawBundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleIdentifier.isEmpty,
              !bundleIdentifier.contains("/")
        else {
            throw SessionServiceError.invalidService
        }

        try repository.transaction { state in
            Self.reconcile(&state, now: now)
            if state.settings.usageObservationEnabled {
                var rollup =
                    state.usage.applications[bundleIdentifier] ?? UsageRollup()
                rollup.merge(
                    activeSeconds: activeSeconds,
                    visitCount: 0,
                    lastSeenAt: now
                )
                state.usage.applications[bundleIdentifier] = rollup
            }

            guard state.settings.historyEnabled,
                  historyEnabledAtObservation == true,
                  wasOnBreak == true,
                  state.settings.blocks(bundleIdentifier: bundleIdentifier),
                  let sessionID
            else {
                return
            }

            Self.updateCounters(
                for: sessionID,
                in: &state
            ) { counters in
                counters.restrictedServiceSeconds[
                    bundleIdentifier,
                    default: 0
                ] += activeSeconds
            }
        }
    }

    public func importHistorySummary(
        _ entries: [HistorySummaryEntry],
        now: Date = Date()
    ) throws {
        try repository.transaction { state in
            guard state.settings.usageObservationEnabled else {
                return
            }

            for entry in entries.prefix(10_000) {
                guard let domain = DomainSanitizer.aggregateKey(
                    from: entry.domain
                ) else {
                    continue
                }

                var rollup = state.usage.domains[domain] ?? UsageRollup()
                rollup.merge(
                    activeSeconds: 0,
                    visitCount: min(max(0, entry.visitCount), 1_000_000),
                    lastSeenAt: min(entry.lastVisitAt ?? now, now)
                )
                state.usage.domains[domain] = rollup
            }
        }
    }

    public func deleteHistoryRecord(id: UUID) throws {
        try repository.transaction { state in
            state.history.removeAll { $0.id == id }
        }
    }

    public func clearHistory() throws {
        try repository.transaction { state in
            state.history.removeAll()
        }
    }

    public func clearAllHistoryAndUsage() throws {
        try repository.transaction { state in
            state.history.removeAll()
            state.usage = UsageSnapshot()
            state.suggestionState = SuggestionState()
        }
    }

    public func clearUsageRollups() throws {
        try repository.transaction { state in
            state.usage = UsageSnapshot()
            state.suggestionState = SuggestionState()
        }
    }

    public func suggestedDomains(
        now: Date = Date(),
        ignoreWeeklyCadence: Bool = false
    ) throws -> [String] {
        let state = try snapshot(now: now)
        guard state.settings.distractionSuggestionsEnabled else {
            return []
        }

        if !ignoreWeeklyCadence,
           let lastReview = state.suggestionState.lastReviewAt,
           now.timeIntervalSince(lastReview) < 7 * 24 * 60 * 60 {
            return []
        }

        let dismissed = Set(state.suggestionState.dismissedDomains)
        let blocked = Set(state.settings.blockedDomains)
        return state.usage.domains
            .filter { domain, usage in
                Self.knownDistractionDomains.contains(domain)
                    && !dismissed.contains(domain)
                    && !blocked.contains(domain)
                    && (usage.visitCount >= 10 || usage.activeSeconds >= 15 * 60)
            }
            .sorted { lhs, rhs in
                let lhsScore =
                    Double(lhs.value.visitCount) + lhs.value.activeSeconds / 60
                let rhsScore =
                    Double(rhs.value.visitCount) + rhs.value.activeSeconds / 60
                return lhsScore > rhsScore
            }
            .map(\.key)
    }

    public func acceptSuggestedDomain(_ rawDomain: String) throws {
        guard let domain = DomainSanitizer.aggregateKey(from: rawDomain) else {
            throw SessionServiceError.invalidDomain
        }
        try repository.transaction { state in
            if !state.settings.blockedDomains.contains(domain) {
                state.settings.blockedDomains.append(domain)
                state.settings.normalize()
            }
        }
    }

    public func dismissSuggestedDomain(_ rawDomain: String) throws {
        guard let domain = DomainSanitizer.aggregateKey(from: rawDomain) else {
            throw SessionServiceError.invalidDomain
        }
        try repository.transaction { state in
            if !state.suggestionState.dismissedDomains.contains(domain) {
                state.suggestionState.dismissedDomains.append(domain)
                state.suggestionState.dismissedDomains.sort()
            }
        }
    }

    public func markSuggestionsReviewed(now: Date = Date()) throws {
        try repository.transaction { state in
            state.suggestionState.lastReviewAt = now
        }
    }

    public func acknowledgeWorkFocusCleanup() throws {
        try repository.transaction { state in
            state.workFocusCleanupPending = false
        }
    }

    private static func reconcile(_ state: inout PersistedState, now: Date) {
        guard var session = state.activeSession else {
            return
        }

        let reconciliationHorizon = min(now, session.scheduledEndAt)

        if let activeBreak = session.activeBreak,
           reconciliationHorizon >= activeBreak.endsAt {
            if state.settings.historyEnabled {
                session.counters.breakSecondsUsed += max(
                    0,
                    activeBreak.endsAt.timeIntervalSince(activeBreak.startedAt)
                )
            }
            session.activeBreak = nil
            session.focusCycleStartedAt = activeBreak.endsAt
            session.currentFocusIntervalCounted = false
        }

        if state.settings.breakDuration == 0,
           session.activeBreak == nil {
            let interval = state.settings.focusDuration
            let elapsed = max(
                0,
                reconciliationHorizon.timeIntervalSince(
                    session.focusCycleStartedAt
                )
            )
            let completedIntervals = Int(elapsed / interval)
            if completedIntervals > 0 {
                if state.settings.historyEnabled {
                    session.counters.completedFocusIntervals +=
                        completedIntervals
                }
                session.focusCycleStartedAt =
                    session.focusCycleStartedAt.addingTimeInterval(
                        TimeInterval(completedIntervals) * interval
                    )
            }
            session.currentFocusIntervalCounted = false
        } else if session.activeBreak == nil,
           !session.currentFocusIntervalCounted,
           reconciliationHorizon >= session.focusCycleStartedAt.addingTimeInterval(
               state.settings.focusDuration
            ) {
            session.currentFocusIntervalCounted = true
            if state.settings.historyEnabled {
                session.counters.completedFocusIntervals += 1
            }
        }

        if now >= session.scheduledEndAt {
            finishActiveBreak(
                in: &session,
                at: session.scheduledEndAt,
                recordStatistics: state.settings.historyEnabled
            )
            archive(
                session,
                reason: .completed,
                actualEndAt: session.scheduledEndAt,
                in: &state
            )
            state.activeSession = nil
            return
        }

        state.activeSession = session
    }

    private static func finishActiveBreak(
        in session: inout ActiveSession,
        at endDate: Date,
        recordStatistics: Bool
    ) {
        guard let activeBreak = session.activeBreak else {
            return
        }

        let effectiveEnd = min(endDate, activeBreak.endsAt)
        if recordStatistics {
            session.counters.breakSecondsUsed += max(
                0,
                effectiveEnd.timeIntervalSince(activeBreak.startedAt)
            )
        }
        session.activeBreak = nil
    }

    private static func archive(
        _ session: ActiveSession,
        reason: SessionEndReason,
        actualEndAt: Date,
        in state: inout PersistedState
    ) {
        if session.workFocusManaged {
            state.workFocusCleanupPending = true
        }

        guard state.settings.historyEnabled else {
            return
        }

        state.history.append(
            SessionRecord(
                id: session.id,
                startedAt: session.startedAt,
                scheduledEndAt: session.scheduledEndAt,
                actualEndAt: actualEndAt,
                endReason: reason,
                counters: session.counters
            )
        )
    }

    private static func makePublicState(
        from state: PersistedState,
        now: Date
    ) -> PublicSessionState {
        guard let session = state.activeSession else {
            return PublicSessionState(
                generatedAt: now,
                profileName: state.settings.activeProfileName,
                phase: .inactive,
                isSessionActive: false,
                shouldBlockRestrictedServices: false,
                sessionID: nil,
                startedAt: nil,
                scheduledEndAt: nil,
                sessionRemainingSeconds: 0,
                focusAvailableAt: nil,
                focusRemainingSeconds: 0,
                breakEndsAt: nil,
                breakRemainingSeconds: 0,
                canStartBreak: false,
                canExtendBreak: false,
                focusDurationSeconds: state.settings.focusDuration,
                breakDurationSeconds: state.settings.breakDuration,
                usageObservationEnabled:
                    state.settings.usageObservationEnabled,
                historyEnabled: state.settings.historyEnabled,
                blockedDomains: state.settings.blockedDomains
            )
        }

        let sessionRemaining = max(
            0,
            session.scheduledEndAt.timeIntervalSince(now)
        )

        if let activeBreak = session.activeBreak {
            let breakRemaining = max(0, activeBreak.endsAt.timeIntervalSince(now))
            return PublicSessionState(
                generatedAt: now,
                profileName: state.settings.activeProfileName,
                phase: .onBreak,
                isSessionActive: true,
                shouldBlockRestrictedServices: false,
                sessionID: session.id,
                startedAt: session.startedAt,
                scheduledEndAt: session.scheduledEndAt,
                sessionRemainingSeconds: sessionRemaining,
                focusAvailableAt: nil,
                focusRemainingSeconds: 0,
                breakEndsAt: activeBreak.endsAt,
                breakRemainingSeconds: breakRemaining,
                canStartBreak: false,
                canExtendBreak: breakRemaining > 0
                    && breakRemaining
                        <= state.settings.extensionEligibilityWindow
                    && activeBreak.endsAt < session.scheduledEndAt,
                focusDurationSeconds: state.settings.focusDuration,
                breakDurationSeconds: state.settings.breakDuration,
                usageObservationEnabled:
                    state.settings.usageObservationEnabled,
                historyEnabled: state.settings.historyEnabled,
                blockedDomains: state.settings.blockedDomains
            )
        }

        if state.settings.breakDuration == 0 {
            return PublicSessionState(
                generatedAt: now,
                profileName: state.settings.activeProfileName,
                phase: .focusing,
                isSessionActive: true,
                shouldBlockRestrictedServices: true,
                sessionID: session.id,
                startedAt: session.startedAt,
                scheduledEndAt: session.scheduledEndAt,
                sessionRemainingSeconds: sessionRemaining,
                focusAvailableAt: nil,
                focusRemainingSeconds: sessionRemaining,
                breakEndsAt: nil,
                breakRemainingSeconds: 0,
                canStartBreak: false,
                canExtendBreak: false,
                focusDurationSeconds: state.settings.focusDuration,
                breakDurationSeconds: 0,
                usageObservationEnabled:
                    state.settings.usageObservationEnabled,
                historyEnabled: state.settings.historyEnabled,
                blockedDomains: state.settings.blockedDomains
            )
        }

        let focusAvailableAt = session.focusCycleStartedAt.addingTimeInterval(
            state.settings.focusDuration
        )
        let focusRemaining = session.currentFocusIntervalCounted
            ? 0
            : max(0, focusAvailableAt.timeIntervalSince(now))
        let phase: SessionPhase = session.currentFocusIntervalCounted
            ? .breakAvailable
            : .focusing

        return PublicSessionState(
            generatedAt: now,
            profileName: state.settings.activeProfileName,
            phase: phase,
            isSessionActive: true,
            shouldBlockRestrictedServices: true,
            sessionID: session.id,
            startedAt: session.startedAt,
            scheduledEndAt: session.scheduledEndAt,
            sessionRemainingSeconds: sessionRemaining,
            focusAvailableAt: focusAvailableAt,
            focusRemainingSeconds: focusRemaining,
            breakEndsAt: nil,
            breakRemainingSeconds: 0,
            canStartBreak: session.currentFocusIntervalCounted,
            canExtendBreak: false,
            focusDurationSeconds: state.settings.focusDuration,
            breakDurationSeconds: state.settings.breakDuration,
            usageObservationEnabled: state.settings.usageObservationEnabled,
            historyEnabled: state.settings.historyEnabled,
            blockedDomains: state.settings.blockedDomains
        )
    }

    private static func aggregateServiceKey(_ rawValue: String) throws -> String {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !trimmed.isEmpty,
              trimmed.count <= 255,
              !trimmed.contains("/"),
              !trimmed.contains("?"),
              !trimmed.contains("#")
        else {
            throw SessionServiceError.invalidService
        }
        return trimmed
    }

    private static func updateCounters(
        for sessionID: UUID,
        in state: inout PersistedState,
        _ update: (inout SessionCounters) -> Void
    ) {
        if var activeSession = state.activeSession,
           activeSession.id == sessionID {
            update(&activeSession.counters)
            state.activeSession = activeSession
            return
        }

        guard let historyIndex = state.history.firstIndex(
            where: { $0.id == sessionID }
        ) else {
            return
        }
        var record = state.history[historyIndex]
        update(&record.counters)
        state.history[historyIndex] = record
    }

    private static let knownDistractionDomains: Set<String> = [
        "youtube.com",
        "twitch.tv",
        "netflix.com",
        "facebook.com",
        "tiktok.com",
        "steamcommunity.com",
        "pinterest.com",
        "ycombinator.com"
    ]
}
