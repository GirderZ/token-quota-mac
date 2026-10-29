import Foundation

enum QuotaDates {
    static func timestamp(_ date: Date, includeYear: Bool = false, includeSeconds: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = (includeYear ? "yyyy年M月d日" : "M月d日") + "（EEEE）HH:mm" + (includeSeconds ? ":ss" : "")
        return formatter.string(from: date)
    }
    static func shortReset(_ date: Date, relativeTo now: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: date)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return time
        case 1: return "明天 " + time
        case -1: return "昨天 " + time
        case 2...: return "\(days)天后 " + time
        default: return "\(-days)天前 " + time
        }
    }
    static func lastSync(_ date: Date?, relativeTo now: Date) -> String {
        guard let date else { return "上次同步：暂无" }
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        return "上次同步：\(minutes)分钟前"
    }
}
