//
//  KuttukeApp.swift
//  Kuttuke
//
//  Created by harumi.sagawa on 2026/10/09.
//

import SwiftUI

@main
struct KuttukeApp: App {
    init() {
        InterstitialAdManager.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(KuttukeTheme.orange)
        }
    }
}
