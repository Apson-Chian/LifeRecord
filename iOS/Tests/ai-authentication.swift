import Foundation

@main struct AIAuthenticationChecks {
    static func main() throws {
        let official = "https://api.deepseek.com/chat/completions"
        for raw in ["sk-local-test-only", "  sk-local-test-only\n", "Bearer sk-local-test-only", "Authorization: Bearer sk-local-test-only", "Bearer \"sk-local-test-only\""] {
            for style in ["Bearer Token", "api-key 请求头", "自定义请求头"] {
                let header = try AIAuthentication.header(endpoint: official, style: style, customHeader: "X-API-Key", key: raw)
                precondition(header.name == "Authorization" && header.value == "Bearer sk-local-test-only")
            }
        }
        precondition(AIAuthentication.isOfficialDeepSeek("https://API.DEEPSEEK.COM:443/v1/chat/completions"))
        for address in ["https://api.deepseek.com.evil.test/chat/completions", "http://api.deepseek.com/chat/completions", "https://api.deepseek.com:8443/chat/completions"] {
            precondition(!AIAuthentication.isOfficialDeepSeek(address))
        }
        let custom = try AIAuthentication.header(endpoint: "https://gateway.test/v1/chat/completions", style: "自定义请求头", customHeader: "X-Credential", key: "gateway-key")
        precondition(custom.name == "X-Credential" && custom.value == "gateway-key")
        for invalid in ["", "sk-local\nkey", "sk-local\u{200b}key", "sk-***masked", "Bearer Bearer sk-local"] {
            do { _ = try AIAuthentication.normalizedKey(invalid, bearer: true); preconditionFailure("Invalid credential accepted") } catch {}
        }
        do { _ = try AIAuthentication.header(endpoint: "https://gateway.test", style: "自定义请求头", customHeader: "Invalid Header\n", key: "key"); preconditionFailure("Invalid header accepted") } catch {}
        precondition(AIAuthentication.deepSeekFailure(status: 401)?.contains("鉴权") == true)
        precondition(AIAuthentication.deepSeekFailure(status: 402)?.contains("余额") == true)
        precondition(AIAuthentication.deepSeekFailure(status: 429) == nil)
        print("PASS: official DeepSeek Bearer header, pasted prefix cleanup, lookalike-host isolation, custom authentication, credential validation and 401/402 distinction")
    }
}
