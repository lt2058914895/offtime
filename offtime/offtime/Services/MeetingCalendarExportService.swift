import Foundation

struct MeetingCalendarParticipant: Hashable {
    let cityName: String
    let cityEn: String
    let timezoneId: String?
}

struct MeetingCityTimezoneCandidate: Hashable {
    let cityName: String
    let cityEn: String
    let timezoneId: String
}

enum MeetingCityTimezoneResolver {
    /// 旧记录没有保存时区时，仅在城市目录能唯一确定时区时回填。
    static func timezoneId(
        cityName: String,
        cityEn: String,
        candidates: [MeetingCityTimezoneCandidate],
        preferredTimezoneId: String? = nil
    ) -> String? {
        guard !candidates.isEmpty else { return nil }

        let normalizedEnglishName = CityIdentity.normalizedEnglishName(cityEn)
        let exactMatches = normalizedEnglishName.isEmpty ? [] : candidates.filter {
            $0.cityName == cityName &&
            CityIdentity.normalizedEnglishName($0.cityEn) == normalizedEnglishName
        }
        let chineseNameMatches = cityName.isEmpty ? [] : candidates.filter {
            $0.cityName == cityName
        }
        let englishNameMatches = normalizedEnglishName.isEmpty ? [] : candidates.filter {
            CityIdentity.normalizedEnglishName($0.cityEn) == normalizedEnglishName
        }
        let matches = [exactMatches, chineseNameMatches, englishNameMatches]
            .first(where: { !$0.isEmpty }) ?? []
        guard !matches.isEmpty else { return nil }

        if let preferredTimezoneId,
           matches.contains(where: { $0.timezoneId == preferredTimezoneId }) {
            return preferredTimezoneId
        }

        let timezoneIds = Set(
            matches.map(\.timezoneId).filter { TimeZone(identifier: $0) != nil }
        )
        return timezoneIds.count == 1 ? timezoneIds.first : nil
    }
}

struct MeetingCalendarEvent {
    let uid: String
    let startDate: Date
    let durationMinutes: Int
    let localTimezoneId: String
    let participants: [MeetingCalendarParticipant]
}

struct SharedCalendarFile: Identifiable {
    let id = UUID()
    let url: URL
}

enum MeetingCalendarExportService {
    static func makeICS(
        event: MeetingCalendarEvent,
        now: Date = Date(),
        locale: Locale = .current
    ) -> String {
        let endDate = event.startDate.addingTimeInterval(Double(event.durationMinutes) * 60)
        let lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//OffTime//Meeting Planner//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "BEGIN:VEVENT",
            "UID:\(event.uid)@offtime.lt",
            "DTSTAMP:\(utcTimestamp(now))",
            "DTSTART:\(utcTimestamp(event.startDate))",
            "DTEND:\(utcTimestamp(endDate))",
            "SUMMARY:\(escaped(summary(for: event)))",
            "DESCRIPTION:\(escaped(description(for: event, locale: locale)))",
            "STATUS:CONFIRMED",
            "TRANSP:OPAQUE",
            "SEQUENCE:0",
            "END:VEVENT",
            "END:VCALENDAR"
        ]

        return lines.map(folded).joined(separator: "\r\n") + "\r\n"
    }

    static func makeTemporaryFile(
        event: MeetingCalendarEvent,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> URL {
        cleanupExpiredTemporaryFiles(fileManager: fileManager)
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("OffTime-Meeting-Shares", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(fileName(for: event))
        try makeICS(event: event, now: now).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func removeTemporaryFile(at url: URL, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: url.deletingLastPathComponent())
    }

    static func cleanupExpiredTemporaryFiles(fileManager: FileManager = .default) {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("OffTime-Meeting-Shares", isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for entry in entries {
            guard let createdAt = try? entry.resourceValues(forKeys: [.creationDateKey]).creationDate,
                  createdAt < cutoff else {
                continue
            }
            try? fileManager.removeItem(at: entry)
        }
    }

    private static func fileName(for event: MeetingCalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: event.localTimezoneId) ?? .current
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "OffTime-Meeting-\(formatter.string(from: event.startDate)).ics"
    }

    private static func summary(for event: MeetingCalendarEvent) -> String {
        let names = event.participants.map {
            CityDisplay.primaryName(cityName: $0.cityName, cityEn: $0.cityEn)
        }
        guard !names.isEmpty else {
            return String(localized: "meeting.ics.summary.empty")
        }

        return names.joined(separator: String(localized: "meeting.slots.constraints.join"))
    }

    private static func description(for event: MeetingCalendarEvent, locale: Locale) -> String {
        let endDate = event.startDate.addingTimeInterval(Double(event.durationMinutes) * 60)
        var lines = [
            String(format: String(localized: "meeting.ics.duration"), event.durationMinutes)
        ]

        var unresolvedNames: [String] = []
        for participant in event.participants {
            let name = CityDisplay.primaryName(
                cityName: participant.cityName,
                cityEn: participant.cityEn
            )
            guard let timezoneId = participant.timezoneId,
                  let timezone = TimeZone(identifier: timezoneId) else {
                unresolvedNames.append(name)
                continue
            }

            let range = localRangeText(
                start: event.startDate,
                end: endDate,
                timezone: timezone,
                locale: locale
            )
            lines.append(
                String(
                    format: String(localized: "meeting.ics.participant"),
                    name,
                    range
                )
            )
        }

        if !unresolvedNames.isEmpty {
            let names = unresolvedNames.joined(
                separator: String(localized: "meeting.slots.constraints.join")
            )
            lines.append(
                String(format: String(localized: "meeting.ics.participants"), names)
            )

            let timezone = TimeZone(identifier: event.localTimezoneId) ?? .current
            let range = localRangeText(
                start: event.startDate,
                end: endDate,
                timezone: timezone,
                locale: locale
            )
            lines.append(
                String(format: String(localized: "meeting.ics.local_time"), range)
            )
        }

        return lines.joined(separator: "\n")
    }

    private static func localRangeText(
        start: Date,
        end: Date,
        timezone: TimeZone,
        locale: Locale
    ) -> String {
        let startDay = dayText(start, timezone: timezone, locale: locale)
        let endDay = dayText(end, timezone: timezone, locale: locale)
        let startTime = timeText(start, timezone: timezone, locale: locale)
        let endTime = timeText(end, timezone: timezone, locale: locale)

        if startDay == endDay {
            return "\(startDay) \(startTime)–\(endTime)"
        }
        return "\(startDay) \(startTime)–\(endDay) \(endTime)"
    }

    private static func dayText(_ date: Date, timezone: TimeZone, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timezone
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "yMMMMdEEEE",
            options: 0,
            locale: locale
        ) ?? "yyyy/MM/dd EEE"
        return formatter.string(from: date)
    }

    private static func timeText(_ date: Date, timezone: TimeZone, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timezone
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "jmm",
            options: 0,
            locale: locale
        ) ?? "HH:mm"
        return formatter.string(from: date)
    }

    private static func utcTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
    }

    private static func folded(_ line: String) -> String {
        var result = ""
        var current = ""
        var currentBytes = 0
        var limit = 75

        for character in line {
            let characterBytes = String(character).utf8.count
            if currentBytes + characterBytes > limit {
                result += current + "\r\n "
                current = String(character)
                currentBytes = characterBytes
                limit = 74
            } else {
                current.append(character)
                currentBytes += characterBytes
            }
        }

        return result + current
    }
}
