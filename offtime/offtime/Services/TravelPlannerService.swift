import Foundation

enum TravelDirection: Equatable {
    case same
    case behind
    case ahead
}

enum TravelAdjustmentLevel: Equatable {
    case none
    case small
    case medium
    case large
}

enum TravelTimelineEventKind: Equatable {
    case departure
    case arrival
    case wake
    case daylight
    case sleep
}

struct TravelTimelineEvent: Equatable, Identifiable {
    let kind: TravelTimelineEventKind
    let dayIndex: Int
    let destinationDate: Date
    let originDate: Date

    var id: String {
        "\(kind)-\(dayIndex)-\(destinationDate.timeIntervalSince1970)"
    }
}

struct TravelPlan: Equatable {
    let originName: String
    let destinationName: String
    let originTimezoneId: String
    let destinationTimezoneId: String
    let departureDate: Date
    let arrivalDate: Date
    let tripDays: Int
    let offsetMinutes: Int
    let offsetText: String
    let direction: TravelDirection
    let adjustmentLevel: TravelAdjustmentLevel
    let flightDuration: TimeInterval
    let flightDurationText: String
    let wakeTime: TravelScheduleTime
    let sleepTime: TravelScheduleTime
    let timeline: [TravelTimelineEvent]
}

struct TravelScheduleTime: Codable, Equatable {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        self.init(
            hour: min(max(components.hour ?? 0, 0), 23),
            minute: min(max(components.minute ?? 0, 0), 59)
        )
    }

    static let wake = TravelScheduleTime(hour: 7, minute: 0)
    static let sleep = TravelScheduleTime(hour: 22, minute: 0)

    var text: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

struct TravelLeg: Codable, Equatable, Identifiable {
    let id: UUID
    var origin: CitySuggestion
    var destination: CitySuggestion
    var departureDate: Date
    var arrivalDate: Date

    init(
        id: UUID = UUID(),
        origin: CitySuggestion,
        destination: CitySuggestion,
        departureDate: Date,
        arrivalDate: Date
    ) {
        self.id = id
        self.origin = origin
        self.destination = destination
        self.departureDate = departureDate
        self.arrivalDate = arrivalDate
    }
}

struct TravelItinerary: Equatable {
    let routeNames: [String]
    let plans: [TravelPlan]
}

enum TravelPlanError: Error, Equatable {
    case invalidArrival(index: Int?)
    case invalidTripDays(index: Int?)
    case invalidTimezone
    case invalidSequence(index: Int)
    case discontinuousRoute(index: Int)
}

final class TravelPlannerService {
    static let shared = TravelPlannerService()

    private init() {}

    func makePlan(
        origin: CitySuggestion,
        destination: CitySuggestion,
        departureDate: Date,
        arrivalDate: Date,
        tripDays: Int,
        wakeTime: TravelScheduleTime = .wake,
        sleepTime: TravelScheduleTime = .sleep
    ) throws -> TravelPlan {
        guard arrivalDate > departureDate else {
            throw TravelPlanError.invalidArrival(index: nil)
        }
        guard (1...30).contains(tripDays) else {
            throw TravelPlanError.invalidTripDays(index: nil)
        }

        guard let originTimezone = TimeZone(identifier: origin.timezoneId),
              let destinationTimezone = TimeZone(identifier: destination.timezoneId) else {
            throw TravelPlanError.invalidTimezone
        }

        let offsetMinutes = Self.offsetMinutes(
            originTimezone: originTimezone,
            destinationTimezone: destinationTimezone,
            date: departureDate
        )
        let flightDuration = arrivalDate.timeIntervalSince(departureDate)
        let timeline = Self.timeline(
            departureDate: departureDate,
            arrivalDate: arrivalDate,
            tripDays: tripDays,
            originTimezone: originTimezone,
            destinationTimezone: destinationTimezone,
            wakeTime: wakeTime,
            sleepTime: sleepTime
        )

        return TravelPlan(
            originName: origin.cityName,
            destinationName: destination.cityName,
            originTimezoneId: origin.timezoneId,
            destinationTimezoneId: destination.timezoneId,
            departureDate: departureDate,
            arrivalDate: arrivalDate,
            tripDays: tripDays,
            offsetMinutes: offsetMinutes,
            offsetText: Self.offsetText(minutes: offsetMinutes),
            direction: Self.direction(minutes: offsetMinutes),
            adjustmentLevel: Self.adjustmentLevel(minutes: offsetMinutes),
            flightDuration: flightDuration,
            flightDurationText: Self.durationText(flightDuration),
            wakeTime: wakeTime,
            sleepTime: sleepTime,
            timeline: timeline
        )
    }

    func makeItinerary(
        legs: [TravelLeg],
        tripEndDate: Date,
        wakeTime: TravelScheduleTime = .wake,
        sleepTime: TravelScheduleTime = .sleep
    ) throws -> TravelItinerary {
        guard let firstLeg = legs.first else {
            throw TravelPlanError.invalidSequence(index: 0)
        }

        for (index, leg) in legs.enumerated() {
            guard leg.arrivalDate > leg.departureDate else {
                throw TravelPlanError.invalidArrival(index: index)
            }

            if index > 0 {
                let previousLeg = legs[index - 1]
                guard leg.origin.id == previousLeg.destination.id else {
                    throw TravelPlanError.discontinuousRoute(index: index)
                }
                guard leg.departureDate > previousLeg.arrivalDate else {
                    throw TravelPlanError.invalidSequence(index: index)
                }
            }
        }

        var plans: [TravelPlan] = []
        for (index, leg) in legs.enumerated() {
            let plannedDays = index == legs.count - 1
                ? try Self.finalStopDays(
                    arrivalDate: leg.arrivalDate,
                    endDate: tripEndDate,
                    timezoneId: leg.destination.timezoneId,
                    legIndex: index
                )
                : Self.stopDays(
                    arrivalDate: leg.arrivalDate,
                    nextDepartureDate: legs[index + 1].departureDate,
                    timezoneId: leg.destination.timezoneId
                )

            plans.append(try makePlan(
                origin: leg.origin,
                destination: leg.destination,
                departureDate: leg.departureDate,
                arrivalDate: leg.arrivalDate,
                tripDays: plannedDays,
                wakeTime: wakeTime,
                sleepTime: sleepTime
            ))
        }

        return TravelItinerary(
            routeNames: [firstLeg.origin.cityName] + legs.map(\.destination.cityName),
            plans: plans
        )
    }

    private static func finalStopDays(
        arrivalDate: Date,
        endDate: Date,
        timezoneId: String,
        legIndex: Int
    ) throws -> Int {
        guard let timezone = TimeZone(identifier: timezoneId) else {
            throw TravelPlanError.invalidTimezone
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let arrivalDay = calendar.startOfDay(for: arrivalDate)
        let endDay = calendar.startOfDay(for: endDate)
        let days = calendar.dateComponents([.day], from: arrivalDay, to: endDay).day ?? -1
        let tripDays = days + 1

        guard (1...30).contains(tripDays) else {
            throw TravelPlanError.invalidTripDays(index: legIndex)
        }

        return tripDays
    }

    private static func stopDays(
        arrivalDate: Date,
        nextDepartureDate: Date,
        timezoneId: String
    ) -> Int {
        guard let timezone = TimeZone(identifier: timezoneId) else { return 1 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let arrivalDay = calendar.startOfDay(for: arrivalDate)
        let departureDay = calendar.startOfDay(for: nextDepartureDate)
        let days = calendar.dateComponents([.day], from: arrivalDay, to: departureDay).day ?? 0
        return min(max(days + 1, 1), 30)
    }

    private static func offsetMinutes(
        originTimezone: TimeZone,
        destinationTimezone: TimeZone,
        date: Date
    ) -> Int {
        let difference = destinationTimezone.secondsFromGMT(for: date) -
            originTimezone.secondsFromGMT(for: date)
        return Int((Double(difference) / 60).rounded())
    }

    private static func direction(minutes: Int) -> TravelDirection {
        if minutes > 0 { return .ahead }
        if minutes < 0 { return .behind }
        return .same
    }

    private static func adjustmentLevel(minutes: Int) -> TravelAdjustmentLevel {
        let absoluteMinutes = abs(minutes)
        if absoluteMinutes == 0 { return .none }
        if absoluteMinutes <= 180 { return .small }
        if absoluteMinutes <= 360 { return .medium }
        return .large
    }

    private static func offsetText(minutes: Int) -> String {
        if minutes == 0 { return "0h" }

        let sign = minutes < 0 ? "-" : "+"
        let absoluteMinutes = abs(minutes)
        let hours = absoluteMinutes / 60
        let remainder = absoluteMinutes % 60

        if hours == 0 { return "\(sign)\(remainder)m" }
        if remainder == 0 { return "\(sign)\(hours)h" }
        return "\(sign)\(hours)h\(remainder)m"
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = max(Int((duration / 60).rounded()), 1)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h\(minutes)m"
    }

    private static func timeline(
        departureDate: Date,
        arrivalDate: Date,
        tripDays: Int,
        originTimezone: TimeZone,
        destinationTimezone: TimeZone,
        wakeTime: TravelScheduleTime,
        sleepTime: TravelScheduleTime
    ) -> [TravelTimelineEvent] {
        var destinationCalendar = Calendar(identifier: .gregorian)
        destinationCalendar.timeZone = destinationTimezone

        guard let firstDay = destinationCalendar.dateInterval(of: .day, for: arrivalDate)?.start else {
            return []
        }

        var events: [TravelTimelineEvent] = [
            event(.departure, dayIndex: 1, date: departureDate),
            event(.arrival, dayIndex: 1, date: arrivalDate)
        ]

        for dayOffset in 0..<tripDays {
            guard let dayStart = destinationCalendar.date(byAdding: .day, value: dayOffset, to: firstDay) else {
                continue
            }
            let dayIndex = dayOffset + 1

            let scheduleEvents: [(TravelTimelineEventKind, TravelScheduleTime)] = [
                (.wake, wakeTime),
                (.daylight, TravelScheduleTime(hour: 12, minute: 0)),
                (.sleep, sleepTime)
            ]

            for (kind, time) in scheduleEvents {
                guard let eventDate = destinationCalendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: dayStart),
                      eventDate >= arrivalDate else {
                    continue
                }
                events.append(
                    event(
                        kind,
                        dayIndex: dayIndex,
                        date: eventDate
                    )
                )
            }
        }

        return events.sorted { $0.destinationDate < $1.destinationDate }
    }

    private static func event(
        _ kind: TravelTimelineEventKind,
        dayIndex: Int,
        date: Date
    ) -> TravelTimelineEvent {
        TravelTimelineEvent(
            kind: kind,
            dayIndex: dayIndex,
            destinationDate: date,
            originDate: date
        )
    }
}
