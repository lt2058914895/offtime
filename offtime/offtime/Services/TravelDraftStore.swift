import Foundation

struct TravelDraft: Codable, Equatable {
    var legs: [TravelLeg]
    var tripEndDate: Date
    var wakeTime: TravelScheduleTime
    var sleepTime: TravelScheduleTime
    var activeLegIndex: Int
}

final class TravelDraftStore {
    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "travel_draft_v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func load() -> TravelDraft? {
        guard let data = defaults.data(forKey: storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(TravelDraft.self, from: data)
    }

    func save(_ draft: TravelDraft) {
        guard let data = try? JSONEncoder().encode(draft) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
