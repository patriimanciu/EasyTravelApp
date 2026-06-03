//
//  ContentView.swift
//  EasyTravelApp
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TravelStore
    @State private var selectedTab: AppTab = .trips

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .trips:
                    NavigationStack {
                        TripsView()
                            .toolbar(.hidden, for: .navigationBar)
                    }
                case .inbox:
                    NavigationStack {
                        InboxView()
                            .toolbar(.hidden, for: .navigationBar)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FloatingTabBar(
                selection: $selectedTab,
                inboxBadge: store.inbox.count
            )
        }
        .background(AppTheme.screenBackground.ignoresSafeArea())
        .tint(AppTheme.charcoal)
    }
}

#Preview("App") {
    ContentView()
        .environmentObject(TravelStore.preview)
}

#Preview("Trips tab") {
    PreviewShell.navigation {
        TripsView()
            .toolbar(.hidden, for: .navigationBar)
    }
    .environmentObject(TravelStore.preview)
    .appScreenBackground()
}
