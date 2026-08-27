import Foundation
import UIKit

enum LifeLink {
    static let lifeTrackScheme = "lifetrack"

    @MainActor
    @discardableResult
    static func openLifeTrack() -> Bool {
        guard let url = URL(string: "\(lifeTrackScheme)://") else { return false }
        guard UIApplication.shared.canOpenURL(url) else { return false }
        UIApplication.shared.open(url)
        return true
    }
}
