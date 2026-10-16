import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
protocol CoachBackgroundExecuting: AnyObject {
    func begin(_ id: UUID, expiration: @escaping @MainActor () -> Void)
    func end(_ id: UUID)
}

/// A finite UIKit assertion, balanced on success, failure, stop and expiration.
@MainActor
final class CoachBackgroundExecution: CoachBackgroundExecuting {
    #if canImport(UIKit)
    private var identifiers: [UUID: UIBackgroundTaskIdentifier] = [:]
    #endif

    func begin(_ id: UUID, expiration: @escaping @MainActor () -> Void) {
        #if canImport(UIKit)
        let token = UIApplication.shared.beginBackgroundTask(withName: "Coach answer") { expiration() }
        if token != .invalid { identifiers[id] = token }
        #endif
    }

    func end(_ id: UUID) {
        #if canImport(UIKit)
        if let token = identifiers.removeValue(forKey: id) { UIApplication.shared.endBackgroundTask(token) }
        #endif
    }
}
