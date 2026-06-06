import SwiftUI

struct EditLocationView: View {
    @EnvironmentObject private var store: TravelStore
    @Environment(\.dismiss) private var dismiss

    let locationID: LocationItem.ID
    let tripID: Trip.ID?

    @State private var name: String = ""
    @State private var category: LocationItem.Category = .other
    @State private var country: String = ""
    @State private var city: String = ""
    @State private var address: String = ""
    @State private var phoneNumber: String = ""
    @State private var urlString: String = ""
    @State private var openingHoursDraftText: String = ""
    @State private var notes: String = ""
    @State private var visitPriority: LocationItem.VisitPriority = .normal
    @State private var initialLocation: LocationItem?

    private var isInboxLocation: Bool { tripID == nil }

    private var categories: [LocationItem.Category] {
        LocationItem.Category.allCases.sorted(by: { $0.sortRank < $1.sortRank })
    }

    private var currentLocation: LocationItem? {
        store.location(id: locationID, tripID: tripID)
    }

    var body: some View {
        Group {
            if initialLocation != nil {
                formContent()
            } else {
                ContentUnavailableView("Location not found", systemImage: "mappin.slash")
            }
        }
        .navigationTitle("Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
            }
        }
        .tint(AppTheme.charcoal)
        .onAppear(perform: loadFromStore)
        .onChange(of: currentLocation?.id) { _, _ in loadFromStore() }
    }

    @ViewBuilder
    private func formContent() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                AppFormSection(title: "Place") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Category", selection: $category) {
                        ForEach(categories) { cat in
                            Text(cat.title).tag(cat)
                        }
                    }
                }

                AppFormSection(
                    title: "Details",
                    footer: detailsFooter
                ) {
                    if isInboxLocation {
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
                    }
                    AppFormField(label: "Address", placeholder: "Street address", text: $address, autocapitalizeWords: true)
                    AppFormField(label: "Phone", placeholder: "Optional", text: $phoneNumber)
                    AppFormField(label: "Website", placeholder: "https://…", text: $urlString)
                    TextEditor(text: $openingHoursDraftText)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(AppTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if !isInboxLocation {
                    AppFormSection(title: "Itinerary priority") {
                        Picker("Priority", selection: $visitPriority) {
                            ForEach(LocationItem.VisitPriority.allCases.sorted(by: { $0.rawValue > $1.rawValue })) { p in
                                Text(p.title).tag(p)
                            }
                        }
                        HStack(spacing: 8) {
                            PriorityPill(priority: visitPriority)
                            Text(visitPriority.planningHint)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                AppFormSection(title: "Notes") {
                    TextField("What I want to do here", text: $notes, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .appPagePadding()
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .appScreenBackground()
    }

    private var detailsFooter: String {
        if isInboxLocation {
            return "Country and city help filter the inbox. Opening hours: one line per day."
        }
        return "City and country are set on the trip (Trip settings). Opening hours: one line per day."
    }

    private func loadFromStore() {
        guard let loc = currentLocation else {
            initialLocation = nil
            return
        }
        initialLocation = loc
        name = loc.name
        category = loc.category
        country = loc.country ?? ""
        city = loc.city ?? ""
        address = loc.address ?? ""
        phoneNumber = loc.phoneNumber ?? ""
        urlString = loc.url ?? ""
        openingHoursDraftText = (loc.openingHours ?? []).joined(separator: "\n")
        notes = loc.notes ?? ""
        visitPriority = loc.visitPriority
    }

    private func nonBlank(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func parseHoursLines(_ text: String) -> [String]? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines
    }

    private func save() {
        guard let loc = initialLocation else { return }

        let updated = LocationItem(
            id: loc.id,
            name: nonBlank(name) ?? loc.name,
            latitude: loc.latitude,
            longitude: loc.longitude,
            category: category,
            notes: nonBlank(notes),
            address: nonBlank(address),
            city: isInboxLocation ? nonBlank(city) : loc.city,
            country: isInboxLocation ? nonBlank(country) : loc.country,
            phoneNumber: nonBlank(phoneNumber),
            url: nonBlank(urlString),
            openingHours: parseHoursLines(openingHoursDraftText),
            visitPriority: visitPriority,
            createdAt: loc.createdAt,
            source: loc.source
        )

        store.updateLocation(tripID: tripID, location: updated)
        dismiss()
    }
}

#Preview("Edit location") {
    PreviewShell.navigation {
        EditLocationView(
            locationID: PreviewData.parisLocationID,
            tripID: PreviewData.parisTripID
        )
    }
    .environmentObject(TravelStore.preview)
}

#Preview("Edit inbox location") {
    PreviewShell.navigation {
        EditLocationView(
            locationID: PreviewData.inboxLocationID,
            tripID: nil
        )
    }
    .environmentObject(TravelStore.preview)
}
