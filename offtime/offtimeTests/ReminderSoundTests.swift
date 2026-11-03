import XCTest
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

    func testProviderMapsSystemAndBuiltInSounds() {
        let provider = BuiltInReminderSoundProvider()

        XCTAssertNotNil(provider.notificationSound(for: .system))
        XCTAssertEqual(provider.fingerprint(for: .system), "system")

        for sound in ReminderSound.builtInCases {
            XCTAssertNotNil(provider.notificationSound(for: sound))
            XCTAssertTrue(provider.fingerprint(for: sound).hasPrefix("builtin:"))
        }
    }

    func testPreferencesFallsBackForUnknownValue() {
        let suiteName = "ReminderSoundTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertEqual(
            ReminderSoundPreferences.resolvedDefault(from: defaults),
            ReminderSoundPreferences.fallbackSound
        )

        defaults.set("unknown", forKey: ReminderSoundPreferences.defaultSoundKey)
        XCTAssertEqual(
            ReminderSoundPreferences.resolvedDefault(from: defaults),
            ReminderSoundPreferences.fallbackSound
        )

        defaults.set(
            ReminderSound.alarm.rawValue,
            forKey: ReminderSoundPreferences.defaultSoundKey
        )
        XCTAssertEqual(
            ReminderSoundPreferences.resolvedDefault(from: defaults),
            .alarm
        )
    }
}
