import SwiftUI
import MapKit

struct AddLocationView: View {
    @EnvironmentObject private var store: TravelStore
    let tripID: Trip.ID
    @Binding var isPresented: Bool

    @StateObject private var searchVM = PlaceSearchViewModel()

    @State private var name: String = ""
    @State private var category: LocationItem.Category = .landmark
    @State private var notes: String = ""

    private var trip: Trip? {
        store.trips.first(where: { $0.id == tripID })
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return searchVM.selectedCoordinate != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    AppSheetIntro(
                        title: "Add a place",
                        subtitle: introSubtitle,
                        systemImage: "mappin.and.ellipse",
                        accent: AppTheme.categoryTint(.landmark)
                    )

                    searchBlock
                    detailsBlock
                }
                .appPagePadding()
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .scrollDismissesKeyboard(.interactively)
            .appScreenBackground()
            .navigationTitle("New Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundStyle(AppTheme.charcoal)
                }
            }
            .safeAreaInset(edge: .bottom) {
                AppCharcoalButton(title: "Add to trip", disabled: !canSave) {
                    addLocation()
                }
                .appPagePadding()
                .padding(.vertical, 12)
                .background(AppTheme.screenBackground)
            }
            .tint(AppTheme.charcoal)
            .presentationBackground(AppTheme.screenBackground)
            .onAppear(perform: configureSearchFromTrip)
        }
    }

    private var introSubtitle: String {
        if let summary = trip?.placeFilterSummary {
            return "Search is biased to \(summary) — set in Trip settings if you need to change it."
        }
        return "Set country (and optional city) in Trip settings to bias Maps suggestions."
    }

    private func configureSearchFromTrip() {
        guard let trip else { return }
        searchVM.applyTripContext(TripPlaceSearchContext.make(from: trip))
    }

    // MARK: - Search

    private var searchBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Search on Maps")

            if let summary = trip?.placeFilterSummary {
                AppTipBanner(
                    text: "Suggestions filtered to \(summary).",
                    systemImage: "location.magnifyingglass"
                )
            } else if trip != nil, trip!.trimmedCountry.isEmpty {
                AppFormBanner(
                    text: "Add a country in Trip settings to improve Maps suggestions.",
                    style: .info
                )
            }

            AppFormSearchBar(
                text: $searchVM.query,
                category: category,
                isSearching: searchVM.isSearching,
                placeholder: searchPlaceholder,
                onClear: {
                    searchVM.query = ""
                    searchVM.clearSelection()
                }
            )

            if let msg = searchVM.lastErrorMessage {
                AppFormBanner(text: msg, style: .error)
            }

            if searchVM.isShowingUnfilteredFallback {
                AppFormBanner(
                    text: "No matches for this trip’s place filter — showing broader results.",
                    style: .info
                )
            }

            searchResultsContent
        }
    }

    private var searchPlaceholder: String {
        if let summary = trip?.placeFilterSummary {
            return "e.g. Louvre Museum, \(summary)"
        }
        return "e.g. Louvre Museum"
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        if let selectedName = searchVM.selectedName,
           let coord = searchVM.selectedCoordinate
        {
            AppSelectablePlaceRow(
                title: selectedName,
                subtitle: formattedCoordinates(coord),
                category: category,
                isSelected: true
            )
            AppFormFooterText("Selected on Maps — adjust the name below if needed.")
        } else if searchVM.isSearching, !searchVM.query.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text("Searching…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else if !searchVM.completions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Suggestions", trailing: "\(searchVM.completions.count)")
                ForEach(searchVM.completions, id: \.self) { completion in
                    Button {
                        Task {
                            await searchVM.select(completion)
                            if let selectedName = searchVM.selectedName {
                                name = selectedName
                            } else {
                                name = completion.title
                            }
                        }
                    } label: {
                        AppSelectablePlaceRow(
                            title: completion.title,
                            subtitle: completion.subtitle,
                            category: category
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if searchVM.query.isEmpty {
            AppFormFooterText("Type a place name to search on Apple Maps.")
        }
    }

    // MARK: - Details

    private var detailsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Details")

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Category")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    CategoryPickerChips(selection: $category)
                }

                AppFormField(
                    label: "Display name",
                    placeholder: "Name on your trip",
                    text: $name,
                    autocapitalizeWords: true
                )

                AppFormField(
                    label: "Notes",
                    placeholder: "Optional — what you want to do here",
                    text: $notes,
                    axis: .vertical,
                    lineLimit: 3...6
                )
            }
            .softCard()
        }
    }

    private func formattedCoordinates(_ coord: CLLocationCoordinate2D) -> String {
        var parts: [String] = []
        if let summary = trip?.placeFilterSummary {
            parts.append(summary)
        }
        parts.append(String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
        return parts.joined(separator: " · ")
    }

    private func addLocation() {
        guard let coord = searchVM.selectedCoordinate else { return }
        let notesTrimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let loc = LocationItem(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: coord.latitude,
            longitude: coord.longitude,
            category: category,
            notes: notesTrimmed.isEmpty ? nil : notesTrimmed,
            address: searchVM.selectedAddress,
            phoneNumber: searchVM.selectedPhoneNumber,
            url: searchVM.selectedURL,
            openingHours: nil,
            source: .manual()
        )
        store.addLocation(to: tripID, location: loc)
        isPresented = false
    }
}

#Preview("Add location") {
    @Previewable @State var isPresented = true
    AddLocationView(tripID: PreviewData.parisTripID, isPresented: $isPresented)
        .environmentObject(TravelStore.preview)
}
