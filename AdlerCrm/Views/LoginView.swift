// /AdlerCRM/Views/LoginView.swift  08/04/2026 06:00:00 EDT
import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss

    // Flow steps
    enum Step {
        case credentials
        case totpSetup
        case totpVerify
    }

    @State private var step: Step = .credentials
    @State private var error = ""
    @State private var loading = false

    // Credentials
    @State private var username = ""
    @State private var password = ""

    // TOTP
    @State private var tempToken = ""
    @State private var userName = ""
    @State private var qrImageData: Data?
    @State private var manualSecret = ""
    @State private var totpCode = ""

    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Header
                        headerSection

                        // Body
                        VStack(spacing: 16) {
                            if !error.isEmpty {
                                errorBanner
                            }

                            switch step {
                            case .credentials:
                                credentialsForm
                            case .totpSetup:
                                totpSetupForm
                            case .totpVerify:
                                totpVerifyForm
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.title3)
                    }
                }
            }
        }
        .interactiveDismissDisabled(loading)
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "0d1f0f"),
                    Color(hex: "1a3d20")
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 10) {
                Image("adler-logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                    .cornerRadius(12)

                Text(headerTitle)
                    .font(.custom("Syne-ExtraBold", size: 20))
                    .foregroundColor(.white)

                Text(headerSubtitle)
                    .font(.custom("DMSans-Regular", size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.vertical, 28)
        }
    }

    private var headerTitle: String {
        switch step {
        case .credentials: return "Welcome Back"
        case .totpSetup: return "Set Up Authenticator"
        case .totpVerify: return "Two-Factor Verification"
        }
    }

    private var headerSubtitle: String {
        switch step {
        case .credentials: return "Sign in to Adler Resources CRM"
        case .totpSetup: return "Hi \(userName) — let's secure your account"
        case .totpVerify: return "Enter the code from your authenticator app"
        }
    }

    // MARK: - Error Banner

    private var errorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
            Text(error)
                .font(.custom("DMSans-Medium", size: 13))
        }
        .foregroundColor(Color(hex: "c1121f"))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.theme.red.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: "c1121f").opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    // MARK: - Step 1: Credentials

    private var credentialsForm: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Username")
                    .font(.custom("DMSans-SemiBold", size: 13))
                    .foregroundColor(Color.theme.text)

                TextField("Enter your username", text: $username)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .modifier(InputFieldStyle())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Password")
                    .font(.custom("DMSans-SemiBold", size: 13))
                    .foregroundColor(Color.theme.text)

                SecureField("Enter your password", text: $password)
                    .textContentType(.password)
                    .modifier(InputFieldStyle())
            }

            Button(action: handleCredentials) {
                HStack {
                    if loading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.9)
                    }
                    Text(loading ? "Signing in…" : "Sign In")
                }
                .modifier(PrimaryButtonStyle())
            }
            .disabled(loading || username.isEmpty || password.isEmpty)
            .opacity(username.isEmpty || password.isEmpty ? 0.6 : 1)
        }
    }

    // MARK: - Step 2: TOTP Setup

    private var totpSetupForm: some View {
        VStack(spacing: 16) {
            Text("You need an authenticator app to sign in. Scan the QR code below with your app to get started.")
                .font(.custom("DMSans-Regular", size: 13))
                .foregroundColor(Color.theme.textSecondary)
                .lineSpacing(3)

            // App Store link
            Link(destination: URL(string: "https://apps.apple.com/app/google-authenticator/id388497605")!) {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                        .font(.subheadline)
                    Text("Get Google Authenticator")
                        .font(.custom("DMSans-SemiBold", size: 13))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.theme.text)
                .cornerRadius(50)
            }

            divider("or use any authenticator app")

            // QR Code
            if let qrData = qrImageData, let uiImage = UIImage(data: qrData) {
                Image(uiImage: uiImage)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.theme.border, lineWidth: 2)
                    )
                    .padding(.vertical, 4)
            }

            // Manual secret
            if !manualSecret.isEmpty {
                VStack(spacing: 4) {
                    Text("Manual entry key")
                        .font(.custom("DMSans-Medium", size: 11))
                        .foregroundColor(Color.theme.textSecondary)
                    Text(manualSecret)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Color.theme.text)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color.theme.background)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundColor(Color.theme.border)
                        )
                        .textSelection(.enabled)
                }
            }

            divider("enter 6-digit code to confirm")

            // Code input
            totpCodeInput

            Button(action: handleVerifyCode) {
                HStack {
                    if loading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.9)
                    }
                    Text(loading ? "Verifying…" : "Verify & Activate")
                }
                .modifier(PrimaryButtonStyle())
            }
            .disabled(loading || totpCode.count < 6)
            .opacity(totpCode.count < 6 ? 0.6 : 1)

            backButton
        }
    }

    // MARK: - Step 3: TOTP Verify

    private var totpVerifyForm: some View {
        VStack(spacing: 16) {
            Text("Open your authenticator app and enter the 6-digit code for Adler Resources CRM.")
                .font(.custom("DMSans-Regular", size: 13))
                .foregroundColor(Color.theme.textSecondary)
                .lineSpacing(3)
                .multilineTextAlignment(.center)

            totpCodeInput

            Button(action: handleVerifyCode) {
                HStack {
                    if loading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.9)
                    }
                    Text(loading ? "Verifying…" : "Verify")
                }
                .modifier(PrimaryButtonStyle())
            }
            .disabled(loading || totpCode.count < 6)
            .opacity(totpCode.count < 6 ? 0.6 : 1)

            backButton
        }
    }

    // MARK: - Shared Components

    private var totpCodeInput: some View {
        TextField("000000", text: $totpCode)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .multilineTextAlignment(.center)
            .font(.custom("Syne-Bold", size: 28))
            .tracking(8)
            .foregroundColor(Color.theme.text)
            .padding(14)
            .background(Color.theme.background)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.theme.border, lineWidth: 1.5)
            )
            .focused($codeFocused)
            .onChange(of: totpCode) { _, newValue in
                totpCode = String(newValue.filter { $0.isNumber }.prefix(6))
            }
            .onAppear { codeFocused = true }
    }

    private var backButton: some View {
        Button(action: handleBack) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.left")
                    .font(.caption2)
                Text("Back to sign in")
                    .font(.custom("DMSans-Regular", size: 13))
            }
            .foregroundColor(Color.theme.textSecondary)
        }
        .padding(.top, 4)
    }

    private func divider(_ text: String) -> some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.theme.border)
                .frame(height: 1)
            Text(text)
                .font(.custom("DMSans-Regular", size: 11))
                .foregroundColor(Color.theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
            Rectangle()
                .fill(Color.theme.border)
                .frame(height: 1)
        }
    }

    // MARK: - Actions

    private func handleCredentials() {
        guard !username.isEmpty, !password.isEmpty else { return }
        error = ""
        loading = true

        Task {
            let result = await auth.login(username: username, password: password)
            loading = false

            if result.success {
                dismiss()
                return
            }

            if result.totpRequired {
                tempToken = result.tempToken ?? ""
                userName = result.userName ?? username

                if result.totpSetupNeeded {
                    // Fetch QR code
                    loading = true
                    do {
                        let setup = try await auth.setupTOTP(tempToken: tempToken)
                        parseQRDataURL(setup.qr)
                        manualSecret = setup.secret
                        step = .totpSetup
                    } catch {
                        self.error = error.localizedDescription
                    }
                    loading = false
                } else {
                    step = .totpVerify
                }
            } else {
                error = result.error ?? "Invalid username or password."
            }
        }
    }

    private func handleVerifyCode() {
        let code = totpCode.trimmingCharacters(in: .whitespaces)
        guard code.count >= 6 else {
            error = "Please enter the 6-digit code from your authenticator app."
            return
        }
        error = ""
        loading = true

        Task {
            do {
                try await auth.verifyTOTP(tempToken: tempToken, code: code)
                loading = false
                dismiss()
            } catch {
                self.error = error.localizedDescription
                totpCode = ""
                loading = false
            }
        }
    }

    private func handleBack() {
        step = .credentials
        error = ""
        totpCode = ""
        tempToken = ""
        qrImageData = nil
        manualSecret = ""
    }

    // MARK: - Helpers

    private func parseQRDataURL(_ dataURL: String) {
        // Format: "data:image/png;base64,iVBOR..."
        guard let commaIndex = dataURL.firstIndex(of: ",") else { return }
        let base64String = String(dataURL[dataURL.index(after: commaIndex)...])
        qrImageData = Data(base64Encoded: base64String)
    }
}

// MARK: - Style Modifiers

struct InputFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.custom("DMSans-Regular", size: 14))
            .padding(12)
            .background(Color.theme.background)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.theme.border, lineWidth: 1.5)
            )
    }
}

struct PrimaryButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.custom("Syne-Bold", size: 15))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color(hex: "1a3d20"))
            .cornerRadius(10)
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}
