import SwiftUI
import MapKit

/// Used for navigation to LocationDetailView from both trip list and inbox.
struct LocationDetailRoute: Hashable {
    let tripID: Trip.ID?
    let locationID: LocationItem.ID
}

struct LocationDetailView: View {
    @EnvironmentObject private var store: TravelStore
    let locationID: LocationItem.ID
    let tripID: Trip.ID?

    @State private var name: String = ""
    @State private var category: LocationItem.Category = .other
    @State private var address: String = ""
    @State private var phoneNumber: String = ""
    @State private var urlString: String = ""
    @State private var openingHours: String = ""
    @State private var notes: String = ""
    @State private var initialLocation: LocationItem?
    @State private var hasChanges: Bool = false

    private var currentLocation: LocationItem? {
        store.location(id: locationID, tripID: tripID)
    }

    var body: some View {
        Group {
            if let _ = initialLocation {
                Form {
                    Section("Place") {
                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.words)
                        Picker("Category", selection: $category) {
                            ForEach(LocationItem.Category.allCases.sorted(by: { $0.sortRank < $1.sortRank })) { cat in
                                Text(cat.title).tag(cat)
                            }
                        }
                    }

                    Section("Details") {
                        TextField("Address", text: $address)
                            .textInputAutocapitalization(.words)
                        TextField("Phone", text: $phoneNumber)
                            .keyboardType(.phonePad)
                        TextField("Website", text: $urlString)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                        TextField("Opening hours", text: $openingHours)
                    }

                    Section {
                        TextField("What I want to do here", text: $notes, axis: .vertical)
                            .lineLimit(3...8)
                    } header: {
                        Text("Notes")
                    } footer: {
                        Text("Add your plans or ideas for this spot.")
                    }

                    Section("Map") {
                        if let loc = currentLocation {
                            MiniMapView(latitude: loc.latitude, longitude: loc.longitude, name: loc.name)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                }
                .navigationTitle("Location")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if hasChanges {
                            Button("Save") { save() }
                                .fontWeight(.semibold)
                        }
                    }
                }
                .onChange(of: name) { _, _ in setHasChanges() }
                .onChange(of: category) { _, _ in setHasChanges() }
                .onChange(of: address) { _, _ in setHasChanges() }
                .onChange(of: phoneNumber) { _, _ in setHasChanges() }
                .onChange(of: urlString) { _, _ in setHasChanges() }
                .onChange(of: openingHours) { _, _ in setHasChanges() }
                .onChange(of: notes) { _, _ in setHasChanges() }
            } else {
                ContentUnavailableView("Location not found", systemImage: "mappin.slash")
            }
        }
        .onAppear { loadFromStore() }
        .onChange(of: currentLocation?.id) { _, _ in loadFromStore() }
    }

    private func loadFromStore() {
        guard let loc = currentLocation else {
            initialLocation = nil
            return
        }
        initialLocation = loc
        name = loc.name
        category = loc.category
        address = loc.address ?? ""
        phoneNumber = loc.phoneNumber ?? ""
        urlString = loc.url ?? ""
        openingHours = loc.openingHours ?? ""
        notes = loc.notes ?? ""
        hasChanges = false
    }

    private func setHasChanges() {
        guard let loc = initialLocation else { return }
        hasChanges = name != loc.name
            || category != loc.category
            || address != (loc.address ?? "")
            || phoneNumber != (loc.phoneNumber ?? "")
            || urlString != (loc.url ?? "")
            || openingHours != (loc.openingHours ?? "")
            || notes != (loc.notes ?? "")
    }

    private func save() {
        guard let loc = initialLocation else { return }
        let updated = LocationItem(
            id: loc.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: loc.latitude,
            longitude: loc.longitude,
            category: category,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines),
            address: address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : address.trimmingCharacters(in: .whitespacesAndNewlines),
            phoneNumber: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            url: urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : urlString.trimmingCharacters(in: .whitespacesAndNewlines),
            openingHours: openingHours.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : openingHours.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: loc.createdAt,
            source: loc.source
        )
        store.updateLocation(tripID: tripID, location: updated)
        initialLocation = updated
        hasChanges = false
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
