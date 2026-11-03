import Foundation
import CryptoKit
import UserNotifications

/// 全局提醒音效。
enum ReminderSound: String, CaseIterable, Codable, Identifiable {
    case system
    case gentleMarimba
    case crystalChime
    case alarm
    case classicBell
    case digitalPulse
    case waterDrop
    case morningBirds
    case rhythmTaps

    static let freeBuiltInCases: [ReminderSound] = [
        .gentleMarimba,
        .crystalChime
    ]

    static let proBuiltInCases: [ReminderSound] = [
        .alarm,
        .classicBell,
        .digitalPulse,
        .waterDrop,
        .morningBirds,
        .rhythmTaps
    ]

    static let builtInCases = freeBuiltInCases + proBuiltInCases

    var id: String { rawValue }

    var requiresPro: Bool {
        switch self {
        case .system, .gentleMarimba, .crystalChime:
            return false
        case .alarm, .classicBell, .digitalPulse, .waterDrop, .morningBirds, .rhythmTaps:
            return true
        }
    }

    var displayName: String {
        switch self {
        case .system:
            return String(localized: "reminder.sound.system")
        case .gentleMarimba:
            return String(localized: "reminder.sound.gentleMarimba")
        case .crystalChime:
            return String(localized: "reminder.sound.crystalChime")
        case .alarm:
            return String(localized: "reminder.sound.alarm")
        case .classicBell:
            return String(localized: "reminder.sound.classicBell")
        case .digitalPulse:
            return String(localized: "reminder.sound.digitalPulse")
        case .waterDrop:
            return String(localized: "reminder.sound.waterDrop")
        case .morningBirds:
            return String(localized: "reminder.sound.morningBirds")
        case .rhythmTaps:
            return String(localized: "reminder.sound.rhythmTaps")
        }
    }

    var subtitle: String? {
        switch self {
        case .system:
            return String(localized: "reminder.sound.system.subtitle")
        case .gentleMarimba:
            return String(localized: "reminder.sound.gentleMarimba.subtitle")
        case .crystalChime:
            return String(localized: "reminder.sound.crystalChime.subtitle")
        case .alarm:
            return String(localized: "reminder.sound.alarm.subtitle")
        case .classicBell:
            return String(localized: "reminder.sound.classicBell.subtitle")
        case .digitalPulse:
            return String(localized: "reminder.sound.digitalPulse.subtitle")
        case .waterDrop:
            return String(localized: "reminder.sound.waterDrop.subtitle")
        case .morningBirds:
            return String(localized: "reminder.sound.morningBirds.subtitle")
        case .rhythmTaps:
            return String(localized: "reminder.sound.rhythmTaps.subtitle")
        }
    }

    var iconName: String {
        switch self {
        case .system:
            return "speaker.wave.2.fill"
        case .gentleMarimba:
            return "music.note"
        case .crystalChime:
            return "sparkles"
        case .alarm:
            return "alarm.fill"
        case .classicBell:
            return "bell.fill"
        case .digitalPulse:
            return "waveform.path.ecg"
        case .waterDrop:
            return "drop.fill"
        case .morningBirds:
            return "sun.max.fill"
        case .rhythmTaps:
            return "hand.tap.fill"
        }
    }

    var fileName: String? {
        switch self {
        case .system:
            return nil
        case .gentleMarimba:
            return "reminder-gentle-marimba.caf"
        case .crystalChime:
            return "reminder-crystal-chime.caf"
        case .alarm:
            return "reminder-alarm.caf"
        case .classicBell:
            return "reminder-classic-bell.caf"
        case .digitalPulse:
            return "reminder-digital-pulse.caf"
        case .waterDrop:
            return "reminder-water-drop.caf"
        case .morningBirds:
            return "reminder-morning-birds.caf"
        case .rhythmTaps:
            return "reminder-rhythm-taps.caf"
        }
    }

    var isBuiltIn: Bool { fileName != nil }

    func resourceURL(in bundle: Bundle = .main) -> URL? {
        guard let fileName else { return nil }
        let fileURL = URL(fileURLWithPath: fileName)
        let name = fileURL.deletingPathExtension().lastPathComponent
        let ext = fileURL.pathExtension

        return bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "ReminderSounds")
            ?? bundle.url(
                forResource: name,
                withExtension: ext,
                subdirectory: "Resources/ReminderSounds"
            )
    }
}

enum ReminderSoundPreferences {
    nonisolated static let defaultSoundKey = "settings_defaultReminderSound"
    nonisolated static let fallbackSound: ReminderSound = .system

    nonisolated static func resolvedDefault(from defaults: UserDefaults = .standard) -> ReminderSound {
        guard let rawValue = defaults.string(forKey: defaultSoundKey),
              let sound = ReminderSound(rawValue: rawValue) else {
            return fallbackSound
        }
        return sound
    }
}

protocol ReminderSoundProviding {
    func notificationSound(for sound: ReminderSound) -> UNNotificationSound?
    func fingerprint(for sound: ReminderSound) -> String
}

final class BuiltInReminderSoundProvider: ReminderSoundProviding {
    private let bundle: Bundle
    private var cachedFingerprints: [ReminderSound: String] = [:]

    nonisolated init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func notificationSound(for sound: ReminderSound) -> UNNotificationSound? {
        switch sound {
        case .system:
            return .default
        default:
            guard let fileName = sound.fileName,
                  sound.resourceURL(in: bundle) != nil else {
                return .default
            }
            return UNNotificationSound(named: UNNotificationSoundName(rawValue: fileName))
        }
    }

    func fingerprint(for sound: ReminderSound) -> String {
        if let cachedFingerprint = cachedFingerprints[sound] {
            return cachedFingerprint
        }

        let fingerprint = makeFingerprint(for: sound)
        cachedFingerprints[sound] = fingerprint
        return fingerprint
    }

    private func makeFingerprint(for sound: ReminderSound) -> String {
        switch sound {
        case .system:
            return "system"
        default:
            guard let fileName = sound.fileName else { return sound.rawValue }
            guard let url = sound.resourceURL(in: bundle),
                  let data = try? Data(contentsOf: url) else {
                return "missing:\(fileName)"
            }

            return Self.fingerprint(fileName: fileName, content: data)
        }
    }

    static func fingerprint(fileName: String, content: Data?) -> String {
        guard let content else {
            return "missing:\(fileName)"
        }

        let digest = SHA256.hash(data: content).map { byte in
            String(format: "%02x", byte)
        }.joined()
        return "builtin:\(fileName):\(digest)"
    }
}
