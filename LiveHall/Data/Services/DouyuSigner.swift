import CryptoKit
import Foundation
import JavaScriptCore

enum DouyuSigner {
    private static let entryName = "ub98484234"

    static func sign(script: String, roomID: Int, deviceID: String, timestamp: Int) throws(LiveError) -> String {
        guard let context = JSContext() else { throw .signFailed("无法创建脚本环境") }

        let md5: @convention(block) (String) -> String = { text in
            Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        context.setObject(md5, forKeyedSubscript: "__md5" as NSString)
        context.evaluateScript(
            "var CryptoJS = { MD5: function (s) { var h = __md5(String(s)); return { toString: function () { return h; } }; } };"
        )
        context.evaluateScript(script)
        if let exception = context.exception { throw .signFailed("脚本执行失败：\(exception)") }

        guard let entry = context.objectForKeyedSubscript(entryName), entry.isObject else {
            throw .signFailed("找不到入口函数 \(entryName)")
        }
        let result = entry.call(withArguments: [roomID, deviceID, timestamp])
        if let exception = context.exception { throw .signFailed("签名失败：\(exception)") }
        guard let query = result?.toString(), query.contains("sign=") else { throw .signFailed("签名结果异常") }
        return query
    }
}
