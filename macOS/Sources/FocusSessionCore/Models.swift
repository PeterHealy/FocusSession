import Foundation

public enum SessionPreset: String, Codable, CaseIterable, Sendable {
    case oneHour
    case twoHours
    case fourHours

    public var duration: TimeInterval {
        switch self {
        case .oneHour:
            return 60 * 60
        case .twoHours:
            return 2 * 60 * 60
        case .fourHours:
            return 4 * 60 * 60
        }
    }

    public var title: String {
        switch self {
        case .oneHour:
            return "1 hour"
        case .twoHours:
            return "2 hours"
        case .fourHours:
            return "4 hours"
        }
    }
}

public enum CustomSessionStartCountdown {
    public static let ticks = [3, 2, 1]
}

public enum BreakPatternPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case strict
    case standard
    case deepWork
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .strict:
            return "Strict (55/5)"
        case .standard:
            return "Standard (50/10)"
        case .deepWork:
            return "Long focus (90/10)"
        case .custom:
            return "Custom"
        }
    }

    public var durations: (focus: TimeInterval, breakTime: TimeInterval)? {
        switch self {
        case .strict:
            return (55 * 60, 5 * 60)
        case .standard:
            return (50 * 60, 10 * 60)
        case .deepWork:
            return (90 * 60, 10 * 60)
        case .custom:
            return nil
        }
    }

    public static func matching(
        focusDuration: TimeInterval,
        breakDuration: TimeInterval
    ) -> BreakPatternPreset {
        allCases.first { preset in
            guard let durations = preset.durations else {
                return false
            }
            return durations.focus == focusDuration
                && durations.breakTime == breakDuration
        } ?? .custom
    }
}

public struct FocusProfile: Codable, Equatable, Identifiable, Sendable {
    public static let deepWorkID = "deep-work"
    public static let deepWorkBundleIdentifiers = [
        "com.burbn.instagram",
        "com.facebook.Facebook",
        "com.facebook.Messenger",
        "net.whatsapp.WhatsApp"
    ]
    public static let deepWorkDomains = [
        "facebook.com",
        "instagram.com",
        "messenger.com",
        "whatsapp.com"
    ]

    public var id: String
    public var name: String
    public var focusDuration: TimeInterval
    public var breakDuration: TimeInterval
    public var blockedBundleIdentifiers: [String]
    public var blockedDomains: [String]

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        focusDuration: TimeInterval,
        breakDuration: TimeInterval,
        blockedBundleIdentifiers: [String],
        blockedDomains: [String]
    ) {
        self.id = id
        self.name = name
        self.focusDuration = focusDuration
        self.breakDuration = breakDuration
        self.blockedBundleIdentifiers = blockedBundleIdentifiers
        self.blockedDomains = blockedDomains
        normalize()
    }

    public static func deepWork(
        focusDuration: TimeInterval = 55 * 60,
        breakDuration: TimeInterval = 5 * 60,
        blockedBundleIdentifiers: [String] = deepWorkBundleIdentifiers,
        blockedDomains: [String] = deepWorkDomains
    ) -> FocusProfile {
        FocusProfile(
            id: deepWorkID,
            name: "Deep Work",
            focusDuration: focusDuration,
            breakDuration: breakDuration,
            blockedBundleIdentifiers: blockedBundleIdentifiers,
            blockedDomains: blockedDomains
        )
    }

    public mutating func normalize() {
        id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty || id.count > 100 {
            id = UUID().uuidString.lowercased()
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            name = "Untitled Profile"
        }
        name = String(name.prefix(80))
        focusDuration = max(60, focusDuration)
        breakDuration =
            breakDuration == 0 ? 0 : max(30, breakDuration)
        blockedBundleIdentifiers = Array(
            Set(
                blockedBundleIdentifiers
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0.count <= 255 }
            )
        ).sorted()
        blockedBundleIdentifiers = Array(blockedBundleIdentifiers.prefix(2_000))
        blockedDomains = Array(
            Set(blockedDomains.compactMap(DomainSanitizer.hostname(from:)))
        ).sorted()
        blockedDomains = Array(blockedDomains.prefix(2_000))
    }
}

public enum SessionPhase: String, Codable, Sendable {
    case inactive
    case focusing
    case breakAvailable
    case onBreak
}

public enum SessionEndReason: String, Codable, Sendable {
    case completed
    case endedEarly
}

public struct SessionSettings: Codable, Equatable, Sendable {
    public var focusDuration: TimeInterval
    public var breakDuration: TimeInterval
    public var breakExtensionDuration: TimeInterval
    public var extensionEligibilityWindow: TimeInterval
    public var blockedBundleIdentifiers: [String]
    public var blockedDomains: [String]
    public var historyEnabled: Bool
    public var usageObservationEnabled: Bool
    public var distractionSuggestionsEnabled: Bool
    public var notificationsEnabled: Bool
    public var sessionCompletionNotificationEnabled: Bool
    public var launchAtLoginEnabled: Bool
    public var workFocusAutomationEnabled: Bool
    public var workFocusStartShortcutName: String
    public var workFocusEndShortcutName: String
    public var profiles: [FocusProfile]?
    public var selectedProfileID: String?

    public init(
        focusDuration: TimeInterval = 55 * 60,
        breakDuration: TimeInterval = 5 * 60,
        breakExtensionDuration: TimeInterval = 30,
        extensionEligibilityWindow: TimeInterval = 10,
        blockedBundleIdentifiers: [String] =
            FocusProfile.deepWorkBundleIdentifiers,
        blockedDomains: [String] = FocusProfile.deepWorkDomains,
        historyEnabled: Bool = true,
        usageObservationEnabled: Bool = false,
        distractionSuggestionsEnabled: Bool = false,
        notificationsEnabled: Bool = false,
        sessionCompletionNotificationEnabled: Bool = false,
        launchAtLoginEnabled: Bool = false,
        workFocusAutomationEnabled: Bool = false,
        workFocusStartShortcutName: String = "Start Work Focus",
        workFocusEndShortcutName: String = "Stop Work Focus",
        profiles: [FocusProfile]? = nil,
        selectedProfileID: String? = nil
    ) {
        self.focusDuration = focusDuration
        self.breakDuration = breakDuration
        self.breakExtensionDuration = breakExtensionDuration
        self.extensionEligibilityWindow = extensionEligibilityWindow
        self.blockedBundleIdentifiers = blockedBundleIdentifiers
        self.blockedDomains = blockedDomains
        self.historyEnabled = historyEnabled
        self.usageObservationEnabled = usageObservationEnabled
        self.distractionSuggestionsEnabled = distractionSuggestionsEnabled
        self.notificationsEnabled = notificationsEnabled
        self.sessionCompletionNotificationEnabled = sessionCompletionNotificationEnabled
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.workFocusAutomationEnabled = workFocusAutomationEnabled
        self.workFocusStartShortcutName = workFocusStartShortcutName
        self.workFocusEndShortcutName = workFocusEndShortcutName
        self.profiles = profiles
        self.selectedProfileID = selectedProfileID
        if let profiles,
           let selectedProfileID,
           let selected = profiles.first(where: {
               $0.id == selectedProfileID
           }) {
            self.focusDuration = selected.focusDuration
            self.breakDuration = selected.breakDuration
            self.blockedBundleIdentifiers =
                selected.blockedBundleIdentifiers
            self.blockedDomains = selected.blockedDomains
        }
        normalize()
    }

    public mutating func normalize() {
        focusDuration = max(60, focusDuration)
        breakDuration =
            breakDuration == 0 ? 0 : max(30, breakDuration)
        breakExtensionDuration = max(5, breakExtensionDuration)
        extensionEligibilityWindow = max(1, extensionEligibilityWindow)

        blockedBundleIdentifiers = Array(
            Set(
                blockedBundleIdentifiers
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0.count <= 255 }
            )
        ).sorted()
        blockedBundleIdentifiers = Array(blockedBundleIdentifiers.prefix(2_000))

        blockedDomains = Array(
            Set(blockedDomains.compactMap(DomainSanitizer.hostname(from:)))
        ).sorted()
        blockedDomains = Array(blockedDomains.prefix(2_000))

        workFocusStartShortcutName =
            workFocusStartShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        workFocusEndShortcutName =
            workFocusEndShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)

        if profiles?.isEmpty != false {
            profiles = [
                FocusProfile.deepWork(
                    focusDuration: focusDuration,
                    breakDuration: breakDuration,
                    blockedBundleIdentifiers: blockedBundleIdentifiers,
                    blockedDomains: blockedDomains
                )
            ]
            selectedProfileID = FocusProfile.deepWorkID
        } else {
            profiles = Array(
                (profiles ?? []).map { profile in
                    var normalized = profile
                    normalized.normalize()
                    return normalized
                }
                .prefix(50)
            )
            let profileIDs = Set((profiles ?? []).map(\.id))
            if let selectedProfileID,
               profileIDs.contains(selectedProfileID) {
                self.selectedProfileID = selectedProfileID
            } else {
                selectedProfileID = profiles?.first?.id
            }
        }

        if let selectedProfileID,
           let activeIndex = profiles?.firstIndex(where: {
               $0.id == selectedProfileID
           }) {
            var updated = profiles?[activeIndex]
            updated?.focusDuration = focusDuration
            updated?.breakDuration = breakDuration
            updated?.blockedBundleIdentifiers =
                blockedBundleIdentifiers
            updated?.blockedDomains = blockedDomains
            updated?.normalize()
            if let updated {
                profiles?[activeIndex] = updated
                focusDuration = updated.focusDuration
                breakDuration = updated.breakDuration
                blockedBundleIdentifiers =
                    updated.blockedBundleIdentifiers
                blockedDomains = updated.blockedDomains
            }
        }
    }

    public var resolvedProfiles: [FocusProfile] {
        guard let profiles, !profiles.isEmpty else {
            return [
                FocusProfile.deepWork(
                    focusDuration: focusDuration,
                    breakDuration: breakDuration,
                    blockedBundleIdentifiers: blockedBundleIdentifiers,
                    blockedDomains: blockedDomains
                )
            ]
        }
        return profiles
    }

    public var activeProfile: FocusProfile? {
        let available = resolvedProfiles
        if let selectedProfileID,
           let selected = available.first(where: {
               $0.id == selectedProfileID
           }) {
            return selected
        }
        return available.first
    }

    public var activeProfileName: String {
        activeProfile?.name ?? "Deep Work"
    }

    public mutating func migrateLegacyProfileIfNeeded() {
        guard profiles?.isEmpty != false else {
            normalize()
            return
        }
        let migratedDomains = Array(
            Set(blockedDomains).union(FocusProfile.deepWorkDomains)
        )
        profiles = [
            FocusProfile.deepWork(
                focusDuration: focusDuration,
                breakDuration: breakDuration,
                blockedBundleIdentifiers: blockedBundleIdentifiers,
                blockedDomains: migratedDomains
            )
        ]
        selectedProfileID = FocusProfile.deepWorkID
        blockedDomains = migratedDomains
        normalize()
    }

    public func blocks(bundleIdentifier: String) -> Bool {
        blockedBundleIdentifiers.contains(bundleIdentifier)
    }

    public func blocks(domain rawDomain: String) -> Bool {
        guard let domain = DomainSanitizer.hostname(from: rawDomain) else {
            return false
        }

        return blockedDomains.contains { blocked in
            domain == blocked || domain.hasSuffix("." + blocked)
        }
    }
}

public struct BreakWindow: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var endsAt: Date
    public var extensionCount: Int

    public init(startedAt: Date, endsAt: Date, extensionCount: Int = 0) {
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.extensionCount = extensionCount
    }
}

public struct SessionCounters: Codable, Equatable, Sendable {
    public var completedFocusIntervals: Int
    public var breaksTaken: Int
    public var breakSecondsUsed: TimeInterval
    public var breakExtensions: Int
    public var breakOvertimeSeconds: TimeInterval
    public var blockedAttempts: [String: Int]
    public var restrictedServiceSeconds: [String: TimeInterval]

    public init(
        completedFocusIntervals: Int = 0,
        breaksTaken: Int = 0,
        breakSecondsUsed: TimeInterval = 0,
        breakExtensions: Int = 0,
        breakOvertimeSeconds: TimeInterval = 0,
        blockedAttempts: [String: Int] = [:],
        restrictedServiceSeconds: [String: TimeInterval] = [:]
    ) {
        self.completedFocusIntervals = completedFocusIntervals
        self.breaksTaken = breaksTaken
        self.breakSecondsUsed = breakSecondsUsed
        self.breakExtensions = breakExtensions
        self.breakOvertimeSeconds = breakOvertimeSeconds
        self.blockedAttempts = blockedAttempts
        self.restrictedServiceSeconds = restrictedServiceSeconds
    }
}

public struct ActiveSession: Codable, Equatable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var scheduledEndAt: Date
    public var focusCycleStartedAt: Date
    public var currentFocusIntervalCounted: Bool
    public var activeBreak: BreakWindow?
    public var counters: SessionCounters
    public var workFocusManaged: Bool

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        scheduledEndAt: Date,
        focusCycleStartedAt: Date,
        currentFocusIntervalCounted: Bool = false,
        activeBreak: BreakWindow? = nil,
        counters: SessionCounters = SessionCounters(),
        workFocusManaged: Bool = false
    ) {
        self.id = id
        self.startedAt = startedAt
        self.scheduledEndAt = scheduledEndAt
        self.focusCycleStartedAt = focusCycleStartedAt
        self.currentFocusIntervalCounted = currentFocusIntervalCounted
        self.activeBreak = activeBreak
        self.counters = counters
        self.workFocusManaged = workFocusManaged
    }
}

public struct SessionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var scheduledEndAt: Date
    public var actualEndAt: Date
    public var endReason: SessionEndReason
    public var counters: SessionCounters

    public init(
        id: UUID,
        startedAt: Date,
        scheduledEndAt: Date,
        actualEndAt: Date,
        endReason: SessionEndReason,
        counters: SessionCounters
    ) {
        self.id = id
        self.startedAt = startedAt
        self.scheduledEndAt = scheduledEndAt
        self.actualEndAt = actualEndAt
        self.endReason = endReason
        self.counters = counters
    }

    public var elapsedSeconds: TimeInterval {
        max(0, actualEndAt.timeIntervalSince(startedAt))
    }
}

public struct UsageRollup: Codable, Equatable, Sendable {
    public var activeSeconds: TimeInterval
    public var visitCount: Int
    public var lastSeenAt: Date?

    public init(
        activeSeconds: TimeInterval = 0,
        visitCount: Int = 0,
        lastSeenAt: Date? = nil
    ) {
        self.activeSeconds = activeSeconds
        self.visitCount = visitCount
        self.lastSeenAt = lastSeenAt
    }

    public mutating func merge(
        activeSeconds: TimeInterval,
        visitCount: Int,
        lastSeenAt: Date?
    ) {
        self.activeSeconds += max(0, activeSeconds)
        self.visitCount += max(0, visitCount)
        if let lastSeenAt, self.lastSeenAt == nil || lastSeenAt > self.lastSeenAt! {
            self.lastSeenAt = lastSeenAt
        }
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var applications: [String: UsageRollup]
    public var domains: [String: UsageRollup]

    public init(
        applications: [String: UsageRollup] = [:],
        domains: [String: UsageRollup] = [:]
    ) {
        self.applications = applications
        self.domains = domains
    }
}

public struct SuggestionState: Codable, Equatable, Sendable {
    public var lastReviewAt: Date?
    public var dismissedDomains: [String]

    public init(lastReviewAt: Date? = nil, dismissedDomains: [String] = []) {
        self.lastReviewAt = lastReviewAt
        self.dismissedDomains = dismissedDomains
    }
}

public struct PersistedState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var settings: SessionSettings
    public var activeSession: ActiveSession?
    public var history: [SessionRecord]
    public var usage: UsageSnapshot
    public var suggestionState: SuggestionState
    public var workFocusCleanupPending: Bool

    public init(
        schemaVersion: Int = 1,
        settings: SessionSettings = SessionSettings(),
        activeSession: ActiveSession? = nil,
        history: [SessionRecord] = [],
        usage: UsageSnapshot = UsageSnapshot(),
        suggestionState: SuggestionState = SuggestionState(),
        workFocusCleanupPending: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.settings = settings
        self.activeSession = activeSession
        self.history = history
        self.usage = usage
        self.suggestionState = suggestionState
        self.workFocusCleanupPending = workFocusCleanupPending
    }
}

public struct PublicSessionState: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var profileName: String
    public var phase: SessionPhase
    public var isSessionActive: Bool
    public var shouldBlockRestrictedServices: Bool
    public var sessionID: UUID?
    public var startedAt: Date?
    public var scheduledEndAt: Date?
    public var sessionRemainingSeconds: TimeInterval
    public var focusAvailableAt: Date?
    public var focusRemainingSeconds: TimeInterval
    public var breakEndsAt: Date?
    public var breakRemainingSeconds: TimeInterval
    public var canStartBreak: Bool
    public var canExtendBreak: Bool
    public var focusDurationSeconds: TimeInterval
    public var breakDurationSeconds: TimeInterval
    public var usageObservationEnabled: Bool
    public var historyEnabled: Bool
    public var blockedDomains: [String]

    public init(
        generatedAt: Date,
        profileName: String = "Deep Work",
        phase: SessionPhase,
        isSessionActive: Bool,
        shouldBlockRestrictedServices: Bool,
        sessionID: UUID?,
        startedAt: Date?,
        scheduledEndAt: Date?,
        sessionRemainingSeconds: TimeInterval,
        focusAvailableAt: Date?,
        focusRemainingSeconds: TimeInterval,
        breakEndsAt: Date?,
        breakRemainingSeconds: TimeInterval,
        canStartBreak: Bool,
        canExtendBreak: Bool,
        focusDurationSeconds: TimeInterval,
        breakDurationSeconds: TimeInterval,
        usageObservationEnabled: Bool,
        historyEnabled: Bool,
        blockedDomains: [String]
    ) {
        self.generatedAt = generatedAt
        self.profileName = profileName
        self.phase = phase
        self.isSessionActive = isSessionActive
        self.shouldBlockRestrictedServices = shouldBlockRestrictedServices
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.scheduledEndAt = scheduledEndAt
        self.sessionRemainingSeconds = sessionRemainingSeconds
        self.focusAvailableAt = focusAvailableAt
        self.focusRemainingSeconds = focusRemainingSeconds
        self.breakEndsAt = breakEndsAt
        self.breakRemainingSeconds = breakRemainingSeconds
        self.canStartBreak = canStartBreak
        self.canExtendBreak = canExtendBreak
        self.focusDurationSeconds = focusDurationSeconds
        self.breakDurationSeconds = breakDurationSeconds
        self.usageObservationEnabled = usageObservationEnabled
        self.historyEnabled = historyEnabled
        self.blockedDomains = blockedDomains
    }
}

public struct HistorySummaryEntry: Codable, Equatable, Sendable {
    public var domain: String
    public var visitCount: Int
    public var lastVisitAt: Date?

    public init(domain: String, visitCount: Int, lastVisitAt: Date? = nil) {
        self.domain = domain
        self.visitCount = visitCount
        self.lastVisitAt = lastVisitAt
    }
}

public struct DashboardSummary: Equatable, Sendable {
    public var sessionCount: Int
    public var totalFocusedSeconds: TimeInterval
    public var completedFocusIntervals: Int
    public var breaksTaken: Int
    public var breakSecondsUsed: TimeInterval
    public var breakExtensions: Int
    public var breakOvertimeSeconds: TimeInterval
    public var earlyEndings: Int
    public var blockedAttempts: [String: Int]
    public var restrictedServiceSeconds: [String: TimeInterval]

    public init(history: [SessionRecord]) {
        sessionCount = history.count
        totalFocusedSeconds = history.reduce(0) {
            $0 + max(0, $1.elapsedSeconds - $1.counters.breakSecondsUsed)
        }
        completedFocusIntervals = history.reduce(0) {
            $0 + $1.counters.completedFocusIntervals
        }
        breaksTaken = history.reduce(0) { $0 + $1.counters.breaksTaken }
        breakSecondsUsed = history.reduce(0) {
            $0 + $1.counters.breakSecondsUsed
        }
        breakExtensions = history.reduce(0) { $0 + $1.counters.breakExtensions }
        breakOvertimeSeconds = history.reduce(0) {
            $0 + $1.counters.breakOvertimeSeconds
        }
        earlyEndings = history.filter { $0.endReason == .endedEarly }.count

        var attempts: [String: Int] = [:]
        var serviceSeconds: [String: TimeInterval] = [:]
        for record in history {
            for (service, count) in record.counters.blockedAttempts {
                attempts[service, default: 0] += count
            }
            for (service, seconds) in record.counters.restrictedServiceSeconds {
                serviceSeconds[service, default: 0] += seconds
            }
        }
        blockedAttempts = attempts
        restrictedServiceSeconds = serviceSeconds
    }
}
