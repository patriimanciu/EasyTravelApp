import SwiftUI

struct ImportFromVideoView: View {
    @EnvironmentObject private var store: TravelStore
    @Binding var isPresented: Bool
    var initialVideoURL: String? = nil

    @AppStorage("easytravelBackendBaseURL") private var backendBaseURL: String =
        "https://patriimanciu--easytravel-api-serve.modal.run/"
    @AppStorage("googlePlacesAPIKey") private var googlePlacesAPIKey: String = ""
    @State private var videoURL: String = ""
    @State private var errorMessage: String?

    private var canImport: Bool {
        !videoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    AppFormSection(
                        title: "Backend",
                        footer: "Same server as Plan route. Deploy must include POST /api/process-video."
                    ) {
                        TextField("Base URL", text: $backendBaseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    AppFormSection(title: "Video URL") {
                        TextField("https://…", text: $videoURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    AppFormSection(
                        title: "Opening hours",
                        footer: "Hours use Places API (New) Place Details (`regularOpeningHours`, billed as Enterprise SKU). Enable that API on the key."
                    ) {
                        SecureField("Google Places API key (optional)", text: $googlePlacesAPIKey)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                    }

                    if let errorMessage {
                        AppFormBanner(text: errorMessage, style: .error)
                    }
                }
                .appPagePadding()
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .scrollDismissesKeyboard(.interactively)
            .appScreenBackground()
            .navigationTitle("Import from Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                        .foregroundStyle(AppTheme.charcoal)
                }
            }
            .safeAreaInset(edge: .bottom) {
                AppCharcoalButton(title: "Import", disabled: !canImport) {
                    Task { await importLocations() }
                }
                .appPagePadding()
                .padding(.vertical, 12)
                .background(AppTheme.screenBackground)
            }
            .tint(AppTheme.charcoal)
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
        let trimmed = videoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter a video URL."
            return
        }

        let baseURL = backendBaseURL
        let placesKey = googlePlacesAPIKey
        isPresented = false
        await store.importFromVideo(url: trimmed, baseURL: baseURL, googlePlacesAPIKey: placesKey)
    }
}

#Preview("Import from video") {
    @Previewable @State var isPresented = true
    ImportFromVideoView(isPresented: $isPresented)
        .environmentObject(TravelStore.preview)
}
