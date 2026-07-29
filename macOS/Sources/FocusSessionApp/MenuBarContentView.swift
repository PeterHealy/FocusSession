import AppKit
import FocusSessionCore
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var sessionDurationMinutes = 4 * 60
    @State private var focusIntervalMinutes = 55
    @State private var breakDurationMinutes = 5
    @State private var breaksEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.publicState.isSessionActive {
                activeSessionView
            } else {
                startSessionView
            }

            Divider()

            HStack {
                Button("Dashboard") {
                    openWindow(id: "dashboard")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }

                Button("Settings") {
                    openSettingsWindow()
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 340)
        .alert(
            "Focus Session",
            isPresented: Binding(
                get: { model.lastErrorMessage != nil },
                set: { if !$0 { model.lastErrorMessage = nil } }
            )
        ) {
            Button("OK") {
                model.lastErrorMessage = nil
            }
        } message: {
            Text(model.lastErrorMessage ?? "")
        }
        .onAppear(perform: syncStartConfiguration)
        .onChange(of: model.settings) { _, _ in
            guard model.startCountdownRemaining == nil else {
                return
            }
            syncStartConfiguration()
        }
    }

    private var startSessionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start a focus session")
                .font(.headline)

            Label(
                model.settings.activeProfileName,
                systemImage: "person.crop.circle"
            )
            .font(.subheadline.weight(.semibold))

            Text(
                breaksEnabled
                    ? "Restricted services stay closed until you claim an "
                        + "earned break."
                    : "Restricted services stay closed for the full session."
            )
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                timingStepper(
                    title: "Session length",
                    minutes: $sessionDurationMinutes,
                    range: 15...(12 * 60),
                    step: 15
                )

                Toggle("Take breaks", isOn: $breaksEnabled)

                if breaksEnabled {
                    timingStepper(
                        title: "Break every",
                        minutes: $focusIntervalMinutes,
                        range: 5...180,
                        step: 5
                    )
                    timingStepper(
                        title: "Break length",
                        minutes: $breakDurationMinutes,
                        range: 1...30,
                        step: 1
                    )
                } else {
                    HStack {
                        Text("Break length")
                        Spacer()
                        Text("No breaks")
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(
                .secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10)
            )

            if let remaining = model.startCountdownRemaining {
                HStack(spacing: 12) {
                    Text("\(remaining)")
                        .font(
                            .system(
                                .title,
                                design: .rounded,
                                weight: .bold
                            )
                        )
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Starting Deep Work…")
                            .font(.subheadline.weight(.semibold))
                        Text(
                            DurationText.readable(
                                model.pendingSessionDuration
                                    ?? TimeInterval(
                                        sessionDurationMinutes * 60
                                    )
                            )
                                + " session"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Cancel") {
                        model.cancelStartCountdown()
                    }
                }
                .padding(10)
                .background(
                    .tint.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Starting Deep Work in \(remaining) seconds"
                )
            } else {
                Button("Start Session") {
                    model.startConfiguredSession(
                        sessionDuration:
                            TimeInterval(sessionDurationMinutes * 60),
                        focusDuration:
                            TimeInterval(focusIntervalMinutes * 60),
                        breakDuration:
                            breaksEnabled
                                ? TimeInterval(
                                    breakDurationMinutes * 60
                                )
                                : 0
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var activeSessionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(phaseTitle)
                        .font(.headline)
                    Text(model.publicState.profileName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let end = model.publicState.scheduledEndAt {
                        Text("Session ends \(end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(primaryCountdown)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
            }

            if model.publicState.canStartBreak {
                Button(
                    "Start "
                        + DurationText.readable(
                            model.publicState.breakDurationSeconds
                        )
                        + " break"
                ) {
                    model.startBreak()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            } else if model.publicState.phase == .onBreak {
                if model.publicState.canExtendBreak {
                    Button("+30 seconds") {
                        model.extendBreak()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut(.return, modifiers: [])
                } else {
                    Text("Another 30 seconds becomes available at 10 seconds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(focusStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button("End Session Early…") {
                confirmEndEarly()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var phaseTitle: String {
        switch model.publicState.phase {
        case .inactive:
            return "Ready"
        case .focusing:
            return "Focus"
        case .breakAvailable:
            return "Break ready"
        case .onBreak:
            return "Free-use break"
        }
    }

    private var primaryCountdown: String {
        switch model.publicState.phase {
        case .onBreak:
            return DurationText.compact(model.publicState.breakRemainingSeconds)
        case .focusing:
            return DurationText.compact(model.publicState.focusRemainingSeconds)
        case .breakAvailable:
            return "Ready"
        case .inactive:
            return ""
        }
    }

    private var focusStatusText: String {
        if model.publicState.breakDurationSeconds == 0 {
            return "No breaks • focus until the session ends"
        }
        return "Break available in "
            + DurationText.readable(
                model.publicState.focusRemainingSeconds
            )
    }

    private func timingStepper(
        title: String,
        minutes: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        Stepper(
            value: minutes,
            in: range,
            step: step
        ) {
            HStack {
                Text(title)
                Spacer()
                Text(
                    DurationText.readable(
                        TimeInterval(minutes.wrappedValue * 60)
                    )
                )
                .fontWeight(.semibold)
            }
        }
    }

    private func syncStartConfiguration() {
        focusIntervalMinutes = max(
            1,
            Int(model.settings.focusDuration / 60)
        )
        if model.settings.breakDuration == 0 {
            breaksEnabled = false
        } else {
            breaksEnabled = true
            breakDurationMinutes = max(
                1,
                Int(model.settings.breakDuration / 60)
            )
        }
    }

    private func openSettingsWindow() {
        let action = openSettings
        NSApplication.shared.activate(ignoringOtherApps: true)

        // The menu-bar window is transient. Present Settings on the next run
        // loop so dismissing the menu cannot swallow the new window.
        DispatchQueue.main.async {
            action()
        }
    }

    private func confirmEndEarly() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "End this session early?"
        alert.informativeText =
            "Your completed focus time will be saved to local history."
        let endButton = alert.addButton(withTitle: "End Session")
        endButton.hasDestructiveAction = true
        alert.addButton(withTitle: "Keep Focusing")

        NSApplication.shared.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        // Let the modal finish closing before the menu-bar view changes from
        // active to inactive. This avoids losing the confirmed action as the
        // transient menu window is dismissed.
        DispatchQueue.main.async {
            model.endEarly()
        }
    }
}
