import Foundation

struct LocationItem: Identifiable, Codable, Hashable {
    enum Category: String, CaseIterable, Codable, Hashable, Identifiable {
        case restaurant
        case cafe
        case museum
        case landmark
        case park
        case shopping
        case nightlife
        case hotel
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .restaurant: "Restaurant"
            case .cafe: "Café"
            case .museum: "Museum"
            case .landmark: "Landmark"
            case .park: "Park"
            case .shopping: "Shopping"
            case .nightlife: "Nightlife"
            case .hotel: "Hotel"
            case .other: "Other"
            }
        }

        var sortRank: Int {
            switch self {
            case .landmark: 0
            case .museum: 1
            case .park: 2
            case .restaurant: 3
            case .cafe: 4
            case .shopping: 5
            case .nightlife: 6
            case .hotel: 7
            case .other: 8
            }
        }
    }

    static func category(fromBackendString raw: String) -> Category {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.contains("rest") || s.contains("bistro") || s.contains("food") || s.contains("diner") { return .restaurant }
        if s.contains("cafe") || s.contains("coffee") { return .cafe }
        if s.contains("museum") || s.contains("gallery") { return .museum }
        if s.contains("park") || s.contains("garden") { return .park }
        if s.contains("hotel") { return .hotel }
        if s.contains("shop") || s.contains("market") || s.contains("mall") { return .shopping }
        if s.contains("bar") || s.contains("club") || s.contains("night") { return .nightlife }
        if s.contains("landmark") || s.contains("monument") || s.contains("cathedral") || s.contains("tower") || s.contains("bridge") { return .landmark }
        return .other
    }

    struct Source: Codable, Hashable {
        enum Kind: String, Codable {
            case manual
            case videoExtraction
        }

        var kind: Kind
        var videoURL: String?
        var rawPayload: String?

        static func manual() -> Self {
            Source(kind: .manual, videoURL: nil, rawPayload: nil)
        }
    }

    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var category: Category
    var notes: String?
    var address: String?
    var phoneNumber: String?
    var url: String?
    var openingHours: String?
    var createdAt: Date
    var source: Source

    init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        category: Category = .other,
        notes: String? = nil,
        address: String? = nil,
        phoneNumber: String? = nil,
        url: String? = nil,
        openingHours: String? = nil,
        createdAt: Date = Date(),
        source: Source = .manual()
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
        self.notes = notes
        self.address = address
        self.phoneNumber = phoneNumber
        self.url = url
        self.openingHours = openingHours
        self.createdAt = createdAt
        self.source = source
    }

    // Backward compatible decoding (older JSON won't have new fields)
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        category = try container.decodeIfPresent(Category.self, forKey: .category) ?? .other
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        openingHours = try container.decodeIfPresent(String.self, forKey: .openingHours)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        source = try container.decode(Source.self, forKey: .source)
    }
}

