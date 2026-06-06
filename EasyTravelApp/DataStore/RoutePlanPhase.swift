import Foundation

/// Trip route planning status shown as a centered overlay while the backend computes.
enum RoutePlanPhase: Equatable {
    case idle
    case running(message: String, progress: Double?)
    case success
    case failure(message: String)

    var isBlocking: Bool {
        switch self {
        case .idle, .success, .failure: false
        case .running: true
        }
    }

    var isVisible: Bool {
        self != .idle
    }
}
