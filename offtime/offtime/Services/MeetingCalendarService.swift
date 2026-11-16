import EventKit
import Foundation

enum MeetingCalendarWriteResult: Equatable {
    case created
    case updated
}

enum MeetingCalendarEventStatus: Equatable {
    case available
    case missing
    case accessDenied
}

enum MeetingCalendarServiceError: LocalizedError, Equatable {
    case accessDenied
    case noDefaultCalendar
    case invalidTimeRange
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return AppDisplay.text("meeting.calendar.error.access", AppDisplay.name)
        case .noDefaultCalendar:
            return String(localized: "meeting.calendar.error.noCalendar")
        case .invalidTimeRange:
            return String(localized: "meeting.calendar.error.invalidTime")
        case .saveFailed:
            return String(localized: "meeting.calendar.error.save")
        }
    }

    var requiresSettingsAction: Bool {
        self == .accessDenied
    }
}

@MainActor
final class MeetingCalendarService {
    static let shared = MeetingCalendarService()

    private let store = EKEventStore()
    private let eventIdentifiersKey = "meeting.calendar.eventIdentifiers.v1"
    private let eventStartDatesKey = "meeting.calendar.eventStartDates.v1"
    private var sessionEvents: [String: EKEvent] = [:]

    private init() {}

    func save(
        event: MeetingCalendarEvent,
        integrationKeyOverride: String? = nil,
        title: String? = nil,
        location: String? = nil,
        notes: String? = nil,
        url: URL? = nil,
        leadTimeMinutes: Int?
    ) async throws -> MeetingCalendarWriteResult {
        guard event.startDate < event.startDate.addingTimeInterval(
            Double(event.durationMinutes) * 60
        ) else {
            throw MeetingCalendarServiceError.invalidTimeRange
        }
        guard hasCalendarAccess else {
            throw MeetingCalendarServiceError.accessDenied
        }
        guard let calendar = store.defaultCalendarForNewEvents else {
            throw MeetingCalendarServiceError.noDefaultCalendar
        }

        let integrationKey = integrationKeyOverride ?? Self.integrationKey(for: event)
        var identifiers = storedEventIdentifiers()
        var startDates = storedEventStartDates()
        let existing = sessionEvents[integrationKey]
            ?? identifiers[integrationKey].flatMap(store.event(withIdentifier:))

        let calendarEvent = existing ?? EKEvent(eventStore: store)
        if existing == nil || calendarEvent.calendar == nil {
            calendarEvent.calendar = calendar
        }
        calendarEvent.title = title.flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
        } ?? MeetingCalendarExportService.summary(for: event)
        calendarEvent.startDate = event.startDate
        calendarEvent.endDate = event.startDate.addingTimeInterval(
            Double(event.durationMinutes) * 60
        )
        calendarEvent.timeZone = TimeZone(identifier: event.localTimezoneId) ?? .current
        calendarEvent.location = location?.trimmingCharacters(in: .whitespacesAndNewlines)
        calendarEvent.url = url
        calendarEvent.notes = notes ?? MeetingCalendarExportService.description(
            for: event,
            locale: .current
        )

        calendarEvent.alarms?.forEach(calendarEvent.removeAlarm)
        if let leadTimeMinutes {
            calendarEvent.addAlarm(
                EKAlarm(relativeOffset: -Double(max(leadTimeMinutes, 0)) * 60)
            )
        }

        do {
            try store.save(calendarEvent, span: .thisEvent, commit: true)
        } catch {
            throw MeetingCalendarServiceError.saveFailed
        }

        let result: MeetingCalendarWriteResult = existing == nil ? .created : .updated
        identifiers[integrationKey] = calendarEvent.eventIdentifier
        startDates[integrationKey] = event.startDate.timeIntervalSinceReferenceDate
        UserDefaults.standard.set(identifiers, forKey: eventIdentifiersKey)
        UserDefaults.standard.set(startDates, forKey: eventStartDatesKey)
        sessionEvents[integrationKey] = calendarEvent
        return result
    }

    func hasSavedEvent(for event: MeetingCalendarEvent) -> Bool {
        guard hasCalendarAccess else { return false }
        return storedEventIdentifiers()[Self.integrationKey(for: event)] != nil
    }

    /// 使用日历读取权限核对已记录的事件是否仍存在；用户从 Calendar 删除后清除本地状态。
    func refreshSavedEvent(for event: MeetingCalendarEvent) async -> Bool {
        await eventStatus(for: event) == .available
    }

    func eventStatus(for event: MeetingCalendarEvent) async -> MeetingCalendarEventStatus {
        let integrationKey = Self.integrationKey(for: event)
        guard let identifier = storedEventIdentifiers()[integrationKey] else {
            return .missing
        }

        guard hasCalendarAccess else {
            return .accessDenied
        }

        if store.event(withIdentifier: identifier) != nil {
            return .available
        }

        var identifiers = storedEventIdentifiers()
        var startDates = storedEventStartDates()
        identifiers.removeValue(forKey: integrationKey)
        startDates.removeValue(forKey: integrationKey)
        UserDefaults.standard.set(identifiers, forKey: eventIdentifiersKey)
        UserDefaults.standard.set(startDates, forKey: eventStartDatesKey)
        sessionEvents.removeValue(forKey: integrationKey)
        return .missing
    }

    /// 仅在用户主动选择“添加到日历”时调用。
    func requestAccessIfNeeded() async -> Bool {
        await requestCalendarAccess()
    }

    func savedStartDate(for event: MeetingCalendarEvent) -> Date? {
        guard let timestamp = storedEventStartDates()[Self.integrationKey(for: event)] else {
            return nil
        }
        return Date(timeIntervalSinceReferenceDate: timestamp)
    }

    static func integrationKey(for event: MeetingCalendarEvent) -> String {
        let participants = event.participants.map {
            "\(CityIdentity.normalizedEnglishName($0.cityEn))|\($0.timezoneId ?? "")"
        }.sorted()
        return [
            String(format: "%.0f", event.startDate.timeIntervalSince1970),
            String(event.durationMinutes),
            event.localTimezoneId,
            participants.joined(separator: ",")
        ].joined(separator: "#")
    }

    /// Calendar 的 `calshow` 链接使用 Apple 参考日期（2001-01-01 UTC），不是 Unix 时间戳。
    static func calendarDeepLink(for date: Date) -> URL? {
        let referenceTimestamp = Int(date.timeIntervalSinceReferenceDate.rounded())
        return URL(string: "calshow:\(referenceTimestamp)")
    }

    private var hasCalendarAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .fullAccess || status == .authorized
    }

    private func requestCalendarAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .writeOnly:
            return await withCheckedContinuation { continuation in
                store.requestFullAccessToEvents { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                store.requestFullAccessToEvents { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        case .authorized:
            return true
        @unknown default:
            return false
        }
    }

    private func storedEventIdentifiers() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: eventIdentifiersKey) as? [String: String] ?? [:]
    }

    private func storedEventStartDates() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: eventStartDatesKey) as? [String: Double] ?? [:]
    }
}
