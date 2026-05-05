import Foundation

struct VideoRequestDTO: Codable {
    var url: String
}

struct BackendErrorDTO: Codable {
    var detail: String
}

struct LocationDTO: Codable, Hashable {
    var name: String
    var category: String
    var city: String
    /// Present only when backend extraction found an explicit address in video modalities.
    var address: String?
    var phoneNumber: String?
    var url: String?
    var openingHours: String?
    var sourceModalities: [String]?
    var confidence: Double?

    enum CodingKeys: String, CodingKey {
        case name, category, city, address, url, confidence
        case phoneNumber = "phone_number"
        case openingHours = "opening_hours"
        case sourceModalities = "source_modalities"
    }
}

struct LocationExtractionDTO: Codable, Hashable {
    var locations: [LocationDTO]
}

