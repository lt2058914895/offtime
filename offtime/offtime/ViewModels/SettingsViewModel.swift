import Foundation
import Combine
import SwiftData

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var use24Hour: Bool = AppSettings.defaults.use24Hour
    @Published var themeMode: ThemeMode = AppSettings.defaults.themeMode
    @Published var reminderCount = 0
    @Published var errorMessage: String?
    
    private let cityService = CityService.shared
    private var reminderCountTask: Task<Void, Never>?
    
    init() {
        loadSettings()
    }
    
    private func loadSettings() {
        use24Hour = UserDefaults.standard.object(forKey: "settings_use24Hour") as? Bool
            ?? Locale.systemUses24Hour
        let themeRaw = UserDefaults.standard.integer(forKey: "settings_themeMode")
        themeMode = ThemeMode(rawValue: themeRaw) ?? .system
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(use24Hour, forKey: "settings_use24Hour")
        UserDefaults.standard.set(themeMode.rawValue, forKey: "settings_themeMode")
    }
    
    func toggle24Hour() {
        saveSettings()
    }

    func refreshReminderCount() {
        reminderCountTask?.cancel()
        guard let modelContainer = cityService.modelContainer else {
            reminderCount = 0
            return
        }
        reminderCountTask = Task { [weak self] in
            let count = await Self.fetchReminderCount(in: modelContainer)
            guard !Task.isCancelled else { return }
            self?.reminderCount = count
        }
    }

    nonisolated private static func fetchReminderCount(in modelContainer: ModelContainer) async -> Int {
        await Task.detached(priority: .utility) {
            let context = ModelContext(modelContainer)
            return (try? context.fetchCount(FetchDescriptor<ReminderModel>())) ?? 0
        }.value
    }
    
    func updateTheme(_ mode: ThemeMode) {
        themeMode = mode
        saveSettings()
    }
    
    func exportCities() -> Data? {
        do {
            return try CityService.shared.exportCities()
        } catch {
            errorMessage = String(localized: "settings.export.failed")
            return nil
        }
    }
    
    func importCities(from data: Data, strategy: ImportStrategy) -> Bool {
        do {
            try CityService.shared.importCities(from: data, strategy: strategy)
            Haptics.success()
            return true
        } catch {
            errorMessage = String(localized: "settings.import.failed")
            Haptics.error()
            return false
        }
    }
    
    func dismissError() {
        errorMessage = nil
    }
}
