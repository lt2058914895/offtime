import XCTest
import CryptoKit
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
            [.gentleMarimba, .crystalChime]
        )
        XCTAssertEqual(
            ReminderSound.proBuiltInCases,
            [.alarm, .classicBell, .digitalPulse, .waterDrop, .morningBirds, .rhythmTaps]
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
