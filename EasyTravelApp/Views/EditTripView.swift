import MapKit
import SwiftUI

struct EditTripView: View {
    @EnvironmentObject private var store: TravelStore
    @Binding var isPresented: Bool
    let tripID: Trip.ID

    @State private var name: String = ""
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
            Form {
                Section("Trip") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    Toggle("Trip dates", isOn: $includeDates)

                    if includeDates {
                        DatePicker("Start", selection: $startDate, displayedComponents: [.date])
                        DatePicker("End", selection: $endDate, displayedComponents: [.date])
                    }
                }

                Section {
                    Toggle("Accommodation (daily hub)", isOn: $includeStay)
                    if includeStay {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Stay")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(stayName.isEmpty ? "Not chosen yet" : stayName)
                                    .font(.body)
                            }
                            Spacer()
                            Button("Search maps…") {
                                isPresentingStaySearch = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
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
                } header: {
                    Text("Where you stay")
                } footer: {
                    Text(
                        includeStay
                            ? "Search picks a place from Apple Maps; planning uses walking paths from OSRM, starting and ending each day at this hub."
                            : "Optional. When set, routing assumes you start and end each day here."
                    )
                    .font(.footnote)
                }

                if includeDates || includeStay {
                    Section {
                        Text("Changing trip dates or accommodation clears a saved route plan.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Trip settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                        isPresented = false
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                syncFromStore()
            }
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
        guard !trimmed.isEmpty else { return false }
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
        guard !trimmed.isEmpty else { return }

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
            store.updateTripMetadata(id: tripID, name: trimmed, startDate: s, endDate: e, accommodation: acc)
        } else {
            store.updateTripMetadata(id: tripID, name: trimmed, startDate: nil, endDate: nil, accommodation: acc)
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
