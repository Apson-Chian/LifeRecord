import Foundation

@main struct SyncFailureDescriptionTests {
    struct Snapshot: Decodable { let meals: [Meal] }
    struct Meal: Decodable { let name: String }
    static func main() throws {
        for (json, expected) in [("{\"meals\":[{}]}", "meals.[0].name"), ("{\"meals\":[{\"name\":42}]}", "meals.[0].name"), ("<html>private response</html>", "响应根节点")] {
            do { _ = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8)); fatalError("Expected decoding failure") }
            catch {
                let message = SyncFailureDescription.message(for: error)
                precondition(message.contains(expected))
                precondition(!message.contains("private response"))
            }
        }
        precondition(SyncFailureDescription.message(for: URLError(.timedOut)).contains("超时"))
        precondition(SyncFailureDescription.message(for: URLError(.notConnectedToInternet)).contains("没有网络"))
        print("PASS: decoding paths, response privacy, timeout and offline diagnostics")
    }
}
