import AppKit
import Darwin
import FocusSessionCore
import ServiceManagement
import SwiftUI

@main
struct FocusSessionAppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(model)
        } label: {
            Label {
                Text(model.menuBarTitle)
            } icon: {
                HourglassMenuBarIcon(
                    isActive: model.publicState.isSessionActive,
                    elapsedFraction:
                        model.publicState.sessionElapsedFraction
                )
            }
            .labelStyle(.titleAndIcon)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.menuBarAccessibilityLabel)
        }
        .menuBarExtraStyle(.window)

        Window("Focus Session Dashboard", id: "dashboard") {
            DashboardView()
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 520)
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 560, height: 620)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard CommandLine.arguments.contains("--unregister-login-item") else {
            return
        }

        let loginItem = SMAppService.mainApp
        do {
            if loginItem.status == .enabled
                || loginItem.status == .requiresApproval {
                try loginItem.unregister()
            }
            writeToStandardError(
                "FocusSession: Launch at Login is unregistered.\n"
            )
            exit(EXIT_SUCCESS)
        } catch {
            writeToStandardError(
                "FocusSession: failed to unregister Launch at Login: "
                    + error.localizedDescription
                    + "\n"
            )
            exit(EXIT_FAILURE)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func application(
        _ application: NSApplication,
        open urls: [URL]
    ) {
        guard urls.contains(where: {
            $0.scheme?.lowercased() == "focussession"
        }) else {
            return
        }

        application.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            let opened = application.sendAction(
                Selector(("showSettingsWindow:")),
                to: nil,
                from: nil
            )
            if !opened {
                _ = application.sendAction(
                    Selector(("showPreferencesWindow:")),
                    to: nil,
                    from: nil
                )
            }
        }
    }

    private func writeToStandardError(_ message: String) {
        FileHandle.standardError.write(Data(message.utf8))
    }
}
