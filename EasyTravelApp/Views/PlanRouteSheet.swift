import SwiftUI

struct PlanRouteSheet: View {
    @EnvironmentObject private var store: TravelStore
    @Binding var isPresented: Bool

    let tripID: Trip.ID
    let trip: Trip

    @AppStorage("easytravelBackendBaseURL") private var backendBaseURL: String =
        "https://patriimanciu--easytravel-api-serve.modal.run/"

    enum StartAnchor: String, Identifiable {
        case accommodation = "Accommodation"
        case tripCenter = "Trip center"
        case firstStop = "First stop in list"

        var id: String { rawValue }

        static func pickerCases(for trip: Trip) -> [StartAnchor] {
            if trip.accommodation != nil {
                [.accommodation, .tripCenter, .firstStop]
            } else {
                [.tripCenter, .firstStop]
            }
        }
    }

    enum TravelModelChoice: String, CaseIterable, Identifiable {
        case haversine = "Haversine (crow-flight)"
        case osrm = "OSRM (walking paths)"

        var id: String { rawValue }

        var apiValue: String {
            switch self {
            case .haversine: "haversine"
            case .osrm: "osrm"
            }
        }
    }

    enum ClusteringMethodChoice: String, CaseIterable, Identifiable {
        case kMeans = "K-means"
        case dbscan = "DBSCAN"

        var id: String { rawValue }

        var apiValue: String {
            switch self {
            case .kMeans: "k_means"
            case .dbscan: "dbscan"
            }
        }
    }

    @State private var startAnchor: StartAnchor = .tripCenter
    @State private var numberOfDays: Int = 1
    @State private var useDayBudget = false
    @State private var budgetHours: Double = 8
    @State private var returnToStart = false
    @State private var travelModel: TravelModelChoice = .osrm
    @State private var averageSpeedKmh: Double = 5
    @State private var serviceMinutesPerStop: Double = 0
    @State private var clusteringMethod: ClusteringMethodChoice = .kMeans
    @State private var priorityRebalance = true
    @State private var dbscanEpsKm: Double = 2.5
    @State private var dbscanMinSamples: Int = 2

    @State private var errorMessage: String?
    @State private var lastResponse: PlanItineraryResponseDTO?

    private var canCompute: Bool {
        trip.locations.count >= 2
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    backendSection
                    startSection
                    accommodationSection
                    prioritySection
                    tripSplitSection
                    clusteringSection
                    constraintsSection
                    travelSection
                    if let errorMessage {
                        AppFormBanner(text: errorMessage, style: .error)
                    }
                    lastResultSection
                }
                .appPagePadding()
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .scrollDismissesKeyboard(.interactively)
            .appScreenBackground()
            .navigationTitle("Plan route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                        .foregroundStyle(AppTheme.charcoal)
                }
            }
            .safeAreaInset(edge: .bottom) {
                AppCharcoalButton(
                    title: "Compute route",
                    disabled: !canCompute
                ) {
                    Task { await computeRoute() }
                }
                .appPagePadding()
                .padding(.vertical, 12)
                .background(AppTheme.screenBackground)
            }
            .tint(AppTheme.charcoal)
            .onAppear {
                syncDayCountFromTrip()
                if trip.accommodation != nil {
                    startAnchor = .accommodation
                }
                ensureStartAnchorValid()
            }
            .onChange(of: trip.accommodation?.latitude) { _, _ in ensureStartAnchorValid() }
            .onChange(of: trip.accommodation?.longitude) { _, _ in ensureStartAnchorValid() }
            .onChange(of: trip.startDate) { _, _ in syncDayCountFromTrip() }
            .onChange(of: trip.endDate) { _, _ in syncDayCountFromTrip() }
        }
    }

    @ViewBuilder
    private var backendSection: some View {
        AppFormSection(
            title: "Backend",
            footer: "Same server as Import from Video. Deploy must include POST /api/plan-itinerary."
        ) {
            TextField("Backend base URL", text: $backendBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    @ViewBuilder
    private var startSection: some View {
        AppFormSection(title: "Start position") {
            Picker("Anchor", selection: $startAnchor) {
                ForEach(StartAnchor.pickerCases(for: trip), id: \.rawValue) { anchor in
                    Text(anchor.rawValue).tag(anchor)
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private var accommodationSection: some View {
        if let a = trip.accommodation {
            AppFormSection(title: "Accommodation hub") {
                LabeledContent("Stay", value: a.name)
                Text(
                    "Coordinates \(String(format: "%.5f", a.latitude)), \(String(format: "%.5f", a.longitude)) — each day is hub → stops → hub (walking paths)."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var prioritySection: some View {
        AppFormSection(title: "Visit priority") {
            Text("Set each stop’s priority in the trip list (long-press → Priority) or when editing. Must see and Want to see are always placed on the itinerary; If there's time and Low are added only when the day budget allows.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var tripSplitSection: some View {
        AppFormSection(title: "Trip split") {
            if let d = inclusiveTripDayCount(from: trip) {
                LabeledContent("Days", value: "\(d)")
                AppFormFooterText("From this trip’s start and end dates. The server splits stops into \(d) day(s) using spatial clustering.")
            } else {
                Stepper(value: $numberOfDays, in: 1...365) {
                    Text("Days: \(numberOfDays)")
                }
                AppFormFooterText("Add start and end dates to the trip to lock the day count to your real itinerary length.")
            }
        }
    }

    private var clusteringFooter: String {
        clusteringMethod == .dbscan
            ? "DBSCAN groups nearby POIs by density, then the result is adjusted to your day count. K-means assigns each stop to the nearest of k day-centroids."
            : "K-means partitions POIs into k spatial clusters (one per day). Optional rebalance only moves must-see stops between days—it does not replace clustering."
    }

    @ViewBuilder
    private var clusteringSection: some View {
        AppFormSection(title: "Spatial clustering", footer: clusteringFooter) {
            Picker("Method", selection: $clusteringMethod) {
                ForEach(ClusteringMethodChoice.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            Toggle("Balance must-see across days", isOn: $priorityRebalance)
            if clusteringMethod == .dbscan {
                Stepper(value: $dbscanEpsKm, in: 0.5...20, step: 0.5) {
                    Text(String(format: "Neighbourhood: %.1f km", dbscanEpsKm))
                }
                Stepper(value: $dbscanMinSamples, in: 1...10) {
                    Text("Min samples: \(dbscanMinSamples)")
                }
            }
        }
    }

    @ViewBuilder
    private var constraintsSection: some View {
        AppFormSection(title: "Constraints") {
            Toggle("Cap time per day", isOn: $useDayBudget)
            if useDayBudget {
                Stepper(value: $budgetHours, in: 1...16, step: 0.5) {
                    Text(String(format: "Budget: %.1f h / day", budgetHours))
                }
            }
            if trip.accommodation != nil {
                LabeledContent("Daily loop", value: "Return to stay")
                Text("Each day routes from your accommodation, visits that day’s stops, then returns.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Return to start each day", isOn: $returnToStart)
            }
            Stepper(value: $serviceMinutesPerStop, in: 0...180, step: 15) {
                Text("Visit time: \(Int(serviceMinutesPerStop)) min / stop")
            }
        }
    }

    private var travelFooter: String {
        (travelModel == .osrm
            ? "Stop order and map lines use OSRM with the foot (walking) profile: durations from /table and paths from chained /route legs (public router.project-osrm.org if your server has no OSRM_BASE_URL). Crow-flight fallback only when OSRM has no path."
            : "Stop order uses crow-flight times at the speed above (typical walking pace).")
            + " With trip dates set, the server uses that calendar length for day clusters. With a saved stay, the server builds hub-based daily loops. After Compute succeeds, the day split and routes are saved to the trip automatically—use the day control on the map to switch days."
    }

    @ViewBuilder
    private var travelSection: some View {
        AppFormSection(title: "Travel times", footer: travelFooter) {
            Picker("Model", selection: $travelModel) {
                ForEach(TravelModelChoice.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            Stepper(value: $averageSpeedKmh, in: 3...12, step: 1) {
                Text(
                    travelModel == .osrm
                        ? String(format: "Crow-flight fallback: %.0f km/h", averageSpeedKmh)
                        : String(format: "Assumed speed: %.0f km/h", averageSpeedKmh)
                )
            }
        }
    }

    @ViewBuilder
    private var lastResultSection: some View {
        if let lastResponse {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Last result")
                VStack(alignment: .leading, spacing: 12) {
                    let sortedDays = lastResponse.days.sorted(by: { $0.dayIndex < $1.dayIndex })
                    ForEach(Array(sortedDays.enumerated()), id: \.element.dayIndex) { index, day in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Day \(day.dayIndex + 1)")
                                .font(.headline)
                                .foregroundStyle(AppTheme.charcoal)
                            Text(formatDuration(day.totalTravelSeconds) + " travel · " + formatDuration(day.totalServiceSeconds) + " visits")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if !day.withinBudget {
                                Text("Over daily budget")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            if !day.droppedStopIds.isEmpty {
                                Text("Dropped: \(day.droppedStopIds.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if index < sortedDays.count - 1 {
                            Divider()
                        }
                    }
                    if let meta = lastResponse.metadata, !meta.isEmpty {
                        Text(meta.map { "\($0.key): \($0.value)" }.sorted().joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    AppFormFooterText("This plan is already saved to the trip (list → Route order by day, map → day switcher).")
                }
                .softCard()
            }
        }
    }

    private func inclusiveTripDayCount(from trip: Trip) -> Int? {
        guard let start = trip.startDate, let end = trip.endDate, start <= end else { return nil }
        let d = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: start),
            to: Calendar.current.startOfDay(for: end)
        ).day ?? 0
        return max(1, min(365, d + 1))
    }

    private func syncDayCountFromTrip() {
        if let d = inclusiveTripDayCount(from: trip) {
            numberOfDays = d
        }
    }

    private func tripBoundsISOForAPI() -> (start: String, end: String)? {
        guard let start = trip.startDate, let end = trip.endDate, start <= end else { return nil }
        let cal = Calendar.current
        let s = cal.startOfDay(for: start)
        let e = cal.startOfDay(for: end)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = cal.timeZone
        return (f.string(from: s), f.string(from: e))
    }

    private func ensureStartAnchorValid() {
        let cases = StartAnchor.pickerCases(for: trip)
        if !cases.contains(startAnchor) {
            startAnchor = cases.first ?? .tripCenter
        }
    }

    private func resolvedDayCountForRequest() -> Int {
        inclusiveTripDayCount(from: trip) ?? max(1, min(365, numberOfDays))
    }

    private func startCoordinate() -> (lat: Double, lon: Double)? {
        switch startAnchor {
        case .accommodation:
            guard let a = trip.accommodation else { return nil }
            return (a.latitude, a.longitude)
        case .firstStop:
            guard let first = trip.locations.first else { return nil }
            return (first.latitude, first.longitude)
        case .tripCenter:
            guard !trip.locations.isEmpty else { return nil }
            let lat = trip.locations.map(\.latitude).reduce(0, +) / Double(trip.locations.count)
            let lon = trip.locations.map(\.longitude).reduce(0, +) / Double(trip.locations.count)
            return (lat, lon)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 3600 { return "\(s / 60) min" }
        let h = s / 3600
        let m = (s % 3600) / 60
        return m > 0 ? "\(h) h \(m) m" : "\(h) h"
    }

    @MainActor
    private func computeRoute() async {
        errorMessage = nil
        guard trip.locations.count >= 2 else {
            errorMessage = "Add at least two locations."
            return
        }
        guard let (sLat, sLon) = startCoordinate() else {
            errorMessage = "Could not determine start coordinates."
            return
        }

        let serviceSec = max(0.0, serviceMinutesPerStop * 60.0)
        let stops: [RouteStopDTO] = trip.locations.map { loc in
            RouteStopDTO(
                id: loc.id.uuidString,
                latitude: loc.latitude,
                longitude: loc.longitude,
                visitPriority: loc.visitPriority.rawValue,
                weight: 1.0,
                mandatory: false,
                serviceTimeSeconds: serviceSec,
                category: loc.category.rawValue
            )
        }

        let resolvedDays = resolvedDayCountForRequest()
        let bounds = tripBoundsISOForAPI()
        let effectiveReturn = returnToStart || trip.accommodation != nil

        let budget: Double? = useDayBudget ? max(60, budgetHours * 3600) : nil
        let body = PlanItineraryRequestDTO(
            startLatitude: sLat,
            startLongitude: sLon,
            stops: stops,
            numberOfDays: resolvedDays,
            tripStart: bounds?.start,
            tripEnd: bounds?.end,
            dailyBudgetSeconds: budget,
            returnToStart: effectiveReturn,
            travelModel: travelModel.apiValue,
            averageSpeedKmh: averageSpeedKmh,
            clusteringSeed: 42,
            clusteringMethod: clusteringMethod.apiValue,
            dbscanEpsM: max(100, dbscanEpsKm * 1000),
            dbscanMinSamples: dbscanMinSamples,
            priorityRebalance: priorityRebalance,
            accommodationLatitude: trip.accommodation?.latitude,
            accommodationLongitude: trip.accommodation?.longitude,
            osrmProfile: "foot"
        )

        let baseURL = backendBaseURL
        isPresented = false
        await store.planItinerary(tripID: tripID, baseURL: baseURL, body: body)
    }
}

#Preview("Plan route") {
    @Previewable @State var isPresented = true
    PlanRouteSheet(
        isPresented: $isPresented,
        tripID: PreviewData.parisTripID,
        trip: PreviewData.parisTrip
    )
    .environmentObject(TravelStore.preview)
}
