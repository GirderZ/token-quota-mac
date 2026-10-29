import Foundation

// 与界面显示的整数百分比保持一致；10% 属于红色，40% 属于黄色。
enum QuotaLevel: Equatable {
    case unknown, critical, warning, healthy
    static func classify(_ remaining: Double?) -> QuotaLevel {
        guard let remaining, remaining.isFinite else { return .unknown }
        let displayed = Double(String(format: "%.0f", remaining)) ?? remaining
        if displayed <= 10 { return .critical }
        if displayed <= 40 { return .warning }
        return .healthy
    }
}

struct QuotaWindow {
    let remaining: Double
    let minutes: Int
    let resetsAt: Date?
    var label: String {
        if minutes == 300 { return "5 小时" }
        if minutes == 10080 { return "本周" }
        return minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes) 分钟"
    }
    var percent: String { String(format: "%.0f", remaining) + "%" }
}
enum PlanDisplay {
    // 面板只显示简短常见套餐；复杂、未知和未来类型保留原值但隐藏标签。
    static let known: [String: String] = [
        "free": "FREE", "go": "GO", "plus": "PLUS", "pro": "PRO",
        "prolite": "PRO LITE", "promax": "PRO MAX", "team": "TEAM",
        "business": "BUSINESS", "enterprise": "ENTERPRISE", "edu": "EDU", "sci": "SCI"
    ]
    static func normalized(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw.lowercased()
    }
    static func label(_ raw: String?) -> String? {
        guard let key = normalized(raw) else { return nil }
        return known[key]
    }
}

struct Snapshot {
    let windows: [QuotaWindow]
    let plan: String?
    let resetCount: Int?
    let expiries: [Date]
    let fetchedAt: Date
    var planLabel: String? { PlanDisplay.label(plan) }
    var main: QuotaWindow? { windows.first(where: { $0.minutes == 300 }) ?? windows.first }
    static func parse(_ result: [String: Any], now: Date = Date(), fallbackPlan: String? = nil) throws -> Snapshot {
        let limits: [String: Any]?
        if let all = result["rateLimitsByLimitId"] as? [String: Any] {
            limits = all["codex"] as? [String: Any]
        } else { limits = result["rateLimits"] as? [String: Any] }
        guard let limits else { throw BadgeError.message("接口未返回 Codex 额度") }
        var windows = [QuotaWindow]()
        for key in ["primary", "secondary"] {
            guard let value = limits[key], !(value is NSNull) else { continue }
            guard let w = value as? [String: Any],
                  let used = w["usedPercent"] as? Double, used.isFinite, (0...100).contains(used),
                  let minutes = w["windowDurationMins"] as? Int, minutes > 0 else {
                throw BadgeError.message("收到无法识别的额度数据")
            }
            let reset = (w["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
            windows.append(QuotaWindow(remaining: 100 - used, minutes: minutes, resetsAt: reset))
        }
        windows.sort { $0.minutes < $1.minutes }
        let credits = result["rateLimitResetCredits"] as? [String: Any]
        let entries = credits?["credits"] as? [[String: Any]] ?? []
        let expiries = entries.compactMap { c -> Date? in
            guard c["status"] as? String == "available", let epoch = c["expiresAt"] as? Double else { return nil }
            let d = Date(timeIntervalSince1970: epoch)
            return d > now ? d : nil
        }.sorted()
        let rawPlan = limits["planType"] as? String
        let plan = PlanDisplay.normalized(rawPlan) == nil ? fallbackPlan : rawPlan
        return Snapshot(windows: windows, plan: plan,
                        resetCount: (credits?["availableCount"] as? Int) ?? (credits == nil ? nil : expiries.count),
                        expiries: expiries, fetchedAt: now)
    }
}
enum BadgeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}

// A dedicated stdio client. Only initialize and account/rateLimits/read are sent.
final class QuotaClient {
    private let condition = NSCondition()
    private var replies = [Int: [String: Any]]()
    private var buffer = Data()
    private var sequence = 0
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var closed = true
    var cliPath: String?
    static func findCLI() -> String? {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        var paths = [env["CODEX_BADGE_CLI"] ?? "",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        paths += (env["PATH"] ?? "").split(separator: ":").map { String($0) + "/codex" }
        return paths.first { !$0.isEmpty && fm.isExecutableFile(atPath: $0) }
    }
    func stop() {
        condition.lock()
        closed = true
        let p = process
        process = nil
        let out = output
        output = nil
        let writer = input
        input = nil
        condition.broadcast()
        condition.unlock()
        out?.fileHandleForReading.readabilityHandler = nil
        try? writer?.fileHandleForWriting.close()
        if let p, p.isRunning {
            p.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            }
        }
    }
    private func start() throws {
        guard let path = Self.findCLI() else { throw BadgeError.message("未找到 Codex CLI，请先打开并登录 Codex 或 ChatGPT") }
        cliPath = path
        let p = Process(), stdin = Pipe(), stdout = Pipe()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["app-server", "--stdio"]
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = FileHandle.nullDevice
        condition.lock()
        buffer = Data(); replies = [:]; closed = false
        process = p; input = stdin; output = stdout
        condition.unlock()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            self.condition.lock()
            defer { self.condition.broadcast(); self.condition.unlock() }
            if chunk.isEmpty { self.closed = true; return }
            self.buffer.append(chunk)
            while let index = self.buffer.firstIndex(of: 10) {
                let line = Data(self.buffer[..<index])
                self.buffer.removeSubrange(...index)
                if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = obj["id"] as? Int {
                    self.replies[id] = obj
                }
            }
            if self.buffer.count > 8_000_000 { self.closed = true; self.buffer = Data() }
        }
        do { try p.run() } catch { stop(); throw BadgeError.message("无法启动 Codex CLI") }
        _ = try request("initialize", params: ["clientInfo": ["name": "codex_badge_mac", "title": "Token额度 Mac", "version": "1.5.1"]])
        try send(["method": "initialized", "params": [:]])
    }
    private func send(_ value: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: value)
        data.append(10)
        guard let input else { throw BadgeError.message("Codex 连接已关闭") }
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    private func request(_ method: String, params: [String: Any]) throws -> [String: Any] {
        sequence += 1
        let id = sequence
        try send(["id": id, "method": method, "params": params])
        let deadline = Date(timeIntervalSinceNow: 25)
        condition.lock()
        defer { condition.unlock() }
        while replies[id] == nil && !closed && Date() < deadline { _ = condition.wait(until: deadline) }
        guard let reply = replies.removeValue(forKey: id) else {
            throw BadgeError.message(closed ? "Codex 连接已断开，稍后自动重连" : "额度读取超时，请检查网络后刷新")
        }
        if let error = reply["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? 0
            throw BadgeError.message("额度读取失败（\(code)），请确认 Codex 已登录且网络可用")
        }
        guard let result = reply["result"] as? [String: Any] else { throw BadgeError.message("Codex 返回的数据为空") }
        return result
    }
    func fetch() throws -> Snapshot {
        do {
            condition.lock(); let alive = !closed && process?.isRunning == true; condition.unlock()
            if !alive { stop(); try start() }
            let result = try request("account/rateLimits/read", params: [:])
            let snapshot = try Snapshot.parse(result)
            guard PlanDisplay.normalized(snapshot.plan) == nil else { return snapshot }
            // 部分额度桶不带套餐；仅缺少时只读补查账号类型，不保存账号标识。
            if let accountResult = try? request("account/read", params: ["refreshToken": false]),
               let account = accountResult["account"] as? [String: Any],
               let plan = account["planType"] as? String {
                return try Snapshot.parse(result, fallbackPlan: plan)
            }
            return snapshot
        } catch { stop(); throw error }
    }
}
