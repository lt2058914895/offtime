import Foundation
import SwiftData

// MARK: - 行程状态

/// 行程生命周期状态：由当前时间与行程日期自动推导，不落库。
enum TripStatus: Int, CaseIterable, Identifiable, Codable {
    case ongoing = 0
    case upcoming = 1
    case finished = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .ongoing: return String(localized: "trip.status.ongoing")
        case .upcoming: return String(localized: "trip.status.upcoming")
        case .finished: return String(localized: "trip.status.finished")
        }
    }
}

// MARK: - SwiftData 持久化模型：用户保存的行程

/// 一次行程 = 多段行程(legs) + 结束日期 + 作息时间。
/// 状态（未开始/进行中/已结束）由时间自动推导，避免冗余字段。
@Model
final class TripModel {
    var id: UUID
    /// [TravelLeg] 的 JSON 编码，避免为每段行程单独建表
    var legsData: Data
    var tripEndDate: Date
    var wakeHour: Int
    var wakeMinute: Int
    var sleepHour: Int
    var sleepMinute: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        legs: [TravelLeg],
        tripEndDate: Date,
        wakeTime: TravelScheduleTime = .wake,
        sleepTime: TravelScheduleTime = .sleep,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.legsData = (try? JSONEncoder().encode(legs)) ?? Data()
        self.tripEndDate = tripEndDate
        self.wakeHour = wakeTime.hour
        self.wakeMinute = wakeTime.minute
        self.sleepHour = sleepTime.hour
        self.sleepMinute = sleepTime.minute
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var legs: [TravelLeg] {
        get { (try? JSONDecoder().decode([TravelLeg].self, from: legsData)) ?? [] }
        set { legsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var wakeTime: TravelScheduleTime {
        TravelScheduleTime(hour: wakeHour, minute: wakeMinute)
    }

    var sleepTime: TravelScheduleTime {
        TravelScheduleTime(hour: sleepHour, minute: sleepMinute)
    }

    /// 首段出发时间
    var firstDeparture: Date? {
        legs.first?.departureDate
    }

    /// 路线文案：上海 → 洛杉矶 → 纽约
    var routeText: String {
        guard let firstLeg = legs.first else { return "" }
        let names = [firstLeg.origin.cityName] + legs.map(\.destination.cityName)
        return names.joined(separator: " → ")
    }

    /// 行程区间终点：结束日期当天结束（按最后目的地时区），用于状态与冲突判断。
    var rangeEnd: Date {
        Self.endOfDay(
            tripEndDate,
            timezoneId: legs.last?.destination.timezoneId ?? TimeZone.current.identifier
        )
    }

    /// 与另一行程的时间区间（首段出发 ~ 结束日期当天结束）是否重叠。
    func overlaps(_ other: TripModel) -> Bool {
        guard let start = firstDeparture, let otherStart = other.firstDeparture else {
            return false
        }
        return start < other.rangeEnd && otherStart < rangeEnd
    }

    var status: TripStatus {
        status(at: Date())
    }

    func status(at date: Date) -> TripStatus {
        Self.status(
            at: date,
            firstDeparture: firstDeparture,
            tripEndDate: tripEndDate,
            timezoneId: legs.last?.destination.timezoneId ?? TimeZone.current.identifier
        )
    }

    /// 状态推导规则（纯函数，便于测试）：
    /// - 现在早于首段出发 → 未开始
    /// - 首段出发 ~ 结束日期当天结束（目的地时区）→ 进行中
    /// - 结束日期当天结束之后 → 已结束
    static func status(
        at date: Date,
        firstDeparture: Date?,
        tripEndDate: Date,
        timezoneId: String
    ) -> TripStatus {
        guard let firstDeparture else { return .upcoming }
        if date < firstDeparture { return .upcoming }

        return date < endOfDay(tripEndDate, timezoneId: timezoneId) ? .ongoing : .finished
    }

    /// 某日期在其所属时区下的当天结束时刻（次日 00:00）。
    static func endOfDay(_ date: Date, timezoneId: String) -> Date {
        let timezone = TimeZone(identifier: timezoneId) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) ?? date
    }

    /// 用编辑中的内容覆盖已有行程
    func update(
        legs: [TravelLeg],
        tripEndDate: Date,
        wakeTime: TravelScheduleTime,
        sleepTime: TravelScheduleTime
    ) {
        self.legs = legs
        self.tripEndDate = tripEndDate
        self.wakeHour = wakeTime.hour
        self.wakeMinute = wakeTime.minute
        self.sleepHour = sleepTime.hour
        self.sleepMinute = sleepTime.minute
        updatedAt = Date()
    }
}
