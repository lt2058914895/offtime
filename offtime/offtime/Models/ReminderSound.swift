import Foundation
import CryptoKit
import UserNotifications

/// 全局提醒音效。
enum ReminderSound: String, CaseIterable, Codable, Identifiable {
    case system
    case gentleMarimba
    case alarm
    case digitalPulse
    case rhythmTaps

    static let freeBuiltInCases: [ReminderSound] = [
        .gentleMarimba
    ]

    static let proBuiltInCases: [ReminderSound] = [
        .alarm,
        .digitalPulse,
        .rhythmTaps
    ]

    static let builtInCases = freeBuiltInCases + proBuiltInCases

    var id: String { rawValue }

    var requiresPro: Bool {
        switch self {
        case .system, .gentleMarimba:
            return false
        case .alarm, .digitalPulse, .rhythmTaps:
            return true
        }
    }

    var displayName: String {
        switch self {
        case .system:
            return String(localized: "reminder.sound.system")
        case .gentleMarimba:
            return String(localized: "reminder.sound.gentleMarimba")
        case .alarm:
            return String(localized: "reminder.sound.alarm")
        case .digitalPulse:
            return String(localized: "reminder.sound.digitalPulse")
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
        case .alarm:
            return String(localized: "reminder.sound.alarm.subtitle")
        case .digitalPulse:
            return String(localized: "reminder.sound.digitalPulse.subtitle")
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
        case .alarm:
            return "alarm.fill"
        case .digitalPulse:
            return "waveform.path.ecg"
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
        case .alarm:
            return "reminder-alarm.caf"
        case .digitalPulse:
            return "reminder-digital-pulse.caf"
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

    /// 把任意来源的音效收敛成当前用户实际可用的音效。
    /// Pro 专属音效在权益失效后统一回退到系统默认音效。
    nonisolated static func accessibleSound(
        for sound: ReminderSound,
        isProUnlocked: Bool
    ) -> ReminderSound {
        guard sound.requiresPro, !isProUnlocked else {
            return sound
        }
        return fallbackSound
    }

    /// 只读取已保存值，不修改存储。未知值按系统默认音效处理。
    nonisolated static func storedDefault(from defaults: UserDefaults = .standard) -> ReminderSound {
        guard let rawValue = defaults.string(forKey: defaultSoundKey) else {
            return fallbackSound
        }
        if let sound = ReminderSound(rawValue: rawValue) {
            return sound
        }
        return fallbackSound
    }

    /// 读取并校准全局音效；如果保存值已不可用，会同步写回回退值。
    @discardableResult
    nonisolated static func resolvedDefault(
        from defaults: UserDefaults = .standard,
        isProUnlocked: Bool
    ) -> ReminderSound {
        let storedRawValue = defaults.string(forKey: defaultSoundKey)
        let stored = storedDefault(from: defaults)
        let accessible = accessibleSound(for: stored, isProUnlocked: isProUnlocked)
        if storedRawValue != accessible.rawValue {
            defaults.set(accessible.rawValue, forKey: defaultSoundKey)
        }
        return accessible
    }

    /// 保存前再次校验 Pro 权限，避免绕过 UI 写入不可用音效。
    @discardableResult
    nonisolated static func saveDefault(
        _ sound: ReminderSound,
        to defaults: UserDefaults = .standard,
        isProUnlocked: Bool
    ) -> ReminderSound {
        let accessible = accessibleSound(for: sound, isProUnlocked: isProUnlocked)
        defaults.set(accessible.rawValue, forKey: defaultSoundKey)
        return accessible
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
