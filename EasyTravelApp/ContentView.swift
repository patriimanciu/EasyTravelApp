//
//  ContentView.swift
//  EasyTravelApp
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TravelStore
    @State private var selectedTab: AppTab = .trips

    var body: some View {
        VStack(spacing: 0) {
            VideoImportTopBanner(
                phase: store.videoImportPhase,
                onDismiss: { store.dismissVideoImportBanner() },
                onOpenInbox: { selectedTab = .inbox }
            )

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
        }
        .background(AppTheme.screenBackground.ignoresSafeArea())
        .tint(AppTheme.charcoal)
        .animation(.easeInOut(duration: 0.25), value: store.videoImportPhase)
        .animation(.easeInOut(duration: 0.25), value: store.routePlanPhase)
        .overlay {
            RoutePlanCenterOverlay(
                phase: store.routePlanPhase,
                onDismiss: { store.dismissRoutePlanOverlay() }
            )
        }
        .onChange(of: store.videoImportPhase) { _, phase in
            if case .success = phase {
                selectedTab = .inbox
            }
        }
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
