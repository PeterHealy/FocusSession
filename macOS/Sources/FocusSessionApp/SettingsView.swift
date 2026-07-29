import AppKit
import FocusSessionCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = SessionSettings()
    @State private var breakPattern: BreakPatternPreset = .strict
    @State private var bundleIdentifiersText = ""
    @State private var domainsText = ""
    @State private var newDomain = ""
    @State private var newBundleIdentifier = ""
    @State private var domainInputError: String?
    @State private var appInputError: String?
    @State private var showsBundleIdentifierInput = false
    @State private var profiles: [FocusProfile] = []
    @State private var selectedProfileID = FocusProfile.deepWorkID
    @State private var profileName = "Deep Work"

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "slider.horizontal.3")
                }

            restrictionsTab
                .tabItem {
                    Label("Restrictions", systemImage: "hand.raised")
                }

            privacyTab
                .tabItem {
                    Label("Privacy", systemImage: "lock")
                }
        }
        .padding(16)
        .onAppear(perform: loadDraft)
        .onChange(of: model.settings) { _, _ in
            loadDraft()
        }
    }

    private var generalTab: some View {
        Form {
            Section("Profile") {
                Picker(
                    "Active profile",
                    selection: Binding(
                        get: { selectedProfileID },
                        set: { selectProfile($0) }
                    )
                ) {
                    ForEach(profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }

                TextField("Profile name", text: $profileName)

                HStack {
                    Button("New Profile") {
                        createProfile()
                    }
                    Button("Delete Profile", role: .destructive) {
                        deleteSelectedProfile()
                    }
                    .disabled(profiles.count <= 1)
                }

                Text(
                    "Cycle timing and restriction lists are saved separately "
                        + "for each profile."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Cycle") {
                Picker(
                    "Pattern",
                    selection: Binding(
                        get: { breakPattern },
                        set: { applyBreakPattern($0) }
                    )
                ) {
                    ForEach(BreakPatternPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }

                Stepper(
                    "Focus: \(Int(draft.focusDuration / 60)) minutes",
                    value: Binding(
                        get: { Int(draft.focusDuration / 60) },
                        set: {
                            draft.focusDuration = TimeInterval($0 * 60)
                            breakPattern = .custom
                        }
                    ),
                    in: 1...180
                )

                Toggle(
                    "Take breaks",
                    isOn: Binding(
                        get: { draft.breakDuration > 0 },
                        set: { enabled in
                            draft.breakDuration =
                                enabled
                                    ? max(draft.breakDuration, 5 * 60)
                                    : 0
                            breakPattern = .custom
                        }
                    )
                )

                Stepper(
                    draft.breakDuration == 0
                        ? "Break: No breaks"
                        : "Break: \(Int(draft.breakDuration / 60)) minutes",
                    value: Binding(
                        get: {
                            max(1, Int(draft.breakDuration / 60))
                        },
                        set: {
                            draft.breakDuration = TimeInterval($0 * 60)
                            breakPattern = .custom
                        }
                    ),
                    in: 1...30
                )
                .disabled(draft.breakDuration == 0)

                Text(
                    draft.breakDuration == 0
                        ? "Restrictions stay active for the full session."
                        : "Unused breaks do not accumulate. Extensions remain "
                            + "fixed at 30 seconds and unlock only in the final "
                            + "10 seconds."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle(
                    "Launch Focus Session at login",
                    isOn: $draft.launchAtLoginEnabled
                )
                Text(
                    "Enable this so native-app blocking resumes automatically "
                        + "after restarting the Mac."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle(
                    "Break notifications",
                    isOn: $draft.notificationsEnabled
                )
                Toggle(
                    "Session-complete notification",
                    isOn: $draft.sessionCompletionNotificationEnabled
                )
                .disabled(!draft.notificationsEnabled)
            }

            Section("Work Focus Shortcuts") {
                Toggle(
                    "Run Shortcuts with each session",
                    isOn: $draft.workFocusAutomationEnabled
                )
                TextField(
                    "Start Shortcut",
                    text: $draft.workFocusStartShortcutName
                )
                TextField(
                    "End Shortcut",
                    text: $draft.workFocusEndShortcutName
                )
                Text(
                    "Create these in Apple Shortcuts using Set Focus actions. "
                        + "No private Focus-mode API is used."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            saveButton
        }
        .formStyle(.grouped)
    }

    private var restrictionsTab: some View {
        Form {
            Section {
                if blockedBundleIdentifiers.isEmpty {
                    Label(
                        "No apps are blocked in this profile",
                        systemImage: "checkmark.circle"
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(blockedBundleIdentifiers, id: \.self) {
                        bundleIdentifier in
                        restrictionRow(
                            title: appDisplayName(
                                for: bundleIdentifier
                            ),
                            detail: bundleIdentifier,
                            systemImage: "app.fill"
                        ) {
                            removeBundleIdentifier(bundleIdentifier)
                        }
                    }
                }

                Button {
                    chooseApplications()
                } label: {
                    Label("Choose App…", systemImage: "plus")
                }

                DisclosureGroup(
                    "Add by bundle identifier",
                    isExpanded: $showsBundleIdentifierInput
                ) {
                    HStack {
                        TextField(
                            "e.g. com.apple.MobileSMS",
                            text: $newBundleIdentifier
                        )
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addBundleIdentifier()
                        }

                        Button("Add") {
                            addBundleIdentifier()
                        }
                        .disabled(
                            newBundleIdentifier.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                        )
                    }
                    .padding(.top, 4)
                }

                if let appInputError {
                    Text(appInputError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel(
                            "Could not add app: \(appInputError)"
                        )
                }
            } header: {
                Text("Blocked apps")
            } footer: {
                Text(
                    "Choose any installed app. FocusSession saves only its "
                        + "bundle identifier and never reads its content."
                )
            }

            Section {
                HStack {
                    TextField(
                        "Website or domain",
                        text: $newDomain,
                        prompt: Text("e.g. youtube.com")
                    )
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addDomain()
                    }

                    Button {
                        addDomain()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(
                        newDomain.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }

                if let domainInputError {
                    Text(domainInputError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel(
                            "Could not add website: \(domainInputError)"
                        )
                }

                if blockedDomains.isEmpty {
                    Label(
                        "No websites are blocked in this profile",
                        systemImage: "checkmark.circle"
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(blockedDomains, id: \.self) { domain in
                        restrictionRow(
                            title: domain,
                            systemImage: "globe"
                        ) {
                            removeDomain(domain)
                        }
                    }
                }
            } header: {
                Text("Blocked websites")
            } footer: {
                Text(
                    "Paste a domain or full URL. Page paths, searches and other "
                        + "private details are discarded."
                )
            }

            if !model.suggestedDomains.isEmpty {
                Section("Local suggestions") {
                    ForEach(model.suggestedDomains, id: \.self) { domain in
                        HStack {
                            Text(domain)
                            Spacer()
                            Button("Dismiss") {
                                model.dismissSuggestion(domain)
                            }
                            Button("Add") {
                                model.acceptSuggestion(domain)
                            }
                        }
                    }
                    Button("Done for this week") {
                        model.finishSuggestionReview()
                    }
                }
            }

            saveButton
        }
        .formStyle(.grouped)
    }

    private var blockedBundleIdentifiers: [String] {
        splitLines(bundleIdentifiersText)
    }

    private var blockedDomains: [String] {
        splitLines(domainsText)
    }

    private func restrictionRow(
        title: String,
        detail: String? = nil,
        systemImage: String,
        onRemove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail, detail != title {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            Button(role: .destructive, action: onRemove) {
                Label("Remove \(title)", systemImage: "minus.circle.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Remove \(title)")
        }
        .padding(.vertical, 2)
    }

    private func addDomain() {
        guard let domain = DomainSanitizer.hostname(from: newDomain) else {
            domainInputError =
                "Enter a valid domain or web address, such as youtube.com."
            return
        }

        guard !blockedDomains.contains(domain) else {
            domainInputError = "\(domain) is already in this profile."
            return
        }

        domainsText = (blockedDomains + [domain]).joined(separator: "\n")
        newDomain = ""
        domainInputError = nil
    }

    private func removeDomain(_ domain: String) {
        domainsText = blockedDomains
            .filter { $0 != domain }
            .joined(separator: "\n")
        domainInputError = nil
    }

    private func chooseApplications() {
        let panel = NSOpenPanel()
        panel.title = "Choose apps to block"
        panel.prompt = "Add Apps"
        panel.message =
            "Select one or more installed apps. FocusSession stores only "
            + "their bundle identifiers."
        panel.directoryURL = URL(
            fileURLWithPath: "/Applications",
            isDirectory: true
        )
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else {
            return
        }

        var identifiers = blockedBundleIdentifiers
        var unreadableAppNames: [String] = []
        for applicationURL in panel.urls {
            guard let identifier =
                Bundle(url: applicationURL)?.bundleIdentifier,
                !identifier.isEmpty
            else {
                unreadableAppNames.append(
                    applicationURL.deletingPathExtension().lastPathComponent
                )
                continue
            }
            if !identifiers.contains(identifier) {
                identifiers.append(identifier)
            }
        }

        bundleIdentifiersText = identifiers.joined(separator: "\n")
        appInputError = unreadableAppNames.isEmpty
            ? nil
            : "Could not read \(unreadableAppNames.joined(separator: ", "))."
    }

    private func addBundleIdentifier() {
        let identifier = newBundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidBundleIdentifier(identifier) else {
            appInputError =
                "Enter a bundle identifier such as com.apple.MobileSMS."
            return
        }
        guard !blockedBundleIdentifiers.contains(identifier) else {
            appInputError = "\(identifier) is already in this profile."
            return
        }

        bundleIdentifiersText =
            (blockedBundleIdentifiers + [identifier]).joined(separator: "\n")
        newBundleIdentifier = ""
        appInputError = nil
    }

    private func removeBundleIdentifier(_ identifier: String) {
        bundleIdentifiersText = blockedBundleIdentifiers
            .filter { $0 != identifier }
            .joined(separator: "\n")
        appInputError = nil
    }

    private func isValidBundleIdentifier(_ value: String) -> Bool {
        let components = value.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard components.count >= 2, value.count <= 255 else {
            return false
        }
        return components.allSatisfy { component in
            guard let first = component.first,
                  first.isASCII,
                  first.isLetter
            else {
                return false
            }
            return component.allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
            }
        }
    }

    private func appDisplayName(for bundleIdentifier: String) -> String {
        let knownNames = [
            "com.burbn.instagram": "Instagram",
            "com.facebook.Facebook": "Facebook",
            "com.facebook.Messenger": "Messenger",
            "com.facebook.archon": "Messenger",
            "com.facebook.archon.developerID": "Messenger",
            "com.whatsapp.WhatsApp": "WhatsApp",
            "net.whatsapp.WhatsApp": "WhatsApp"
        ]
        if let knownName = knownNames[bundleIdentifier] {
            return knownName
        }

        guard let applicationURL =
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ),
            let bundle = Bundle(url: applicationURL)
        else {
            return bundleIdentifier
        }

        return (bundle.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String)
            ?? (bundle.object(
                forInfoDictionaryKey: "CFBundleName"
            ) as? String)
            ?? applicationURL.deletingPathExtension().lastPathComponent
    }

    private var privacyTab: some View {
        Form {
            Section("Local records") {
                Toggle("Keep session history", isOn: $draft.historyEnabled)
                Toggle(
                    "Observe aggregate app and domain usage",
                    isOn: $draft.usageObservationEnabled
                )
                Toggle(
                    "Suggest likely distractions",
                    isOn: $draft.distractionSuggestionsEnabled
                )
                .disabled(!draft.usageObservationEnabled)

                Text(
                    "Session history is local and on by default. Aggregate app "
                        + "and domain observation and suggestions stay off "
                        + "until you enable them. Data stays in "
                        + "~/Library/Application Support/FocusSession. No "
                        + "account, analytics, cloud service or network call "
                        + "is used."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Delete local data") {
                Button("Clear all history and usage", role: .destructive) {
                    model.clearAllHistoryAndUsage()
                }
                Button("Clear app and domain rollups", role: .destructive) {
                    model.clearUsageRollups()
                }
            }

            saveButton
        }
        .formStyle(.grouped)
    }

    private var saveButton: some View {
        HStack {
            Spacer()
            Button("Save Settings") {
                draft.blockedBundleIdentifiers = splitLines(
                    bundleIdentifiersText
                )
                draft.blockedDomains = splitLines(domainsText)
                storeCurrentProfile()
                draft.profiles = profiles
                draft.selectedProfileID = selectedProfileID
                if let selected = profiles.first(where: {
                    $0.id == selectedProfileID
                }) {
                    applyProfile(selected, updateTextEditors: false)
                }
                model.saveSettings(draft)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func loadDraft() {
        draft = model.settings
        newDomain = ""
        newBundleIdentifier = ""
        domainInputError = nil
        appInputError = nil
        profiles = draft.resolvedProfiles
        selectedProfileID =
            draft.selectedProfileID.flatMap { requestedID in
                profiles.contains(where: { $0.id == requestedID })
                    ? requestedID
                    : nil
            }
            ?? profiles.first?.id
            ?? FocusProfile.deepWorkID
        if let selected = profiles.first(where: {
            $0.id == selectedProfileID
        }) {
            applyProfile(selected)
        }
    }

    private func applyBreakPattern(_ preset: BreakPatternPreset) {
        breakPattern = preset
        guard let durations = preset.durations else {
            return
        }
        draft.focusDuration = durations.focus
        draft.breakDuration = durations.breakTime
    }

    private func selectProfile(_ profileID: String) {
        guard profileID != selectedProfileID,
              profiles.contains(where: { $0.id == profileID })
        else {
            return
        }
        storeCurrentProfile()
        selectedProfileID = profileID
        if let selected = profiles.first(where: { $0.id == profileID }) {
            applyProfile(selected)
        }
    }

    private func createProfile() {
        storeCurrentProfile()
        let profile = FocusProfile(
            name: "New Profile",
            focusDuration: draft.focusDuration,
            breakDuration: draft.breakDuration,
            blockedBundleIdentifiers:
                splitLines(bundleIdentifiersText),
            blockedDomains: splitLines(domainsText)
        )
        profiles.append(profile)
        selectedProfileID = profile.id
        applyProfile(profile)
    }

    private func deleteSelectedProfile() {
        guard profiles.count > 1 else {
            return
        }
        profiles.removeAll { $0.id == selectedProfileID }
        guard let replacement = profiles.first else {
            return
        }
        selectedProfileID = replacement.id
        applyProfile(replacement)
    }

    private func storeCurrentProfile() {
        guard let index = profiles.firstIndex(where: {
            $0.id == selectedProfileID
        }) else {
            return
        }
        var updated = profiles[index]
        updated.name = profileName
        updated.focusDuration = draft.focusDuration
        updated.breakDuration = draft.breakDuration
        updated.blockedBundleIdentifiers =
            splitLines(bundleIdentifiersText)
        updated.blockedDomains = splitLines(domainsText)
        updated.normalize()
        profiles[index] = updated
        profileName = updated.name
    }

    private func applyProfile(
        _ profile: FocusProfile,
        updateTextEditors: Bool = true
    ) {
        profileName = profile.name
        draft.focusDuration = profile.focusDuration
        draft.breakDuration = profile.breakDuration
        draft.blockedBundleIdentifiers =
            profile.blockedBundleIdentifiers
        draft.blockedDomains = profile.blockedDomains
        breakPattern = BreakPatternPreset.matching(
            focusDuration: profile.focusDuration,
            breakDuration: profile.breakDuration
        )
        if updateTextEditors {
            bundleIdentifiersText =
                profile.blockedBundleIdentifiers.joined(separator: "\n")
            domainsText = profile.blockedDomains.joined(separator: "\n")
        }
    }

    private func splitLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
