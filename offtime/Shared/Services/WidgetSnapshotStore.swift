import Foundation
import os

enum WidgetSnapshotStore {
    static let appGroupID = "group.lt.offtime"
    private static let storageKey = "widget.snapshot.v1"

    private static let logger = Logger(subsystem: "lt.offtime", category: "WidgetSnapshotStore")

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// App Group 是否可用（不可用时 App 与扩展都读写不到共享容器）
    static var isAppGroupAvailable: Bool { defaults != nil }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let defaults else {
            logger.error("App Group \(appGroupID, privacy: .public) 不可用：快照未写入，请检查 App 与 Widget 两个 Target 的 App Groups 能力")
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else {
            logger.error("Widget 快照编码失败")
            return
        }

        defaults.set(data, forKey: storageKey)
        // 扩展在独立进程读取共享容器：不落盘时可能读到旧值/空值，导致组件看起来「没有数据」。
        defaults.synchronize()

        let cityCount = snapshot.cities.count
        if defaults.data(forKey: storageKey) == nil {
            logger.error("Widget 快照写入校验失败（\(cityCount) 个城市）")
        } else {
            logger.debug("已发布 Widget 快照：\(cityCount) 个城市")
        }
    }

    static func load() -> WidgetSnapshot? {
        guard let defaults else {
            logger.error("App Group \(appGroupID, privacy: .public) 不可用：组件读不到共享快照")
            return nil
        }
        guard let data = defaults.data(forKey: storageKey) else {
            logger.debug("共享容器中还没有 Widget 快照：App 尚未发布过城市列表")
            return nil
        }
        do {
            return try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        } catch {
            logger.error("Widget 快照解码失败：\(error.localizedDescription)")
            return nil
        }
    }
}
