import Foundation
import MapKit

enum LocationResolver {
    static func resolveCoordinate(name: String, city: String) async throws -> CLLocationCoordinate2D {
        let query = [name, city].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: ", ")

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]

        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        guard let first = response.mapItems.first else {
            throw NSError(domain: "LocationResolver", code: 404, userInfo: [NSLocalizedDescriptionKey: "No map result for \(query)"])
        }
        return first.placemark.coordinate
    }
}

