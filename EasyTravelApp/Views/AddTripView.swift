import SwiftUI

struct AddTripView: View {
    @EnvironmentObject private var store: TravelStore
    @Binding var isPresented: Bool

    @State private var name: String = ""
    @State private var includeDates = false
    @State private var startDate = Date()
    @State private var endDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    Toggle("Set dates", isOn: $includeDates)

                    if includeDates {
                        DatePicker("Start", selection: $startDate, displayedComponents: [.date])
                        DatePicker("End", selection: $endDate, displayedComponents: [.date])
                    }
                }
            }
            .navigationTitle("New Trip")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        store.addTrip(
                            name: trimmed,
                            startDate: includeDates ? startDate : nil,
                            endDate: includeDates ? endDate : nil
                        )
                        isPresented = false
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview("Add trip") {
    @Previewable @State var isPresented = true
    AddTripView(isPresented: $isPresented)
        .environmentObject(TravelStore.preview)
}
