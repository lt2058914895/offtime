import SwiftUI

struct ReminderSoundPickerView: View {
    let title: String
    let onSave: (ReminderSound) -> Void

    private let savedSound: ReminderSound
    @State private var selection: ReminderSound
    @StateObject private var previewPlayer = ReminderSoundPreviewPlayer()
    @State private var showProPaywall = false
    @State private var shouldApplySoundAfterUnlock = false
    @EnvironmentObject private var proAccessService: ProAccessService
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        selectedSound: ReminderSound,
        onSave: @escaping (ReminderSound) -> Void
    ) {
        self.title = title
        self.onSave = onSave
        self.savedSound = selectedSound
        _selection = State(initialValue: selectedSound)
    }

    private var hasChanges: Bool {
        selection != savedSound
    }

    private var selectionRequiresUnlock: Bool {
        selection.requiresPro && !proAccessService.isUnlocked
    }

    private var isUnlockAction: Bool {
        hasChanges && selectionRequiresUnlock
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    soundRow(
                        sound: .system,
                        title: ReminderSound.system.displayName,
                        subtitle: ReminderSound.system.subtitle,
                        icon: ReminderSound.system.iconName
                    )
                    ForEach(ReminderSound.freeBuiltInCases) { sound in
                        soundRow(
                            sound: sound,
                            title: sound.displayName,
                            subtitle: sound.subtitle,
                            icon: sound.iconName
                        )
                    }
                }

                Section {
                    ForEach(ReminderSound.proBuiltInCases) { sound in
                        soundRow(
                            sound: sound,
                            title: sound.displayName,
                            subtitle: sound.subtitle,
                            icon: sound.iconName
                        )
                    }
                } header: {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                        Text(String(localized: "reminder.sound.pro.section"))
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
                    .textCase(nil)
                } footer: {
                    if !proAccessService.isUnlocked {
                        Text(String(localized: "reminder.sound.pro.footer"))
                    }
                }
            }

            doneButton
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                }
                .accessibilityLabel(String(localized: "common.back"))
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showProPaywall, onDismiss: {
            if !proAccessService.isUnlocked {
                shouldApplySoundAfterUnlock = false
            }
        }) {
            ProPaywallView()
        }
        .onChange(of: proAccessService.isUnlocked) { _, isUnlocked in
            guard isUnlocked, shouldApplySoundAfterUnlock else { return }

            shouldApplySoundAfterUnlock = false
            saveAndDismiss()
        }
        .onDisappear {
            previewPlayer.stop()
        }
    }

    private var doneButton: some View {
        Button {
            if selectionRequiresUnlock {
                previewPlayer.stop()
                shouldApplySoundAfterUnlock = true
                showProPaywall = true
            } else {
                saveAndDismiss()
            }
        } label: {
            HStack(spacing: 6) {
                if isUnlockAction {
                    Image(systemName: "crown.fill")
                }
                Text(String(localized: isUnlockAction ? "reminder.sound.unlock" : "reminder.sound.confirm"))
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(isUnlockAction ? Color.orange : Color.white)
            .background(
                doneButtonBackground,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasChanges)
    }

    private var doneButtonBackground: Color {
        guard hasChanges else { return Color.accentColor.opacity(0.4) }
        return isUnlockAction ? Color.orange.opacity(0.12) : Color.accentColor
    }

    private func saveAndDismiss() {
        onSave(selection)
        dismiss()
    }

    private func soundRow(
        sound: ReminderSound,
        title: String,
        subtitle: String?,
        icon: String
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                select(sound)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundColor(.blue)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .foregroundColor(.primary)

                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    if selection == sound {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.accentColor)
                    }

                    if sound.requiresPro {
                        ProBadge(showsText: false)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if sound.isBuiltIn {
                Button {
                    previewPlayer.toggle(sound)
                } label: {
                    Image(
                        systemName: previewPlayer.playingSound == sound
                            ? "stop.circle.fill"
                            : "play.circle"
                    )
                    .font(.title3)
                    .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "reminder.sound.preview"))
            }
        }
        .padding(.vertical, 2)
    }

    private func select(_ sound: ReminderSound) {
        selection = sound
        if sound.isBuiltIn {
            previewPlayer.toggle(sound)
        } else {
            previewPlayer.stop()
        }
    }
}
