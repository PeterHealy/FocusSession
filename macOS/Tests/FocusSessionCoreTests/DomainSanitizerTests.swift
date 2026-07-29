import XCTest
@testable import FocusSessionCore

final class DomainSanitizerTests: XCTestCase {
    func testExtractsHostnameWithoutBrowsingContent() {
        XCTAssertEqual(
            DomainSanitizer.hostname(
                from: "https://www.Reddit.com/r/mac?token=private#comments"
            ),
            "www.reddit.com"
        )
    }

    func testReducesSubdomainsToRegistrableDomain() {
        XCTAssertEqual(
            DomainSanitizer.registrableDomain(
                from: "https://old.reddit.com/r/mac"
            ),
            "reddit.com"
        )
        XCTAssertEqual(
            DomainSanitizer.registrableDomain(
                from: "https://mail.example.co.uk/inbox"
            ),
            "example.co.uk"
        )
        XCTAssertEqual(
            DomainSanitizer.registrableDomain(
                from: "https://mail.example.co.ie/inbox"
            ),
            "example.co.ie"
        )
    }

    func testBlockedDomainMatchesSubdomain() {
        let settings = SessionSettings(blockedDomains: ["reddit.com"])
        XCTAssertTrue(settings.blocks(domain: "old.reddit.com"))
        XCTAssertFalse(settings.blocks(domain: "notreddit.com"))
    }

    func testSettingsPreserveExactCustomHostnameWithoutBroadening() {
        let settings = SessionSettings(
            blockedDomains: [
                "example.co.ie",
                "old.reddit.com"
            ]
        )

        XCTAssertEqual(
            settings.blockedDomains,
            ["example.co.ie", "old.reddit.com"]
        )
        XCTAssertTrue(settings.blocks(domain: "old.reddit.com"))
        XCTAssertTrue(settings.blocks(domain: "child.old.reddit.com"))
        XCTAssertFalse(settings.blocks(domain: "reddit.com"))
        XCTAssertFalse(settings.blocks(domain: "new.reddit.com"))
    }

    func testCompoundSuffixTableMatchesBrowserCases() {
        let cases = [
            "example.ltd.uk",
            "example.me.uk",
            "example.co.ie",
            "example.id.au",
            "example.govt.nz",
            "example.com.cn",
            "example.com.hk",
            "example.com.mx",
            "example.com.tr",
            "example.com.tw",
            "example.co.kr",
            "example.co.za"
        ]
        for baseDomain in cases {
            XCTAssertEqual(
                DomainSanitizer.registrableDomain(
                    from: "nested.\(baseDomain)"
                ),
                baseDomain
            )
        }
    }

    func testFreshInstallDefaultsContainOnlyFourMetaServices() {
        XCTAssertEqual(
            SessionSettings().blockedDomains,
            [
                "facebook.com",
                "instagram.com",
                "messenger.com",
                "whatsapp.com"
            ]
        )
        XCTAssertEqual(
            SessionSettings().blockedBundleIdentifiers,
            [
                "com.burbn.instagram",
                "com.facebook.Facebook",
                "com.facebook.Messenger",
                "net.whatsapp.WhatsApp"
            ]
        )
    }

    func testLegacySettingsMigrateIntoDeepWorkProfile() {
        var settings = SessionSettings(
            blockedDomains: ["reddit.com", "x.com"]
        )
        settings.profiles = nil
        settings.selectedProfileID = nil

        settings.migrateLegacyProfileIfNeeded()

        XCTAssertEqual(settings.activeProfileName, "Deep Work")
        XCTAssertEqual(settings.selectedProfileID, FocusProfile.deepWorkID)
        XCTAssertTrue(settings.blocks(domain: "reddit.com"))
        XCTAssertTrue(settings.blocks(domain: "facebook.com"))
        XCTAssertTrue(settings.blocks(domain: "messenger.com"))
        XCTAssertFalse(settings.blocks(domain: "twitch.tv"))
        XCTAssertFalse(settings.blocks(domain: "linkedin.com"))
    }

    func testSelectedProfileOwnsCycleAndRestrictions() {
        let writing = FocusProfile(
            id: "writing",
            name: "Writing",
            focusDuration: 45 * 60,
            breakDuration: 8 * 60,
            blockedBundleIdentifiers: [],
            blockedDomains: ["reddit.com"]
        )
        let research = FocusProfile(
            id: "research",
            name: "Research",
            focusDuration: 25 * 60,
            breakDuration: 5 * 60,
            blockedBundleIdentifiers: [],
            blockedDomains: ["x.com"]
        )
        let settings = SessionSettings(
            profiles: [writing, research],
            selectedProfileID: "research"
        )

        XCTAssertEqual(settings.activeProfileName, "Research")
        XCTAssertEqual(settings.focusDuration, 25 * 60)
        XCTAssertTrue(settings.blocks(domain: "x.com"))
        XCTAssertFalse(settings.blocks(domain: "reddit.com"))
    }

    func testProfileAndSettingsPreserveNoBreakMode() {
        var profile = FocusProfile.deepWork(
            focusDuration: 45 * 60,
            breakDuration: 0
        )
        profile.normalize()
        XCTAssertEqual(profile.breakDuration, 0)

        var settings = SessionSettings(
            focusDuration: profile.focusDuration,
            breakDuration: profile.breakDuration,
            profiles: [profile],
            selectedProfileID: profile.id
        )
        settings.normalize()

        XCTAssertEqual(settings.breakDuration, 0)
        XCTAssertEqual(settings.activeProfile?.breakDuration, 0)
    }
}
