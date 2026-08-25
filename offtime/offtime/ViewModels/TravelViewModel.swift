import Combine
import Foundation
import SwiftData

/// 保存行程的结果：成功 / 与已有行程时间冲突 / 保存失败。
enum TripSaveResult: Equatable {
    case saved
    case conflict(UUID)
    case failed
}

@MainActor
final class TravelViewModel: ObservableObject {
    @Published var legs: [TravelLeg]
    @Published var tripEndDate: Date
    @Published var wakeTime: TravelScheduleTime
    @Published var sleepTime: TravelScheduleTime
    @Published var itinerary: TravelItinerary?
    @Published var activeLegIndex: Int
    @Published var errorMessage: String?
    @Published var invalidLegIndex: Int?
    @Published private(set) var isDirty = false

    private let planner: TravelPlannerService
    private var context: ModelContext?
    private var hasLoaded = false
    private var tripID: UUID?
    /// 上次保存到记录的字段快照，用于判断是否有未保存的修改。
    private var savedSnapshot: TripSnapshot?

    private struct TripSnapshot: Equatable {
        var legs: [TravelLeg]
        var tripEndDate: Date
        var wakeTime: TravelScheduleTime
        var sleepTime: TravelScheduleTime
    }

    init(
        now: Date = Date(),
        planner: TravelPlannerService = .shared
    ) {
        self.planner = planner
        self.legs = [Self.defaultLeg(now: now)]
        self.tripEndDate = now.addingTimeInterval(2 * 24 * 60 * 60)
        self.wakeTime = .wake
        self.sleepTime = .sleep
        self.activeLegIndex = 0
        generateItinerary()
    }

    /// 绑定 SwiftData 上下文并加载要编辑的行程（仅首次生效）。
    /// - initialTripID: 从行程列表进入时指定；为空（Tab 模式）加载离现在最近的已保存行程，
    ///   没有已保存行程时保持全新草稿，用于添加新行程。
    func attach(context: ModelContext, initialTripID: UUID? = nil) {
        self.context = context
        guard !hasLoaded else { return }
        hasLoaded = true

        if let initialTripID,
           let trip = TripStore.shared.fetchTrip(id: initialTripID, context: context) {
            apply(trip)
        } else if initialTripID == nil,
                  let nearest = mostRecentTrip(in: context) {
            apply(nearest)
        }
    }

    var activeLeg: TravelLeg? {
        legs.indices.contains(activeLegIndex) ? legs[activeLegIndex] : nil
    }

    var activePlan: TravelPlan? {
        guard let itinerary, itinerary.plans.indices.contains(activeLegIndex) else {
            return nil
        }
        return itinerary.plans[activeLegIndex]
    }

    /// 当前行程是否已保存为行程记录（未保存的草稿不展示状态标签）。
    var isSavedTrip: Bool {
        tripID != nil
    }

    /// 新建行程：重置为默认草稿，不写入存储，等待用户保存。
    func newTrip(now: Date = Date()) {
        tripID = nil
        savedSnapshot = nil
        legs = [Self.defaultLeg(now: now)]
        tripEndDate = now.addingTimeInterval(2 * 24 * 60 * 60)
        wakeTime = .wake
        sleepTime = .sleep
        activeLegIndex = 0
        generateItinerary()
    }

    func selectLeg(_ index: Int) {
        activeLegIndex = index
    }

    func selectOrigin(_ city: CitySuggestion, legIndex: Int) {
        guard legs.indices.contains(legIndex) else { return }
        legs[legIndex].origin = city
        if legIndex > 0 {
            legs[legIndex - 1].destination = city
        }
        generateItinerary()
    }

    func selectDestination(_ city: CitySuggestion, legIndex: Int) {
        guard legs.indices.contains(legIndex) else { return }
        legs[legIndex].destination = city
        if legs.indices.contains(legIndex + 1) {
            legs[legIndex + 1].origin = city
        }
        generateItinerary()
    }

    func swapCities() {
        guard legs.indices.contains(activeLegIndex) else { return }
        let selectedOrigin = legs[activeLegIndex].origin
        let selectedDestination = legs[activeLegIndex].destination
        legs[activeLegIndex].origin = selectedDestination
        legs[activeLegIndex].destination = selectedOrigin
        if activeLegIndex > 0 {
            legs[activeLegIndex - 1].destination = selectedDestination
        }
        if legs.indices.contains(activeLegIndex + 1) {
            legs[activeLegIndex + 1].origin = selectedOrigin
        }
        generateItinerary()
    }

    func updateDeparture(_ date: Date, legIndex: Int) {
        guard legs.indices.contains(legIndex) else { return }
        legs[legIndex].departureDate = date
        if legs[legIndex].arrivalDate <= date {
            legs[legIndex].arrivalDate = date.addingTimeInterval(60 * 60)
        }
        generateItinerary()
    }

    func updateArrival(_ date: Date, legIndex: Int) {
        guard legs.indices.contains(legIndex) else { return }
        legs[legIndex].arrivalDate = date
        if legs[legIndex].departureDate >= date {
            legs[legIndex].departureDate = date.addingTimeInterval(-60 * 60)
        }
        generateItinerary()
    }

    func updateTripEndDate(_ date: Date) {
        tripEndDate = date
        generateItinerary()
    }

    func updateWakeTime(_ date: Date) {
        wakeTime = TravelScheduleTime(date: date)
        generateItinerary()
    }

    func updateSleepTime(_ date: Date) {
        sleepTime = TravelScheduleTime(date: date)
        generateItinerary()
    }

    func addLeg() {
        guard let lastLeg = legs.last else { return }
        let departure = lastLeg.arrivalDate.addingTimeInterval(24 * 60 * 60)
        legs.append(
            TravelLeg(
                origin: lastLeg.destination,
                destination: defaultNextCity(),
                departureDate: departure,
                arrivalDate: departure.addingTimeInterval(5 * 60 * 60)
            )
        )
        activeLegIndex = legs.count - 1
        generateItinerary()
    }

    func removeLeg(_ index: Int) {
        guard legs.count > 1, legs.indices.contains(index) else { return }
        legs.remove(at: index)
        if index > 0, legs.indices.contains(index) {
            legs[index].origin = legs[index - 1].destination
        }
        activeLegIndex = min(activeLegIndex, legs.count - 1)
        generateItinerary()
    }

    /// 保存当前编辑：新行程插入，已保存行程原地更新。
    /// 与其它已保存行程的时间区间重叠时返回 .conflict，不写入。
    @discardableResult
    func save() -> TripSaveResult {
        guard let context else { return .failed }

        if let conflict = conflictingTrip(in: context) {
            return .conflict(conflict.id)
        }

        if let tripID,
           let existing = TripStore.shared.fetchTrip(id: tripID, context: context) {
            existing.update(
                legs: legs,
                tripEndDate: tripEndDate,
                wakeTime: wakeTime,
                sleepTime: sleepTime
            )
            try? context.save()
            savedSnapshot = TripSnapshot(
                legs: legs,
                tripEndDate: tripEndDate,
                wakeTime: wakeTime,
                sleepTime: sleepTime
            )
            isDirty = false
            return .saved
        }

        let trip = TripModel(
            legs: legs,
            tripEndDate: tripEndDate,
            wakeTime: wakeTime,
            sleepTime: sleepTime
        )
        context.insert(trip)
        try? context.save()
        tripID = trip.id
        savedSnapshot = TripSnapshot(
            legs: legs,
            tripEndDate: tripEndDate,
            wakeTime: wakeTime,
            sleepTime: sleepTime
        )
        isDirty = false
        return .saved
    }

    /// 查找与当前编辑时间区间（首段出发 ~ 结束日期当天结束）重叠的其它已保存行程（排除自身）。
    private func conflictingTrip(in context: ModelContext) -> TripModel? {
        let candidate = TripModel(
            legs: legs,
            tripEndDate: tripEndDate,
            wakeTime: wakeTime,
            sleepTime: sleepTime
        )
        let allTrips = (try? context.fetch(FetchDescriptor<TripModel>())) ?? []
        return allTrips.first { $0.id != tripID && candidate.overlaps($0) }
    }

    /// 按时间选择「离现在最近」的已保存行程：进行中 > 最近的未开始 > 最近结束。
    private func mostRecentTrip(in context: ModelContext) -> TripModel? {
        let allTrips = (try? context.fetch(FetchDescriptor<TripModel>())) ?? []
        guard !allTrips.isEmpty else { return nil }

        let now = Date()
        let ongoing = allTrips
            .filter { $0.status(at: now) == .ongoing }
            .min { ($0.firstDeparture ?? .distantFuture) < ($1.firstDeparture ?? .distantFuture) }
        if let ongoing { return ongoing }

        let upcoming = allTrips
            .filter { $0.status(at: now) == .upcoming }
            .min { ($0.firstDeparture ?? .distantFuture) < ($1.firstDeparture ?? .distantFuture) }
        if let upcoming { return upcoming }

        return allTrips
            .filter { $0.status(at: now) == .finished }
            .max { $0.tripEndDate < $1.tripEndDate }
    }

    private func apply(_ trip: TripModel) {
        tripID = trip.id
        legs = trip.legs.isEmpty ? [Self.defaultLeg(now: trip.tripEndDate)] : trip.legs
        tripEndDate = trip.tripEndDate
        wakeTime = trip.wakeTime
        sleepTime = trip.sleepTime
        activeLegIndex = 0
        savedSnapshot = TripSnapshot(
            legs: legs,
            tripEndDate: tripEndDate,
            wakeTime: wakeTime,
            sleepTime: sleepTime
        )
        isDirty = false
        generateItinerary()
    }

    private func defaultNextCity() -> CitySuggestion {
        CitySuggestion(
            id: "America/New_York",
            cityName: String(localized: "travel.city.new_york"),
            cityEn: "New York",
            timezoneId: "America/New_York",
            continent: "america"
        )
    }

    private static func defaultLeg(now: Date) -> TravelLeg {
        let origin = CitySuggestion(
            id: "Asia/Shanghai",
            cityName: String(localized: "travel.city.shanghai"),
            cityEn: "Shanghai",
            timezoneId: "Asia/Shanghai",
            continent: "asia"
        )
        let destination = CitySuggestion(
            id: "America/Los_Angeles",
            cityName: String(localized: "travel.city.los_angeles"),
            cityEn: "Los Angeles",
            timezoneId: "America/Los_Angeles",
            continent: "america"
        )
        return TravelLeg(
            origin: origin,
            destination: destination,
            departureDate: now,
            arrivalDate: now.addingTimeInterval(13 * 60 * 60)
        )
    }

    private func generateItinerary() {
        do {
            itinerary = try planner.makeItinerary(
                legs: legs,
                tripEndDate: tripEndDate,
                wakeTime: wakeTime,
                sleepTime: sleepTime
            )
            activeLegIndex = min(activeLegIndex, max(legs.count - 1, 0))
            errorMessage = nil
            invalidLegIndex = nil
        } catch let error as TravelPlanError {
            errorMessage = message(for: error)
            invalidLegIndex = errorLegIndex(error)
        } catch {
            errorMessage = String(localized: "travel.error.unknown")
            invalidLegIndex = nil
        }
        updateDirtyState()
    }

    /// 与上次保存的快照比较，标记是否有未保存的修改。
    private func updateDirtyState() {
        guard let savedSnapshot else {
            isDirty = false
            return
        }
        isDirty = savedSnapshot.legs != legs
            || savedSnapshot.tripEndDate != tripEndDate
            || savedSnapshot.wakeTime != wakeTime
            || savedSnapshot.sleepTime != sleepTime
    }

    private func message(for error: TravelPlanError) -> String {
        let text: String
        switch error {
        case .invalidArrival:
            text = String(localized: "travel.error.arrival")
        case .invalidTimezone:
            text = String(localized: "travel.error.timezone")
        case .invalidTripDays:
            return String(localized: "travel.error.trip.days")
        case .invalidSequence:
            text = String(localized: "travel.error.sequence")
        case .discontinuousRoute:
            text = String(localized: "travel.error.discontinuous")
        }

        guard let index = errorLegIndex(error) else {
            return text
        }
        return String(
            format: String(localized: "travel.error.leg.format"),
            index + 1,
            text
        )
    }

    private func errorLegIndex(_ error: TravelPlanError) -> Int? {
        switch error {
        case .invalidArrival(let index): return index
        case .invalidTripDays(let index): return index
        case .invalidSequence(let index): return index
        case .discontinuousRoute(let index): return index
        case .invalidTimezone: return nil
        }
    }
}
