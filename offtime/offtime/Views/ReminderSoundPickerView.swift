import SwiftUI

struct ReminderSoundPickerView: View {
    let title: String
    let onSave: (ReminderSound) -> Void

    private let savedSound: ReminderSound
    @State private var selection: ReminderSound
    @StateObject private var previewPlayer = ReminderSoundPreviewPlayer()
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
                    ForEach(ReminderSound.builtInCases) { sound in
                        soundRow(
                            sound: sound,
                            title: sound.displayName,
                            subtitle: sound.subtitle,
                            icon: sound.iconName
                        )
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
        .onDisappear {
            previewPlayer.stop()
        }
    }

    private var doneButton: some View {
        Button {
            onSave(selection)
            dismiss()
        } label: {
            Text(String(localized: "reminder.sound.confirm"))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(.white)
                .background(
                    hasChanges ? Color.accentColor : Color.accentColor.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!hasChanges)
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
