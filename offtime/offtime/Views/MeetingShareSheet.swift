import SwiftUI
import Photos
import UIKit

struct MeetingSharePayload: Identifiable {
    let id = UUID()
    let event: MeetingCalendarEvent
    let use24Hour: Bool
}

/// 日程分享入口：预览图片卡片，并选择分享图片或日历文件。
struct MeetingShareSheet: View {
    let payload: MeetingSharePayload

    @Environment(\.dismiss) private var dismiss
    @State private var stage: ShareStage = .options
    @State private var selectedDetent: PresentationDetent = .height(300)
    @State private var previewImage: UIImage?
    @State private var isPreparingImage = false
    @State private var isSavingImage = false
    @State private var pendingShare: PendingMeetingShare?
    @State private var shareAlert: MeetingShareAlert?
    @State private var toastMessage: String?

    private enum ShareStage: Equatable {
        case options
        case imagePreview
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .options:
                    optionsContent
                case .imagePreview:
                    imagePreviewContent
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if stage == .imagePreview {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: backToOptions) {
                            Image(systemName: "chevron.left")
                                .fontWeight(.semibold)
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                }
            }
            .sheet(item: $pendingShare) { share in
                ShareSheet(items: share.items) {
                    share.cleanup?()
                    pendingShare = nil
                }
            }
            .alert(
                shareAlert?.title ?? "",
                isPresented: Binding(
                    get: { shareAlert != nil },
                    set: { if !$0 { shareAlert = nil } }
                ),
                presenting: shareAlert
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
            .toast(message: $toastMessage)
        }
        .presentationDetents([.height(300), .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
    }

    private var navigationTitle: String {
        stage == .imagePreview
            ? String(localized: "meeting.share.preview.title")
            : String(localized: "meeting.share.action")
    }

    private var optionsContent: some View {
        VStack(spacing: 10) {
            shareActionButton(
                title: String(localized: "meeting.share.ics.action"),
                detail: String(localized: "meeting.share.ics.hint"),
                systemImage: "calendar.badge.plus"
            ) {
                shareCalendarFile()
            }

            shareActionButton(
                title: String(localized: "meeting.share.image.action"),
                detail: String(localized: "meeting.share.image.hint"),
                systemImage: "photo.on.rectangle",
                isLoading: isPreparingImage
            ) {
                showImagePreview()
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var imagePreviewContent: some View {
        ScrollView {
            VStack(spacing: 50) {
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
                        .accessibilityLabel(Text(String(localized: "meeting.share.preview.title")))
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 380)
                }

                imageShareBar
            }
            .padding(16)
            .padding(.bottom, 24)
        }
    }

    private var imageShareBar: some View {
        HStack(spacing: 10) {
            Button {
                saveImageToPhotos()
            } label: {
                HStack(spacing: 7) {
                    if isSavingImage {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.blue)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }

                    Text(
                        String(
                            localized: isSavingImage
                                ? "meeting.share.save.saving"
                                : "meeting.share.save.action"
                        )
                    )
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.blue)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    Color(uiColor: .systemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.55), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSavingImage)

            Button {
                shareImage()
            } label: {
                Text(String(localized: "meeting.share.image.action"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func shareActionButton(
        title: String,
        detail: String,
        systemImage: String,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 38, height: 38)
                .background(Color.accentColor, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.18), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private func showImagePreview() {
        guard !isPreparingImage else { return }

        if previewImage != nil {
            withAnimation(.easeInOut(duration: 0.2)) {
                stage = .imagePreview
                selectedDetent = .large
            }
            return
        }

        isPreparingImage = true
        Task { @MainActor in
            await Task.yield()
            let image = MeetingShareImageRenderer.makeImage(payload: payload)
            isPreparingImage = false

            guard let image else {
                shareAlert = MeetingShareAlert(
                    title: String(localized: "meeting.share.failed.title"),
                    message: String(localized: "meeting.share.image.failed.message")
                )
                return
            }

            previewImage = image
            withAnimation(.easeInOut(duration: 0.2)) {
                stage = .imagePreview
                selectedDetent = .large
            }
        }
    }

    private func backToOptions() {
        withAnimation(.easeInOut(duration: 0.2)) {
            stage = .options
            selectedDetent = .height(300)
        }
    }

    private func shareImage() {
        guard let previewImage else {
            shareAlert = MeetingShareAlert(
                title: String(localized: "meeting.share.failed.title"),
                message: String(localized: "meeting.share.image.failed.message")
            )
            return
        }

        pendingShare = PendingMeetingShare(items: [previewImage])
    }

    private func saveImageToPhotos() {
        guard let previewImage, !isSavingImage else { return }

        isSavingImage = true
        Task { @MainActor in
            defer { isSavingImage = false }

            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                shareAlert = MeetingShareAlert(
                    title: String(localized: "meeting.share.save.permission.title"),
                    message: AppDisplay.text(
                        "meeting.share.save.permission.message",
                        AppDisplay.name
                    ),
                    showsSettingsAction: true
                )
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: previewImage)
                }
                toastMessage = String(localized: "meeting.share.save.success")
            } catch {
                shareAlert = MeetingShareAlert(
                    title: String(localized: "meeting.share.save.failed.title"),
                    message: String(localized: "meeting.share.save.failed.message")
                )
            }
        }
    }

    private func shareCalendarFile() {
        do {
            let url = try MeetingCalendarExportService.makeTemporaryFile(event: payload.event)
            pendingShare = PendingMeetingShare(items: [url]) {
                MeetingCalendarExportService.removeTemporaryFile(at: url)
            }
        } catch {
            shareAlert = MeetingShareAlert(
                title: String(localized: "meeting.share.failed.title"),
                message: String(localized: "meeting.share.failed.message")
            )
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct PendingMeetingShare: Identifiable {
    let id = UUID()
    let items: [Any]
    var cleanup: (() -> Void)?
}

private struct MeetingShareAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var showsSettingsAction = false
}

@MainActor
private enum MeetingShareImageRenderer {
    static func makeImage(payload: MeetingSharePayload) -> UIImage? {
        let renderer = ImageRenderer(
            content: MeetingShareCardView(payload: payload)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 3
        renderer.isOpaque = false
        guard let image = renderer.uiImage else { return nil }
        return flattenedImage(image)
    }

    private static func flattenedImage(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true

        let bounds = CGRect(origin: .zero, size: image.size)
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1).setFill()
            context.fill(bounds)
            image.draw(in: bounds)
        }
    }
}

private struct MeetingShareCardView: View {
    let payload: MeetingSharePayload

    private var event: MeetingCalendarEvent {
        payload.event
    }

    private var endDate: Date {
        event.startDate.addingTimeInterval(Double(event.durationMinutes) * 60)
    }

    private var localTimezone: TimeZone {
        TimeZone(identifier: event.localTimezoneId) ?? .current
    }

    private var cityTitle: String {
        let names = event.participants.map {
            CityDisplay.primaryName(cityName: $0.cityName, cityEn: $0.cityEn)
        }
        guard !names.isEmpty else {
            return String(localized: "meeting.ics.summary.empty")
        }
        return names.joined(separator: String(localized: "meeting.slots.constraints.join"))
    }

    private var localDateText: String {
        dateRangeText(start: event.startDate, end: endDate, timezone: localTimezone)
    }

    private var localTimeText: String {
        timeRangeText(start: event.startDate, end: endDate, timezone: localTimezone)
    }

    private var durationText: String {
        String(format: String(localized: "meeting.settings.duration.format"), event.durationMinutes)
    }

    private var cityRows: [MeetingShareCityRow] {
        event.participants.enumerated().map { index, participant in
            let timezone = participant.timezoneId.flatMap(TimeZone.init(identifier:))
            return MeetingShareCityRow(
                id: index,
                cityName: CityDisplay.primaryName(
                    cityName: participant.cityName,
                    cityEn: participant.cityEn
                ),
                dateText: timezone.map {
                    dateRangeText(start: event.startDate, end: endDate, timezone: $0)
                },
                timeText: timezone.map {
                    timeRangeText(start: event.startDate, end: endDate, timezone: $0)
                }
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(cityTitle)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.black)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text(localDateText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(white: 0.42))

                HStack(alignment: .center, spacing: 10) {
                    Text(localTimeText)
                        .font(.system(size: 34, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .layoutPriority(1)

                    Text(durationText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.blue)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if !cityRows.isEmpty {
                Divider()

                VStack(spacing: 14) {
                    ForEach(cityRows) { row in
                        cityRow(row)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 390, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(20)
        .background(Color(red: 0.95, green: 0.95, blue: 0.97))
    }

    private func cityRow(_ row: MeetingShareCityRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(row.cityName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

            Spacer(minLength: 8)

            if let dateText = row.dateText, let timeText = row.timeText {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(dateText)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.42))
                            .lineLimit(1)

                        Text(timeText)
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.black)
                            .lineLimit(1)
                    }

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(dateText)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.42))
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)

                        Text(timeText)
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.black)
                            .lineLimit(1)
                    }
                }
            } else {
                Text(verbatim: "—")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(white: 0.42))
            }
        }
    }

    private func dateRangeText(start: Date, end: Date, timezone: TimeZone) -> String {
        let startText = dateText(start, timezone: timezone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        guard !calendar.isDate(start, inSameDayAs: end) else {
            return startText
        }
        return "\(startText) – \(dateText(end, timezone: timezone))"
    }

    private func timeRangeText(start: Date, end: Date, timezone: TimeZone) -> String {
        "\(timeText(start, timezone: timezone))–\(timeText(end, timezone: timezone))"
    }

    private func dateText(_ date: Date, timezone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy/MM/dd EEE"
        return formatter.string(from: date)
    }

    private func timeText(_ date: Date, timezone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = timezone
        formatter.dateFormat = payload.use24Hour ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }
}

private struct MeetingShareCityRow: Identifiable {
    let id: Int
    let cityName: String
    let dateText: String?
    let timeText: String?
}
