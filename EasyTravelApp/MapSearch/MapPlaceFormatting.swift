import MapKit

/// Shared postal line from an `MKPlacemark` (same logic as picking a completion in manual add).
enum MapPlaceFormatting {
    static func postalLine(from placemark: MKPlacemark) -> String? {
        var parts: [String] = []
        if let sub = placemark.subThoroughfare { parts.append(sub) }
        if let thoroughfare = placemark.thoroughfare { parts.append(thoroughfare) }
        if let locality = placemark.locality { parts.append(locality) }
        if let admin = placemark.administrativeArea, !parts.contains(admin) { parts.append(admin) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
