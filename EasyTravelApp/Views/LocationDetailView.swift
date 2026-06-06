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

    private var parentTrip: Trip? {
        guard let tripID else { return nil }
        return store.trips.first(where: { $0.id == tripID })
    }

    var body: some View {
        Group {
            if let loc = currentLocation, initialLocation != nil {
                locationScrollContent(loc: loc)
            } else {
                ContentUnavailableView("Location not found", systemImage: "mappin.slash")
            }
        }
        .onAppear { loadFromStore() }
        .onChange(of: currentLocation?.id) { _, _ in loadFromStore() }
    }

    private func locationScrollContent(loc: LocationItem) -> some View {
        ScrollView {
            locationCardsStack(loc: loc)
                    .appPagePadding()
                    .padding(.vertical, 20)
                    .padding(.bottom, 24)
        }
        .appScreenBackground()
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Edit") {
                    EditLocationView(locationID: locationID, tripID: tripID)
                        .environmentObject(store)
                }
                .fontWeight(.semibold)
            }
        }
    }

    @ViewBuilder
    private func locationCardsStack(loc: LocationItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            placeSection(loc: loc).softCard()
            detailsSection(loc: loc).softCard()
            if hasNotes(loc) {
                notesSection(loc: loc).softCard()
            }
            mapSection(loc: loc).softCard(cardPadding: 0)
        }
    }

    private func hasNotes(_ loc: LocationItem) -> Bool {
        guard let notes = loc.notes?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !notes.isEmpty
    }

    @ViewBuilder
    private func placeSection(loc: LocationItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            CategoryIconBadge(category: loc.category, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.charcoal)
                Text(loc.category.title)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.categoryTint(loc.category))
            }
            Spacer(minLength: 0)
        }
    }

    private func detailsSection(loc: LocationItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
                .foregroundStyle(AppTheme.charcoal)
            if let trip = parentTrip {
                if let c = trip.trimmedCity {
                    detailRow(label: "City", value: c)
                }
                if !trip.trimmedCountry.isEmpty {
                    detailRow(label: "Country", value: trip.trimmedCountry)
                }
            } else {
                if let c = loc.trimmedInboxCity {
                    detailRow(label: "City", value: c)
                }
                if let co = loc.trimmedInboxCountry {
                    detailRow(label: "Country", value: co)
                }
            }
            if let address = loc.address, !address.isEmpty {
                detailRow(label: "Address", value: address)
            }
            if let phone = loc.phoneNumber, !phone.isEmpty {
                detailRow(label: "Phone", value: phone)
            }
            if let url = loc.url, !url.isEmpty {
                detailRow(label: "Website", value: url)
            }
            openingHoursContent(loc: loc)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func openingHoursContent(loc: LocationItem) -> some View {
        let summary = openingHoursSummary(loc)
        if summary != "—" {
            detailRow(label: "Hours", value: summary)
        }
        let lines = openingHoursLines(loc)
        if !lines.isEmpty {
            openingHoursLineRows(lines)
        }
    }

    private func openingHoursSummary(_ loc: LocationItem) -> String {
        OpeningHoursFormatter.summary(openingHours: loc.openingHours, category: loc.category)
    }

    private func openingHoursLines(_ loc: LocationItem) -> [String] {
        OpeningHoursFormatter.displayLines(openingHours: loc.openingHours, category: loc.category)
    }

    private func openingHoursLineRows(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private func notesSection(loc: LocationItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)
                .foregroundStyle(AppTheme.charcoal)
            if let notes = loc.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func mapSection(loc: LocationItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Map")
                .font(.headline)
                .foregroundStyle(AppTheme.charcoal)
                .padding(.horizontal, AppTheme.cardPadding)
                .padding(.top, AppTheme.cardPadding)
            MiniMapView(latitude: loc.latitude, longitude: loc.longitude, name: loc.name)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius - 4, style: .continuous))
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
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
        .frame(height: 180)
        .allowsHitTesting(false)
    }
}

#Preview("Location detail — trip") {
    PreviewShell.navigation {
        LocationDetailView(
            locationID: PreviewData.parisLocationID,
            tripID: PreviewData.parisTripID
        )
    }
    .environmentObject(TravelStore.preview)
}

#Preview("Location detail — inbox") {
    PreviewShell.navigation {
        LocationDetailView(
            locationID: PreviewData.inboxLocationID,
            tripID: nil
        )
    }
    .environmentObject(TravelStore.preview)
}

#Preview("Mini map") {
    MiniMapView(
        latitude: PreviewData.parisLocation.latitude,
        longitude: PreviewData.parisLocation.longitude,
        name: PreviewData.parisLocation.name
    )
    .softCard(cardPadding: 0)
    .padding()
}
