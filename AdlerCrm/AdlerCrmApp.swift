// AdlerCRM/AdlerCRMApp.swift  28/03/2026 02:01:42
import SwiftUI

@main
struct AdlerCRMApp: App {
    @StateObject private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var showSessionExpired = false

    var body: some View {
        Group {
            if auth.isAuthenticated {
                MainTabView()
            } else {
                LandingView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: auth.isAuthenticated)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("adlerSessionExpired"))) { _ in
            if auth.isAuthenticated {
                showSessionExpired = true
            }
        }
        .alert("Session Expired", isPresented: $showSessionExpired) {
            Button("Log In Again") {
                auth.logout()
            }
        } message: {
            Text("Your session has expired. Please log in again to continue.")
        }
    }
}
