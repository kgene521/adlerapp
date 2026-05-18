// /AdlerCRM/Views/TestRunnerView.swift  16/04/2026 02:34:00 EDT

import SwiftUI

// MARK: - Models

struct TestRunResponse: Codable {
    let exit_code: Int
    let raw_output: String
    let parsed: ParsedTestOutput
}

struct ParsedTestOutput: Codable {
    let suites: [TestSuite]
    let failures: [TestFailure]
    let summary: TestSummary
}

struct TestSuite: Codable, Identifiable {
    var id: String { file }
    let file: String
    let status: String
    let groups: [TestGroup]
}

struct TestGroup: Codable, Identifiable {
    var id: String { name }
    let name: String
    let tests: [TestResult]
}

struct TestResult: Codable, Identifiable {
    var id: String { name }
    let name: String
    let status: String
    let duration_ms: Int?
}

struct TestFailure: Codable, Identifiable {
    var id: String { test_path }
    let test_path: String
    let detail: [String]
}

struct TestSummary: Codable {
    let suites_failed: Int
    let suites_passed: Int
    let suites_total: Int
    let tests_failed: Int
    let tests_passed: Int
    let tests_total: Int
    let duration_seconds: Double?
}

// MARK: - View

struct TestRunnerView: View {
    @State private var isRunning = false
    @State private var result: TestRunResponse? = nil
    @State private var errorMessage: String? = nil
    @State private var showRawOutput = false
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer? = nil
    @State private var expandedSuites: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                Text("Test Runner")
                    .font(.custom("Syne-Bold", size: 28))
                    .foregroundColor(Color.theme.text)

                // Run button
                Button {
                    runTests()
                } label: {
                    HStack(spacing: 8) {
                        if isRunning {
                            ProgressView()
                                .tint(.white)
                            Text("Running… \(elapsedSeconds)s")
                                .font(.custom("DMSans-SemiBold", size: 16))
                        } else {
                            Image(systemName: "play.fill")
                            Text("Run Tests")
                                .font(.custom("DMSans-SemiBold", size: 16))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isRunning ? Color.theme.textSecondary : Color(hex: "2d6a4f"))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isRunning)

                // Error
                if let errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Color(hex: "c1121f"))
                        Text(errorMessage)
                            .font(.custom("DMSans-Regular", size: 14))
                            .foregroundColor(Color(hex: "c1121f"))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "c1121f").opacity(0.08))
                    .cornerRadius(8)
                }

                // Results
                if let result {
                    resultView(result)
                }
            }
            .padding(16)
        }
        .background(Color.theme.background)
        .navigationTitle("Tests")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Result View

    @ViewBuilder
    private func resultView(_ result: TestRunResponse) -> some View {
        // Summary banner
        summaryBanner(result.parsed.summary, exitCode: result.exit_code)

        // Suite cards
        ForEach(result.parsed.suites) { suite in
            suiteCard(suite, failures: result.parsed.failures)
        }

        // Raw output toggle
        Button {
            showRawOutput.toggle()
        } label: {
            HStack {
                Image(systemName: showRawOutput ? "chevron.down" : "chevron.right")
                Text("Raw Output")
                    .font(.custom("DMSans-Medium", size: 14))
            }
            .foregroundColor(Color.theme.textSecondary)
        }

        if showRawOutput {
            ScrollView(.horizontal) {
                Text(result.raw_output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Color.theme.text)
                    .padding(12)
            }
            .background(Color.theme.surface)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.theme.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Summary Banner

    private func summaryBanner(_ summary: TestSummary, exitCode: Int) -> some View {
        let allPassed = summary.tests_failed == 0
        return VStack(spacing: 12) {
            HStack {
                Image(systemName: allPassed ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 24))
                Text(allPassed ? "All Tests Passed" : "\(summary.tests_failed) Test\(summary.tests_failed == 1 ? "" : "s") Failed")
                    .font(.custom("Syne-Bold", size: 20))
                Spacer()
            }
            .foregroundColor(.white)

            HStack(spacing: 16) {
                summaryPill(label: "Suites", value: "\(summary.suites_passed)/\(summary.suites_total)")
                summaryPill(label: "Tests", value: "\(summary.tests_passed)/\(summary.tests_total)")
                if let dur = summary.duration_seconds {
                    summaryPill(label: "Time", value: String(format: "%.1fs", dur))
                }
            }
        }
        .padding(16)
        .background(allPassed ? Color(hex: "2d6a4f") : Color(hex: "c1121f"))
        .cornerRadius(12)
    }

    private func summaryPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.custom("DMSans-Bold", size: 16))
            Text(label)
                .font(.custom("DMSans-Regular", size: 12))
                .opacity(0.8)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Suite Card

    private func suiteCard(_ suite: TestSuite, failures: [TestFailure]) -> some View {
        let passed = suite.status == "PASS"
        let totalTests = suite.groups.flatMap(\.tests).count
        let failedTests = suite.groups.flatMap(\.tests).filter { $0.status != "passed" }.count
        let passedTests = totalTests - failedTests
        let durationMs = suite.groups.flatMap(\.tests).compactMap(\.duration_ms).reduce(0, +)
        let isExpanded = expandedSuites.contains(suite.id)

        // Failures belonging to this suite
        let suiteFailures = failures.filter { f in
            suite.groups.contains { g in
                g.tests.contains { t in
                    t.status != "passed" && f.test_path.contains(t.name)
                }
            }
        }

        return VStack(alignment: .leading, spacing: 0) {
            // Card header — tappable only if failed
            Button(action: {
                if !passed {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded { expandedSuites.remove(suite.id) }
                        else { expandedSuites.insert(suite.id) }
                    }
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(passed ? Color(hex: "2d6a4f") : Color(hex: "c1121f"))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(suiteName(suite.file))
                            .font(.custom("DMSans-SemiBold", size: 15))
                            .foregroundColor(Color.theme.text)

                        if passed {
                            Text("\(passedTests)/\(totalTests) passed · \(formatDuration(durationMs))")
                                .font(.custom("DMSans-Regular", size: 12))
                                .foregroundColor(Color(hex: "2d6a4f"))
                        } else {
                            Text("\(failedTests) failed, \(passedTests) passed")
                                .font(.custom("DMSans-Medium", size: 12))
                                .foregroundColor(Color(hex: "c1121f"))
                        }
                    }

                    Spacer()

                    Text(passed ? "PASSED" : "FAILED")
                        .font(.custom("DMSans-Bold", size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(passed ? Color(hex: "2d6a4f").opacity(0.12) : Color(hex: "c1121f").opacity(0.12))
                        .foregroundColor(passed ? Color(hex: "2d6a4f") : Color(hex: "c1121f"))
                        .cornerRadius(4)

                    if !passed {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.theme.textSecondary)
                    }
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            .disabled(passed)

            // Expanded detail — only for failed suites
            if !passed && isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider().padding(.horizontal, 14)

                    // Individual tests grouped by describe block
                    ForEach(suite.groups) { group in
                        let groupFailed = group.tests.contains { $0.status != "passed" }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name)
                                .font(.custom("DMSans-SemiBold", size: 12))
                                .foregroundColor(Color.theme.textSecondary)
                                .padding(.top, 8)

                            ForEach(group.tests) { test in
                                HStack(spacing: 6) {
                                    Image(systemName: test.status == "passed" ? "checkmark" : "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(test.status == "passed" ? Color(hex: "2d6a4f") : Color(hex: "c1121f"))
                                        .frame(width: 14)

                                    Text(test.name)
                                        .font(.custom("DMSans-Regular", size: 12))
                                        .foregroundColor(test.status == "passed" ? Color.theme.textSecondary : Color.theme.text)
                                        .lineLimit(2)

                                    Spacer()

                                    if let ms = test.duration_ms {
                                        Text("\(ms)ms")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(Color.theme.textSecondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)

                    // Failure details
                    if !suiteFailures.isEmpty {
                        Divider().padding(.horizontal, 14)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Failure Details")
                                .font(.custom("DMSans-SemiBold", size: 12))
                                .foregroundColor(Color(hex: "c1121f"))
                                .padding(.top, 8)

                            ForEach(suiteFailures) { failure in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(failure.test_path)
                                        .font(.custom("DMSans-Medium", size: 11))
                                        .foregroundColor(Color(hex: "c1121f"))

                                    Text(failure.detail.joined(separator: "\n"))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(Color.theme.text)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.theme.background)
                                        .cornerRadius(6)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                    }
                }
                .background(Color.theme.surface.opacity(0.5))
            }
        }
        .background(Color.theme.surface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(passed ? Color(hex: "2d6a4f").opacity(0.3) : Color(hex: "c1121f").opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func suiteName(_ file: String) -> String {
        // "auth.test.js" → "Authentication & Security"
        let map: [String: String] = [
            "auth.test.js": "Authentication",
            "crud.test.js": "CRUD Operations",
            "features.test.js": "Features",
            "admin.test.js": "Admin",
        ]
        return map[file] ?? file.replacingOccurrences(of: ".test.js", with: "").capitalized
    }

    private func formatDuration(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        let seconds = Double(ms) / 1000.0
        return String(format: "%.1fs", seconds)
    }

    // MARK: - Run Tests

    private func runTests() {
        isRunning = true
        errorMessage = nil
        result = nil
        expandedSuites = []
        elapsedSeconds = 0
        showRawOutput = false

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedSeconds += 1
        }

        Task {
            do {
                let response: TestRunResponse = try await APIClient.shared.request(
                    path: "/tests/run",
                    method: "POST",
                    body: [:]
                )
                await MainActor.run {
                    result = response
                    isRunning = false
                    timer?.invalidate()
                    timer = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRunning = false
                    timer?.invalidate()
                    timer = nil
                }
            }
        }
    }
}
