import SwiftUI

@main
struct WalletApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .statusBarHidden(false)
        }
    }
}

struct RootView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            WalletWebView()
                .ignoresSafeArea()          // web content runs edge-to-edge so
        }                                    // CSS env(safe-area-inset-*) is correct
    }
}
