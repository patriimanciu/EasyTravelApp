import Foundation

/// Global video-import status shown in the app-wide top banner.
enum VideoImportPhase: Equatable {
    case idle
    case running(message: String, progress: Double?)
    case success(count: Int)
    case failure(message: String)

    var isVisible: Bool {
        self != .idle
    }
}
