import Combine
import Foundation

@MainActor
final class NotificationNavigationCenter: ObservableObject {
    static let shared = NotificationNavigationCenter()

    @Published private(set) var pendingMeetingID: UUID?

    private init() {}

    func openMeeting(_ meetingID: UUID) {
        pendingMeetingID = meetingID
    }

    func clearMeeting() {
        pendingMeetingID = nil
    }
}
