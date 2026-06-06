import MapKit
import SwiftUI

struct EditTripView: View {
    @EnvironmentObject private var store: TravelStore
    @Binding var isPresented: Bool
    let tripID: Trip.ID

    @State private var name: String = ""
    @State private var country: String = ""
    @State private var city: String = ""
    @State private var includeDates = false
    @State private var startDate = Date()
    @State private var endDate = Date()

    @State private var includeStay = false
    @State private var stayName: String = ""
    @State private var stayLatText: String = ""
    @State private var stayLonText: String = ""
    @State private var isPresentingStaySearch = false

    private var trip: Trip? {
        store.trips.first(where: { $0.id == tripID })
    }

    /// Biases Apple local search toward the trip’s stops (city-scale).
    private var staySearchBiasRegion: MKCoordinateRegion? {
        guard let t = trip, !t.locations.isEmpty else { return nil }
        let lats = t.locations.map(\.latitude)
        let lons = t.locations.map(\.longitude)
        guard let minLa = lats.min(), let maxLa = lats.max(),
              let minLo = lons.min(), let maxLo = lons.max()
        else { return nil }
        let center = CLLocationCoordinate2D(latitude: (minLa + maxLa) / 2, longitude: (minLo + maxLo) / 2)
        let spanLat = max(0.06, (maxLa - minLa) * 2.0)
        let spanLon = max(0.06, (maxLo - minLo) * 2.0)
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    AppFormSection(
                        title: "Trip",
                        footer: "Country is required. City is optional. All stops use these values for Maps search when you add locations."
                    ) {
                        AppFormField(label: "Name", placeholder: "Trip name", text: $name, autocapitalizeWords: true)
                        AppFormField(label: "Country", placeholder: "Required", text: $country, autocapitalizeWords: true)
                        AppFormField(label: "City", placeholder: "Optional", text: $city, autocapitalizeWords: true)
                        Toggle("Trip dates", isOn: $includeDates)
                        if includeDates {
                            DatePicker("Start", selection: $startDate, displayedComponents: [.date])
                            DatePicker("End", selection: $endDate, displayedComponents: [.date])
                        }
                    }

                    AppFormSection(
                        title: "Where you stay",
                        footer: includeStay
                            ? "Search picks a place from Apple Maps; planning uses walking paths from OSRM, starting and ending each day at this hub."
                            : "Optional. When set, routing assumes you start and end each day here."
                    ) {
                        Toggle("Accommodation (daily hub)", isOn: $includeStay)
                        if includeStay {
                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Stay")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(stayName.isEmpty ? "Not chosen yet" : stayName)
                                        .font(.body)
                                        .foregroundStyle(AppTheme.charcoal)
                                }
                                Button {
                                    isPresentingStaySearch = true
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "magnifyingglass")
                                        Text("Search maps…")
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .foregroundStyle(.white)
                                    .background(AppTheme.charcoal, in: RoundedRectangle(cornerRadius: AppTheme.pillRadius, style: .continuous))
                                }
                                .buttonStyle(.plain)

                                if let lat = Double(stayLatText.replacingOccurrences(of: ",", with: ".")),
                                   let lon = Double(stayLonText.replacingOccurrences(of: ",", with: ".")),
                                   !stayLatText.isEmpty
                                {
                                    Text(String(format: "Coordinates %.5f, %.5f", lat, lon))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                TextField("Display name (optional edit)", text: $stayName)
                                    .textInputAutocapitalization(.words)
                            }
                        }
                    }

                    if includeDates || includeStay {
                        AppTipBanner(
                            text: "Changing trip dates or accommodation clears a saved route plan.",
                            systemImage: "info.circle"
                        )
                    }
                }
                .appPagePadding()
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .appScreenBackground()
            .navigationTitle("Trip settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundStyle(AppTheme.charcoal)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .tint(AppTheme.charcoal)
            .onAppear { syncFromStore() }
            .sheet(isPresented: $isPresentingStaySearch) {
                AccommodationSearchView(
                    biasRegion: staySearchBiasRegion,
                    onPick: { title, lat, lon in
                        stayName = title
                        stayLatText = String(format: "%.6f", lat)
                        stayLonText = String(format: "%.6f", lon)
                    }
                )
            }
        }
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmedCountry.isEmpty else { return false }
        if includeStay {
            let n = stayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !n.isEmpty else { return false }
            guard let lat = Double(stayLatText.replacingOccurrences(of: ",", with: ".")),
                  let lon = Double(stayLonText.replacingOccurrences(of: ",", with: "."))
            else { return false }
            guard (-90 ... 90).contains(lat), (-180 ... 180).contains(lon) else { return false }
        }
        return true
    }

    private func syncFromStore() {
        guard let t = trip else { return }
        name = t.name
        country = t.country
        city = t.city ?? ""
        if let s = t.startDate, let e = t.endDate {
            includeDates = true
            startDate = s
            endDate = e
        } else {
            includeDates = false
            startDate = Date()
            endDate = Date()
        }
        if let a = t.accommodation {
            includeStay = true
            stayName = a.name
            stayLatText = String(format: "%.6f", a.latitude)
            stayLonText = String(format: "%.6f", a.longitude)
        } else {
            includeStay = false
            stayName = ""
            stayLatText = ""
            stayLonText = ""
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmedCountry.isEmpty else { return }
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let cityValue = trimmedCity.isEmpty ? nil : trimmedCity

        let acc: TripAccommodation?
        if includeStay,
           let lat = Double(stayLatText.replacingOccurrences(of: ",", with: ".")),
           let lon = Double(stayLonText.replacingOccurrences(of: ",", with: ".")),
           (-90 ... 90).contains(lat), (-180 ... 180).contains(lon)
        {
            let n = stayName.trimmingCharacters(in: .whitespacesAndNewlines)
            acc = TripAccommodation(name: n.isEmpty ? "Stay" : n, latitude: lat, longitude: lon)
        } else {
            acc = nil
        }

        if includeDates {
            let cal = Calendar.current
            let s = cal.startOfDay(for: startDate)
            var e = cal.startOfDay(for: endDate)
            if e < s { e = s }
            store.updateTripMetadata(
                id: tripID, name: trimmed, country: trimmedCountry, city: cityValue,
                startDate: s, endDate: e, accommodation: acc
            )
        } else {
            store.updateTripMetadata(
                id: tripID, name: trimmed, country: trimmedCountry, city: cityValue,
                startDate: nil, endDate: nil, accommodation: acc
            )
        }
    }
}

#Preview("Edit trip") {
    @Previewable @State var isPresented = true
    EditTripView(
        isPresented: $isPresented,
        tripID: PreviewData.parisTripID
    )
    .environmentObject(TravelStore.preview)
}
