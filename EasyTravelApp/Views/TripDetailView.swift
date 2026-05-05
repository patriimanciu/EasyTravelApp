import SwiftUI

struct TripDetailView: View {
    @EnvironmentObject private var store: TravelStore
    let tripID: Trip.ID

    @State private var isPresentingAddLocation = false
    @State private var isPresentingImport = false
    @State private var selectedTab: Tab = .list

    enum Tab: String, CaseIterable, Identifiable {
        case list = "List"
        case map = "Map"

        var id: String { rawValue }
    }

    private var trip: Trip? {
        store.trips.first(where: { $0.id == tripID })
    }

    private var groupedLocations: [(category: LocationItem.Category, locations: [LocationItem])] {
        guard let trip else { return [] }
        let groups = Dictionary(grouping: trip.locations, by: { $0.category })
        return groups
            .map { (category: $0.key, locations: $0.value.sorted(by: { $0.createdAt > $1.createdAt })) }
            .sorted(by: { $0.category.sortRank < $1.category.sortRank })
    }

    var body: some View {
        Group {
            if let trip {
                VStack(spacing: 0) {
                    Picker("View", selection: $selectedTab) {
                        ForEach(Tab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    if selectedTab == .map {
                        TripMapView(trip: trip)
                    } else {
                        List {
                            if trip.locations.isEmpty {
                                Section("Locations") {
                                    ContentUnavailableView("No locations yet", systemImage: "mappin.and.ellipse")
                                }
                            } else {
                                ForEach(groupedLocations, id: \.category) { group in
                                    Section(group.category.title) {
                                        ForEach(group.locations) { loc in
                                            NavigationLink(value: LocationDetailRoute(tripID: tripID, locationID: loc.id)) {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(loc.name)
                                                        .font(.headline)
                                                    Text(String(format: "%.5f, %.5f", loc.latitude, loc.longitude))
                                                        .font(.subheadline)
                                                        .foregroundStyle(.secondary)
                                                    if let notes = loc.notes, !notes.isEmpty {
                                                        Text(notes)
                                                            .font(.footnote)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                            }
                                        }
                                        .onDelete { offsets in
                                            let idsToDelete = offsets.compactMap { index in
                                                group.locations[safe: index]?.id
                                            }
                                            for id in idsToDelete {
                                                store.deleteLocation(tripID: tripID, locationID: id)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle(trip.name)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isPresentingImport = true
                        } label: {
                            Image(systemName: "tray.and.arrow.down")
                        }
                        .accessibilityLabel("Import from video")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isPresentingAddLocation = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add location")
                    }
                }
                .sheet(isPresented: $isPresentingAddLocation) {
                    AddLocationView(tripID: tripID, isPresented: $isPresentingAddLocation)
                }
                .sheet(isPresented: $isPresentingImport) {
                    ImportFromVideoView(isPresented: $isPresentingImport)
                }
                .navigationDestination(for: LocationDetailRoute.self) { route in
                    LocationDetailView(locationID: route.locationID, tripID: route.tripID)
                        .environmentObject(store)
                }
            } else {
                ContentUnavailableView("Trip not found", systemImage: "exclamationmark.triangle")
            }
        }
    }
}

