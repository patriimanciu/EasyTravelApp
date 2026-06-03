import SwiftUI

struct TripsView: View {
    @EnvironmentObject private var store: TravelStore
    @State private var isPresentingAddTrip = false
    @State private var isPresentingImport = false
    @State private var planTripID: Trip.ID?
    @State private var tripToDelete: Trip.ID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                HomeHeaderView(
                    greeting: "Hello",
                    subtitle: "Your trips",
                    onAddTrip: { isPresentingAddTrip = true }
                )
                .padding(.top, 8)

                PlanHeroCard {
                    handlePlanWithAI()
                }

                SectionTitle(
                    title: store.trips.isEmpty ? "Get started" : "Your trips",
                    trailing: store.trips.isEmpty ? nil : "\(store.trips.count)"
                )

                if store.trips.isEmpty {
                    AppEmptyState(
                        title: "No trips yet",
                        systemImage: "airplane.departure",
                        message: "Create a trip or import places from a video to begin planning."
                    )
                } else {
                    VStack(spacing: 16) {
                        ForEach(store.trips) { trip in
                            NavigationLink(value: trip.id) {
                                TripListingCard(trip: trip)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Plan route…") {
                                    planTripID = trip.id
                                }
                                .disabled(trip.locations.count < 2)
                                Button("Delete", role: .destructive) {
                                    tripToDelete = trip.id
                                }
                            }
                        }
                    }
                }
            }
            .appPagePadding()
            .padding(.top, 12)
            .appBottomTabPadding()
        }
        .appScreenBackground()
        .navigationDestination(for: UUID.self) { tripID in
            TripDetailView(tripID: tripID)
        }
        .sheet(isPresented: $isPresentingAddTrip) {
            AddTripView(isPresented: $isPresentingAddTrip)
        }
        .sheet(isPresented: $isPresentingImport) {
            ImportFromVideoView(isPresented: $isPresentingImport)
        }
        .sheet(isPresented: Binding(
            get: { planTripID != nil },
            set: { if !$0 { planTripID = nil } }
        )) {
            if let tripID = planTripID, let trip = store.trips.first(where: { $0.id == tripID }) {
                PlanRouteSheet(isPresented: Binding(
                    get: { planTripID != nil },
                    set: { if !$0 { planTripID = nil } }
                ), tripID: tripID, trip: trip)
                .environmentObject(store)
            }
        }
        .confirmationDialog(
            "Delete this trip?",
            isPresented: Binding(
                get: { tripToDelete != nil },
                set: { if !$0 { tripToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let id = tripToDelete {
                Button("Delete", role: .destructive) {
                    if let idx = store.trips.firstIndex(where: { $0.id == id }) {
                        store.deleteTrips(at: IndexSet(integer: idx))
                    }
                    tripToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { tripToDelete = nil }
        }
    }

    private func handlePlanWithAI() {
        if let trip = store.trips.first(where: { $0.locations.count >= 2 }) {
            planTripID = trip.id
        } else if store.trips.isEmpty {
            isPresentingImport = true
        } else {
            isPresentingAddTrip = true
        }
    }
}

#Preview("Trips — with data") {
    PreviewShell.navigation {
        TripsView()
            .toolbar(.hidden, for: .navigationBar)
    }
    .environmentObject(TravelStore.preview)
    .appScreenBackground()
}

#Preview("Trips — empty") {
    PreviewShell.navigation {
        TripsView()
            .toolbar(.hidden, for: .navigationBar)
    }
    .environmentObject(PreviewData.emptyStore)
    .appScreenBackground()
}
