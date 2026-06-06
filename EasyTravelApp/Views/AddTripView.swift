import SwiftUI

struct AddTripView: View {
    @EnvironmentObject private var store: TravelStore
    @Binding var isPresented: Bool

    @State private var name: String = ""
    @State private var country: String = ""
    @State private var city: String = ""
    @State private var includeDates = false
    @State private var startDate = Date()
    @State private var endDate = Date()

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    AppSheetIntro(
                        title: "New trip",
                        subtitle: "Set where you’re going — every stop on this trip uses the same country (and optional city) for Maps search.",
                        systemImage: "airplane.departure",
                        accent: AppTheme.peachDeep
                    )

                    VStack(alignment: .leading, spacing: 14) {
                        AppFormField(
                            label: "Trip name",
                            placeholder: "e.g. Paris weekend",
                            text: $name,
                            autocapitalizeWords: true
                        )
                        AppFormField(
                            label: "Country",
                            placeholder: "Required — e.g. France",
                            text: $country,
                            autocapitalizeWords: true
                        )
                        AppFormField(
                            label: "City",
                            placeholder: "Optional — e.g. Paris",
                            text: $city,
                            autocapitalizeWords: true
                        )
                        AppFormToggleRow(
                            title: "Travel dates",
                            subtitle: "Optional — locks day count when you plan a route",
                            isOn: $includeDates
                        )
                        if includeDates {
                            AppFormDateRow(label: "Start", date: $startDate)
                            AppFormDateRow(label: "End", date: $endDate)
                        }
                    }
                    .softCard()
                }
                .appPagePadding()
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .scrollDismissesKeyboard(.interactively)
            .appScreenBackground()
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundStyle(AppTheme.charcoal)
                }
            }
            .safeAreaInset(edge: .bottom) {
                AppCharcoalButton(title: "Create trip", disabled: !canAdd) {
                    addTrip()
                }
                .appPagePadding()
                .padding(.vertical, 12)
                .background(AppTheme.screenBackground)
            }
            .tint(AppTheme.charcoal)
            .presentationBackground(AppTheme.screenBackground)
        }
    }

    private func addTrip() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmedCountry.isEmpty else { return }
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        store.addTrip(
            name: trimmed,
            country: trimmedCountry,
            city: trimmedCity.isEmpty ? nil : trimmedCity,
            startDate: includeDates ? startDate : nil,
            endDate: includeDates ? endDate : nil
        )
        isPresented = false
    }
}

#Preview("Add trip") {
    @Previewable @State var isPresented = true
    AddTripView(isPresented: $isPresented)
        .environmentObject(TravelStore.preview)
}
