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
}

struct LocationExtractionDTO: Codable, Hashable {
    var locations: [LocationDTO]
}

