//
//  KuttukeApp.swift
//  Kuttuke
//
//  Created by harumi.sagawa on 2026/10/09.
//

import SwiftUI

/// App Storeのアプリページ（シェアする文章に添える）
enum AppStoreLink {
    static let url = URL(string: "https://apps.apple.com/app/id6820843882")!
}

@main
struct KuttukeApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(KuttukeTheme.orange)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task { await InterstitialAdManager.shared.start() }
        }
    }
}
