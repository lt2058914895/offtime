import Foundation
import SwiftData
import WidgetKit
import os

@MainActor
enum WidgetSnapshotService {
    private static let logger = Logger(subsystem: "lt.offtime", category: "WidgetSnapshotService")
    static func publish(modelContainer: ModelContainer, settings: AppSettings) {
        do {
            let descriptor = FetchDescriptor<CityModel>(sortBy: [SortDescriptor(\.sortIndex)])
            let cities = try modelContainer.mainContext.fetch(descriptor)
            let localTimezoneId = settings.currentCityTimezoneId ?? TimeZone.current.identifier

            let snapshots = cities.map { city in
                WidgetCitySnapshot(
                    id: city.id.uuidString,
                    cityName: city.cityName,
                    cityEn: city.cityEn,
                    countryCode: city.country,
                    timezoneId: city.timezoneId,
                    workStartHour: city.workStartHour,
                    workEndHour: city.workEndHour,
                    isLocal: city.timezoneId == localTimezoneId
                )
            }

            let snapshot = WidgetSnapshot(
                cities: snapshots,
                localTimezoneId: localTimezoneId,
                use24Hour: settings.use24Hour,
                updatedAt: Date()
            )

            // 内容没变化就不写盘、也不请求刷新：WidgetKit 的刷新次数有配额，
            // 被浪费掉会让真正需要刷新的时候（加了城市）反而刷不出来。
            if WidgetSnapshotStore.isUpToDate(with: snapshot) {
                logger.debug("Widget 快照内容未变化，跳过刷新")
                return
            }

            guard WidgetSnapshotStore.save(snapshot) else { return }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            logger.error("发布 Widget 快照失败: \(error.localizedDescription)")
        }
    }

}
