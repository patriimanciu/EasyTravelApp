import SwiftUI
internal import _LocationEssentials

struct ImportFromVideoView: View {
    @EnvironmentObject private var store: TravelStore
    @Binding var isPresented: Bool
    var initialVideoURL: String? = nil

    @AppStorage("easytravelBackendBaseURL") private var backendBaseURL: String =
        "https://patriimanciu--easytravel-api-serve.modal.run/"
    /// MapKit search has no opening hours; optional Google Places API (New) key fills them on import.
    @AppStorage("googlePlacesAPIKey") private var googlePlacesAPIKey: String = ""
    @State private var videoURL: String = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var importedCount: Int?
    @State private var progressMessage: String?
    @State private var placesHoursDebug: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend") {
                    TextField("Base URL", text: $backendBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Video URL") {
                    TextField("https://…", text: $videoURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    SecureField("Google Places API key (optional)", text: $googlePlacesAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                } header: {
                    Text("Opening hours")
                } footer: {
                    Text("Hours use Places API (New) Place Details (`regularOpeningHours`, billed as Enterprise SKU). Enable that API on the key.")
                        .font(.footnote)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if let importedCount {
                    Section {
                        Text("Imported \(importedCount) location(s).")
                    }
                }

                if let progressMessage {
                    Section {
                        Text(progressMessage)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let placesHoursDebug, !placesHoursDebug.isEmpty {
                    Section("Hours debug") {
                        Text(placesHoursDebug)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Import from Video")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isImporting ? "Importing…" : "Import") {
                        Task { await importLocations() }
                    }
                    .disabled(isImporting || videoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let initialVideoURL, videoURL.isEmpty {
                    videoURL = initialVideoURL
                }
            }
        }
    }

    @MainActor
    private func importLocations() async {
        errorMessage = nil
        importedCount = nil
        progressMessage = nil
        placesHoursDebug = nil
        isImporting = true
        defer { isImporting = false }

        do {
            let client = BackendClient(baseURLString: backendBaseURL)
            let trimmedVideoURL = videoURL.trimmingCharacters(in: .whitespacesAndNewlines)
            progressMessage = "Calling backend…"
            let extraction = try await client.processVideo(url: trimmedVideoURL)

            if extraction.locations.isEmpty {
                errorMessage = "Backend returned 0 locations."
                return
            }

            progressMessage = "Finding coordinates on Maps…"

            let placesKey = googlePlacesAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

            // Resolve coordinates concurrently (small cap to reduce throttling).
            let created: [LocationItem] = try await withThrowingTaskGroup(of: LocationItem?.self) { group in
                var iterator = extraction.locations.makeIterator()

                func enqueueNext() {
                    guard let next = iterator.next() else { return }
                    group.addTask {
                        do {
                            let trimmedBackendAddr = Self.nonBlank(next.address)
                            let place = try await LocationResolver.resolvePlace(
                                name: next.name,
                                city: next.city,
                                address: trimmedBackendAddr
                            )
                            // Same enrichment as manual add: prefer Apple Maps POI fields, fall back to LLM/OCR extras.
                            let address = place.formattedAddress ?? trimmedBackendAddr
                            let phoneNumber = Self.nonBlank(place.phoneNumber) ?? Self.nonBlank(next.phoneNumber)
                            let url = Self.nonBlank(place.url) ?? Self.nonBlank(next.url)
                            let backendHoursLines = Self.hoursLines(from: next.openingHours)
                            let mergedHoursLines: [String]?
                            if let backendHoursLines {
                                mergedHoursLines = backendHoursLines
                            } else if placesKey.isEmpty {
                                mergedHoursLines = nil
                            } else {
                                let (hours, debug) = await PlacesOpeningHoursFetcher.weekdayDescriptionsWithDebug(
                                    placeName: next.name,
                                    city: next.city,
                                    coordinate: place.coordinate,
                                    apiKey: placesKey
                                )
                                if let debug, !debug.isEmpty {
                                    // Keep the last debug (usually enough to diagnose: API disabled / billing / key restrictions)
                                    await MainActor.run { placesHoursDebug = debug }
                                }
                                mergedHoursLines = hours
                            }
                            let openingHours = mergedHoursLines
                            let notesParts = ["Imported from video", next.city]
                            return LocationItem(
                                name: next.name,
                                latitude: place.coordinate.latitude,
                                longitude: place.coordinate.longitude,
                                category: LocationItem.category(fromBackendString: next.category),
                                notes: notesParts.joined(separator: " • "),
                                address: address,
                                phoneNumber: phoneNumber,
                                url: url,
                                openingHours: openingHours,
                                source: .init(kind: .videoExtraction, videoURL: trimmedVideoURL, rawPayload: nil)
                            )
                        } catch {
                            // Skip items we can't geocode (keeps import robust).
                            return nil
                        }
                    }
                }

                for _ in 0..<min(3, extraction.locations.count) { enqueueNext() }

                var acc: [LocationItem] = []
                acc.reserveCapacity(extraction.locations.count)

                while let result = try await group.next() {
                    if let result { acc.append(result) }
                    enqueueNext()
                }

                return acc
            }

            if created.isEmpty {
                errorMessage = "Couldn’t find coordinates for any returned locations."
                return
            }

            store.addToInbox(created)
            importedCount = created.count
            progressMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Trimmed non-empty string from optional backend fields.
    private static func nonBlank(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func hoursLines(from raw: String?) -> [String]? {
        guard let raw = nonBlank(raw) else { return nil }
        let lines = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines
    }
}

