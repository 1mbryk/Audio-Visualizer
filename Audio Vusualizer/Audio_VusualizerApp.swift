//
//  Audio_VusualizerApp.swift
//  Audio Vusualizer
//
//  Created by Mацвей Пажытных on 12.11.2026.
//

import SwiftUI

@main
struct Audio_VusualizerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1200, height: 520)

        Settings {
            SettingsView()
        }
    }
}
