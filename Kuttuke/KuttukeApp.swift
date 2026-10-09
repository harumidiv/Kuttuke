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
