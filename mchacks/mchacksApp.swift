//
//  mchacksApp.swift
//  mchacks
//
//  Created by Omar Lahlou Mimi on 2026-01-13.
//

import SwiftUI
import MapboxMaps

@main
struct mchacksApp: App {
    init() {
        // Set Mapbox access token
        MapboxOptions.accessToken = "sk.eyJ1Ijoib21hcmxhaG1pbWkiLCJhIjoiY21rY3V6ZGJrMDVsZDNmcTh1bmlmZHh4cSJ9.HDp0rzKa9umGwh7YuMYpQg"

        // Initialize EmergencyContactManager singleton
        _ = EmergencyContactManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
