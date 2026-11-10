import Foundation

func formatBroadcastDuration(_ interval: TimeInterval) -> String {
    let minutes = max(0, Int(interval) / 60)
    switch minutes {
    case 0: return "不到1分钟"
    case 1..<60: return "\(minutes)分钟"
    default: return minutes % 60 == 0 ? "\(minutes / 60)小时" : "\(minutes / 60)小时\(minutes % 60)分钟"
    }
}
