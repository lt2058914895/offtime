import Foundation
import SwiftData

/// 行程数据访问与旧草稿迁移。
@MainActor
final class TripStore {
    static let shared = TripStore()

    private let draftStore = TravelDraftStore()

    private init() {}

    /// 把旧版 UserDefaults 单草稿迁移为第一条行程（一次性，迁移后即清理）。
    func migrateLegacyDraftIfNeeded(context: ModelContext) {
        guard let draft = draftStore.load() else { return }
        let trip = TripModel(
            legs: draft.legs,
            tripEndDate: draft.tripEndDate,
            wakeTime: draft.wakeTime,
            sleepTime: draft.sleepTime
        )
        context.insert(trip)
        try? context.save()
        draftStore.clear()
    }

    func fetchTrip(id: UUID, context: ModelContext) -> TripModel? {
        var descriptor = FetchDescriptor<TripModel>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
