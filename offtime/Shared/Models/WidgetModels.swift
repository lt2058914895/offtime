import Foundation

struct WidgetCitySnapshot: Codable, Hashable, Identifiable {
    let id: String
    let cityName: String
    let cityEn: String
    let countryCode: String
    let timezoneId: String
    let workStartHour: Int
    let workEndHour: Int
    let isLocal: Bool
}

struct WidgetSnapshot: Codable, Hashable {
    let cities: [WidgetCitySnapshot]
    let localTimezoneId: String
    let use24Hour: Bool
    let updatedAt: Date
}

extension WidgetSnapshot {
    static func fallback(date: Date = Date()) -> WidgetSnapshot {
        let timezone = TimeZone.current
        let rawName = timezone.identifier.split(separator: "/").last.map(String.init) ?? timezone.identifier
        let cityName = rawName.replacingOccurrences(of: "_", with: " ")
        let city = WidgetCitySnapshot(
            id: "local",
            cityName: cityName,
            cityEn: cityName,
            countryCode: "",
            timezoneId: timezone.identifier,
            workStartHour: 9,
            workEndHour: 18,
            isLocal: true
        )

        return WidgetSnapshot(
            cities: [city],
            localTimezoneId: timezone.identifier,
            use24Hour: true,
            updatedAt: date
        )
    }

    /// 没有共享数据时的快照（App 从未发布过 / App Group 不可用）。
    /// 与 `fallback(date:)` 的区别：这里**不含任何城市**，让组件明确显示「打开 App 添加城市」，
    /// 而不是伪装成一个真实城市，掩盖数据链路的问题。
    static func empty(
        use24Hour: Bool = true,
        localTimezoneId: String = TimeZone.current.identifier,
        date: Date = Date()
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            cities: [],
            localTimezoneId: localTimezoneId,
            use24Hour: use24Hour,
            updatedAt: date
        )
    }

    /// 占位与预览用示例快照：只在系统的占位（redacted）渲染和 Xcode/组件画廊预览里使用。
    /// 组件画廊在 App 还没发布过数据时读不到共享快照，若直接返回空快照，大尺寸预览会
    /// 空掉一大片、看起来像「没有数据」；给几个示例城市能让预览反映真实排版。
    static func sample(date: Date = Date()) -> WidgetSnapshot {
        let localTimezoneId = "Asia/Shanghai"
        let cities = [
            WidgetCitySnapshot(
                id: "sample.shanghai",
                cityName: "上海",
                cityEn: "Shanghai",
                countryCode: "CN",
                timezoneId: localTimezoneId,
                workStartHour: 9,
                workEndHour: 18,
                isLocal: true
            ),
            WidgetCitySnapshot(
                id: "sample.tokyo",
                cityName: "东京",
                cityEn: "Tokyo",
                countryCode: "JP",
                timezoneId: "Asia/Tokyo",
                workStartHour: 9,
                workEndHour: 18,
                isLocal: false
            ),
            WidgetCitySnapshot(
                id: "sample.newyork",
                cityName: "纽约",
                cityEn: "New York",
                countryCode: "US",
                timezoneId: "America/New_York",
                workStartHour: 9,
                workEndHour: 18,
                isLocal: false
            )
        ]

        return WidgetSnapshot(
            cities: cities,
            localTimezoneId: localTimezoneId,
            use24Hour: true,
            updatedAt: date
        )
    }
}
