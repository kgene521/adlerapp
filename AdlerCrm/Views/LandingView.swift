//
//  LandingView.swift
//  AdlerCrm
//
//  Created by E. K. Khanine on 3/25/26.
//

// AdlerCRM/Views/LandingView.swift
import SwiftUI

struct LandingView: View {
    @State private var showLogin = false
    @State private var appear = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "0d1f0f"),
                    Color(hex: "1a3d20"),
                    Color(hex: "0a1a0c")
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Decorative circles (subtle environmental feel)
            GeometryReader { geo in
                Circle()
                    .fill(Color(hex: "2d6a4f").opacity(0.15))
                    .frame(width: geo.size.width * 0.8)
                    .offset(x: -geo.size.width * 0.2, y: -geo.size.height * 0.1)

                Circle()
                    .fill(Color(hex: "15361e").opacity(0.2))
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: geo.size.width * 0.5, y: geo.size.height * 0.5)
            }

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    HStack(spacing: 10) {
                        Image("adler-logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 36)
                            .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Adler Resources")
                                .font(.custom("Syne-Bold", size: 15))
                                .foregroundColor(.white)
                            Text("Used Cooking Oil Management")
                                .font(.custom("DMSans-Regular", size: 10))
                                .foregroundColor(.white.opacity(0.45))
                        }
                    }

                    Spacer()

                    Button(action: { showLogin = true }) {
                        Text("Sign In →")
                            .font(.custom("Syne-SemiBold", size: 13))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 50)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                            )
                            .cornerRadius(50)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Spacer()

                // Hero content
                VStack(spacing: 0) {
                    // Logo
                    Image("adler-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 160, height: 160)
                        .shadow(color: Color(hex: "52b788").opacity(0.3), radius: 30, y: 8)
                        .padding(.bottom, 28)
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 20)

                    // Eyebrow
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: "52b788"))
                            .frame(width: 6, height: 6)

                        Text("SUSTAINABLE WASTE-TO-RESOURCE SOLUTIONS")
                            .font(.custom("DMSans-Medium", size: 10))
                            .tracking(1)
                            .foregroundColor(Color(hex: "52b788"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color(hex: "52b788").opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 50)
                            .stroke(Color(hex: "52b788").opacity(0.3), lineWidth: 1)
                    )
                    .cornerRadius(50)
                    .padding(.bottom, 24)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 20)

                    // Headline
                    VStack(spacing: 4) {
                        Text("Turning Waste Oil into")
                            .font(.custom("Syne-ExtraBold", size: 32))
                            .foregroundColor(.white)

                        Text("Renewable Futures")
                            .font(.custom("Syne-ExtraBold", size: 32))
                            .foregroundColor(Color(hex: "e8a84e"))
                    }
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 20)

                    // Subtitle
                    Text("Adler Resources partners with food businesses across the region to collect, process, and repurpose used cooking oil — keeping waste out of drains and putting it to work as clean, renewable biodiesel.")
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 36)
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 20)

                    // CTA Button
                    Button(action: { showLogin = true }) {
                        Text("Open CRM →")
                            .font(.custom("Syne-Bold", size: 15))
                            .foregroundColor(Color(hex: "0d1f0f"))
                            .padding(.horizontal, 36)
                            .padding(.vertical, 14)
                            .background(Color(hex: "c8893a"))
                            .cornerRadius(50)
                            .shadow(color: Color(hex: "c8893a").opacity(0.4), radius: 20, y: 6)
                    }
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 20)
                }

                Spacer()

                // Bottom stats
                HStack(spacing: 0) {
                    Spacer()
                    StatItem(value: "101", label: "DEPOT DR.")
                    Spacer()
                    StatItem(value: "540", label: "232-9705")
                    Spacer()
                    StatItem(value: "VA", label: "BOONES MILL")
                    Spacer()
                }
                .padding(.vertical, 24)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1),
                    alignment: .top
                )
                .opacity(appear ? 1 : 0)
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginView()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                appear = true
            }
        }
    }
}

struct StatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.custom("Syne-ExtraBold", size: 22))
                .foregroundColor(Color(hex: "52b788"))
            Text(label)
                .font(.custom("DMSans-Regular", size: 9))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.4))
        }
    }
}

// MARK: - Hex Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    LandingView()
        .environmentObject(AuthManager())
}
