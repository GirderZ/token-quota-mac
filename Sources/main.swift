import Cocoa

if CommandLine.arguments.contains("--self-test") {
    do { try runQuotaTests(); exit(0) } catch { fputs("\(error)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--probe") {
    let client = QuotaClient()
    do {
        let snapshot = try client.fetch()
        let safe: [String: Any] = ["windows": snapshot.windows.map { ["window": $0.label, "remaining": $0.percent] }, "resetCount": snapshot.resetCount as Any? ?? NSNull()]
        let data = try JSONSerialization.data(withJSONObject: safe, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self)); client.stop(); exit(0)
    } catch { client.stop(); fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
