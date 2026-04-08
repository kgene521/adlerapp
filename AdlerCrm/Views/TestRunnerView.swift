// /AdlerCRM/Views/TestRunnerView.swift  08/04/2026 15:12:00

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
    @State private var selectedFile: String? = nil
    @State private var isRunning = false
    @State private var result: TestRunResponse? = nil
    @State private var errorMessage: String? = nil
    @State private var showRawOutput = false
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer? = nil

    private let testFiles: [(label: String, value: String?)] = [
        ("All Tests", nil),
        ("Auth", "auth"),
        ("CRUD", "crud"),
        ("Features", "features"),
        ("Admin", "admin")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                Text("Test Runner")
                    .font(.custom("Syne-Bold", size: 28))
                    .foregroundColor(Color(hex: "0f1117"))

                // File picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Test Suite")
                        .font(.custom("DMSans-Medium", size: 14))
                        .foregroundColor(Color(hex: "7a7f94"))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(testFiles, id: \.label) { file in
                                Button {
                                    selectedFile = file.value
                                } label: {
                                    Text(file.label)
                                        .font(.custom("DMSans-Medium", size: 14))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            selectedFile == file.value
                                                ? Color(hex: "2d6a4f")
                                                : Color(hex: "f5f4f0")
                                        )
                                        .foregroundColor(
                                            selectedFile == file.value
                                                ? .white
                                                : Color(hex: "0f1117")
                                        )
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color(hex: "e2dfd6"), lineWidth: selectedFile == file.value ? 0 : 1)
                                        )
                                }
                                .disabled(isRunning)
                            }
                        }
                    }
                }

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
                            Text("Run \(selectedFile != nil ? selectedFile!.capitalized : "All") Tests")
                                .font(.custom("DMSans-SemiBold", size: 16))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isRunning ? Color(hex: "7a7f94") : Color(hex: "2d6a4f"))
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
        .background(Color(hex: "f5f4f0"))
        .navigationTitle("Tests")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Result View

    @ViewBuilder
    private func resultView(_ result: TestRunResponse) -> some View {
        // Summary banner
        summaryBanner(result.parsed.summary, exitCode: result.exit_code)

        // Suite results
        ForEach(result.parsed.suites) { suite in
            suiteCard(suite)
        }

        // Failure details
        if !result.parsed.failures.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Failure Details")
                    .font(.custom("Syne-Bold", size: 18))
                    .foregroundColor(Color(hex: "c1121f"))

                ForEach(result.parsed.failures) { failure in
                    failureCard(failure)
                }
            }
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
            .foregroundColor(Color(hex: "7a7f94"))
        }

        if showRawOutput {
            ScrollView(.horizontal) {
                Text(result.raw_output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Color(hex: "0f1117"))
                    .padding(12)
            }
            .background(Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "e2dfd6"), lineWidth: 1)
            )
        }
    }

    // MARK: - Summary Banner

    private func summaryBanner(_ summary: TestSummary, exitCode: Int) -> some View {
        let allPassed = summary.tests_failed == 0 && exitCode == 0
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

    private func suiteCard(_ suite: TestSuite) -> some View {
        let passed = suite.status == "PASS"
        return VStack(alignment: .leading, spacing: 10) {
            // Suite header
            HStack(spacing: 8) {
                Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(passed ? Color(hex: "2d6a4f") : Color(hex: "c1121f"))
                Text(suite.file)
                    .font(.custom("DMSans-SemiBold", size: 15))
                    .foregroundColor(Color(hex: "0f1117"))
                Spacer()
                Text(passed ? "PASS" : "FAIL")
                    .font(.custom("DMSans-Bold", size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(passed ? Color(hex: "2d6a4f").opacity(0.12) : Color(hex: "c1121f").opacity(0.12))
                    .foregroundColor(passed ? Color(hex: "2d6a4f") : Color(hex: "c1121f"))
                    .cornerRadius(4)
            }

            // Groups
            ForEach(suite.groups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.custom("DMSans-Medium", size: 13))
                        .foregroundColor(Color(hex: "7a7f94"))
                        .padding(.top, 4)

                    ForEach(group.tests) { test in
                        HStack(spacing: 6) {
                            Image(systemName: test.status == "passed" ? "checkmark" : "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(test.status == "passed" ? Color(hex: "2d6a4f") : Color(hex: "c1121f"))
                                .frame(width: 16)

                            Text(test.name)
                                .font(.custom("DMSans-Regular", size: 13))
                                .foregroundColor(Color(hex: "0f1117"))
                                .lineLimit(2)

                            Spacer()

                            if let ms = test.duration_ms {
                                Text("\(ms)ms")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(Color(hex: "7a7f94"))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: "e2dfd6"), lineWidth: 1)
        )
    }

    // MARK: - Failure Card

    private func failureCard(_ failure: TestFailure) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(failure.test_path)
                .font(.custom("DMSans-SemiBold", size: 13))
                .foregroundColor(Color(hex: "c1121f"))

            Text(failure.detail.joined(separator: "\n"))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Color(hex: "0f1117"))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "f5f4f0"))
                .cornerRadius(6)
        }
        .padding(12)
        .background(Color(hex: "c1121f").opacity(0.04))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: "c1121f").opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Run Tests

    private func runTests() {
        isRunning = true
        errorMessage = nil
        result = nil
        elapsedSeconds = 0

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedSeconds += 1
        }

        Task {
            do {
                let body: [String: Any]? = selectedFile != nil ? ["file": selectedFile!] : nil
                let response: TestRunResponse = try await APIClient.shared.request(
                    path: "/tests/run",
                    method: "POST",
                    body: body
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
