import MapKit

/// Map region and place filter from a trip’s country (required) and optional city.
struct TripPlaceSearchContext {
    let region: MKCoordinateRegion?
    let city: String?
    let country: String?

    var hasPlaceFilter: Bool {
        let co = country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let c = city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !co.isEmpty || !c.isEmpty
    }

    var filterSummary: String? {
        let co = country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let c = city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch (c.isEmpty, co.isEmpty) {
        case (false, false): return "\(c), \(co)"
        case (false, true): return c
        case (true, false): return co
        case (true, true): return nil
        }
    }

    static func make(from trip: Trip) -> TripPlaceSearchContext {
        TripPlaceSearchContext(
            region: coordinateRegion(for: trip),
            city: trip.trimmedCity,
            country: trip.trimmedCountry.isEmpty ? nil : trip.trimmedCountry
        )
    }

    private static func coordinateRegion(for trip: Trip) -> MKCoordinateRegion? {
        var lats = trip.locations.map(\.latitude)
        var lons = trip.locations.map(\.longitude)
        if let a = trip.accommodation {
            lats.append(a.latitude)
            lons.append(a.longitude)
        }
        guard let minLa = lats.min(), let maxLa = lats.max(),
              let minLo = lons.min(), let maxLo = lons.max()
        else { return nil }
        let center = CLLocationCoordinate2D(
            latitude: (minLa + maxLa) / 2,
            longitude: (minLo + maxLo) / 2
        )
        let spanLat = max(0.06, (maxLa - minLa) * 2.0)
        let spanLon = max(0.06, (maxLo - minLo) * 2.0)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
        )
    }
}
