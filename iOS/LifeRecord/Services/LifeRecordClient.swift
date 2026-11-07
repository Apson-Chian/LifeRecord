import Foundation

extension URLRequest {
    mutating func identifyLifeRecordClient() {
        guard let url, url.host?.lowercased() == "apsonchian.ltd",
              url.path.hasPrefix("/liferecord-api/") else { return }
        setValue("ios", forHTTPHeaderField: "X-LifeRecord-Client")
    }
}
