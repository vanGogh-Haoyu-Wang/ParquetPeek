import Foundation

public enum Formatters {
    public static func rows(_ value: Int64) -> String {
        value.formatted()
    }

    public static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    public static func pageRange(offset: Int64, count: Int, total: Int64) -> String {
        guard total > 0, count > 0 else {
            return "0 of \(rows(total))"
        }
        let start = offset + 1
        let end = min(offset + Int64(count), total)
        return "\(rows(start))-\(rows(end)) of \(rows(total))"
    }
}

public enum PageMath {
    public static func nextOffset(current: Int64, pageSize: Int, totalRows: Int64) -> Int64 {
        min(current + Int64(pageSize), max(totalRows - 1, 0))
    }

    public static func previousOffset(current: Int64, pageSize: Int) -> Int64 {
        max(current - Int64(pageSize), 0)
    }

    public static func clampedOffset(_ offset: Int64, totalRows: Int64) -> Int64 {
        min(max(offset, 0), max(totalRows - 1, 0))
    }
}
