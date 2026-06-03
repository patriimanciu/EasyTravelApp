//
//  EasyTravelAppApp.swift
//  EasyTravelApp
//
//  Created by patri manciu on 12.03.2026.
//

import SwiftUI

@main
struct EasyTravelAppApp: App {
    @StateObject private var store = TravelStore()
    @State private var pendingImport: PendingImport?

    struct PendingImport: Identifiable {
        var id = UUID()
        var videoURL: String
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(AppTheme.charcoal)
                .onOpenURL { url in
                    // Expected format: easytravel://import?url=<sharedVideoURL>
                    if url.scheme?.lowercased() == "easytravel" {
                        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                        let shared = components?.queryItems?.first(where: { $0.name == "url" })?.value
                        if let shared, !shared.isEmpty {
                            pendingImport = PendingImport(videoURL: shared)
                        }
                    }
                }
                .sheet(item: $pendingImport) { item in
                    ImportFromVideoView(isPresented: Binding(
                        get: { pendingImport != nil },
                        set: { if !$0 { pendingImport = nil } }
                    ), initialVideoURL: item.videoURL)
                }
        }
    }
}
