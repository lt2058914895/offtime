import Foundation
import os

/// 组件快照的共享存储：App 写入、Widget 扩展读取。
///
/// 存的是 App Group 容器里的一个文件，而不是 UserDefaults：
/// UserDefaults 的值会缓存在各进程内，扩展进程不保证马上看到 App 刚写入的新值，
/// 表现出来就是「在 App 里加了城市，组件却还是旧的」——直到扩展进程重建或时间线
/// 重新请求（最长约 1 小时）才刷新。文件每次读都是最新内容，不存在跨进程缓存不一致。
///
/// 兼容：旧版本写在 UserDefaults（`legacyStorageKey`），这里保留读取回退，
/// 已装用户升级后不会因为换了存储位置而读到空数据。
enum WidgetSnapshotStore {
    static let appGroupID = "group.lt.offtime"
    /// 旧版本的存储位置（UserDefaults），仅用于读取回退
    private static let legacyStorageKey = "widget.snapshot.v1"
    private static let fileName = "widget-snapshot.json"

    private static let logger = Logger(subsystem: "lt.offtime", category: "WidgetSnapshotStore")

    /// App Group 容器目录（不可用时为 nil：App 与扩展都读写不到共享数据）
    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static var fileURL: URL? {
        containerURL?.appendingPathComponent(fileName, isDirectory: false)
    }

    private static var legacyDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// App Group 是否可用（不可用时 App 与扩展都读写不到共享容器）
    static var isAppGroupAvailable: Bool { containerURL != nil }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            logger.error("Widget 快照编码失败")
            return
        }
        guard let fileURL else {
            logger.error("App Group \(appGroupID, privacy: .public) 不可用：快照未写入，请检查 App 与 Widget 两个 Target 的 App Groups 能力")
            return
        }

        do {
            // .atomic：先写临时文件再替换，读侧不会拿到写了一半的 JSON
            try data.write(to: fileURL, options: [.atomic])
            logger.debug("已发布 Widget 快照：\(snapshot.cities.count) 个城市")
        } catch {
            logger.error("Widget 快照写入失败：\(error.localizedDescription)")
        }
    }

    /// 文件里已写入的快照是否与 `snapshot` 内容相同（只读文件，不回退 UserDefaults）。
    ///
    /// 用于「内容没变就别再请求刷新」的判断：文件还不存在时（升级后首次发布）
    /// 一律返回 false，让调用方照常写入，把数据从旧位置迁到文件。
    static func isUpToDate(with snapshot: WidgetSnapshot) -> Bool {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let stored = decode(data)
        else { return false }

        return stored.hasSameContent(as: snapshot)
    }

    static func load() -> WidgetSnapshot? {
        if let fileURL, let data = try? Data(contentsOf: fileURL), let snapshot = decode(data) {
            return snapshot
        }

        // 回退：升级前的快照还在 UserDefaults 里（下次发布时会写到文件中）
        guard let legacy = legacyDefaults?.data(forKey: legacyStorageKey) else {
            logger.debug("共享容器中还没有 Widget 快照：App 尚未发布过城市列表")
            return nil
        }
        return decode(legacy)
    }

    private static func decode(_ data: Data) -> WidgetSnapshot? {
        do {
            return try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        } catch {
            logger.error("Widget 快照解码失败：\(error.localizedDescription)")
            return nil
        }
    }
}
