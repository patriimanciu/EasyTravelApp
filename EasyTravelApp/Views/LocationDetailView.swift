import SwiftUI
import MapKit
internal import _LocationEssentials

/// Used for navigation to LocationDetailView from both trip list and inbox.
struct LocationDetailRoute: Hashable {
    let tripID: Trip.ID?
    let locationID: LocationItem.ID
}

struct LocationDetailView: View {
    @EnvironmentObject private var store: TravelStore
    let locationID: LocationItem.ID
    let tripID: Trip.ID?

    @State private var initialLocation: LocationItem?

    private var currentLocation: LocationItem? {
        store.location(id: locationID, tripID: tripID)
    }

    var body: some View {
        Group {
            if let loc = currentLocation, initialLocation != nil {
                Form {
                    placeSection(loc: loc)
                    detailsSection(loc: loc)
                    notesSection(loc: loc)
                    mapSection(loc: loc)
                }
                .navigationTitle("Location")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink("Edit") {
                            EditLocationView(locationID: locationID, tripID: tripID)
                                .environmentObject(store)
                        }
                        .fontWeight(.semibold)
                    }
                }
            } else {
                ContentUnavailableView("Location not found", systemImage: "mappin.slash")
            }
        }
        .onAppear { loadFromStore() }
        .onChange(of: currentLocation?.id) { _, _ in loadFromStore() }
    }

    @ViewBuilder
    private func placeSection(loc: LocationItem) -> some View {
        Section {
            Text(loc.name)
                .font(.headline)
            Text(loc.category.title)
                .foregroundStyle(.secondary)
        } header: {
            Text("Place")
        }
    }

    @ViewBuilder
    private func detailsSection(loc: LocationItem) -> some View {
        Section {
            if let address = loc.address, !address.isEmpty {
                LabeledContent("Address", value: address)
            }
            if let phone = loc.phoneNumber, !phone.isEmpty {
                LabeledContent("Phone", value: phone)
            }
            if let url = loc.url, !url.isEmpty {
                LabeledContent("Website", value: url)
            }

            let summary = OpeningHoursFormatter.summary(openingHours: loc.openingHours, category: loc.category)
            if summary != "—" {
                LabeledContent("Opening hours", value: summary)
            }

            let lines = OpeningHoursFormatter.displayLines(openingHours: loc.openingHours, category: loc.category)
            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Details")
        }
    }

    @ViewBuilder
    private func notesSection(loc: LocationItem) -> some View {
        Section {
            if let notes = loc.notes, !notes.isEmpty {
                Text(notes)
            } else {
                Text("No notes yet.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Notes")
        } footer: {
            Text("Add your plans or ideas for this spot.")
        }
    }

    @ViewBuilder
    private func mapSection(loc: LocationItem) -> some View {
        Section {
            MiniMapView(latitude: loc.latitude, longitude: loc.longitude, name: loc.name)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("Map")
        }
    }

    private func loadFromStore() {
        guard let loc = currentLocation else {
            initialLocation = nil
            return
        }
        initialLocation = loc
    }
}

// Small map preview for the detail page
struct MiniMapView: View {
    let latitude: Double
    let longitude: Double
    let name: String

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))) {
            Annotation(name, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
            }
        }
        .frame(height: 160)
        .allowsHitTesting(false)
    }
}
