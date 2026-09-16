import Foundation

protocol MeetingPlannerProviding {
    static func workingHours(participant: MeetingParticipant, localTimezoneId: String, date: Date) -> [Bool]
    static func hourlyOverlap(participants: [MeetingParticipant], localTimezoneId: String, date: Date) -> MeetingOverlap
    static func windows(hourlyOverlap: [Bool], localTimezoneId: String, date: Date) -> [MeetingWindow]
    static func state(of participant: MeetingParticipant, at date: Date) -> MeetingParticipantState
    static func state(of participant: MeetingParticipant, from startDate: Date, to endDate: Date) -> MeetingParticipantState
    static func recommendedSlots(
        participants: [MeetingParticipant],
        localTimezoneId: String,
        durationMinutes: Int,
        startDate: Date,
        endDate: Date,
        date: Date,
        stepMinutes: Int
    ) -> [MeetingSlot]
    static func slotGroups(from slots: [MeetingSlot]) -> [MeetingSlotGroup]
    static func maxOverlapMinutes(
        participants: [MeetingParticipant],
        localTimezoneId: String,
        startDate: Date,
        endDate: Date,
        date: Date
    ) -> Int
    static func constraintParticipants(
        participants: [MeetingParticipant],
        localTimezoneId: String,
        startDate: Date,
        endDate: Date,
        date: Date
    ) -> [MeetingConstraint]
}

extension MeetingPlannerService: MeetingPlannerProviding {}
