import Foundation
import CryptoKit
import UserNotifications

/// 全局提醒音效。
enum ReminderSound: String, CaseIterable, Codable, Identifiable {
    case system
    case gentleMarimba
    case alarm

    static let builtInCases: [ReminderSound] = [
        .gentleMarimba,
        .alarm
    ]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return String(localized: "reminder.sound.system")
        case .gentleMarimba:
            return String(localized: "reminder.sound.gentleMarimba")
        case .alarm:
            return String(localized: "reminder.sound.alarm")
        }
    }

    var subtitle: String? {
        switch self {
        case .system:
            return String(localized: "reminder.sound.system.subtitle")
        case .gentleMarimba:
            return String(localized: "reminder.sound.gentleMarimba.subtitle")
        case .alarm:
            return String(localized: "reminder.sound.alarm.subtitle")
        }
    }

    var iconName: String {
        switch self {
        case .system:
            return "speaker.wave.2.fill"
        case .gentleMarimba:
            return "music.note"
        case .alarm:
            return "alarm.fill"
        }
    }

    var fileName: String? {
        switch self {
        case .system:
            return nil
        case .gentleMarimba:
            return "reminder-gentle-marimba.caf"
        case .alarm:
            return "reminder-alarm.caf"
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
    static let defaultSoundKey = "settings_defaultReminderSound"
    static let fallbackSound: ReminderSound = .system

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
        case .gentleMarimba, .alarm:
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
        case .gentleMarimba, .alarm:
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
