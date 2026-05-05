import Foundation
import MapKit

/// First hit from `MKLocalSearch` — same source of truth as manually picked places in `PlaceSearchViewModel`.
/// Apple does **not** expose opening hours on `MKMapItem`; use `PlacesOpeningHoursFetcher` if you need hours programmatically.
struct ResolvedMapPlace: Sendable {
    let coordinate: CLLocationCoordinate2D
    let formattedAddress: String?
    let phoneNumber: String?
    let url: String?
}

enum LocationResolver {
    /// Geocodes by natural language query and returns Apple Maps POI metadata when available (address, phone, website).
    static func resolvePlace(name: String, city: String, address: String? = nil) async throws -> ResolvedMapPlace {
        let parts = [name, address, city].compactMap { raw -> String? in
            guard let raw else { return nil }
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        let query = parts.joined(separator: ", ")

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]

        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        guard let item = response.mapItems.first else {
            throw NSError(domain: "LocationResolver", code: 404, userInfo: [NSLocalizedDescriptionKey: "No map result for \(query)"])
        }
        let pm = item.placemark
        return ResolvedMapPlace(
            coordinate: pm.coordinate,
            formattedAddress: MapPlaceFormatting.postalLine(from: pm),
            phoneNumber: item.phoneNumber,
            url: item.url?.absoluteString
        )
    }
}
