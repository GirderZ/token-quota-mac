import Foundation

func runQuotaTests() throws {
    func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        if !condition() { fputs("FAIL: \(label)\n", stderr); exit(1) }
    }
    func parse(_ json: String) throws -> Snapshot {
        try Snapshot.parse(JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any], now: Date(timeIntervalSince1970: 1000))
    }
    let swapped = try parse(#"{"rateLimits":{"primary":{"usedPercent":31,"windowDurationMins":10080},"secondary":{"usedPercent":4,"windowDurationMins":300}}}"#)
    check(swapped.main?.remaining == 96, "Classify by window duration, not primary/secondary order")
    check(swapped.windows.count == 2, "Both windows")
    let weekly = try parse(#"{"rateLimits":{"primary":{"usedPercent":40,"windowDurationMins":10080},"secondary":null}}"#)
    check(weekly.main?.label == "本周" && weekly.main?.remaining == 60, "Weekly-only plan")
    let preferred = try parse(#"{"rateLimits":{"primary":{"usedPercent":90,"windowDurationMins":300}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":12,"windowDurationMins":300}}}}"#)
    check(preferred.main?.remaining == 88, "Prefer codex bucket")
    let nulls = try parse(#"{"rateLimits":{"primary":null,"secondary":null}}"#)
    check(nulls.main == nil, "Null is unknown, not zero")
    for invalid in [#"{"rateLimits":{"primary":{"usedPercent":101,"windowDurationMins":300}}}"#, #"{"rateLimits":{"primary":{"usedPercent":-1,"windowDurationMins":300}}}"#, #"{"rateLimits":{"primary":{"windowDurationMins":300}}}"#, #"{"rateLimitsByLimitId":{"other":{}},"rateLimits":{}}"#] {
        var failed = false
        do { _ = try parse(invalid) } catch { failed = true }
        check(failed, "Reject malformed / unrelated quota")
    }
    let credits = try parse(#"{"rateLimits":{},"rateLimitResetCredits":{"credits":[{"status":"available","expiresAt":2000},{"status":"available","expiresAt":900},{"status":"consumed","expiresAt":3000}]}}"#)
    check(credits.resetCount == 1 && credits.expiries.count == 1, "Ignore consumed and expired credits")
    print("PASS: 10 quota parsing checks")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let iso = ISO8601DateFormatter()
    let beforeMidnight = iso.date(from: "2026-10-28T15:55:00Z")!
    check(QuotaDates.shortReset(iso.date(from: "2026-10-28T15:58:00Z")!, relativeTo: beforeMidnight, calendar: calendar) == "23:58", "24-hour same-day reset")
    check(QuotaDates.shortReset(iso.date(from: "2026-10-28T16:10:00Z")!, relativeTo: beforeMidnight, calendar: calendar) == "明天 00:10", "Midnight reset carries tomorrow label")
    check(QuotaDates.lastSync(beforeMidnight.addingTimeInterval(-119), relativeTo: beforeMidnight) == "上次同步：1分钟前", "Elapsed minutes use last successful fetch")
    check(QuotaDates.lastSync(beforeMidnight.addingTimeInterval(30), relativeTo: beforeMidnight) == "上次同步：0分钟前", "Clock adjustment cannot show negative minutes")
    print("PASS: 4 time display checks")
    for (value, expected) in [(0.0, QuotaLevel.critical), (10, .critical), (10.4, .critical),
                              (11, .warning), (40, .warning), (40.4, .warning), (41, .healthy)] {
        check(QuotaLevel.classify(value) == expected, "Quota color matches displayed percentage at \(value)")
    }
    check(QuotaLevel.classify(nil) == .unknown, "Unknown quota stays neutral")
    print("PASS: 8 quota level checks")
    let expectedPlans: [String: String?] = [
        "free": "FREE", "go": "GO", "plus": "PLUS", "pro": "PRO", "prolite": "PRO LITE", "promax": "PRO MAX",
        "team": "TEAM", "self_serve_business_prolite": nil, "self_serve_business_usage_based": nil,
        "business": "BUSINESS", "ent26": nil, "enterprise_cbp_automation": nil, "enterprise_cbp_usage_based": nil,
        "enterprise": "ENTERPRISE", "edu": "EDU", "edu_plus": nil, "edu_pro": nil, "sci": "SCI", "sci_plus": nil, "unknown": nil
    ]
    for (raw, expected) in expectedPlans {
        let snapshot = try Snapshot.parse(["rateLimits": ["planType": raw]])
        check(snapshot.plan == raw && snapshot.planLabel == expected, "Account plan \(raw)")
    }
    check(PlanDisplay.label("future_plan") == nil, "Future plan labels stay hidden")
    check(PlanDisplay.label(nil) == nil, "Missing plan is not PLUS")
    let fallback = try Snapshot.parse(["rateLimits": [:]], fallbackPlan: "enterprise")
    check(fallback.planLabel == "ENTERPRISE", "Missing bucket plan uses account result")
    print("PASS: 23 plan presentation checks")
    let rect = CGRect(x: 11, y: 23, width: 74, height: 68)
    let bounds = TokenGlyphGeometry.path(in: rect).boundingBoxOfPath
    check(abs(bounds.midX - rect.midX) < 0.001 && abs(bounds.midY - rect.midY) < 0.001, "Raw T outline normalized on both axes")
    print("PASS: raw T outline normalization check")
}
