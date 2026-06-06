import MapKit

/// Shared address fields from an `MKMapItem` (same logic as picking a completion in manual add).
enum MapPlaceFormatting {
    static func coordinate(from item: MKMapItem) -> CLLocationCoordinate2D {
        item.location.coordinate
    }

    static func city(from item: MKMapItem) -> String? {
        nonBlank(item.addressRepresentations?.cityName)
    }

    static func country(from item: MKMapItem) -> String? {
        nonBlank(item.addressRepresentations?.regionName)
    }

    static func postalLine(from item: MKMapItem) -> String? {
        if let formatted = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true) {
            return nonBlank(formatted)
        }
        return nonBlank(item.address?.fullAddress)
    }

    static func shortAddress(from item: MKMapItem) -> String? {
        nonBlank(item.address?.shortAddress)
    }

    private static func nonBlank(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
