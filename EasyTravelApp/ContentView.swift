//
//  ContentView.swift
//  EasyTravelApp
//
//  Created by patri manciu on 12.03.2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TravelStore
    
    var body: some View {
        TabView {
            NavigationStack {
                TripsView()
                    .navigationTitle("Trips")
            }
            .tabItem {
                Label("Trips", systemImage: "airplane")
            }

            NavigationStack {
                InboxView()
            }
            .tabItem {
                Label("Inbox", systemImage: "tray")
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(TravelStore())
}
