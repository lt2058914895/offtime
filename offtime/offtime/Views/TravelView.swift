import SwiftUI

struct TravelView: View {
    @StateObject private var viewModel = TravelViewModel()
    @State private var selectedLegID: UUID?
    @State private var selectingOrigin = true
    @State private var showCitySelector = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TravelInputSection(
                        viewModel: viewModel,
                        selectedLegID: $selectedLegID,
                        selectingOrigin: $selectingOrigin,
                        showCitySelector: $showCitySelector
                    )

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
            .toolbar(.hidden, for: .navigationBar)
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
        }
    }
}
