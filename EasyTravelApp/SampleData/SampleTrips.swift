import Foundation

enum SampleTrips {
    static func make() -> [Trip] {
        [
            Trip(
                name: "Paris",
                startDate: nil,
                endDate: nil,
                locations: [
                    LocationItem(
                        name: "Eiffel Tower",
                        latitude: 48.858370,
                        longitude: 2.294481,
                        category: .landmark
                    ),
                    LocationItem(
                        name: "Louvre Museum",
                        latitude: 48.860611,
                        longitude: 2.337644,
                        category: .museum
                    ),
                    LocationItem(
                        name: "Notre‑Dame Cathedral",
                        latitude: 48.853000,
                        longitude: 2.349900,
                        category: .landmark
                    ),
                    LocationItem(
                        name: "Luxembourg Gardens",
                        latitude: 48.846222,
                        longitude: 2.337160,
                        category: .park
                    ),
                    LocationItem(
                        name: "Le Relais de l’Entrecôte (Porte Maillot)",
                        latitude: 48.878900,
                        longitude: 2.283500,
                        category: .restaurant
                    )
                ]
            ),
            Trip(
                name: "London",
                startDate: nil,
                endDate: nil,
                locations: [
                    LocationItem(
                        name: "Big Ben",
                        latitude: 51.500729,
                        longitude: -0.124625,
                        category: .landmark
                    ),
                    LocationItem(
                        name: "British Museum",
                        latitude: 51.519413,
                        longitude: -0.126957,
                        category: .museum
                    ),
                    LocationItem(
                        name: "Tower Bridge",
                        latitude: 51.505456,
                        longitude: -0.075356,
                        category: .landmark
                    ),
                    LocationItem(
                        name: "Hyde Park",
                        latitude: 51.507268,
                        longitude: -0.165730,
                        category: .park
                    ),
                    LocationItem(
                        name: "Borough Market",
                        latitude: 51.505444,
                        longitude: -0.090111,
                        category: .shopping
                    )
                ]
            ),
            Trip(
                name: "Barcelona",
                startDate: nil,
                endDate: nil,
                locations: [
                    LocationItem(
                        name: "Sagrada Família",
                        latitude: 41.403630,
                        longitude: 2.174356,
                        category: .landmark
                    ),
                    LocationItem(
                        name: "Park Güell",
                        latitude: 41.414494,
                        longitude: 2.152694,
                        category: .park
                    ),
                    LocationItem(
                        name: "Casa Batlló",
                        latitude: 41.391667,
                        longitude: 2.164944,
                        category: .landmark
                    ),
                    LocationItem(
                        name: "La Boqueria",
                        latitude: 41.382500,
                        longitude: 2.171900,
                        category: .shopping
                    ),
                    LocationItem(
                        name: "Cervecería Catalana",
                        latitude: 41.394200,
                        longitude: 2.155900,
                        category: .restaurant
                    )
                ]
            )
        ]
    }
}

