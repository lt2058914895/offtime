import SwiftUI
import Combine

@MainActor
final class ReminderListViewModel: ObservableObject {
    @Published var reminders: [CityReminderGroup] = []
    @Published var isLoading = false

    private let reminderService = CityReminderService()

    func loadReminders() async {
        isLoading = true
        reminders = await reminderService.allReminders()
        isLoading = false
    }

    func deleteReminder(_ reminder: CityReminderGroup) async {
        await reminderService.removeReminder(id: reminder.id)
        reminders.removeAll { $0.id == reminder.id }
    }
}