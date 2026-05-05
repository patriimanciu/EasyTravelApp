import SwiftUI
internal import _LocationEssentials

struct ImportFromVideoView: View {
    @EnvironmentObject private var store: TravelStore
    @Binding var isPresented: Bool
    var initialVideoURL: String? = nil

    @State private var backendBaseURL: String = "https://patriimanciu--easytravel-api-serve.modal.run/"
    @State private var videoURL: String = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var importedCount: Int?
    @State private var progressMessage: String?

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

            // Resolve coordinates concurrently (small cap to reduce throttling).
            let created: [LocationItem] = try await withThrowingTaskGroup(of: LocationItem?.self) { group in
                var iterator = extraction.locations.makeIterator()

                func enqueueNext() {
                    guard let next = iterator.next() else { return }
                    group.addTask {
                        do {
                            let coord = try await LocationResolver.resolveCoordinate(name: next.name, city: next.city)
                            return LocationItem(
                                name: next.name,
                                latitude: coord.latitude,
                                longitude: coord.longitude,
                                category: LocationItem.category(fromBackendString: next.category),
                                notes: "Imported from video • \(next.city)",
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
}

