import SwiftUI

/// 工作时段重叠可视化：24 小时色条 + 状态文案。
/// 绿色段 = 本地与目标城市均在 9:00–18:00 工作时段；红色竖线 = 当前时刻。
struct WorkingHoursBar: View {
    let overlap: WorkingHoursOverlap
    /// 本地时区标识，用于把 nextOverlapDate 格式化为本地时间字符串
    let localTimezoneId: String

    /// 当前本地小时（含分钟小数），用于色条上的"现在"标记
    private var currentHourValue: Double {
        overlap.currentLocalHour
    }

    /// 把下一个重叠起点格式化为本地时间字符串，跨天带「明日/昨日」前缀
    private func nextOverlapText(_ date: Date) -> String {
        guard let localTz = TimeZone(identifier: localTimezoneId) else {
            return ""
        }
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = localTz

        let formatter = DateFormatter()
        formatter.timeZone = localTz
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        let timeText = formatter.string(from: date)

        // 比较目标日与今日的日序，判断是否跨天
        let todayStart = localCalendar.dateInterval(of: .day, for: Date())?.start ?? Date()
        let targetStart = localCalendar.dateInterval(of: .day, for: date)?.start ?? date
        let dayDiff = localCalendar.dateComponents([.day], from: todayStart, to: targetStart).day ?? 0

        if dayDiff > 0 {
            return "\(String(localized: "clock.tomorrow")) \(timeText)"
        } else if dayDiff < 0 {
            return "\(String(localized: "clock.yesterday")) \(timeText)"
        }
        return timeText
    }

    private var statusText: String {
        if overlap.isCurrentlyOverlapping {
            return String(localized: "clock.working.now")
        }
        if let next = overlap.nextOverlapDate {
            return nextOverlapText(next)
        }
        return String(localized: "clock.working.none")
    }

    var body: some View {
        HStack(spacing: 8) {
            Canvas { context, size in
                let segW = size.width / 24
                let h = size.height
                for hour in 0..<24 {
                    let x = CGFloat(hour) * segW
                    let rect = CGRect(x: x, y: 0, width: max(segW - 1, 1), height: h)
                    let color: Color = overlap.hourlyOverlap[hour] ? .green : Color(.systemGray5)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
                }
                // "现在"标记
                let nowX = CGFloat(currentHourValue) * segW
                let marker = CGRect(x: nowX - 1, y: -1.5, width: 2, height: h + 3)
                context.fill(Path(roundedRect: marker, cornerRadius: 1), with: .color(.red))
            }
            .frame(height: 6)

            HStack(spacing: 2) {
                Image(systemName: overlap.isCurrentlyOverlapping ? "phone.fill" : "phone")
                    .font(.system(size: 9))
                Text(statusText)
            }
            .font(.caption2)
            .foregroundColor(overlap.isCurrentlyOverlapping ? .green : .secondary)
            .lineLimit(1)
        }
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if overlap.isCurrentlyOverlapping {
            return String(localized: "clock.working.now")
        }
        if let next = overlap.nextOverlapDate {
            return String(format: String(localized: "clock.working.next"), nextOverlapText(next))
        }
        return String(localized: "clock.working.none")
    }
}
