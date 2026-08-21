import Combine
import Foundation

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

    private let planner: TravelPlannerService
    private let draftStore: TravelDraftStore

    init(
        now: Date = Date(),
        planner: TravelPlannerService = .shared,
        draftStore: TravelDraftStore = TravelDraftStore()
    ) {
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
        self.planner = planner
        self.draftStore = draftStore

        if let draft = draftStore.load() {
            self.legs = draft.legs
            self.tripEndDate = draft.tripEndDate
            self.wakeTime = draft.wakeTime
            self.sleepTime = draft.sleepTime
            self.activeLegIndex = draft.activeLegIndex
        } else {
            self.legs = [
                TravelLeg(
                    origin: origin,
                    destination: destination,
                    departureDate: now,
                    arrivalDate: now.addingTimeInterval(13 * 60 * 60)
                )
            ]
            self.tripEndDate = now.addingTimeInterval(2 * 24 * 60 * 60)
            self.wakeTime = .wake
            self.sleepTime = .sleep
            self.activeLegIndex = 0
        }
        generateItinerary()
    }

    func generateItinerary() {
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
        saveDraft()
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

    private func defaultNextCity() -> CitySuggestion {
        CitySuggestion(
            id: "America/New_York",
            cityName: String(localized: "travel.city.new_york"),
            cityEn: "New York",
            timezoneId: "America/New_York",
            continent: "america"
        )
    }

    private func saveDraft() {
        draftStore.save(
            TravelDraft(
                legs: legs,
                tripEndDate: tripEndDate,
                wakeTime: wakeTime,
                sleepTime: sleepTime,
                activeLegIndex: activeLegIndex
            )
        )
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
