// /AdlerCRM/Views/MainTabView.swift  08/04/2026 01:22:00 EDT
import SwiftUI
import Combine

// MARK: - More Menu Toolbar Modifier

struct MoreMenuToolbar: ViewModifier {
    var showHomeButton: Bool = true
    @Binding var showQuickActions: Bool
    @State private var showMore = false
    @State private var showNotifications = false
    @ObservedObject private var notifManager = NotificationManager.shared

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 14) {
                        Button(action: { showMore = true }) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color(hex: "0f1117"))
                        }
                        Button(action: { showNotifications = true }) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(notifManager.unreadCount > 0 ? Color(hex: "c8893a") : Color(hex: "7a7f94"))
                                if notifManager.unreadCount > 0 {
                                    Text("\(min(notifManager.unreadCount, 99))")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(Color(hex: "c1121f"))
                                        .cornerRadius(8)
                                        .offset(x: 8, y: -6)
                                }
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if showHomeButton {
                        Button(action: { showQuickActions = true }) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 15))
                                .foregroundColor(Color(hex: "c8893a"))
                        }
                    }
                }
            }
            .sheet(isPresented: $showMore) {
                NavigationStack {
                    MoreMenuView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { showMore = false }
                                    .font(.custom("DMSans-Medium", size: 14))
                                    .foregroundColor(Color(hex: "c8893a"))
                            }
                        }
                }
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsSheet()
            }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var selectedTab = "businesses"
    @State private var showNotificationsFromBanner = false
    @StateObject private var notifManager = NotificationManager.shared

    // Quick Actions
    @State private var showQuickActions = true
    @State private var showComposeNotification = false
    @State private var showTestRunner = false

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                // Businesses
                NavigationStack {
                    BusinessListView()
                        .modifier(MoreMenuToolbar(showQuickActions: $showQuickActions))
                }
                .tabItem {
                    Image(systemName: "building.2.fill")
                    Text("Businesses")
                }
                .tag("businesses")

                // Routes
                NavigationStack {
                    RoutePlannerView()
                        .modifier(MoreMenuToolbar(showQuickActions: $showQuickActions))
                }
                .tabItem {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    Text("Routes")
                }
                .tag("routes")

                // Calendar
                NavigationStack {
                    CalendarRouteView()
                        .modifier(MoreMenuToolbar(showQuickActions: $showQuickActions))
                }
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Calendar")
                }
                .tag("calendar")

                // Custom Route
                NavigationStack {
                    CustomRouteView()
                        .modifier(MoreMenuToolbar(showQuickActions: $showQuickActions))
                }
                .tabItem {
                    Image(systemName: "pencil.and.list.clipboard")
                    Text("Custom")
                }
                .tag("custom")

                // ToDo
                NavigationStack {
                    TodoView()
                        .modifier(MoreMenuToolbar(showQuickActions: $showQuickActions))
                }
                .tabItem {
                    Image(systemName: "checklist")
                    Text("To-Do")
                }
                .tag("todo")

                // Map — no Home button
                NavigationStack {
                    CollectionMapView()
                        .modifier(MoreMenuToolbar(showHomeButton: false, showQuickActions: $showQuickActions))
                }
                .tabItem {
                    Image(systemName: "map.fill")
                    Text("Map")
                }
                .tag("map")
            }
            .tint(Color(hex: "c8893a"))

            // Notification banner overlay
            NotificationBanner(showNotifications: $showNotificationsFromBanner)
        }
        .onAppear { notifManager.startPolling() }
        .onDisappear { notifManager.stopPolling() }
        .sheet(isPresented: $showNotificationsFromBanner) {
            NotificationsSheet()
        }
        .sheet(isPresented: $showQuickActions) {
            QuickActionsSheet { action in
                handleQuickAction(action)
            }
        }
        .sheet(isPresented: $showComposeNotification) {
            ComposeNotificationSheet(onSent: {})
        }
        .sheet(isPresented: $showTestRunner) {
            NavigationStack {
                TestRunnerView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showTestRunner = false }
                                .font(.custom("DMSans-Medium", size: 14))
                                .foregroundColor(Color(hex: "c8893a"))
                        }
                    }
            }
        }
    }

    // MARK: - Quick Action Handler

    private func handleQuickAction(_ action: QuickActionType) {
        switch action {
        case .switchTab(let tab):
            selectedTab = tab
        case .openSheet(let sheet):
            switch sheet {
            case .notifications:
                showComposeNotification = true
            case .tests:
                showTestRunner = true
            case .employees:
                // Placeholder — will open employee management when implemented
                break
            }
        }
    }
}

// MARK: - More Menu

struct MoreMenuView: View {
    @EnvironmentObject var auth: AuthManager

    private var isAdmin: Bool {
        auth.currentUser?.role == "Administrator"
    }

    private var canManage: Bool {
        isAdmin || auth.currentUser?.role == "Operations Manager"
    }

    var body: some View {
        List {
            // User info header
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "c8893a"))
                            .frame(width: 44, height: 44)
                        Text(initials(auth.currentUser?.name ?? "?"))
                            .font(.custom("Syne-Bold", size: 16))
                            .foregroundColor(Color(hex: "0f1117"))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(auth.currentUser?.name ?? "User")
                            .font(.custom("DMSans-SemiBold", size: 16))
                            .foregroundColor(Color(hex: "0f1117"))
                        Text(auth.currentUser?.role ?? "")
                            .font(.custom("DMSans-Regular", size: 13))
                            .foregroundColor(Color(hex: "7a7f94"))
                    }
                }
                .padding(.vertical, 4)
            }

            // Management
            Section("Management") {
                NavigationLink(destination: CorporateView()) {
                    Label("Corporate", systemImage: "building.columns.fill")
                        .foregroundColor(Color(hex: "c8893a"))
                }

                Label("Employees", systemImage: "person.2.fill")
                    .foregroundColor(Color(hex: "7a7f94"))

                if canManage {
                    NavigationLink(destination: RegionsView()) {
                        Label("Regions", systemImage: "map.circle.fill")
                            .foregroundColor(Color(hex: "c8893a"))
                    }
                }

                if isAdmin {
                    NavigationLink(destination: TestRunnerView()) {
                        Label("Tests", systemImage: "testtube.2")
                            .foregroundColor(Color(hex: "c8893a"))
                    }
                }
            }

            // Account
            Section("Account") {
                Label("Change Password", systemImage: "lock.fill")
                    .foregroundColor(Color(hex: "7a7f94"))

                Button(action: { auth.logout() }) {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundColor(Color(hex: "c1121f"))
                }
            }
        }
        .navigationTitle("More")
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).map { String($0.prefix(1)) }.joined().uppercased()
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthManager())
}
