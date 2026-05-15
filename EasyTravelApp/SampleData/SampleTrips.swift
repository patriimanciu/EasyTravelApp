import Foundation

enum SampleTrips {
    // MARK: - Shared hour templates (sample / illustrative)

    private static let hoursMuseumParis: [String] = [
        "Monday: Closed",
        "Tuesday: 9:30 AM – 6:00 PM",
        "Wednesday: 9:30 AM – 9:45 PM",
        "Thursday: 9:30 AM – 6:00 PM",
        "Friday: 9:30 AM – 9:45 PM",
        "Saturday: 9:00 AM – 6:00 PM",
        "Sunday: 9:00 AM – 6:00 PM",
    ]

    private static let hoursMuseumParisShort: [String] = [
        "Tuesday–Sunday: 9:30 AM – 6:00 PM",
        "Monday: Closed",
    ]

    private static let hoursParkParis: [String] = [
        "Monday–Sunday: 7:30 AM – 8:30 PM",
        "Last entry may close earlier by season.",
    ]

    private static let hoursParkParisLong: [String] = [
        "Monday–Sunday: 7:00 AM – 11:00 PM",
    ]

    private static let hoursCemeteryParis: [String] = [
        "Monday–Sunday: 8:00 AM – 6:00 PM",
        "Saturday: opens 8:30 AM November–March.",
    ]

    private static let hoursRestaurantParis: [String] = [
        "Monday–Sunday: 12:00 PM – 2:30 PM",
        "Monday–Sunday: 7:00 PM – 11:00 PM",
    ]

    private static let hoursCafeParis: [String] = [
        "Monday–Sunday: 7:30 AM – 1:00 AM",
    ]

    private static let hoursShoppingParis: [String] = [
        "Monday–Saturday: 10:00 AM – 8:00 PM",
        "Sunday: 11:00 AM – 8:00 PM",
    ]

    private static let hoursMarketParis: [String] = [
        "Tuesday–Friday: 9:00 AM – 1:00 PM, 4:00 PM – 7:30 PM",
        "Saturday: 9:00 AM – 7:30 PM",
        "Sunday: 9:00 AM – 1:30 PM",
    ]

    private static let hoursLandmarkOutdoor: [String] = [
        "Public space: always accessible; ticketed areas have separate hours on venue site.",
    ]

    private static let hoursNightParis: [String] = [
        "Shows: typically 7:00 PM & 9:00 PM",
        "Box office: daily 10:00 AM – 11:30 PM",
    ]

    private static let hoursMuseumLondon: [String] = [
        "Monday–Sunday: 10:00 AM – 5:00 PM",
        "Friday: open until 8:30 PM (selected galleries).",
    ]

    private static let hoursMarketLondon: [String] = [
        "Monday–Thursday: 10:00 AM – 5:00 PM",
        "Friday: 10:00 AM – 6:00 PM",
        "Saturday: 8:00 AM – 5:00 PM",
        "Sunday: 10:00 AM – 3:00 PM",
    ]

    private static let hoursParkLondon: [String] = [
        "Monday–Sunday: 5:00 AM – 12:00 AM",
    ]

    private static let hoursMuseumBarcelona: [String] = [
        "Monday–Saturday: 9:00 AM – 8:00 PM",
        "Sunday: 10:00 AM – 3:00 PM",
    ]

    private static let hoursParkBarcelona: [String] = [
        "Monday–Sunday: 9:30 AM – 7:30 PM",
        "Time slots may apply (book online).",
    ]

    private static let hoursRestaurantBarcelona: [String] = [
        "Monday–Sunday: 1:00 PM – 4:00 PM",
        "Monday–Sunday: 8:00 PM – 11:30 PM",
    ]

    // MARK: - Row builders

    private static func parisStop(
        name: String,
        latitude: Double,
        longitude: Double,
        category: LocationItem.Category,
        address: String,
        openingHours: [String],
        notes: String? = nil,
        phoneNumber: String? = "+33 1 49 52 42 00",
        url: String? = nil
    ) -> LocationItem {
        LocationItem(
            name: name,
            latitude: latitude,
            longitude: longitude,
            category: category,
            notes: notes ?? "Sample Paris stop for routing, map, and detail UI tests.",
            address: address,
            phoneNumber: phoneNumber,
            url: url,
            openingHours: openingHours,
            source: .manual()
        )
    }

    private static func londonStop(
        name: String,
        latitude: Double,
        longitude: Double,
        category: LocationItem.Category,
        address: String,
        openingHours: [String],
        notes: String? = nil,
        phoneNumber: String? = "+44 20 7946 0958",
        url: String? = nil
    ) -> LocationItem {
        LocationItem(
            name: name,
            latitude: latitude,
            longitude: longitude,
            category: category,
            notes: notes ?? "Sample London stop for routing and detail UI tests.",
            address: address,
            phoneNumber: phoneNumber,
            url: url,
            openingHours: openingHours,
            source: .manual()
        )
    }

    private static func barcelonaStop(
        name: String,
        latitude: Double,
        longitude: Double,
        category: LocationItem.Category,
        address: String,
        openingHours: [String],
        notes: String? = nil,
        phoneNumber: String? = "+34 932 85 44 40",
        url: String? = nil
    ) -> LocationItem {
        LocationItem(
            name: name,
            latitude: latitude,
            longitude: longitude,
            category: category,
            notes: notes ?? "Sample Barcelona stop for routing and detail UI tests.",
            address: address,
            phoneNumber: phoneNumber,
            url: url,
            openingHours: openingHours,
            source: .manual()
        )
    }

    private static var parisTripStart: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: DateComponents(year: 2026, month: 6, day: 10))!
    }

    private static var parisTripEnd: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: DateComponents(year: 2026, month: 6, day: 16))!
    }

    private static var londonTripStart: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: DateComponents(year: 2026, month: 7, day: 8))!
    }

    private static var londonTripEnd: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: DateComponents(year: 2026, month: 7, day: 9))!
    }

    static func make() -> [Trip] {
        [
            Trip(
                name: "Paris",
                startDate: parisTripStart,
                endDate: parisTripEnd,
                accommodation: TripAccommodation(
                    name: "Sample stay — Le Marais",
                    latitude: 48.8593,
                    longitude: 2.3622
                ),
                locations: [
                    parisStop(
                        name: "Eiffel Tower",
                        latitude: 48.858370,
                        longitude: 2.294481,
                        category: .landmark,
                        address: "Champ de Mars, 5 Av. Anatole France, 75007 Paris, France",
                        openingHours: hoursLandmarkOutdoor,
                        phoneNumber: "+33 892 70 12 39", url: "https://www.toureiffel.paris"
                    ),
                    parisStop(
                        name: "Arc de Triomphe",
                        latitude: 48.873792,
                        longitude: 2.295028,
                        category: .landmark,
                        address: "Pl. Charles de Gaulle, 75008 Paris, France",
                        openingHours: ["Monday–Sunday: 10:00 AM – 11:00 PM"],
                        url: "https://www.paris-arc-de-triomphe.fr"
                    ),
                    parisStop(
                        name: "Louvre Museum",
                        latitude: 48.860611,
                        longitude: 2.337644,
                        category: .museum,
                        address: "Rue de Rivoli, 75001 Paris, France",
                        openingHours: hoursMuseumParis,
                        phoneNumber: "+33 1 40 20 53 17", url: "https://www.louvre.fr"
                    ),
                    parisStop(
                        name: "Musée d'Orsay",
                        latitude: 48.859961,
                        longitude: 2.326561,
                        category: .museum,
                        address: "1 Rue de la Légion d'Honneur, 75007 Paris, France",
                        openingHours: hoursMuseumParisShort,
                        url: "https://www.musee-orsay.fr"
                    ),
                    parisStop(
                        name: "Centre Pompidou",
                        latitude: 48.860647,
                        longitude: 2.352240,
                        category: .museum,
                        address: "Place Georges-Pompidou, 75004 Paris, France",
                        openingHours: ["Monday: 2:00 PM – 9:00 PM", "Tuesday–Sunday: 11:00 AM – 9:00 PM"],
                        url: "https://www.centrepompidou.fr"
                    ),
                    parisStop(
                        name: "Notre-Dame Cathedral",
                        latitude: 48.852968,
                        longitude: 2.349902,
                        category: .landmark,
                        address: "6 Parvis Notre-Dame - Pl. Jean-Paul II, 75004 Paris, France",
                        openingHours: ["Monday–Sunday: 8:00 AM – 6:45 PM"],
                        notes: "Exterior and parvis; interior reopening hours may differ—check official site.",
                        url: "https://www.notredamedeparis.fr"
                    ),
                    parisStop(
                        name: "Sainte-Chapelle",
                        latitude: 48.855378,
                        longitude: 2.345097,
                        category: .landmark,
                        address: "10 Bd du Palais, 75001 Paris, France",
                        openingHours: ["Monday–Sunday: 9:00 AM – 7:00 PM"],
                        url: "https://www.sainte-chapelle.fr"
                    ),
                    parisStop(
                        name: "Panthéon",
                        latitude: 48.846222,
                        longitude: 2.345994,
                        category: .landmark,
                        address: "Pl. du Panthéon, 75005 Paris, France",
                        openingHours: hoursMuseumParisShort,
                        url: "https://www.paris-pantheon.fr"
                    ),
                    parisStop(
                        name: "Luxembourg Gardens",
                        latitude: 48.846222,
                        longitude: 2.337160,
                        category: .park,
                        address: "75006 Paris, France",
                        openingHours: hoursParkParisLong,
                        url: "https://www.senat.fr/patrimoine/jardin-du-luxembourg.html"
                    ),
                    parisStop(
                        name: "Jardin des Tuileries",
                        latitude: 48.863395,
                        longitude: 2.327995,
                        category: .park,
                        address: "Pl. de la Concorde, 75001 Paris, France",
                        openingHours: hoursParkParisLong,
                        url: "https://www.paris.fr/lieux/jardin-des-tuileries-1795"
                    ),
                    parisStop(
                        name: "Place de la Concorde",
                        latitude: 48.865633,
                        longitude: 2.321236,
                        category: .landmark,
                        address: "Pl. de la Concorde, 75008 Paris, France",
                        openingHours: hoursLandmarkOutdoor,
                        notes: "Major public square; fountains and obelisk viewable at all times."
                    ),
                    parisStop(
                        name: "Grand Palais",
                        latitude: 48.865633,
                        longitude: 2.318435,
                        category: .museum,
                        address: "3 Av. du Général Eisenhower, 75008 Paris, France",
                        openingHours: ["Hours vary by exhibition—see website."],
                        url: "https://www.grandpalais.fr"
                    ),
                    parisStop(
                        name: "Petit Palais",
                        latitude: 48.866109,
                        longitude: 2.314977,
                        category: .museum,
                        address: "Av. Winston Churchill, 75008 Paris, France",
                        openingHours: ["Tuesday–Sunday: 10:00 AM – 6:00 PM", "Monday: Closed"],
                        phoneNumber: nil, url: "https://www.petitpalais.paris.fr"
                    ),
                    parisStop(
                        name: "Hôtel des Invalides",
                        latitude: 48.856528,
                        longitude: 2.312705,
                        category: .landmark,
                        address: "129 Rue de Grenelle, 75007 Paris, France",
                        openingHours: hoursMuseumParisShort,
                        url: "https://www.musee-armee.fr"
                    ),
                    parisStop(
                        name: "Musée Rodin",
                        latitude: 48.855307,
                        longitude: 2.315853,
                        category: .museum,
                        address: "77 Rue de Varenne, 75007 Paris, France",
                        openingHours: ["Tuesday–Sunday: 10:00 AM – 6:30 PM", "Monday: Closed"],
                        url: "https://www.musee-rodin.fr"
                    ),
                    parisStop(
                        name: "Musée de l'Orangerie",
                        latitude: 48.863491,
                        longitude: 2.327838,
                        category: .museum,
                        address: "Jardin des Tuileries, 75001 Paris, France",
                        openingHours: ["Wednesday–Monday: 9:00 AM – 6:00 PM", "Tuesday: Closed"],
                        url: "https://www.musee-orangerie.fr"
                    ),
                    parisStop(
                        name: "Opéra Garnier",
                        latitude: 48.871944,
                        longitude: 2.331634,
                        category: .landmark,
                        address: "Pl. de l'Opéra, 75009 Paris, France",
                        openingHours: ["Self-guided visits: typically 10:00 AM – 5:00 PM (check site)."],
                        url: "https://www.operadeparis.fr"
                    ),
                    parisStop(
                        name: "Galeries Lafayette",
                        latitude: 48.873779,
                        longitude: 2.332044,
                        category: .shopping,
                        address: "40 Bd Haussmann, 75009 Paris, France",
                        openingHours: hoursShoppingParis,
                        url: "https://haussmann.galerieslafayette.com"
                    ),
                    parisStop(
                        name: "Place Vendôme",
                        latitude: 48.867142,
                        longitude: 2.329747,
                        category: .neighborhood,
                        address: "Pl. Vendôme, 75001 Paris, France",
                        openingHours: hoursLandmarkOutdoor,
                        notes: "Historic square; boutiques keep their own hours."
                    ),
                    parisStop(
                        name: "Sacré-Cœur Basilica",
                        latitude: 48.886704,
                        longitude: 2.343104,
                        category: .landmark,
                        address: "35 Rue du Chevalier de la Barre, 75018 Paris, France",
                        openingHours: ["Monday–Sunday: 6:30 AM – 10:30 PM"],
                        url: "https://www.sacre-coeur-montmartre.com"
                    ),
                    parisStop(
                        name: "Moulin Rouge",
                        latitude: 48.884123,
                        longitude: 2.332251,
                        category: .nightlife,
                        address: "82 Bd de Clichy, 75018 Paris, France",
                        openingHours: hoursNightParis,
                        phoneNumber: "+33 1 53 09 82 82", url: "https://www.moulinrouge.fr"
                    ),
                    parisStop(
                        name: "Place des Vosges",
                        latitude: 48.855400,
                        longitude: 2.365500,
                        category: .park,
                        address: "Pl. des Vosges, 75004 Paris, France",
                        openingHours: hoursParkParisLong,
                        url: "https://www.paris.fr/lieux/place-des-vosges-1825"
                    ),
                    parisStop(
                        name: "Picasso Museum",
                        latitude: 48.859871,
                        longitude: 2.362152,
                        category: .museum,
                        address: "5 Rue de Thorigny, 75003 Paris, France",
                        openingHours: ["Tuesday–Friday: 10:30 AM – 6:00 PM", "Saturday–Sunday: 9:30 AM – 6:00 PM", "Monday: Closed"],
                        url: "https://www.museepicassoparis.fr"
                    ),
                    parisStop(
                        name: "Canal Saint-Martin",
                        latitude: 48.871400,
                        longitude: 2.366500,
                        category: .neighborhood,
                        address: "Quai de Jemmapes / Quai de Valmy, 75010 Paris, France",
                        openingHours: hoursLandmarkOutdoor,
                        notes: "Towpath walk; cafés along the canal have individual hours."
                    ),
                    parisStop(
                        name: "Père Lachaise (main gate)",
                        latitude: 48.863400,
                        longitude: 2.393400,
                        category: .park,
                        address: "16 Rue du Repos, 75020 Paris, France",
                        openingHours: hoursCemeteryParis,
                        url: "https://www.pere-lachaise.com"
                    ),
                    parisStop(
                        name: "Parc de la Villette",
                        latitude: 48.893600,
                        longitude: 2.390200,
                        category: .park,
                        address: "211 Av. Jean Jaurès, 75019 Paris, France",
                        openingHours: hoursParkParisLong,
                        url: "https://parcdelavillette.fr"
                    ),
                    parisStop(
                        name: "Parc des Buttes-Chaumont",
                        latitude: 48.877900,
                        longitude: 2.381400,
                        category: .park,
                        address: "1 Rue Botzaris, 75019 Paris, France",
                        openingHours: hoursParkParisLong,
                        url: "https://www.paris.fr/lieux/parc-des-buttes-chaumont-1757"
                    ),
                    parisStop(
                        name: "Montparnasse Tower",
                        latitude: 48.842100,
                        longitude: 2.322500,
                        category: .landmark,
                        address: "33 Av. du Maine, 75015 Paris, France",
                        openingHours: ["Monday–Sunday: 9:30 AM – 11:30 PM"],
                        url: "https://www.tourmontparnasse56.com"
                    ),
                    parisStop(
                        name: "Catacombs of Paris",
                        latitude: 48.833800,
                        longitude: 2.332400,
                        category: .museum,
                        address: "1 Av. du Colonel Henri Rol-Tanguy, 75014 Paris, France",
                        openingHours: ["Tuesday–Sunday: 9:45 AM – 8:30 PM", "Monday: Closed"],
                        phoneNumber: "+33 1 43 22 47 63", url: "https://www.catacombes.paris.fr"
                    ),
                    parisStop(
                        name: "BNF François-Mitterrand",
                        latitude: 48.833700,
                        longitude: 2.375900,
                        category: .landmark,
                        address: "Quai François Mauriac, 75706 Paris Cedex 13, France",
                        openingHours: ["Tuesday–Saturday: 9:00 AM – 8:00 PM", "Monday: 2:00 PM – 8:00 PM", "Sunday: Closed"],
                        url: "https://www.bnf.fr"
                    ),
                    parisStop(
                        name: "Marché d'Aligre",
                        latitude: 48.849000,
                        longitude: 2.382500,
                        category: .shopping,
                        address: "Pl. d'Aligre, 75012 Paris, France",
                        openingHours: hoursMarketParis,
                        notes: "Covered market + open-air stalls; busiest mornings.",
                        phoneNumber: nil
                    ),
                    parisStop(
                        name: "Rue Crémieux",
                        latitude: 48.848600,
                        longitude: 2.370300,
                        category: .neighborhood,
                        address: "Rue Crémieux, 75012 Paris, France",
                        openingHours: hoursLandmarkOutdoor,
                        notes: "Pedestrian street; respect residents—no loud groups."
                    ),
                    parisStop(
                        name: "Shakespeare and Company",
                        latitude: 48.850938,
                        longitude: 2.347079,
                        category: .shopping,
                        address: "37 Rue de la Bûcherie, 75005 Paris, France",
                        openingHours: ["Monday–Sunday: 10:00 AM – 8:00 PM"],
                        phoneNumber: "+33 1 43 25 40 93", url: "https://shakespeareandcompany.com"
                    ),
                    parisStop(
                        name: "Saint-Germain-des-Prés",
                        latitude: 48.853842,
                        longitude: 2.335412,
                        category: .neighborhood,
                        address: "Pl. Saint-Germain des Prés, 75006 Paris, France",
                        openingHours: ["Church: daily hours vary; square always accessible."],
                        url: "https://www.eglise-sgp.org"
                    ),
                    parisStop(
                        name: "Le Marais (Hôtel de Ville)",
                        latitude: 48.856614,
                        longitude: 2.352222,
                        category: .neighborhood,
                        address: "Pl. de l'Hôtel de Ville, 75004 Paris, France",
                        openingHours: hoursLandmarkOutdoor,
                        notes: "City hall square; Marais shops have individual hours."
                    ),
                    parisStop(
                        name: "Bateaux-Mouches (Alma)",
                        latitude: 48.863700,
                        longitude: 2.301400,
                        category: .landmark,
                        address: "Port de la Conférence, 75008 Paris, France",
                        openingHours: ["Cruises: frequent departures Apr–Sep; reduced in winter—see site."],
                        phoneNumber: "+33 1 42 25 96 10", url: "https://www.bateaux-mouches.fr"
                    ),
                    parisStop(
                        name: "Trocadéro Gardens",
                        latitude: 48.861595,
                        longitude: 2.289282,
                        category: .park,
                        address: "Pl. du Trocadéro et du 11 Novembre, 75016 Paris, France",
                        openingHours: hoursParkParisLong,
                        url: "https://www.paris.fr/lieux/jardins-du-trocadero-100534"
                    ),
                    parisStop(
                        name: "Café de Flore",
                        latitude: 48.854128,
                        longitude: 2.332550,
                        category: .cafe,
                        address: "172 Bd Saint-Germain, 75006 Paris, France",
                        openingHours: hoursCafeParis,
                        phoneNumber: "+33 1 45 48 55 26", url: "https://cafedeflore.fr"
                    ),
                    parisStop(
                        name: "Les Deux Magots",
                        latitude: 48.853802,
                        longitude: 2.332364,
                        category: .cafe,
                        address: "6 Pl. Saint-Germain des Prés, 75006 Paris, France",
                        openingHours: hoursCafeParis,
                        phoneNumber: "+33 1 45 48 55 25", url: "https://www.lesdeuxmagots.fr"
                    ),
                    parisStop(
                        name: "Le Relais de l'Entrecôte (Porte Maillot)",
                        latitude: 48.878900,
                        longitude: 2.283500,
                        category: .restaurant,
                        address: "15 Rue Marbeuf, 75008 Paris, France",
                        openingHours: hoursRestaurantParis,
                        phoneNumber: "+33 1 49 52 07 89", url: "https://www.relaisentrecote.fr"
                    ),
                    parisStop(
                        name: "Brasserie Lipp",
                        latitude: 48.851200,
                        longitude: 2.333600,
                        category: .restaurant,
                        address: "151 Bd Saint-Germain, 75006 Paris, France",
                        openingHours: ["Monday–Sunday: 9:00 AM – 1:00 AM"],
                        phoneNumber: "+33 1 45 48 53 91", url: "https://www.brasserie-lipp.fr"
                    ),
                    parisStop(
                        name: "Le Bouillon Pigalle",
                        latitude: 48.883200,
                        longitude: 2.337400,
                        category: .restaurant,
                        address: "22 Bd de Clichy, 75018 Paris, France",
                        openingHours: ["Monday–Sunday: 12:00 PM – 12:00 AM"],
                        phoneNumber: "+33 1 42 59 69 31", url: "https://www.bouillon-pigalle.com"
                    ),
                    parisStop(
                        name: "Marché Bastille",
                        latitude: 48.853200,
                        longitude: 2.369200,
                        category: .shopping,
                        address: "Bd Richard Lenoir, 75011 Paris, France",
                        openingHours: hoursMarketParis,
                        phoneNumber: "+33 1 43 24 87 84"
                    ),
                    parisStop(
                        name: "Cimetière du Montparnasse",
                        latitude: 48.838100,
                        longitude: 2.326400,
                        category: .park,
                        address: "3 Bd Edgar Quinet, 75014 Paris, France",
                        openingHours: hoursCemeteryParis,
                        url: "https://www.paris.fr/equipements/cimetiere-du-montparnasse-4217"
                    ),
                ]
            ),
            Trip(
                name: "London",
                startDate: londonTripStart,
                endDate: londonTripEnd,
                accommodation: TripAccommodation(
                    name: "Sample stay — South Bank",
                    latitude: 51.5045,
                    longitude: -0.1147
                ),
                locations: [
                    londonStop(
                        name: "Big Ben (Elizabeth Tower)",
                        latitude: 51.500729,
                        longitude: -0.124625,
                        category: .landmark,
                        address: "London SW1A 0AA, United Kingdom",
                        openingHours: ["Exterior viewing: always; UK Parliament tours—book on parliament.uk."],
                        phoneNumber: "+44 20 7219 4272", url: "https://www.parliament.uk"
                    ),
                    londonStop(
                        name: "British Museum",
                        latitude: 51.519413,
                        longitude: -0.126957,
                        category: .museum,
                        address: "Great Russell St, London WC1B 3DG, United Kingdom",
                        openingHours: hoursMuseumLondon,
                        phoneNumber: "+44 20 7323 8299", url: "https://www.britishmuseum.org"
                    ),
                    londonStop(
                        name: "Tower Bridge",
                        latitude: 51.505456,
                        longitude: -0.075356,
                        category: .landmark,
                        address: "Tower Bridge Rd, London SE1 2UP, United Kingdom",
                        openingHours: ["Monday–Sunday: 9:30 AM – 6:00 PM"],
                        phoneNumber: "+44 7403 852165", url: "https://www.towerbridge.org.uk"
                    ),
                    londonStop(
                        name: "Hyde Park",
                        latitude: 51.507268,
                        longitude: -0.165730,
                        category: .park,
                        address: "London W2 2UH, United Kingdom",
                        openingHours: hoursParkLondon,
                        url: "https://www.royalparks.org.uk/parks/hyde-park"
                    ),
                    londonStop(
                        name: "Borough Market",
                        latitude: 51.505444,
                        longitude: -0.090111,
                        category: .shopping,
                        address: "8 Southwark St, London SE1 1TL, United Kingdom",
                        openingHours: hoursMarketLondon,
                        phoneNumber: "+44 20 7407 1002", url: "https://boroughmarket.org.uk"
                    ),
                ]
            ),
            Trip(
                name: "Barcelona",
                startDate: nil,
                endDate: nil,
                locations: [
                    barcelonaStop(
                        name: "Sagrada Família",
                        latitude: 41.403630,
                        longitude: 2.174356,
                        category: .landmark,
                        address: "C/ de Mallorca, 401, 08013 Barcelona, Spain",
                        openingHours: ["Monday–Sunday: 9:00 AM – 6:00 PM", "Seasonal evening slots—see website."],
                        phoneNumber: "+34 932 08 04 14", url: "https://sagradafamilia.org"
                    ),
                    barcelonaStop(
                        name: "Park Güell",
                        latitude: 41.414494,
                        longitude: 2.152694,
                        category: .park,
                        address: "08024 Barcelona, Spain",
                        openingHours: hoursParkBarcelona,
                        phoneNumber: "+34 934 09 18 31", url: "https://parkguell.barcelona"
                    ),
                    barcelonaStop(
                        name: "Casa Batlló",
                        latitude: 41.391667,
                        longitude: 2.164944,
                        category: .landmark,
                        address: "Pg. de Gràcia, 43, 08007 Barcelona, Spain",
                        openingHours: hoursMuseumBarcelona,
                        phoneNumber: "+34 932 16 03 06", url: "https://www.casabatllo.es"
                    ),
                    barcelonaStop(
                        name: "La Boqueria",
                        latitude: 41.382500,
                        longitude: 2.171900,
                        category: .shopping,
                        address: "La Rambla, 91, 08001 Barcelona, Spain",
                        openingHours: ["Monday–Saturday: 8:00 AM – 8:30 PM", "Sunday: Closed"],
                        phoneNumber: "+34 933 18 25 84", url: "https://www.boqueria.barcelona"
                    ),
                    barcelonaStop(
                        name: "Cervecería Catalana",
                        latitude: 41.394200,
                        longitude: 2.155900,
                        category: .restaurant,
                        address: "C/ de Mallorca, 236, 08008 Barcelona, Spain",
                        openingHours: hoursRestaurantBarcelona,
                        phoneNumber: "+34 932 16 03 68", url: "https://www.cerveceriacatalana.com"
                    ),
                ]
            ),
        ]
    }
}
