// AdlerCRM/Services/NotificationManager.swift  03/04/2026 01:31:39
import SwiftUI
import Combine
import UserNotifications

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    @Published var unreadCount = 0
    private var pollingTask: Task<Void, Never>?

    func startPolling() {
        requestBadgePermission()
        poll()
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                self?.poll()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func poll() {
        Task {
            do {
                let count = try await APIClient.shared.getUnreadCount()
                unreadCount = count
                updateBadge(count)
            } catch { }
        }
    }

    private func updateBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
    }

    private func requestBadgePermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge]) { _, _ in }
    }
}
