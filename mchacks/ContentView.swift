//
//  ContentView.swift
//  mchacks
//
//  Created by Omar Lahlou Mimi on 2026-01-13.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var emergencyManager = EmergencyContactManager.shared
    @State private var showEmergencySetup = false

    var body: some View {
        MainNavigationView()
            .onAppear {
                // Show emergency contact setup on first launch if not set
                if !emergencyManager.hasEmergencyContact {
                    showEmergencySetup = true
                }
            }
            .fullScreenCover(isPresented: $showEmergencySetup) {
                EmergencyContactSetupView(isFirstLaunch: true) {
                    showEmergencySetup = false
                }
            }
    }
}

#Preview {
    ContentView()
}
