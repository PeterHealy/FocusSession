import AppKit
import FocusSessionCore
import Foundation

@MainActor
final class NativeAppMonitor {
    private struct ObservationContext {
        var bundleIdentifier: String?
        var sessionID: UUID?
        var wasOnBreak: Bool
        var historyEnabledAtObservation: Bool
    }

    private let service: SessionService
    private let hud: BlockingHUDController
    private var activationObserver: NSObjectProtocol?
    private var sleepObservers: [NSObjectProtocol] = []
    private var currentContext = ObservationContext(
        bundleIdentifier: nil,
        sessionID: nil,
        wasOnBreak: false,
        historyEnabledAtObservation: false
    )
    private var currentActivityStartedAt = Date()
    private var isObservationSuspended = false

    init(service: SessionService, hud: BlockingHUDController) {
        self.service = service
        self.hud = hud
    }

    func start() {
        guard activationObserver == nil else {
            return
        }

        let workspace = NSWorkspace.shared
        currentActivityStartedAt = Date()
        currentContext = makeObservationContext(
            bundleIdentifier:
                workspace.frontmostApplication?.bundleIdentifier,
            now: currentActivityStartedAt
        )

        activationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication else {
                return
            }

            Task { @MainActor in
                self?.didActivate(application)
            }
        }

        for name in [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification
        ] {
            sleepObservers.append(
                workspace.notificationCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.suspendObservation()
                    }
                }
            )
        }

        for name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification
        ] {
            sleepObservers.append(
                workspace.notificationCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.resumeObservation()
                    }
                }
            )
        }
    }

    func stop() {
        flushCurrentActivity()
        hud.hideShield()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                activationObserver
            )
        }
        activationObserver = nil
        for observer in sleepObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        sleepObservers.removeAll()
    }

    func flushCurrentActivity(now: Date = Date()) {
        guard !isObservationSuspended,
              let bundleIdentifier = currentContext.bundleIdentifier
        else {
            currentActivityStartedAt = now
            return
        }
        let elapsed = now.timeIntervalSince(currentActivityStartedAt)
        guard elapsed > 0 else {
            return
        }

        do {
            try service.recordApplicationActivity(
                bundleIdentifier: bundleIdentifier,
                activeSeconds: min(elapsed, 60 * 60),
                sessionID: currentContext.sessionID,
                wasOnBreak: currentContext.wasOnBreak,
                historyEnabledAtObservation:
                    currentContext.historyEnabledAtObservation,
                now: now
            )
        } catch {
            // Observation is best effort and must never interrupt a session.
        }
        currentActivityStartedAt = now
        currentContext = makeObservationContext(
            bundleIdentifier: bundleIdentifier,
            now: now
        )
    }

    func beginNewObservationSegment(now: Date = Date()) {
        currentActivityStartedAt = now
        currentContext = makeObservationContext(
            bundleIdentifier:
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            now: now
        )
    }

    func enforceCurrentRestrictions(showNotice: Bool) {
        guard let current = try? service.currentState(),
              current.publicState.shouldBlockRestrictedServices
        else {
            return
        }

        let state = current.publicState
        let blocked = Set(current.snapshot.settings.blockedBundleIdentifiers)
        for application in NSWorkspace.shared.runningApplications {
            guard let bundleIdentifier = application.bundleIdentifier,
                  blocked.contains(bundleIdentifier)
            else {
                continue
            }

            let wasActive = application.isActive
            if wasActive {
                block(
                    application,
                    state: state,
                    showNotice: showNotice
                )
            } else {
                _ = application.hide()
            }
        }
    }

    func enforceFrontmostRestriction(showNotice: Bool) {
        guard let application =
            NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = application.bundleIdentifier,
              let current = try? service.currentState(),
              current.publicState.shouldBlockRestrictedServices,
              current.snapshot.settings.blocks(
                  bundleIdentifier: bundleIdentifier
              )
        else {
            return
        }
        block(
            application,
            state: current.publicState,
            showNotice: showNotice
        )
    }

    func updateBreakShotClock(
        state: PublicSessionState,
        settings: SessionSettings
    ) {
        guard state.phase == .onBreak,
              state.breakRemainingSeconds > 0,
              state.breakRemainingSeconds <= 10,
              let application = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = application.bundleIdentifier,
              settings.blocks(bundleIdentifier: bundleIdentifier)
        else {
            hud.hideShotClock()
            return
        }

        hud.showShotClock(
            remainingSeconds: state.breakRemainingSeconds
        ) { [weak self] in
            guard let self else {
                return
            }
            do {
                _ = try self.service.extendBreak()
                self.hud.hideShotClock()
            } catch {
                self.hud.show(message: error.localizedDescription)
            }
        }
    }

    private func didActivate(_ application: NSRunningApplication) {
        let now = Date()
        flushCurrentActivity(now: now)
        currentActivityStartedAt = now

        guard let current = try? service.currentState(now: now) else {
            currentContext = ObservationContext(
                bundleIdentifier: application.bundleIdentifier,
                sessionID: nil,
                wasOnBreak: false,
                historyEnabledAtObservation: false
            )
            return
        }
        currentContext = makeObservationContext(
            bundleIdentifier: application.bundleIdentifier,
            current: current
        )

        guard let bundleIdentifier = application.bundleIdentifier,
              current.publicState.shouldBlockRestrictedServices,
              current.snapshot.settings.blocks(
                  bundleIdentifier: bundleIdentifier
              )
        else {
            hud.hideShield()
            return
        }
        let state = current.publicState

        try? service.recordBlockedAttempt(
            service: bundleIdentifier,
            sessionID: currentContext.sessionID,
            wasOnBreak: currentContext.wasOnBreak,
            historyEnabledAtObservation:
                currentContext.historyEnabledAtObservation,
            now: now
        )
        block(
            application,
            state: state,
            showNotice: true
        )
    }

    private func block(
        _ application: NSRunningApplication,
        state: PublicSessionState,
        showNotice: Bool
    ) {
        let message = blockMessage(
            applicationName: application.localizedName,
            state: state
        )
        let didHide = application.hide()
        if didHide && application.isHidden {
            hud.hideShield()
            if showNotice {
                hud.show(message: message)
            }
        } else {
            hud.showShield(message: message)
        }

        for delay in [0.15, 0.5, 1.0] {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + delay
            ) { [weak self, weak application] in
                guard let self, let application,
                      !application.isTerminated
                else {
                    return
                }
                if application.isHidden {
                    self.hud.hideShield()
                    return
                }
                _ = application.hide()
                if application.isHidden {
                    self.hud.hideShield()
                }
            }
        }
    }

    private func suspendObservation() {
        guard !isObservationSuspended else {
            return
        }
        flushCurrentActivity()
        isObservationSuspended = true
        hud.hideShotClock()
        hud.hideShield()
    }

    private func resumeObservation() {
        isObservationSuspended = false
        currentActivityStartedAt = Date()
        currentContext = makeObservationContext(
            bundleIdentifier:
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            now: currentActivityStartedAt
        )
    }

    private func makeObservationContext(
        bundleIdentifier: String?,
        now: Date
    ) -> ObservationContext {
        guard let current = try? service.currentState(now: now) else {
            return ObservationContext(
                bundleIdentifier: bundleIdentifier,
                sessionID: nil,
                wasOnBreak: false,
                historyEnabledAtObservation: false
            )
        }
        return makeObservationContext(
            bundleIdentifier: bundleIdentifier,
            current: current
        )
    }

    private func makeObservationContext(
        bundleIdentifier: String?,
        current: (
            snapshot: PersistedState,
            publicState: PublicSessionState
        )
    ) -> ObservationContext {
        ObservationContext(
            bundleIdentifier: bundleIdentifier,
            sessionID: current.publicState.sessionID,
            wasOnBreak: current.publicState.phase == .onBreak,
            historyEnabledAtObservation:
                current.snapshot.settings.historyEnabled
        )
    }

    private func blockMessage(
        applicationName: String?,
        state: PublicSessionState
    ) -> String {
        let name = applicationName ?? "This app"
        if state.canStartBreak {
            return "\(name) is paused by \(state.profileName). Your "
                + DurationText.readable(state.breakDurationSeconds)
                + " break is ready."
        }
        if state.breakDurationSeconds == 0 {
            return "\(name) is paused by \(state.profileName). "
                + "No breaks are scheduled for this session."
        }
        return "\(name) is paused by \(state.profileName). Break available in "
            + DurationText.readable(state.focusRemainingSeconds)
            + "."
    }
}
