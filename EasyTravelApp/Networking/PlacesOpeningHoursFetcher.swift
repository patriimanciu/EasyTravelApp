import CoreLocation
import Foundation

/// Google **Places API (New)** — MapKit does not expose business hours on `MKMapItem`.
/// User adds an API key in Import → optional; billing / quota are on the developer’s Google Cloud project.
///
/// Enable “Places API (New)” and create an API key restricted to this API + your iOS bundle if desired.
enum PlacesOpeningHoursFetcher {

    /// Weekday-based lines like "Monday: 9:00 AM – 5:00 PM", or nil if unavailable / no key / error.
    static func weekdayDescriptionsIfAvailable(
        placeName: String,
        city: String,
        coordinate: CLLocationCoordinate2D,
        apiKey: String
    ) async -> [String]? {
        let (hours, _) = await weekdayDescriptionsWithDebug(
            placeName: placeName,
            city: city,
            coordinate: coordinate,
            apiKey: apiKey
        )
        return hours
    }

    /// Same as `weekdayDescriptionsIfAvailable` but also returns a debug message on failure.
    /// Debug text is safe to show in-app (no API key included).
    static func weekdayDescriptionsWithDebug(
        placeName: String,
        city: String,
        coordinate: CLLocationCoordinate2D,
        apiKey: String
    ) async -> (hours: [String]?, debug: String?) {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return (nil, "No Google Places API key provided.") }

        let query = [placeName, city]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        guard !query.isEmpty else { return (nil, "Empty Places text query.") }

        let (placeId, searchDebug) = await searchPlaceId(textQuery: query, coordinate: coordinate, apiKey: key)
        guard let placeId else {
            return (nil, searchDebug ?? "Places Text Search returned no place id.")
        }
        return await fetchWeekdayDescriptions(placeId: placeId, apiKey: key)
    }

    // MARK: - Places API (New)

    private static func searchPlaceId(
        textQuery: String,
        coordinate: CLLocationCoordinate2D,
        apiKey: String
    ) async -> (placeId: String?, debug: String?) {
        guard let url = URL(string: "https://places.googleapis.com/v1/places:searchText") else {
            return (nil, "Invalid Places Text Search URL.")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        req.setValue("places.id", forHTTPHeaderField: "X-Goog-FieldMask")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "textQuery": textQuery,
            "locationBias": [
                "circle": [
                    "center": [
                        "latitude": coordinate.latitude,
                        "longitude": coordinate.longitude,
                    ],
                    "radius": 1500.0,
                ],
            ],
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return (nil, "Failed to encode Places Text Search JSON body.")
        }
        req.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                return (nil, "Places Text Search: invalid response.")
            }
            guard (200...299).contains(http.statusCode) else {
                return (nil, "Places Text Search HTTP \(http.statusCode): \(truncateBody(data))")
            }
            let decoded = try JSONDecoder().decode(TextSearchResponse.self, from: data)
            return (decoded.places?.first?.id, nil)
        } catch {
            return (nil, "Places Text Search error: \(error.localizedDescription)")
        }
    }

    private static func fetchWeekdayDescriptions(placeId: String, apiKey: String) async -> (hours: [String]?, debug: String?) {
        guard let encoded = placeId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://places.googleapis.com/v1/places/\(encoded)") else { return (nil, "Invalid Place Details URL.") }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        req.setValue("regularOpeningHours.weekdayDescriptions", forHTTPHeaderField: "X-Goog-FieldMask")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                return (nil, "Places Details: invalid response.")
            }
            guard (200...299).contains(http.statusCode) else {
                return (nil, "Places Details HTTP \(http.statusCode): \(truncateBody(data))")
            }
            let decoded = try JSONDecoder().decode(PlaceDetailsResponse.self, from: data)
            let rawLines = decoded.regularOpeningHours?.weekdayDescriptions ?? []
            let lines = rawLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return (lines.isEmpty ? nil : lines, lines.isEmpty ? "Places Details returned no opening hours." : nil)
        } catch {
            return (nil, "Places Details error: \(error.localizedDescription)")
        }
    }

    private static func truncateBody(_ data: Data) -> String {
        let s = String(data: data, encoding: .utf8) ?? ""
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "(empty body)" }
        if trimmed.count <= 220 { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 220)
        return String(trimmed[..<idx]) + "…"
    }

    private struct TextSearchResponse: Decodable {
        let places: [PlaceRef]?
        struct PlaceRef: Decodable {
            /// Standalone Place ID suitable for `GET …/v1/places/{placeId}`.
            let id: String
        }
    }

    private struct PlaceDetailsResponse: Decodable {
        let regularOpeningHours: RegularOpeningHours?
        struct RegularOpeningHours: Decodable {
            let weekdayDescriptions: [String]?
        }
    }
}
