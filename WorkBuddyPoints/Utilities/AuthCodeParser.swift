import Foundation

/// 智能粘贴识别结果
struct ParsedCredential {
    var mode: CredentialMode
    var refreshToken: String = ""
    var bearerToken: String = ""
    var cookie: String = ""
    var userAgent: String = ""
    var checkinDomain: String?
}

/// 把用户粘贴进来的各种凭据形态识别成结构化凭据。
/// 支持：WBAUTH1: 网页授权码 / 客户端登录态 JSON / JWT / Cookie 串 / 长效令牌。
enum AuthCodeParser {

    /// 粘贴 Cookie 但拿不到原始 UA 时的兜底 UA
    static let fallbackUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    static func parse(_ raw: String) -> ParsedCredential? {
        let text = raw.trimmed
        if text.isEmpty { return nil }

        // 1) WBAUTH1: 网页授权码（自带原始 UA 与站点域名）
        if text.hasPrefix("WBAUTH1:") {
            return parseAuthCode(String(text.dropFirst("WBAUTH1:".count)))
        }

        // 2) JSON：客户端登录态 workbuddy-desktop.info 或授权码载荷
        if text.hasPrefix("{") {
            return parseJSON(text)
        }

        // 3) JWT（Bearer）
        if text.hasPrefix("eyJ") {
            return ParsedCredential(mode: .bearer, bearerToken: text)
        }

        // 4) 含 "=" 视为 Cookie 串
        if text.contains("=") {
            return ParsedCredential(mode: .cookie, cookie: text, userAgent: fallbackUserAgent)
        }

        // 5) 其余按长效令牌处理
        return ParsedCredential(mode: .refreshToken, refreshToken: text)
    }

    // MARK: - WBAUTH1 授权码

    private static func parseAuthCode(_ payload: String) -> ParsedCredential? {
        var base64 = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data),
              let fields = object as? [String: Any],
              let value = fields["value"] as? String, !value.isEmpty else {
            return nil
        }
        let ua = (fields["ua"] as? String) ?? ""
        let domain = (fields["domain"] as? String).map(host(fromOrigin:))
        let mode = (fields["mode"] as? String) == "bearer" ? CredentialMode.bearer : .cookie
        return ParsedCredential(
            mode: mode,
            bearerToken: mode == .bearer ? value : "",
            cookie: mode == .cookie ? value : "",
            userAgent: ua.isEmpty ? fallbackUserAgent : ua,
            checkinDomain: domain
        )
    }

    // MARK: - JSON（客户端登录态 / 授权码载荷）

    private static func parseJSON(_ text: String) -> ParsedCredential? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else { return nil }

        // 客户端登录态：{"auth":{"accessToken":..,"domain":..}}
        if let auth = root["auth"] as? [String: Any] {
            let token = (auth["accessToken"] as? String) ?? ""
            let domain = (auth["domain"] as? String).map(host(fromOrigin:))
            if token.hasPrefix("eyJ") {
                return ParsedCredential(mode: .bearer, bearerToken: token, checkinDomain: domain)
            }
            return ParsedCredential(mode: .refreshToken, refreshToken: token, checkinDomain: domain)
        }

        // 授权码载荷：{"v":1,"mode":"cookie|bearer","value":..,"ua":..,"domain":..}
        if let value = root["value"] as? String, !value.isEmpty {
            let ua = (root["ua"] as? String) ?? fallbackUserAgent
            let domain = (root["domain"] as? String).map(host(fromOrigin:))
            let mode = (root["mode"] as? String) == "bearer" ? CredentialMode.bearer : .cookie
            return ParsedCredential(
                mode: mode,
                bearerToken: mode == .bearer ? value : "",
                cookie: mode == .cookie ? value : "",
                userAgent: ua,
                checkinDomain: domain
            )
        }
        return nil
    }

    /// origin（https://www.xxx.cn）转主机名
    static func host(fromOrigin value: String) -> String {
        var text = value.trimmed
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        if let slash = text.firstIndex(of: "/") {
            text = String(text[..<slash])
        }
        return text
    }
}
