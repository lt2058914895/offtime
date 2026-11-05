import XCTest
import CryptoKit
import UserNotifications
@testable import offtime

final class ReminderSoundTests: XCTestCase {
    func testBuiltInSoundsHaveBundledFiles() {
        for sound in ReminderSound.builtInCases {
            XCTAssertNotNil(
                sound.resourceURL(in: .main),
                "Missing bundled audio for \(sound.rawValue)"
            )
        }
    }

    func testSystemSoundDoesNotReferenceAudioFile() {
        XCTAssertNil(ReminderSound.system.fileName)
        XCTAssertFalse(ReminderSound.system.isBuiltIn)
    }

    func testFreeAndProSoundTiers() {
        XCTAssertEqual(
            ReminderSound.freeBuiltInCases,
            [.gentleMarimba]
        )
        XCTAssertEqual(
            ReminderSound.proBuiltInCases,
            [.alarm, .doorKnock, .digitalPulse, .waterDrop, .rhythmTaps]
        )
        XCTAssertEqual(
            ReminderSound.builtInCases,
            ReminderSound.freeBuiltInCases + ReminderSound.proBuiltInCases
        )
        XCTAssertFalse(ReminderSound.system.requiresPro)
        XCTAssertTrue(ReminderSound.freeBuiltInCases.allSatisfy { !$0.requiresPro })
        XCTAssertTrue(ReminderSound.proBuiltInCases.allSatisfy(\.requiresPro))
    }

    func testProviderMapsSystemAndBuiltInSounds() throws {
        let provider = BuiltInReminderSoundProvider()

        XCTAssertNotNil(provider.notificationSound(for: .system))
        XCTAssertEqual(provider.fingerprint(for: .system), "system")

        for sound in ReminderSound.builtInCases {
            XCTAssertNotNil(provider.notificationSound(for: sound))
            let expectedDigest = SHA256.hash(
                data: try Data(contentsOf: XCTUnwrap(sound.resourceURL(in: .main)))
            ).map { byte in
                String(format: "%02x", byte)
            }.joined()
            XCTAssertEqual(
                provider.fingerprint(for: sound),
                "builtin:\(sound.fileName ?? ""):\(expectedDigest)"
            )
        }
    }

    func testFingerprintChangesWhenContentChangesWithSameFileName() {
        let first = BuiltInReminderSoundProvider.fingerprint(
            fileName: "reminder-alarm.caf",
            content: Data([1, 2, 3])
        )
        let second = BuiltInReminderSoundProvider.fingerprint(
            fileName: "reminder-alarm.caf",
            content: Data([1, 2, 4])
        )

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.hasPrefix("builtin:reminder-alarm.caf:"))
    }

    func testPreferencesFallsBackForUnknownValue() {
        let suiteName = "ReminderSoundTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertEqual(
            ReminderSoundPreferences.resolvedDefault(from: defaults, isProUnlocked: false),
            ReminderSoundPreferences.fallbackSound
        )

        defaults.set("unknown", forKey: ReminderSoundPreferences.defaultSoundKey)
        XCTAssertEqual(
            ReminderSoundPreferences.resolvedDefault(from: defaults, isProUnlocked: false),
            ReminderSoundPreferences.fallbackSound
        )

        // The removed Morning Birds option may still be stored on an existing device.
        defaults.set("morningBirds", forKey: ReminderSoundPreferences.defaultSoundKey)
        XCTAssertEqual(
            ReminderSoundPreferences.resolvedDefault(from: defaults, isProUnlocked: true),
            ReminderSoundPreferences.fallbackSound
        )
        XCTAssertEqual(
            defaults.string(forKey: ReminderSoundPreferences.defaultSoundKey),
            ReminderSoundPreferences.fallbackSound.rawValue
        )

        // The removed Crystal Chime option may also still be stored on an existing device.
        defaults.set("crystalChime", forKey: ReminderSoundPreferences.defaultSoundKey)
        XCTAssertEqual(
            ReminderSoundPreferences.resolvedDefault(from: defaults, isProUnlocked: true),
            ReminderSoundPreferences.fallbackSound
        )
        XCTAssertEqual(
            defaults.string(forKey: ReminderSoundPreferences.defaultSoundKey),
            ReminderSoundPreferences.fallbackSound.rawValue
        )

        defaults.set("classicBell", forKey: ReminderSoundPreferences.defaultSoundKey)
        XCTAssertEqual(
            ReminderSoundPreferences.resolvedDefault(from: defaults, isProUnlocked: true),
            .doorKnock
        )
        XCTAssertEqual(
            defaults.string(forKey: ReminderSoundPreferences.defaultSoundKey),
            ReminderSound.doorKnock.rawValue
        )

        defaults.set(
            ReminderSound.alarm.rawValue,
            forKey: ReminderSoundPreferences.defaultSoundKey
        )
        XCTAssertEqual(
            ReminderSoundPreferences.resolvedDefault(from: defaults, isProUnlocked: false),
            ReminderSoundPreferences.fallbackSound
        )
        XCTAssertEqual(
            defaults.string(forKey: ReminderSoundPreferences.defaultSoundKey),
            ReminderSoundPreferences.fallbackSound.rawValue
        )

        defaults.set(
            ReminderSound.alarm.rawValue,
            forKey: ReminderSoundPreferences.defaultSoundKey
        )
        XCTAssertEqual(
            ReminderSoundPreferences.resolvedDefault(from: defaults, isProUnlocked: true),
            .alarm
        )
    }

    func testSaveDefaultClampsProSoundWhenLocked() {
        let suiteName = "ReminderSoundTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertEqual(
            ReminderSoundPreferences.saveDefault(.alarm, to: defaults, isProUnlocked: false),
            ReminderSoundPreferences.fallbackSound
        )
        XCTAssertEqual(
            ReminderSoundPreferences.storedDefault(from: defaults),
            ReminderSoundPreferences.fallbackSound
        )

        XCTAssertEqual(
            ReminderSoundPreferences.saveDefault(.gentleMarimba, to: defaults, isProUnlocked: false),
            .gentleMarimba
        )
        XCTAssertEqual(
            ReminderSoundPreferences.storedDefault(from: defaults),
            .gentleMarimba
        )
    }

    func testForegroundNotificationPresentationIncludesBannerAndSound() {
        let options = ReminderNotificationDelegate.foregroundPresentationOptions
        XCTAssertTrue(options.contains(.banner))
        XCTAssertTrue(options.contains(.list))
        XCTAssertTrue(options.contains(.sound))
    }
}
