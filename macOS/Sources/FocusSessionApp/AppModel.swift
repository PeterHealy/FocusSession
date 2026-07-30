import AppKit
import Combine
import FocusSessionCore
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var publicState: PublicSessionState
    @Published private(set) var settings: SessionSettings
    @Published private(set) var history: [SessionRecord] = []
    @Published private(set) var usage = UsageSnapshot()
    @Published private(set) var summary = DashboardSummary(history: [])
    @Published private(set) var suggestedDomains: [String] = []
    @Published private(set) var startCountdownRemaining: Int?
    @Published private(set) var pendingSessionDuration: TimeInterval?
    @Published var lastErrorMessage: String?

    let service: SessionService

    private let shortcutRunner = ShortcutRunner()
    private let launchAtLoginController = LaunchAtLoginController()
    private let notifier = NotificationCoordinator()
    private let hud = BlockingHUDController()
    private var monitor: NativeAppMonitor?
    private var stateTimer: Timer?
    private var tickCount = 0
    private var previousPhase: SessionPhase = .inactive
    private var currentBreakStartedAt: Date?
    private var warnedBreakStartedAt: Date?
    private var lastWorkFocusCleanupAttempt: Date?
    private var startCountdownTask: Task<Void, Never>?

    init() {
        do {
            service = try SessionService()
        } catch {
            fatalError(
                "Focus Session could not open its local state: "
                    + error.localizedDescription
            )
        }

        let initialSettings = SessionSettings()
        settings = initialSettings
        publicState = Self.inactiveState(settings: initialSettings)

        guard !CommandLine.arguments.contains(
            "--unregister-login-item"
        ) else {
            return
        }

        migrateLegacyProfilesIfNeeded()

        let monitor = NativeAppMonitor(service: service, hud: hud)
        self.monitor = monitor
        monitor.start()
        refresh()
        monitor.enforceCurrentRestrictions(showNotice: false)

        stateTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    var menuBarTitle: String {
        guard publicState.isSessionActive else {
            return "Focus"
        }
        return DurationText.compact(
            publicState.sessionRemainingSeconds
        )
    }

    var menuBarAccessibilityLabel: String {
        guard publicState.isSessionActive else {
            return "Focus Session is inactive"
        }
        return "Focus Session active, "
            + DurationText.readable(
                publicState.sessionRemainingSeconds
            )
            + " remaining"
    }

    func startConfiguredSession(
        sessionDuration: TimeInterval,
        focusDuration: TimeInterval,
        breakDuration: TimeInterval
    ) {
        guard !publicState.isSessionActive else {
            present(SessionServiceError.sessionAlreadyActive)
            return
        }
        guard sessionDuration >= 60,
              focusDuration >= 60,
              breakDuration == 0 || breakDuration >= 30
        else {
            lastErrorMessage = "Choose valid session and break timing."
            return
        }

        cancelStartCountdown()
        pendingSessionDuration = sessionDuration
        startCountdownRemaining = 3
        startCountdownTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            for remaining in CustomSessionStartCountdown.ticks {
                guard !Task.isCancelled else {
                    return
                }
                self.startCountdownRemaining = remaining
                do {
                    try await Task.sleep(
                        nanoseconds: 1_000_000_000
                    )
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else {
                return
            }
            self.startCountdownRemaining = nil
            self.pendingSessionDuration = nil
            self.startCountdownTask = nil
            self.applyTimingAndStart(
                sessionDuration: sessionDuration,
                focusDuration: focusDuration,
                breakDuration: breakDuration
            )
        }
    }

    func cancelStartCountdown() {
        startCountdownTask?.cancel()
        startCountdownTask = nil
        startCountdownRemaining = nil
        pendingSessionDuration = nil
    }

    private func applyTimingAndStart(
        sessionDuration: TimeInterval,
        focusDuration: TimeInterval,
        breakDuration: TimeInterval
    ) {
        do {
            var updatedSettings = settings
            updatedSettings.focusDuration = focusDuration
            updatedSettings.breakDuration = breakDuration
            try service.updateSettings(updatedSettings)
            refresh()
            startImmediately(
                endingAt: Date().addingTimeInterval(sessionDuration)
            )
        } catch {
            present(error)
        }
    }

    private func startImmediately(endingAt: Date) {
        monitor?.flushCurrentActivity()
        let manageWorkFocus = startWorkFocusIfConfigured()
        do {
            _ = try service.startSession(
                endingAt: endingAt,
                workFocusManaged: manageWorkFocus
            )
            refresh()
            monitor?.beginNewObservationSegment()
            monitor?.enforceCurrentRestrictions(showNotice: false)
        } catch {
            if manageWorkFocus {
                _ = shortcutRunner.run(
                    named: settings.workFocusEndShortcutName
                )
            }
            present(error)
        }
    }

    func startBreak() {
        do {
            monitor?.flushCurrentActivity()
            _ = try service.startBreak()
            warnedBreakStartedAt = nil
            refresh()
            monitor?.beginNewObservationSegment()
        } catch {
            present(error)
        }
    }

    func extendBreak() {
        do {
            _ = try service.extendBreak()
            refresh()
        } catch {
            present(error)
        }
    }

    func endEarly() {
        do {
            monitor?.flushCurrentActivity()
            _ = try service.endSessionEarly()
            refresh()
            monitor?.beginNewObservationSegment()
        } catch {
            present(error)
        }
    }

    func saveSettings(_ updatedSettings: SessionSettings) {
        do {
            monitor?.flushCurrentActivity()
            var settingsToSave = updatedSettings
            let shouldRequestNotifications =
                !settings.notificationsEnabled
                    && updatedSettings.notificationsEnabled
            if settings.launchAtLoginEnabled
                != updatedSettings.launchAtLoginEnabled {
                switch launchAtLoginController.setEnabled(
                    updatedSettings.launchAtLoginEnabled
                ) {
                case .success:
                    break
                case let .failure(error):
                    settingsToSave.launchAtLoginEnabled =
                        settings.launchAtLoginEnabled
                    lastErrorMessage =
                        "Launch at Login could not be changed: "
                            + error.localizedDescription
                }
            }

            try service.updateSettings(settingsToSave)
            if shouldRequestNotifications {
                notifier.requestAuthorization()
            }
            refresh()
            monitor?.beginNewObservationSegment()
            monitor?.enforceCurrentRestrictions(showNotice: false)
        } catch {
            present(error)
        }
    }

    func deleteHistoryRecord(id: UUID) {
        do {
            try service.deleteHistoryRecord(id: id)
            refresh()
        } catch {
            present(error)
        }
    }

    func clearAllHistoryAndUsage() {
        do {
            try service.clearAllHistoryAndUsage()
            refresh()
        } catch {
            present(error)
        }
    }

    func clearUsageRollups() {
        do {
            try service.clearUsageRollups()
            refresh()
        } catch {
            present(error)
        }
    }

    func acceptSuggestion(_ domain: String) {
        do {
            try service.acceptSuggestedDomain(domain)
            refresh()
        } catch {
            present(error)
        }
    }

    func dismissSuggestion(_ domain: String) {
        do {
            try service.dismissSuggestedDomain(domain)
            refresh()
        } catch {
            present(error)
        }
    }

    func finishSuggestionReview() {
        do {
            try service.markSuggestionsReviewed()
            refresh()
        } catch {
            present(error)
        }
    }

    func refresh(includeSuggestions: Bool = true) {
        do {
            let now = Date()
            flushObservationAtElapsedBoundary(now: now)
            let current = try service.currentState(now: now)
            let snapshot = current.snapshot
            let newPublicState = current.publicState

            settings = snapshot.settings
            history = snapshot.history.sorted { $0.startedAt > $1.startedAt }
            usage = snapshot.usage
            summary = DashboardSummary(history: snapshot.history)
            currentBreakStartedAt =
                snapshot.activeSession?.activeBreak?.startedAt
            if includeSuggestions {
                suggestedDomains =
                    (try? service.suggestedDomains(now: now)) ?? []
            }

            handlePhaseTransition(
                from: previousPhase,
                to: newPublicState.phase
            )
            previousPhase = newPublicState.phase
            publicState = newPublicState

            if snapshot.workFocusCleanupPending {
                finishManagedWorkFocus()
            }
        } catch {
            present(error)
        }
    }

    private func tick() {
        tickCount += 1
        refresh(includeSuggestions: tickCount.isMultiple(of: 60))
        monitor?.updateBreakShotClock(
            state: publicState,
            settings: settings
        )
        if publicState.shouldBlockRestrictedServices {
            monitor?.enforceFrontmostRestriction(showNotice: false)
        }

        if tickCount.isMultiple(of: 15) {
            monitor?.flushCurrentActivity()
        }

        guard publicState.phase == .onBreak,
              publicState.breakRemainingSeconds > 0,
              publicState.breakRemainingSeconds <= 60,
              let currentBreakStartedAt,
              warnedBreakStartedAt != currentBreakStartedAt
        else {
            return
        }

        warnedBreakStartedAt = currentBreakStartedAt
        if settings.notificationsEnabled {
            notifier.send(
                title: "One minute left",
                body: "Your free-use break is nearly finished."
            )
        }
    }

    private func handlePhaseTransition(
        from previous: SessionPhase,
        to current: SessionPhase
    ) {
        if current == .breakAvailable, previous != .breakAvailable,
           settings.notificationsEnabled {
            notifier.send(
                title: "Break available",
                body: "Your "
                    + DurationText.readable(settings.breakDuration)
                    + " free-use break is ready when you are."
            )
        }

        if previous == .onBreak,
           current == .focusing || current == .breakAvailable {
            monitor?.enforceCurrentRestrictions(showNotice: true)
        }

        if previous != .inactive,
           current == .inactive,
           settings.notificationsEnabled,
           settings.sessionCompletionNotificationEnabled {
            notifier.send(
                title: "Focus session complete",
                body: "The scheduled session has ended."
            )
        }
    }

    private func flushObservationAtElapsedBoundary(now: Date) {
        if publicState.phase == .onBreak,
           let breakEndsAt = publicState.breakEndsAt,
           now >= breakEndsAt {
            monitor?.flushCurrentActivity(now: breakEndsAt)
            return
        }

        if publicState.isSessionActive,
           let scheduledEndAt = publicState.scheduledEndAt,
           now >= scheduledEndAt {
            monitor?.flushCurrentActivity(now: scheduledEndAt)
        }
    }

    private func startWorkFocusIfConfigured() -> Bool {
        guard settings.workFocusAutomationEnabled,
              !settings.workFocusStartShortcutName.isEmpty
        else {
            return false
        }

        switch shortcutRunner.run(named: settings.workFocusStartShortcutName) {
        case .success:
            return true
        case let .failure(error):
            lastErrorMessage =
                "The session will start without Work Focus: "
                    + error.localizedDescription
            return false
        }
    }

    private func finishManagedWorkFocus() {
        let now = Date()
        if let lastWorkFocusCleanupAttempt,
           now.timeIntervalSince(lastWorkFocusCleanupAttempt) < 60 {
            return
        }
        lastWorkFocusCleanupAttempt = now

        guard !settings.workFocusEndShortcutName.isEmpty else {
            lastErrorMessage =
                "Work Focus was started, but no ending Shortcut is configured."
            return
        }

        switch shortcutRunner.run(named: settings.workFocusEndShortcutName) {
        case .success:
            do {
                try service.acknowledgeWorkFocusCleanup()
                lastWorkFocusCleanupAttempt = nil
            } catch {
                present(error)
            }
        case let .failure(error):
            lastErrorMessage =
                "The Work Focus ending Shortcut failed: "
                    + error.localizedDescription
        }
    }

    private func present(_ error: Error) {
        lastErrorMessage = error.localizedDescription
    }

    private func migrateLegacyProfilesIfNeeded() {
        guard let current = try? service.currentState() else {
            return
        }
        var migrated = current.snapshot.settings
        migrated.migrateLegacyProfileIfNeeded()
        guard migrated != current.snapshot.settings else {
            return
        }
        try? service.updateSettings(migrated)
    }

    private static func inactiveState(
        settings: SessionSettings
    ) -> PublicSessionState {
        PublicSessionState(
            generatedAt: Date(),
            profileName: settings.activeProfileName,
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
            focusDurationSeconds: settings.focusDuration,
            breakDurationSeconds: settings.breakDuration,
            usageObservationEnabled: settings.usageObservationEnabled,
            historyEnabled: settings.historyEnabled,
            blockedDomains: settings.blockedDomains
        )
    }
}

enum DurationText {
    static func compact(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    static func readable(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600
            ? [.hour, .minute]
            : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: max(0, seconds)) ?? "0 min"
    }
}
