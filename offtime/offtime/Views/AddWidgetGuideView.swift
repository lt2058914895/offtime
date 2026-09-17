import SwiftUI

/// 「添加小组件」引导页（设置页入口）。
///
/// 设计目标：一眼看懂。整页只用三种信息层级——
/// 1. 卡片标题（图标 + 一句话）；
/// 2. 横向流程图（3 个序号图标 + 极短文案，替代原来的 5 条长列表）；
/// 3. 与真实组件同构的示意图（小 = 1 个城市、中 = 2 个、大 = 最多 6 个，
///    与 `OffTimeWidget.supportedFamilies` 对应）。
struct AddWidgetGuideView: View {
    /// 尺寸预览当前选中的档位，默认中尺寸（最常用的取舍）
    @State private var selectedSize: WidgetSizeOption = .medium
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroCard
                stepsCard(
                    icon: "iphone.gen3",
                    tint: .blue,
                    title: String(localized: "widget.guide.home.title"),
                    steps: homeSteps,
                    note: String(localized: "widget.guide.home.hint")
                )
                stepsCard(
                    icon: "lock.fill",
                    tint: .indigo,
                    title: String(localized: "widget.guide.lock.title"),
                    steps: lockSteps,
                    note: String(localized: "widget.guide.lock.footer")
                )
                sizeCard
                tipsCard
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "settings.add.widget"))
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
                .accessibilityLabel(Text(String(localized: "common.back")))
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - 顶部说明

    private var heroCard: some View {
        GuideCard {
            HStack(alignment: .center, spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppDisplay.text("settings.add.widget.subtitle", AppDisplay.name))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(localized: "widget.guide.subtitle"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - 步骤卡片

    private func stepsCard(
        icon: String,
        tint: Color,
        title: String,
        steps: [GuideStep],
        note: String
    ) -> some View {
        GuideCard {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(icon: icon, tint: tint, title: title)

                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        GuideFlowStep(index: index + 1, step: step)

                        if index < steps.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color.secondary.opacity(0.45))
                                .frame(width: 18)
                                .padding(.top, 17)
                        }
                    }
                }

                NoteRow(text: note, icon: "info.circle.fill")
            }
        }
    }

    /// 主屏幕路径：长按桌面 → 点「＋」→ 选 OffTime
    private var homeSteps: [GuideStep] {
        [
            GuideStep(
                icon: "hand.tap.fill",
                title: String(localized: "widget.guide.home.step1.title"),
                detail: String(localized: "widget.guide.home.step1.detail")
            ),
            GuideStep(
                icon: "plus.circle.fill",
                title: String(localized: "widget.guide.home.step2.title"),
                detail: String(localized: "widget.guide.home.step2.detail")
            ),
            GuideStep(
                icon: "square.grid.2x2",
                title: AppDisplay.text("widget.guide.home.step3.title", AppDisplay.name),
                detail: String(localized: "widget.guide.home.step3.detail")
            )
        ]
    }

    /// 锁定屏幕路径：长按锁屏 → 点组件区域 → 选 OffTime 样式
    private var lockSteps: [GuideStep] {
        [
            GuideStep(
                icon: "lock.rotation",
                title: String(localized: "widget.guide.lock.step1.title"),
                detail: String(localized: "widget.guide.lock.step1.detail")
            ),
            GuideStep(
                icon: "rectangle.inset.filled",
                title: String(localized: "widget.guide.lock.step2.title"),
                detail: String(localized: "widget.guide.lock.step2.detail")
            ),
            GuideStep(
                icon: "circle.dashed",
                title: AppDisplay.text("widget.guide.lock.step3.title", AppDisplay.name),
                detail: String(localized: "widget.guide.lock.step3.detail")
            )
        ]
    }

    // MARK: - 尺寸卡片

    private var sizeCard: some View {
        GuideCard {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(
                    icon: "square.on.square",
                    tint: .teal,
                    title: String(localized: "widget.guide.size.title")
                )

                HStack(spacing: 8) {
                    ForEach(WidgetSizeOption.allCases) { option in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedSize = option
                            }
                        } label: {
                            SizeChip(option: option, isSelected: option == selectedSize)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(option.title))
                        .accessibilityValue(Text(option.cityCaption))
                        .accessibilityAddTraits(option == selectedSize ? [.isSelected] : [])
                    }
                }

                VStack(spacing: 10) {
                    WidgetMock(option: selectedSize)

                    Text(selectedSize.cityCaption)
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 2)

                NoteRow(text: String(localized: "widget.guide.size.footer"), icon: "arrow.triangle.2.circlepath")
            }
        }
    }

    // MARK: - 小提示卡片

    private var tipsCard: some View {
        GuideCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(
                    icon: "lightbulb.fill",
                    tint: .orange,
                    title: String(localized: "widget.guide.tips.title")
                )

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                        NoteRow(text: tip.text, icon: tip.icon, tint: tip.tint)
                    }
                }
            }
        }
    }

    /// 三条提示各自一个图标，扫一眼就知道说的是「顺序 / 刷新 / 空状态」
    private var tips: [(icon: String, tint: Color, text: String)] {
        [
            ("list.number", .blue, String(localized: "widget.guide.tips.order")),
            ("arrow.clockwise", .green, String(localized: "widget.guide.tips.refresh")),
            ("questionmark.circle.fill", .orange, AppDisplay.text("widget.guide.tips.empty", AppDisplay.name))
        ]
    }
}

// MARK: - 模型

private struct GuideStep {
    let icon: String
    let title: String
    let detail: String
}

/// 尺寸档位：文案、比例与「能显示几个城市」都集中在这里，方便与 `OffTimeWidget.supportedFamilies` 对齐。
private enum WidgetSizeOption: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return String(localized: "widget.guide.size.small")
        case .medium: return String(localized: "widget.guide.size.medium")
        case .large: return String(localized: "widget.guide.size.large")
        }
    }

    /// 「能显示几个城市」——原页面只有小字说明，这里贴近示意图展示，扫一眼就知道该选哪个
    var cityCaption: String {
        switch self {
        case .small: return String(localized: "widget.guide.size.caption.small")
        case .medium: return String(localized: "widget.guide.size.caption.medium")
        case .large: return String(localized: "widget.guide.size.caption.large")
        }
    }

    /// 宽高比（宽 / 高）：小 = 1:1，中 ≈ 2.14:1，大 ≈ 0.95:1（与桌面上的真实形状一致）
    var aspectRatio: CGFloat {
        switch self {
        case .small: return 1
        case .medium: return 2.14
        case .large: return 0.95
        }
    }

    /// 示意图宽度上限：中 / 大占满一行，小尺寸缩到与真实比例相当
    var previewMaxWidth: CGFloat {
        switch self {
        case .small: return 132
        case .medium: return 280
        case .large: return 240
        }
    }

    /// 预览区域高度：由宽高比换算，保证缩略后形状与桌面一致
    var previewHeight: CGFloat { previewMaxWidth / aspectRatio }

    /// 示意图内部字号：按预览宽度等比缩放，比例取自真实组件的字号 / 宽度
    func titleSize(_ width: CGFloat) -> CGFloat {
        max(9.5, width * (self == .small ? 0.13 : self == .medium ? 0.06 : 0.056))
    }

    func timeSize(_ width: CGFloat) -> CGFloat {
        max(12, width * (self == .small ? 0.30 : self == .medium ? 0.10 : 0.075))
    }

    func dateSize(_ width: CGFloat) -> CGFloat {
        max(7.5, width * (self == .small ? 0.08 : self == .medium ? 0.034 : 0.036))
    }

    var glyphSize: CGSize {
        switch self {
        case .small: return CGSize(width: 16, height: 16)
        case .medium: return CGSize(width: 30, height: 14)
        case .large: return CGSize(width: 21, height: 22)
        }
    }
}

/// 示意图用的示例城市：固定文案（图标 + 城市名 + 时间 + 时差），只为说明版式，不读真实数据。
private struct MockCity {
    let name: String
    let englishName: String
    let time: String
    let relation: String?
    let isNight: Bool

    var displayName: String {
        CityDisplay.primaryName(cityName: name, cityEn: englishName)
    }

    static let beijing = MockCity(name: "北京", englishName: "Beijing", time: "09:41", relation: nil, isNight: false)
    static let tokyo = MockCity(name: "东京", englishName: "Tokyo", time: "10:41", relation: "+1h", isNight: false)
    static let london = MockCity(name: "伦敦", englishName: "London", time: "02:41", relation: "-7h", isNight: true)
    static let newYork = MockCity(name: "纽约", englishName: "New York", time: "21:41", relation: "-12h", isNight: true)
    static let paris = MockCity(name: "巴黎", englishName: "Paris", time: "03:41", relation: "-6h", isNight: true)
}

// MARK: - 组件

/// 卡片容器：与会议页、转换页保持同一套视觉（16pt 圆角 + 极浅投影）
private struct GuideCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.03), radius: 4)
    }
}

/// 卡片标题：彩色图标 + 标题，一眼分辨「主屏幕 / 锁定屏幕 / 尺寸 / 提示」
private struct CardHeader: View {
    let icon: String
    let tint: Color
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(title)
                .font(.headline)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 流程图节点：序号图标 + 一行标题 + 一行极短说明
private struct GuideFlowStep: View {
    let index: Int
    let step: GuideStep

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: step.icon)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }

                Text("\(index)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.accentColor))
                    .offset(x: 4, y: -3)
            }

            VStack(spacing: 2) {
                Text(step.title)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Text(step.detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
    }
}

/// 说明行：小图标 + 次要说明文字
private struct NoteRow: View {
    let text: String
    var icon: String = "info.circle.fill"
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(tint)
                .padding(.top, 1)

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 尺寸选择按钮：内部用一个等比小方块/长条示意形状差异
private struct SizeChip: View {
    let option: WidgetSizeOption
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.9) : Color.secondary.opacity(0.35))
                .frame(width: option.glyphSize.width, height: option.glyphSize.height)

            Text(option.title)
                .font(.footnote)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
        )
        .foregroundColor(isSelected ? .white : .primary)
    }
}

/// 组件示意图：按真实版式渲染（小 = 城市 + 大号时间；中 = 左右两列；大 = 逐行列表），
/// 让用户在添加前就看清成品长什么样。
private struct WidgetMock: View {
    let option: WidgetSizeOption

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, option.previewMaxWidth)
            let height = width / option.aspectRatio

            mock(width: width, height: height)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: option.previewHeight)
    }

    private func mock(width: CGFloat, height: CGFloat) -> some View {
        content(width: width)
            .padding(width * 0.075)
            .frame(width: width, height: height)
            .background(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.16), Color(.tertiarySystemFill)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        switch option {
        case .small:
            column(MockCity.beijing, width: width)
        case .medium:
            HStack(spacing: width * 0.04) {
                column(MockCity.beijing, width: width)
                Divider()
                column(MockCity.newYork, width: width)
            }
        case .large:
            VStack(spacing: 0) {
                let cities = [MockCity.beijing, MockCity.london, MockCity.newYork, MockCity.tokyo, MockCity.paris]
                ForEach(Array(cities.enumerated()), id: \.offset) { index, city in
                    row(city, width: width)
                        .frame(maxHeight: .infinity)
                    if index < cities.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    /// 小 / 中尺寸的列版式：城市行 → 大号时间 → 日期行
    private func column(_ city: MockCity, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            cityTitle(city, width: width)
            Spacer(minLength: 2)
            Text(city.time)
                .font(.system(size: option.timeSize(width), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 2)
            dateLine(city, width: width)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 大尺寸的行版式：左侧城市信息，右侧时间
    private func row(_ city: MockCity, width: CGFloat) -> some View {
        HStack(spacing: width * 0.05) {
            VStack(alignment: .leading, spacing: width * 0.012) {
                cityTitle(city, width: width)
                dateLine(city, width: width)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(city.time)
                .font(.system(size: option.timeSize(width), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func cityTitle(_ city: MockCity, width: CGFloat) -> some View {
        HStack(spacing: width * 0.035) {
            Image(systemName: city.isNight ? "moon.stars.fill" : "sun.max.fill")
                .font(.system(size: option.titleSize(width) * 0.85))
                .foregroundColor(city.isNight ? .indigo : .orange)

            Text(city.displayName)
                .font(.system(size: option.titleSize(width), weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func dateLine(_ city: MockCity, width: CGFloat) -> some View {
        Text(mockDateText(relation: city.relation))
            .font(.system(size: option.dateSize(width)))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func mockDateText(relation: String?) -> String {
        let date = String(localized: "widget.guide.mock.date")
        guard let relation else {
            return "\(date) · \(String(localized: "widget.guide.mock.local"))"
        }
        return "\(date) · \(relation)"
    }
}

#Preview {
    NavigationStack {
        AddWidgetGuideView()
    }
}
