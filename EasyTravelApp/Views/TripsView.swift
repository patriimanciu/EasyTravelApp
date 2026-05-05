import SwiftUI

struct TripsView: View {
    @EnvironmentObject private var store: TravelStore
    @State private var isPresentingAddTrip = false

    var body: some View {
        List {
            if store.trips.isEmpty {
                ContentUnavailableView("No trips yet", systemImage: "airplane")
            } else {
                ForEach(store.trips) { trip in
                    NavigationLink(value: trip.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(trip.name)
                                .font(.headline)
                            Text("\(trip.locations.count) location(s)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: store.deleteTrips)
            }
        }
        .navigationDestination(for: UUID.self) { tripID in
            TripDetailView(tripID: tripID)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingAddTrip = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add trip")
            }
        }
        .sheet(isPresented: $isPresentingAddTrip) {
            AddTripView(isPresented: $isPresentingAddTrip)
        }
    }
}

