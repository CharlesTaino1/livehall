import CryptoKit
import Foundation
import JavaScriptCore

enum DouyinSigner {
    private static let aBogusScript = loadScript("a_bogus")
    private static let socketScript = loadScript("webmssdk")

    static func signedURL(_ url: String, userAgent: String) throws(LiveError) -> URL {
        let token = randomToken(length: 107)
        guard let query = "\(url)&msToken=\(token)".split(separator: "?", maxSplits: 1).last else {
            throw .signFailed("接口地址没有参数")
        }
        let value = try evaluate(
            aBogusScript, call: "getABogus", arguments: [String(query), userAgent])
        guard let signed = URL(string: "\(url)&msToken=\(token)&a_bogus=\(percentEncoded(value))") else {
            throw .signFailed("签名后的地址无效")
        }
        return signed
    }

    static func socketSignature(roomID: String, uniqueID: String, userAgent: String) throws(LiveError) -> String {
        let parameters =
            "live_id=1,aid=6383,version_code=180800,webcast_sdk_version=1.3.0,room_id=\(roomID),sub_room_id=,"
            + "sub_channel_id=,did_rule=3,user_unique_id=\(uniqueID),device_platform=web,device_type=,ac=,"
            + "identity=audience"
        let stub = Insecure.MD5.hash(data: Data(parameters.utf8)).map { String(format: "%02x", $0) }.joined()
        for _ in 0..<20 {
            let value = try evaluate(socketScript, call: "getMSSDKSignature", arguments: [stub, userAgent])
            if !value.contains("-"), !value.contains("=") { return value }
        }
        throw .signFailed("弹幕签名一直带非法字符")
    }

    private static func evaluate(_ script: String, call function: String, arguments: [String]) throws(LiveError)
        -> String
    {
        guard let context = JSContext() else { throw .signFailed("无法创建脚本环境") }
        context.evaluateScript(script)
        if let exception = context.exception { throw .signFailed("脚本执行失败：\(exception)") }
        guard let entry = context.objectForKeyedSubscript(function), entry.isObject else {
            throw .signFailed("找不到入口函数 \(function)")
        }
        let result = entry.call(withArguments: arguments)
        if let exception = context.exception { throw .signFailed("签名失败：\(exception)") }
        guard let value = result?.toString(), !value.isEmpty, value != "undefined" else {
            throw .signFailed("签名结果为空")
        }
        return value
    }

    private static func loadScript(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
            let script = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return script
    }

    private static func randomToken(length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }

    private static func percentEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}
