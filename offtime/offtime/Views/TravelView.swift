import SwiftUI
import SwiftData
import Combine

/// 行程规划 Tab：编辑当前行程并生成倒时差计划。
/// - Tab 模式：自带导航栈，导航栏提供「新建行程」，页面底部提供「保存当前行程」。
/// - 嵌入模式：从行程列表进入，复用同一编辑界面，仅显示返回按钮。
struct TravelView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TravelViewModel
    @State private var selectedLegID: UUID?
    @State private var selectingOrigin = true
    @State private var showCitySelector = false
    @State private var toastMessage: String?
    @State private var conflictTripID: UUID?
    @State private var showConflictAlert = false
    @State private var showConflictTrip = false
    @State private var now = Date()

    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    let initialTripID: UUID?
    let isEmbedded: Bool

    init(initialTripID: UUID? = nil, isEmbedded: Bool = false) {
        self.initialTripID = initialTripID
        self.isEmbedded = isEmbedded
        _viewModel = StateObject(wrappedValue: TravelViewModel())
    }

    var body: some View {
        Group {
            if isEmbedded {
                content
                    .toolbar(.hidden, for: .tabBar)
            } else {
                NavigationStack {
                    content
                }
            }
        }
        .sheet(isPresented: $showCitySelector) {
            NavigationStack {
                CitySelectorView(onCitySelected: { city in
                    guard let selectedLegID,
                          let index = viewModel.legs.firstIndex(where: { $0.id == selectedLegID }) else {
                        return
                    }

                    if selectingOrigin {
                        viewModel.selectOrigin(city, legIndex: index)
                    } else {
                        viewModel.selectDestination(city, legIndex: index)
                    }
                })
            }
        }
        .alert(
            String(localized: "trip.save.conflict.title"),
            isPresented: $showConflictAlert
        ) {
            Button(String(localized: "trip.save.conflict.view")) {
                showConflictTrip = true
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                conflictTripID = nil
            }
        } message: {
            Text(String(localized: "trip.save.conflict"))
        }
        .sheet(isPresented: $showConflictTrip) {
            NavigationStack {
                if let conflictTripID {
                    TravelView(initialTripID: conflictTripID, isEmbedded: true)
                }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel.isSavedTrip {
                    statusCapsule
                }

                TravelInputSection(
                    viewModel: viewModel,
                    selectedLegID: $selectedLegID,
                    selectingOrigin: $selectingOrigin,
                    showCitySelector: $showCitySelector
                )
                .disabled(isViewOnly)

                if let errorMessage = viewModel.errorMessage {
                    TravelErrorView(message: errorMessage)
                } else if let itinerary = viewModel.itinerary {
                    TravelSummarySection(itinerary: itinerary)

                    if let plan = viewModel.activePlan {
                        TravelTimelineSection(
                            plan: plan,
                            itinerary: itinerary,
                            activeLegIndex: viewModel.activeLegIndex,
                            onSelectLeg: viewModel.selectLeg
                        )

                        if !isViewOnly {
                            saveTripButton
                        }

                        TravelAdviceSection(
                            plan: plan,
                            activeLegIndex: viewModel.activeLegIndex,
                            legCount: itinerary.plans.count
                        )
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "tab.travel"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEmbedded)
        .toolbar {
            if isEmbedded {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            } else {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.newTrip()
                    } label: {
                        Text(String(localized: "trip.new"))
                    }
                }
            }
        }
        .onAppear {
            viewModel.attach(context: modelContext, initialTripID: initialTripID)
            now = Date()
        }
        .onReceive(refreshTimer) { _ in
            now = Date()
        }
        .toast(message: $toastMessage)
    }

    /// 当前编辑行程的状态胶囊：未开始 / 进行中 / 已结束。
    private var statusCapsule: some View {
        HStack(spacing: 8) {
            Text(String(localized: "travel.status"))
                .font(.caption)
                .foregroundColor(.secondary)
            Text(currentStatus.displayName)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(statusColor)
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private var currentStatus: TripStatus {
        TripModel.status(
            at: now,
            firstDeparture: viewModel.legs.first?.departureDate,
            tripEndDate: viewModel.tripEndDate,
            timezoneId: viewModel.legs.last?.destination.timezoneId ?? TimeZone.current.identifier
        )
    }

    private var statusColor: Color {
        switch currentStatus {
        case .ongoing: return .green
        case .upcoming: return .blue
        case .finished: return Color(.systemGray)
        }
    }

    /// 已结束行程为历史记录，进入详情仅可查看，不允许修改。
    private var isViewOnly: Bool {
        viewModel.isSavedTrip && currentStatus == .finished
    }

    /// 保存当前行程：独立大按钮卡片，位于睡眠调整建议卡片上方。
    private var saveTripButton: some View {
        Button {
            saveTrip()
        } label: {
            Label(saveButtonTitle, systemImage: "square.and.arrow.down")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isSaveEnabled)
    }

    /// 草稿或无修改时显示「保存当前行程」；已保存且有修改时显示「修改当前行程」。
    private var saveButtonTitle: LocalizedStringKey {
        viewModel.isDirty ? "trip.update.current" : "trip.save.current"
    }

    /// 已保存且无修改时置灰不可点击。
    private var isSaveEnabled: Bool {
        !viewModel.isSavedTrip || viewModel.isDirty
    }

    private func saveTrip() {
        switch viewModel.save() {
        case .saved:
            toastMessage = String(localized: "trip.saved")
        case .conflict(let tripID):
            conflictTripID = tripID
            showConflictAlert = true
        case .failed:
            toastMessage = String(localized: "trip.save.failed")
        }
    }
}
