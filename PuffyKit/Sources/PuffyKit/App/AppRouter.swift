import SwiftUI

public enum MainTab: Hashable, CaseIterable, Sendable {
    case summary, trends, scan, awards, profile

    public var title: String {
        switch self {
        case .summary: "Summary"
        case .trends: "Trends"
        case .scan: "Scan"
        case .awards: "Awards"
        case .profile: "Profile"
        }
    }

    public var symbol: String {
        switch self {
        case .summary: "heart"
        case .trends: "chart.bar"
        case .scan: "camera"
        case .awards: "star"
        case .profile: "person"
        }
    }
}

public enum Route: Hashable {
    case scanDetail(UUID)
    case timeLapse
    case photoGrid
    case patterns
    case goals
    case challenges
    case awardDetail(String)
    case driveSettings
    case reminderTime
    case exportData
    case privacy
}

/// Navigation state shared across tabs and deep links (`puffymeter://scan`, …).
@MainActor
@Observable
public final class AppRouter {
    public var selectedTab: MainTab = .summary
    public var summaryPath: [Route] = []
    public var trendsPath: [Route] = []
    public var awardsPath: [Route] = []
    public var profilePath: [Route] = []

    public init() {}

    public func presentDriveSettings() {
        selectedTab = .profile
        profilePath = [.driveSettings]
    }

    public func showScanDetail(_ id: UUID) {
        selectedTab = .trends
        trendsPath = [.scanDetail(id)]
    }

    /// Handles `puffymeter://<route>` URLs from widgets and notifications.
    public func handle(url: URL) {
        guard url.scheme == "puffymeter" else { return }
        let host = url.host() ?? ""
        switch host {
        case "summary": selectedTab = .summary; summaryPath = []
        case "scan": selectedTab = .scan
        case "trends": selectedTab = .trends; trendsPath = []
        case "awards":
            selectedTab = .awards
            let id = url.pathComponents.dropFirst().first
            awardsPath = id.map { [.awardDetail($0)] } ?? []
        case "award":
            selectedTab = .awards
            if let id = url.pathComponents.dropFirst().first { awardsPath = [.awardDetail(id)] }
        case "profile": selectedTab = .profile; profilePath = []
        case "drive": presentDriveSettings()
        default: break
        }
    }
}
