import CoreLocation
import MapKit
import SwiftUI

/// Apple’s `MKDirections` is heavily throttled (~50 requests / 60s per app). Serialize + cache + cap usage.
private actor MKDirectionsGate {
    static let shared = MKDirectionsGate()
    private var lastRequestAt = Date.distantPast

    func waitTurn(minimumInterval: TimeInterval) async {
        let gap = minimumInterval
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRequestAt)
        if elapsed < gap {
            let ns = UInt64(max(0, gap - elapsed) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
        }
        lastRequestAt = Date()
    }
}

private enum WalkingLegCache {
    private static let lock = NSLock()
    private static var storage: [String: [CLLocationCoordinate2D]] = [:]

    static func key(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> String {
        func q(_ x: Double) -> String { String(format: "%.5f", x) }
        // v4: alternates + step polylines (invalidate older cache entries).
        return "\(q(a.latitude)),\(q(a.longitude))→\(q(b.latitude)),\(q(b.longitude))|v4"
    }

    static func get(_ key: String) -> [CLLocationCoordinate2D]? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    static func set(_ key: String, _ value: [CLLocationCoordinate2D]) {
        lock.lock()
        defer { lock.unlock() }
        if storage.count > 400 {
            storage.removeAll(keepingCapacity: true)
        }
        storage[key] = value
    }
}

struct TripMapView: View {
    let trip: Trip
    /// When non-nil and `trip.plannedDays` is set, map shows only that day’s stops and polyline.
    var plannedDayIndex: Int?

    @State private var position: MapCameraPosition = .automatic
    /// Single merged MapKit **walking** polyline (hub → stops → hub when accommodation is set).
    @State private var roadRouteCoordinates: [CLLocationCoordinate2D] = []
    @State private var isRouteUpdating = false

    private var sortedPlannedDays: [TripPlannedDay] {
        (trip.plannedDays ?? []).sorted { $0.dayIndex < $1.dayIndex }
    }

    private var usesPerDayPlan: Bool {
        trip.hasItineraryDates && !sortedPlannedDays.isEmpty && plannedDayIndex != nil
    }

    private var shouldGenerateRoute: Bool {
        trip.hasItineraryDates && displayStops.count >= 2
    }

    private var activePlannedDay: TripPlannedDay? {
        guard usesPerDayPlan, let idx = plannedDayIndex else { return nil }
        let clamped = min(max(0, idx), sortedPlannedDays.count - 1)
        return sortedPlannedDays[safe: clamped]
    }

    private var displayStops: [LocationItem] {
        if let day = activePlannedDay {
            let byID = Dictionary(uniqueKeysWithValues: trip.locations.map { ($0.id, $0) })
            return day.orderedLocationIds.compactMap { byID[$0] }
        }
        return trip.locations
    }

    /// Ordered coordinates for on-map walking directions (Apple follows pedestrian paths; backend polyline is not drawn).
    private var routingWaypoints: [CLLocationCoordinate2D] {
        var pts: [CLLocationCoordinate2D] = []
        if let a = trip.accommodation {
            pts.append(CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude))
        }
        pts.append(contentsOf: displayStops.map(\.coordinate))
        if let a = trip.accommodation {
            let hub = CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude)
            if let last = pts.last,
               abs(last.latitude - hub.latitude) > 1e-8 || abs(last.longitude - hub.longitude) > 1e-8 {
                pts.append(hub)
            }
        }
        return pts
    }

    private var routeSignature: String {
        let dayPart = plannedDayIndex.map { "d:\($0)" } ?? "full"
        let acc = trip.accommodation.map { "a:\($0.latitude),\($0.longitude)" } ?? "a:none"
        let wp = routingWaypoints.map { "\(String(format: "%.6f", $0.latitude)),\(String(format: "%.6f", $0.longitude))" }
            .joined(separator: "|")
        let ids = displayStops.map(\.id.uuidString).joined(separator: ",")
        let datesPart = trip.hasItineraryDates ? "dates:yes" : "dates:no"
        return "\(dayPart)|\(datesPart)|\(acc)|mk-walk-v4|\(wp)|\(ids)"
    }

    private var accommodationCoordinate: CLLocationCoordinate2D? {
        guard let a = trip.accommodation else { return nil }
        return CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude)
    }

    private var routeLoadingMessage: String {
        if usesPerDayPlan, let idx = plannedDayIndex {
            return "Loading Day \(idx + 1)…"
        }
        return "Updating route…"
    }

    var body: some View {
        Map(position: $position) {
            if shouldGenerateRoute, !isRouteUpdating, roadRouteCoordinates.count >= 2 {
                MapPolyline(coordinates: roadRouteCoordinates)
                    .stroke(.blue.opacity(0.82), lineWidth: 4)
            }

            ForEach(Array(displayStops.enumerated()), id: \.element.id) { index, loc in
                Annotation(loc.name, coordinate: loc.coordinate) {
                    ZStack {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(tint(for: loc.category), .white)
                            .shadow(radius: 2)
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .offset(y: -5)
                    }
                }
            }

            if let accCoord = accommodationCoordinate, let acc = trip.accommodation {
                Annotation(acc.name, coordinate: accCoord) {
                    Image(systemName: "bed.double.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.teal, .white)
                        .shadow(radius: 2)
                }
            }
        }
        .mapControls {
            MapCompass()
            MapPitchToggle()
            MapUserLocationButton()
            MapScaleView()
        }
        .overlay {
            if isRouteUpdating {
                mapLoadingOverlay
            }
        }
        .allowsHitTesting(!isRouteUpdating)
        .task(id: routeSignature) {
            roadRouteCoordinates = []
            position = cameraPositionFittingDisplay()
            guard shouldGenerateRoute else {
                isRouteUpdating = false
                return
            }
            isRouteUpdating = true
            await rebuildFallbackRoadRoutesIfNeeded()
            guard !Task.isCancelled else { return }
            isRouteUpdating = false
        }
        .onAppear {
            if !isRouteUpdating {
                position = cameraPositionFittingDisplay()
            }
        }
    }

    /// Covers only the embedded map frame (parent sets height + corner clip).
    private var mapLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.08)
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.regular)
                Text(routeLoadingMessage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.charcoal.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(routeLoadingMessage)
    }

    private func tint(for category: LocationItem.Category) -> Color {
        AppTheme.categoryTint(category)
    }

    @MainActor
    private func rebuildFallbackRoadRoutesIfNeeded() async {
        let waypoints = routingWaypoints
        guard waypoints.count >= 2 else {
            roadRouteCoordinates = []
            position = cameraPositionFittingDisplay()
            return
        }

        let legCount = waypoints.count - 1
        /// Cap MKDirections calls per rebuild (Apple throttles ~50/min per app); extra legs use straight chords.
        let maxAppleWalkingLegs = 14

        var merged: [CLLocationCoordinate2D] = []

        for i in 0 ..< legCount {
            try? Task.checkCancellation()
            let a = waypoints[i]
            let b = waypoints[i + 1]
            let same =
                abs(a.latitude - b.latitude) < 1e-8 && abs(a.longitude - b.longitude) < 1e-8
            if same { continue }
            let useMK = i < maxAppleWalkingLegs
            let leg: [CLLocationCoordinate2D]
            if useMK, let coords = await Self.walkingPolyline(from: a, to: b), coords.count >= 2 {
                leg = coords
            } else {
                leg = [a, b]
            }
            Self.appendCoordinates(&merged, leg, dedupeWithinMeters: 5)
        }

        roadRouteCoordinates = merged
        position = cameraPositionFittingDisplay()
    }

    /// One Directions request per leg, spaced apart and cached, so tab switches and revisits stay under quota.
    private static func walkingPolyline(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> [CLLocationCoordinate2D]? {
        if Task.isCancelled { return nil }
        let cacheKey = WalkingLegCache.key(from, to)
        if let cached = WalkingLegCache.get(cacheKey) {
            return cached
        }

        await MKDirectionsGate.shared.waitTurn(minimumInterval: 1.28)
        if Task.isCancelled { return nil }

        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: from.latitude, longitude: from.longitude),
            address: nil
        )
        request.destination = MKMapItem(
            location: CLLocation(latitude: to.latitude, longitude: to.longitude),
            address: nil
        )
        request.transportType = .walking
        request.requestsAlternateRoutes = true
        // Walking-specific hints; MapKit may ignore some for non-driving modes.
        request.tollPreference = .avoid
        request.highwayPreference = .avoid

        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            let routes = response.routes
            guard let route = pickPreferredWalkingRoute(routes) else { return nil }
            let coords = walkingCoordinates(from: route)
            guard coords.count >= 2 else { return nil }
            WalkingLegCache.set(cacheKey, coords)
            return coords
        } catch {
            return nil
        }
    }

    /// Among Apple’s walking options, prefer a slightly **longer** route when its ETA is still competitive—often
    /// follows paths and crossings instead of cutting the shortest chord through parks or car lanes.
    private static func pickPreferredWalkingRoute(_ routes: [MKRoute]) -> MKRoute? {
        guard !routes.isEmpty else { return nil }
        guard routes.count > 1 else { return routes.first }
        guard let fastest = routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else {
            return routes.first
        }
        let timeCap = max(fastest.expectedTravelTime * 1.28, fastest.expectedTravelTime + 90)
        let pool = routes.filter { $0.expectedTravelTime <= timeCap }
        return pool.max(by: { $0.distance < $1.distance }) ?? fastest
    }

    /// Prefer geometry built from each `MKRoute.Step` polyline (finer at corners and crossings) with fallbacks.
    private static func walkingCoordinates(from route: MKRoute) -> [CLLocationCoordinate2D] {
        var merged: [CLLocationCoordinate2D] = []
        merged.reserveCapacity(route.polyline.pointCount)
        for step in route.steps where step.polyline.pointCount >= 2 {
            let part = coordinates(from: step.polyline)
            appendCoordinates(&merged, part, dedupeWithinMeters: 2)
        }
        if merged.count >= 2 {
            return merged
        }
        return coordinates(from: route.polyline)
    }

    private static func appendCoordinates(
        _ dest: inout [CLLocationCoordinate2D],
        _ addition: [CLLocationCoordinate2D],
        dedupeWithinMeters: CLLocationDistance
    ) {
        guard !addition.isEmpty else { return }
        if dest.isEmpty {
            dest.append(contentsOf: addition)
            return
        }
        var start = 0
        if let last = dest.last {
            let first = addition[0]
            let gap = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: first.latitude, longitude: first.longitude))
            if gap < dedupeWithinMeters {
                start = 1
            }
        }
        if start < addition.count {
            dest.append(contentsOf: addition[start...])
        }
    }

    private static func coordinates(from polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return coords
    }

    private func cameraPositionFittingDisplay() -> MapCameraPosition {
        var lats = displayStops.map(\.latitude)
        var lons = displayStops.map(\.longitude)
        if let a = trip.accommodation {
            lats.append(a.latitude)
            lons.append(a.longitude)
        }
        for c in roadRouteCoordinates {
            lats.append(c.latitude)
            lons.append(c.longitude)
        }

        guard !lats.isEmpty,
              let minLat = lats.min(),
              let maxLat = lats.max(),
              let minLon = lons.min(),
              let maxLon = lons.max()
        else { return .automatic }

        let latSpan = max(0.01, (maxLat - minLat) * 1.35)
        let lonSpan = max(0.01, (maxLon - minLon) * 1.35)

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )

        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        )

        return .region(region)
    }
}

private extension LocationItem {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

#Preview("Map — all stops") {
    TripMapView(trip: PreviewData.parisTrip, plannedDayIndex: nil)
        .frame(height: 420)
}

#Preview("Map — day 1") {
    TripMapView(trip: PreviewData.parisTrip, plannedDayIndex: 0)
        .frame(height: 420)
}
