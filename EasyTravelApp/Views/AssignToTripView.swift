import SwiftUI

struct AssignToTripView: View {
    @EnvironmentObject private var store: TravelStore
    @Binding var isPresented: Bool
    var selectedLocationIDs: Set<LocationItem.ID> = []

    var body: some View {
        NavigationStack {
            List {
                if store.trips.isEmpty {
                    ContentUnavailableView("No trips yet", systemImage: "airplane")
                } else {
                    ForEach(store.trips) { trip in
                        Button {
                            store.moveInboxLocations(selectedLocationIDs, to: trip.id)
                            isPresented = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(trip.name)
                                    .font(.headline)
                                Text("\(trip.locations.count) location(s)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(selectedLocationIDs.count > 1 ? "Assign \(selectedLocationIDs.count) to Trip" : "Assign to Trip")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}

#Preview("Assign to trip") {
    @Previewable @State var isPresented = true
    AssignToTripView(
        isPresented: $isPresented,
        selectedLocationIDs: Set(TravelStore.preview.inbox.map(\.id))
    )
    .environmentObject(TravelStore.preview)
}