import Foundation

struct LocationItem: Identifiable, Codable, Hashable {
    enum Category: String, CaseIterable, Codable, Hashable, Identifiable {
        case restaurant
        case cafe
        case museum
        case landmark
        case park
        case neighborhood
        case city
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
            case .neighborhood: "Neighborhood"
            case .city: "City"
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
            case .neighborhood: 3
            case .city: 4
            case .restaurant: 5
            case .cafe: 6
            case .shopping: 7
            case .nightlife: 8
            case .hotel: 9
            case .other: 10
            }
        }
    }

    /// How strongly this stop should appear on the itinerary (5 = must include, 1 = only if time).
    enum VisitPriority: Int, CaseIterable, Codable, Hashable, Identifiable {
        case low = 1
        case ifTime = 2
        case normal = 3
        case high = 4
        case mustSee = 5

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .mustSee: "Must see"
            case .high: "Want to see"
            case .normal: "Normal"
            case .ifTime: "If there's time"
            case .low: "Low priority"
            }
        }

        var planningHint: String {
            switch self {
            case .mustSee: "Always scheduled; dropped only if impossible."
            case .high: "Scheduled before lower-priority stops."
            case .normal: "Standard."
            case .ifTime, .low: "Added when the day budget allows."
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
        if s.contains("neighborhood") || s.contains("neighbourhood") || s.contains("district") || s.contains("borough") || s.contains("quarter") {
            return .neighborhood
        }
        if s.contains("landmark") || s.contains("monument") || s.contains("cathedral") || s.contains("tower") || s.contains("bridge") { return .landmark }
        if s == "city" { return .city }
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
    /// Weekday-based lines (e.g. "Monday: 9:00 AM – 5:00 PM").
    /// Stored as multiple lines so the UI can render each day separately.
    var openingHours: [String]?
    var visitPriority: VisitPriority
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
        openingHours: [String]? = nil,
        visitPriority: VisitPriority = .normal,
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
        self.visitPriority = visitPriority
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
        // Backward compatibility: older JSON stored openingHours as a single string.
        if let lines = try container.decodeIfPresent([String].self, forKey: .openingHours) {
            openingHours = lines.isEmpty ? nil : lines
        } else if let legacy = try container.decodeIfPresent(String.self, forKey: .openingHours) {
            let split = legacy
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            openingHours = split.isEmpty ? nil : split
        } else {
            openingHours = nil
        }
        if let p = try container.decodeIfPresent(Int.self, forKey: .visitPriority) {
            visitPriority = VisitPriority(rawValue: min(5, max(1, p))) ?? .normal
        } else {
            visitPriority = .normal
        }
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        source = try container.decode(Source.self, forKey: .source)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(address, forKey: .address)
        try c.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(openingHours, forKey: .openingHours)
        try c.encode(visitPriority.rawValue, forKey: .visitPriority)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(source, forKey: .source)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, category, notes, address, phoneNumber, url, openingHours
        case visitPriority
        case createdAt, source
    }
}

