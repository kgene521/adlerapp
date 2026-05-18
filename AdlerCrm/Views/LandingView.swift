// /AdlerCRM/Views/LandingView.swift  08/04/2026 06:00:00 EDT
import SwiftUI

struct LandingView: View {
    @State private var showLogin = false
    @State private var appear = false

    var body: some View {
        ZStack {
            Color.theme.surface
                .ignoresSafeArea()

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
                                .foregroundColor(Color.theme.text)
                            Text("Used Cooking Oil Management")
                                .font(.custom("DMSans-Regular", size: 10))
                                .foregroundColor(Color.theme.textSecondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Spacer()

                VStack(spacing: 0) {
                    Image("adler-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 160, height: 160)
                        .padding(.bottom, 28)
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 20)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.theme.green)
                            .frame(width: 6, height: 6)
                        Text("SUSTAINABLE WASTE-TO-RESOURCE SOLUTIONS")
                            .font(.custom("DMSans-Medium", size: 10))
                            .tracking(1)
                            .foregroundColor(Color.theme.green)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.theme.green.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 50).stroke(Color.theme.green.opacity(0.2), lineWidth: 1))
                    .cornerRadius(50)
                    .padding(.bottom, 24)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 20)

                    VStack(spacing: 4) {
                        Text("Used Cooking Oil")
                            .font(.custom("Syne-ExtraBold", size: 32))
                            .foregroundColor(Color.theme.text)
                        Text("Management")
                            .font(.custom("Syne-ExtraBold", size: 32))
                            .foregroundColor(Color.theme.gold)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 20)

                    Text("Adler Resources partners with food businesses across the region to collect, process, and repurpose used cooking oil — keeping waste out of drains and putting it to work as clean, renewable biodiesel.")
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundColor(Color.theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 36)
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 20)

                    Button(action: { showLogin = true }) {
                        Text("Login")
                            .font(.custom("Syne-Bold", size: 15))
                            .foregroundColor(.white)
                            .padding(.horizontal, 36)
                            .padding(.vertical, 14)
                            .background(Color.theme.gold)
                            .cornerRadius(50)
                    }
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 20)
                }

                Spacer()

                Text("(540) 232-9705")
                    .font(.custom("Syne-ExtraBold", size: 32))
                    .foregroundColor(Color.theme.text)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .overlay(Rectangle().fill(Color.theme.border).frame(height: 1), alignment: .top)
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
