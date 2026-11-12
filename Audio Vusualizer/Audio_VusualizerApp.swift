//
//  Audio_VusualizerApp.swift
//  Audio Vusualizer
//
//  Created by Mацвей Пажытных on 12.11.2026.
//

import SwiftUI

@main
struct Audio_VusualizerApp: App {
    init() {
        SettingsKey.migrate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1200, height: 520)

        Settings {
            SettingsView()
        }
        // Sized by the content: 480 pt wide, 620 pt tall by default, resizable vertically.
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 620)
    }
}
