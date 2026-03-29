// AdlerCRM/Views/MainTabView.swift  28/03/2026 17:28:32
import SwiftUI
import Combine

// MARK: - More Menu Toolbar Modifier

struct MoreMenuToolbar: ViewModifier {
    @State private var showMore = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showMore = true }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(hex: "0f1117"))
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
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var selectedTab = "businesses"

    var body: some View {
        TabView(selection: $selectedTab) {
            // Businesses
            NavigationStack {
                BusinessListView()
                    .modifier(MoreMenuToolbar())
            }
            .tabItem {
                Image(systemName: "building.2.fill")
                Text("Businesses")
            }
            .tag("businesses")

            // Routes
            NavigationStack {
                RoutePlannerView()
                    .modifier(MoreMenuToolbar())
            }
            .tabItem {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                Text("Routes")
            }
            .tag("routes")

            // Calendar
            NavigationStack {
                CalendarRouteView()
                    .modifier(MoreMenuToolbar())
            }
            .tabItem {
                Image(systemName: "calendar")
                Text("Calendar")
            }
            .tag("calendar")

            // Custom Route
            NavigationStack {
                CustomRouteView()
                    .modifier(MoreMenuToolbar())
            }
            .tabItem {
                Image(systemName: "pencil.and.list.clipboard")
                Text("Custom")
            }
            .tag("custom")

            // Map
            NavigationStack {
                CollectionMapView()
                    .modifier(MoreMenuToolbar())
            }
            .tabItem {
                Image(systemName: "map.fill")
                Text("Map")
            }
            .tag("map")
        }
        .tint(Color(hex: "c8893a"))
    }
}

// MARK: - More Menu

struct MoreMenuView: View {
    @EnvironmentObject var auth: AuthManager

    private var canManage: Bool {
        auth.currentUser?.role == "Administrator" || auth.currentUser?.role == "Operations Manager"
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
                Label("Employees", systemImage: "person.2.fill")
                    .foregroundColor(Color(hex: "7a7f94"))

                if canManage {
                    NavigationLink(destination: RegionsView()) {
                        Label("Regions", systemImage: "map.circle.fill")
                            .foregroundColor(Color(hex: "c8893a"))
                    }
                }

                Label("Reports", systemImage: "chart.pie.fill")
                    .foregroundColor(Color(hex: "7a7f94"))
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
