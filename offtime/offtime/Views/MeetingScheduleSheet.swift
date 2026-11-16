import SwiftUI
import SwiftData
import UIKit

struct MeetingScheduleSheet: View {
    let payload: MeetingSharePayload
    let editingMeeting: MeetingModel?
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var draft: MeetingScheduleDraft
    @State private var pendingDestination: MeetingScheduleDestination?
    @State private var alert: MeetingScheduleAlert?
    @State private var conflictingSchedule: MeetingModel?

    private var isSaving: Bool {
        pendingDestination != nil
    }

    init(
        payload: MeetingSharePayload,
        editingMeeting: MeetingModel? = nil,
        onComplete: @escaping () -> Void
    ) {
        self.payload = payload
        self.editingMeeting = editingMeeting
        self.onComplete = onComplete
        let startDate = editingMeeting?.startDate ?? payload.event.startDate
        let durationMinutes = editingMeeting?.durationMinutes ?? payload.event.durationMinutes
        _draft = State(
            initialValue: MeetingScheduleDraft(
                title: editingMeeting?.title ?? MeetingCalendarExportService.summary(for: payload.event),
                startDate: startDate,
                endDate: startDate.addingTimeInterval(
                    Double(durationMinutes) * 60
                ),
                notes: editingMeeting?.notes ?? "",
                leadTimeMinutes: editingMeeting?.reminderLeadTimeMinutes ?? 10
            )
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let conflictingSchedule {
                    conflictBanner(conflictingSchedule)
                }

                MeetingScheduleForm(
                    draft: draft,
                    displayTimezone: TimeZone(
                        identifier: payload.event.localTimezoneId
                    ) ?? .current
                )
            }
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
            }
            .navigationTitle(
                String(
                    localized: editingMeeting == nil
                        ? "meeting.calendar.editor.title"
                        : "meeting.schedule.edit.title"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                    }
                    .disabled(isSaving)
                }
            }
            .alert(
                alert?.title ?? "",
                isPresented: Binding(
                    get: { alert != nil },
                    set: { if !$0 { alert = nil } }
                ),
                presenting: alert
            ) { alert in
                if alert.showsSettingsAction {
                    Button(String(localized: "meeting.share.save.settings.action")) {
                        openSettings()
                    }
                }
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { alert in
                Text(alert.message)
            }
        }
        .onAppear {
            if editingMeeting == nil {
                refreshConflict()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
    }

    private var bottomActionBar: some View {
        Group {
            if editingMeeting == nil {
                HStack(spacing: 10) {
                    scheduleActionButton(
                        destination: .systemCalendar
                    )
                    scheduleActionButton(
                        destination: .inAppReminder
                    )
                }
            } else {
                Button {
                    saveEditedSchedule()
                } label: {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Text(String(localized: "meeting.schedule.saveChanges"))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        Color.accentColor,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSaving || conflictingSchedule != nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func conflictBanner(_ meeting: MeetingModel) -> some View {
        let title = meeting.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayTitle = title.isEmpty
            ? meeting.participantNames.joined(
                separator: String(localized: "meeting.slots.constraints.join")
            )
            : title

        return VStack(alignment: .leading, spacing: 4) {
            Label(
                String(localized: "meeting.schedule.conflict.title"),
                systemImage: "exclamationmark.circle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)

            Text(
                String(
                    format: conflictMessage(
                        for: meeting.scheduleSource
                    ),
                    displayTitle
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.10))
    }

    private func conflictMessage(for source: MeetingScheduleSource) -> String {
        switch source {
        case .systemCalendar:
            return String(localized: "meeting.schedule.conflict.systemCalendar")
        case .inAppReminder:
            return String(localized: "meeting.schedule.conflict.inAppReminder")
        }
    }

    private func scheduleActionButton(
        destination: MeetingScheduleDestination
    ) -> some View {
        Button {
            createSchedule(using: destination)
        } label: {
            HStack(spacing: 6) {
                if pendingDestination == destination {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(destination.actionTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                Color.accentColor,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSaving || conflictingSchedule != nil)
    }

    private func createSchedule(using destination: MeetingScheduleDestination) {
        guard !isSaving else { return }
        guard draft.endDate > draft.startDate else {
            alert = MeetingScheduleAlert(
                title: String(localized: "meeting.calendar.failed.title"),
                message: String(localized: "meeting.calendar.error.invalidTime")
            )
            return
        }

        let durationMinutes = max(
            1,
            Int(draft.endDate.timeIntervalSince(draft.startDate) / 60)
        )
        let event = MeetingCalendarEvent(
            uid: payload.event.uid,
            startDate: draft.startDate,
            durationMinutes: durationMinutes,
            localTimezoneId: payload.event.localTimezoneId,
            participants: payload.event.participants
        )

        guard !hasConflict(for: event) else {
            alert = MeetingScheduleAlert(
                title: String(localized: "meeting.add.conflict.title"),
                message: String(localized: "meeting.add.conflict")
            )
            return
        }

        switch destination {
        case .systemCalendar:
            createSystemCalendarSchedule(event: event)
        case .inAppReminder:
            createInAppSchedule(event: event)
        }
    }

    private func saveEditedSchedule() {
        guard let editingMeeting, !isSaving else { return }
        let durationMinutes = editingMeeting.durationMinutes
        let event = MeetingCalendarEvent(
            uid: editingMeeting.id.uuidString,
            startDate: editingMeeting.startDate,
            durationMinutes: durationMinutes,
            localTimezoneId: editingMeeting.localTimezoneId,
            participants: payload.event.participants
        )
        pendingDestination = editingMeeting.scheduleSource == .systemCalendar
            ? .systemCalendar
            : .inAppReminder
        Task { @MainActor in
            defer { pendingDestination = nil }

            switch editingMeeting.scheduleSource {
            case .inAppReminder:
                await saveEditedInAppSchedule(
                    editingMeeting,
                    event: event
                )
            case .systemCalendar:
                await saveEditedSystemCalendarSchedule(
                    editingMeeting,
                    event: event
                )
            }
        }
    }

    private func saveEditedInAppSchedule(
        _ editingMeeting: MeetingModel,
        event: MeetingCalendarEvent
    ) async {
        let candidate = editedMeetingCandidate(
            from: editingMeeting,
            event: event,
            source: .inAppReminder
        )
        let identifier: String?

        do {
            identifier = try await MeetingReminderService.shared.schedule(for: candidate)
        } catch MeetingReminderServiceError.reminderDatePassed {
            await MeetingReminderService.shared.cancel(for: editingMeeting.id)
            identifier = nil
        } catch let error as MeetingReminderServiceError {
            alert = MeetingScheduleAlert(
                title: String(localized: "meeting.reminder.failed.title"),
                message: error.localizedDescription,
                showsSettingsAction: error.requiresSettingsAction
            )
            return
        } catch {
            alert = MeetingScheduleAlert(
                title: String(localized: "meeting.reminder.failed.title"),
                message: String(localized: "meeting.reminder.error.schedule")
            )
            return
        }

        editingMeeting.title = candidate.title
        editingMeeting.notes = candidate.notes
        editingMeeting.reminderLeadTimeMinutes = candidate.reminderLeadTimeMinutes
        editingMeeting.notificationIdentifier = identifier

        do {
            try modelContext.save()
            finish()
        } catch {
            await MeetingReminderService.shared.cancel(for: editingMeeting.id)
            modelContext.rollback()
            _ = try? await MeetingReminderService.shared.schedule(for: editingMeeting)
            alert = MeetingScheduleAlert(
                title: String(localized: "meeting.reminder.failed.title"),
                message: String(localized: "meeting.reminder.error.schedule")
            )
        }
    }

    private func saveEditedSystemCalendarSchedule(
        _ editingMeeting: MeetingModel,
        event: MeetingCalendarEvent
    ) async {
        let granted = await MeetingCalendarService.shared.requestAccessIfNeeded()
        guard granted else {
            alert = MeetingScheduleAlert(
                title: String(localized: "meeting.calendar.permission.title"),
                message: AppDisplay.text(
                    "meeting.calendar.error.access",
                    AppDisplay.name
                ),
                showsSettingsAction: true
            )
            return
        }

        switch await MeetingCalendarService.shared.eventStatus(for: event) {
        case .available:
            break
        case .missing:
            alert = MeetingScheduleAlert(
                title: String(localized: "meeting.calendar.failed.title"),
                message: String(localized: "meeting.calendar.error.eventMissing")
            )
            return
        case .accessDenied:
            alert = MeetingScheduleAlert(
                title: String(localized: "meeting.calendar.permission.title"),
                message: AppDisplay.text(
                    "meeting.calendar.error.access",
                    AppDisplay.name
                ),
                showsSettingsAction: true
            )
            return
        }

        let candidate = editedMeetingCandidate(
            from: editingMeeting,
            event: event,
            source: .systemCalendar
        )
        let customNotes = candidate.notes

        do {
            _ = try await MeetingCalendarService.shared.save(
                event: event,
                title: candidate.title,
                location: "",
                notes: MeetingCalendarExportService.calendarNotes(
                    for: event,
                    customNotes: customNotes,
                    locale: .current
                ),
                url: nil,
                leadTimeMinutes: candidate.reminderLeadTimeMinutes
            )

            editingMeeting.title = candidate.title
            editingMeeting.notes = candidate.notes
            editingMeeting.reminderLeadTimeMinutes = candidate.reminderLeadTimeMinutes
            try modelContext.save()
            finish()
        } catch let error as MeetingCalendarServiceError {
            modelContext.rollback()
            alert = MeetingScheduleAlert(
                title: String(localized: "meeting.calendar.failed.title"),
                message: error.localizedDescription,
                showsSettingsAction: error.requiresSettingsAction
            )
        } catch {
            modelContext.rollback()
            alert = MeetingScheduleAlert(
                title: String(localized: "meeting.calendar.failed.title"),
                message: String(localized: "meeting.calendar.error.save")
            )
        }
    }

    private func editedMeetingCandidate(
        from meeting: MeetingModel,
        event: MeetingCalendarEvent,
        source: MeetingScheduleSource
    ) -> MeetingModel {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty
            ? MeetingCalendarExportService.summary(for: event)
            : trimmedTitle
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return MeetingModel(
            id: meeting.id,
            startDate: meeting.startDate,
            durationMinutes: meeting.durationMinutes,
            localTimezoneId: meeting.localTimezoneId,
            participantNames: meeting.participantNames,
            participantEnNames: meeting.participantEnNames,
            participantTimezoneIds: meeting.participantTimezoneIds,
            createdAt: meeting.createdAt,
            title: title,
            notes: notes.isEmpty ? nil : notes,
            reminderLeadTimeMinutes: draft.leadTimeMinutes,
            scheduleSource: source,
            calendarIntegrationKey: source == .systemCalendar
                ? meeting.calendarIntegrationKey
                : nil
        )
    }

    private func createSystemCalendarSchedule(event: MeetingCalendarEvent) {
        guard pendingDestination == nil else { return }
        pendingDestination = .systemCalendar

        Task { @MainActor in
            defer { pendingDestination = nil }

            let granted = await MeetingCalendarService.shared.requestAccessIfNeeded()
            guard granted else {
                alert = MeetingScheduleAlert(
                    title: String(localized: "meeting.calendar.permission.title"),
                    message: AppDisplay.text(
                        "meeting.calendar.error.access",
                        AppDisplay.name
                    ),
                    showsSettingsAction: true
                )
                return
            }

            do {
                _ = try await MeetingCalendarService.shared.save(
                    event: event,
                    title: draft.title,
                    location: "",
                    notes: MeetingCalendarExportService.calendarNotes(
                        for: event,
                        customNotes: draft.notes,
                        locale: .current
                    ),
                    url: nil,
                    leadTimeMinutes: draft.leadTimeMinutes
                )
                let meeting = makeMeeting(
                    event: event,
                    source: .systemCalendar,
                    notificationIdentifier: nil,
                    calendarIntegrationKey: MeetingCalendarService.integrationKey(for: event)
                )
                modelContext.insert(meeting)
                try modelContext.save()
                finish()
            } catch let error as MeetingCalendarServiceError {
                alert = MeetingScheduleAlert(
                    title: String(localized: "meeting.calendar.failed.title"),
                    message: error.localizedDescription,
                    showsSettingsAction: error.requiresSettingsAction
                )
            } catch {
                alert = MeetingScheduleAlert(
                    title: String(localized: "meeting.calendar.failed.title"),
                    message: String(localized: "meeting.calendar.error.save")
                )
            }
        }
    }

    private func createInAppSchedule(event: MeetingCalendarEvent) {
        guard pendingDestination == nil else { return }
        pendingDestination = .inAppReminder

        Task { @MainActor in
            defer { pendingDestination = nil }

            let meeting = makeMeeting(
                event: event,
                source: .inAppReminder,
                notificationIdentifier: nil,
                calendarIntegrationKey: nil
            )

            do {
                meeting.notificationIdentifier = try await MeetingReminderService.shared.schedule(
                    for: meeting
                )
                modelContext.insert(meeting)
                try modelContext.save()
                finish()
            } catch let error as MeetingReminderServiceError {
                alert = MeetingScheduleAlert(
                    title: String(localized: "meeting.reminder.failed.title"),
                    message: error.localizedDescription,
                    showsSettingsAction: error.requiresSettingsAction
                )
            } catch {
                if meeting.notificationIdentifier != nil {
                    await MeetingReminderService.shared.cancel(for: meeting.id)
                }
                modelContext.rollback()
                alert = MeetingScheduleAlert(
                    title: String(localized: "meeting.reminder.failed.title"),
                    message: String(localized: "meeting.reminder.error.schedule")
                )
            }
        }
    }

    private func makeMeeting(
        event: MeetingCalendarEvent,
        source: MeetingScheduleSource,
        notificationIdentifier: String?,
        calendarIntegrationKey: String?
    ) -> MeetingModel {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty
            ? MeetingCalendarExportService.summary(for: event)
            : trimmedTitle
        return MeetingModel(
            startDate: event.startDate,
            durationMinutes: event.durationMinutes,
            localTimezoneId: event.localTimezoneId,
            participantNames: event.participants.map(\.cityName),
            participantEnNames: event.participants.map(\.cityEn),
            participantTimezoneIds: event.participants.map { $0.timezoneId ?? "" },
            title: title,
            notes: draft.notes.isEmpty ? nil : draft.notes,
            reminderLeadTimeMinutes: draft.leadTimeMinutes,
            scheduleSource: source,
            notificationIdentifier: notificationIdentifier,
            calendarIntegrationKey: calendarIntegrationKey
        )
    }

    private func hasConflict(
        for event: MeetingCalendarEvent,
        excluding excludedID: UUID? = nil
    ) -> Bool {
        let endDate = event.startDate.addingTimeInterval(
            Double(event.durationMinutes) * 60
        )
        let existing = (try? modelContext.fetch(FetchDescriptor<MeetingModel>())) ?? []
        return existing.contains { meeting in
            guard meeting.id != excludedID else { return false }
            let meetingEnd = meeting.startDate.addingTimeInterval(
                Double(meeting.durationMinutes) * 60
            )
            return event.startDate < meetingEnd && meeting.startDate < endDate
        }
    }

    private func refreshConflict() {
        let endDate = draft.endDate
        guard endDate > draft.startDate else {
            conflictingSchedule = nil
            return
        }

        let existing = (try? modelContext.fetch(FetchDescriptor<MeetingModel>())) ?? []
        conflictingSchedule = existing.first { meeting in
            guard meeting.id != editingMeeting?.id else { return false }
            let meetingEnd = meeting.startDate.addingTimeInterval(
                Double(meeting.durationMinutes) * 60
            )
            return draft.startDate < meetingEnd && meeting.startDate < endDate
        }
    }

    private func finish() {
        onComplete()
        dismiss()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private enum MeetingScheduleDestination: String {
    case systemCalendar
    case inAppReminder

    var actionTitle: String {
        switch self {
        case .systemCalendar:
            return String(localized: "meeting.schedule.action.systemCalendar")
        case .inAppReminder:
            return String(localized: "meeting.schedule.action.inAppReminder")
        }
    }
}

@MainActor
@Observable
private final class MeetingScheduleDraft {
    var title: String
    var startDate: Date
    var endDate: Date
    var notes: String
    var leadTimeMinutes: Int?

    init(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String,
        leadTimeMinutes: Int?
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.leadTimeMinutes = leadTimeMinutes
    }
}

private struct MeetingScheduleForm: View {
    @Bindable var draft: MeetingScheduleDraft
    let displayTimezone: TimeZone
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
        case notes
    }

    private var alertOptions: [(minutes: Int?, title: String)] {
        [
            (nil, String(localized: "meeting.calendar.alert.none")),
            (0, String(localized: "meeting.calendar.alert.onTime")),
            (5, String(localized: "meeting.calendar.alert.5")),
            (10, String(localized: "meeting.calendar.alert.10")),
            (15, String(localized: "meeting.calendar.alert.15")),
            (30, String(localized: "meeting.calendar.alert.30")),
            (60, String(localized: "meeting.calendar.alert.60")),
            (120, String(localized: "meeting.calendar.alert.120")),
            (1_440, String(localized: "meeting.calendar.alert.1day")),
            (2_880, String(localized: "meeting.calendar.alert.2days")),
            (10_080, String(localized: "meeting.calendar.alert.1week"))
        ]
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    TextField(
                        String(localized: "meeting.calendar.field.title"),
                        text: $draft.title
                    )
                    .focused($focusedField, equals: .title)
                    .submitLabel(.done)
                    .onSubmit {
                        focusedField = nil
                    }

                    if focusedField == .title, !draft.title.isEmpty {
                        Button {
                            draft.title = ""
                            focusedField = .title
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "common.clear"))
                    }
                }
            }

            Section {
                DatePicker(
                    String(localized: "meeting.calendar.field.start"),
                    selection: $draft.startDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .allowsHitTesting(false)

                DatePicker(
                    String(localized: "meeting.calendar.field.end"),
                    selection: $draft.endDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .allowsHitTesting(false)
            }

            Section {
                Picker(
                    String(localized: "meeting.calendar.field.alert"),
                    selection: $draft.leadTimeMinutes
                ) {
                    ForEach(alertOptions, id: \.minutes) { option in
                        Text(option.title).tag(option.minutes)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                TextField(
                    String(localized: "meeting.calendar.field.notes"),
                    text: $draft.notes,
                    axis: .vertical
                )
                .lineLimit(5, reservesSpace: true)
                .textInputAutocapitalization(.sentences)
                .focused($focusedField, equals: .notes)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .systemGroupedBackground))
        .environment(\.timeZone, displayTimezone)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "common.done")) {
                    focusedField = nil
                }
            }
        }
    }

}

private struct MeetingScheduleAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var showsSettingsAction = false
}
