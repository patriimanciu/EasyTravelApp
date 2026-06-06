import SwiftUI
import MapKit

struct AddInboxLocationView: View {
    @EnvironmentObject private var store: TravelStore
    @Binding var isPresented: Bool

    @StateObject private var searchVM = PlaceSearchViewModel()

    @State private var country: String = ""
    @State private var city: String = ""
    @State private var name: String = ""
    @State private var category: LocationItem.Category = .landmark
    @State private var notes: String = ""

    private var trimmedCountry: String {
        country.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCity: String? {
        let t = city.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private var placeFilterSummary: String? {
        TripPlaceSearchContext(
            region: nil,
            city: trimmedCity,
            country: trimmedCountry.isEmpty ? nil : trimmedCountry
        ).filterSummary
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
                        subtitle: "Search on Maps, then save to your inbox before assigning to a trip.",
                        systemImage: "tray.and.arrow.down.fill",
                        accent: AppTheme.categoryTint(.landmark)
                    )

                    placeFieldsBlock
                    searchBlock
                    detailsBlock
                }
                .appPagePadding()
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .scrollDismissesKeyboard(.interactively)
            .appScreenBackground()
            .navigationTitle("New Inbox Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundStyle(AppTheme.charcoal)
                }
            }
            .safeAreaInset(edge: .bottom) {
                AppCharcoalButton(title: "Add to inbox", disabled: !canSave) {
                    addLocation()
                }
                .appPagePadding()
                .padding(.vertical, 12)
                .background(AppTheme.screenBackground)
            }
            .tint(AppTheme.charcoal)
            .presentationBackground(AppTheme.screenBackground)
            .onAppear(perform: applySearchContext)
            .onChange(of: country) { _, _ in applySearchContext() }
            .onChange(of: city) { _, _ in applySearchContext() }
        }
    }

    private var placeFieldsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Place")

            VStack(alignment: .leading, spacing: 16) {
                AppFormField(
                    label: "Country",
                    placeholder: "e.g. France",
                    text: $country,
                    autocapitalizeWords: true
                )

                AppFormField(
                    label: "City",
                    placeholder: "Optional — e.g. Paris",
                    text: $city,
                    autocapitalizeWords: true
                )

                if trimmedCountry.isEmpty {
                    AppFormBanner(
                        text: "Add a country to improve Maps suggestions and inbox filtering.",
                        style: .info
                    )
                }
            }
            .softCard()
        }
    }

    private var searchBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Search on Maps")

            if let summary = placeFilterSummary {
                AppTipBanner(
                    text: "Suggestions filtered to \(summary).",
                    systemImage: "location.magnifyingglass"
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
                    text: "No matches for your place filter — showing broader results.",
                    style: .info
                )
            }

            searchResultsContent
        }
    }

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
                    placeholder: "Name in your inbox",
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

    private var searchPlaceholder: String {
        if let summary = placeFilterSummary {
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
            AppFormFooterText("Selected on Maps — adjust the name and place fields below if needed.")
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
                            if country.isEmpty, let pickedCountry = searchVM.selectedCountry {
                                country = pickedCountry
                            }
                            if city.isEmpty, let pickedCity = searchVM.selectedCity {
                                city = pickedCity
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

    private func applySearchContext() {
        searchVM.applyTripContext(
            TripPlaceSearchContext(
                region: nil,
                city: trimmedCity,
                country: trimmedCountry.isEmpty ? nil : trimmedCountry
            )
        )
    }

    private func formattedCoordinates(_ coord: CLLocationCoordinate2D) -> String {
        var parts: [String] = []
        if let summary = placeFilterSummary {
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
            city: nonBlank(city) ?? searchVM.selectedCity,
            country: nonBlank(country) ?? searchVM.selectedCountry,
            phoneNumber: searchVM.selectedPhoneNumber,
            url: searchVM.selectedURL,
            openingHours: nil,
            source: .manual()
        )
        store.addToInbox([loc])
        isPresented = false
    }

    private func nonBlank(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

#Preview("Add inbox location") {
    @Previewable @State var isPresented = true
    AddInboxLocationView(isPresented: $isPresented)
        .environmentObject(TravelStore.preview)
}
