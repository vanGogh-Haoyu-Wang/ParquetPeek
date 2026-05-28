import Foundation

public struct ParquetDocument: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let url: URL
    public let handle: Int64
    public var metadata: ParquetMetadata
    public var columns: [ParquetColumn]

    public init(url: URL, handle: Int64, metadata: ParquetMetadata, columns: [ParquetColumn]) {
        self.url = url
        self.handle = handle
        self.metadata = metadata
        self.columns = columns
    }

    public var displayName: String {
        url.lastPathComponent
    }
}

public struct ParquetMetadata: Codable, Equatable, Sendable {
    public var path: String
    public var rowCount: Int64
    public var columnCount: Int
    public var rowGroupCount: Int
    public var createdBy: String
    public var rowGroups: [ParquetRowGroup]

    public init(path: String, rowCount: Int64, columnCount: Int, rowGroupCount: Int, createdBy: String, rowGroups: [ParquetRowGroup]) {
        self.path = path
        self.rowCount = rowCount
        self.columnCount = columnCount
        self.rowGroupCount = rowGroupCount
        self.createdBy = createdBy
        self.rowGroups = rowGroups
    }
}

public struct ParquetRowGroup: Codable, Identifiable, Equatable, Sendable {
    public var index: Int
    public var rowCount: Int64
    public var totalByteSize: Int64

    public init(index: Int, rowCount: Int64, totalByteSize: Int64) {
        self.index = index
        self.rowCount = rowCount
        self.totalByteSize = totalByteSize
    }

    public var id: Int { index }
}

public struct ParquetColumn: Codable, Identifiable, Equatable, Sendable {
    public var index: Int
    public var name: String
    public var physicalType: String
    public var logicalType: String
    public var nullable: Bool

    public init(index: Int, name: String, physicalType: String, logicalType: String, nullable: Bool) {
        self.index = index
        self.name = name
        self.physicalType = physicalType
        self.logicalType = logicalType
        self.nullable = nullable
    }

    public var id: Int { index }
}

public struct RowPage: Codable, Equatable, Sendable {
    public var offset: Int64
    public var limit: Int
    public var cancelled: Bool
    public var columns: [String]
    public var rows: [[String]]

    public init(offset: Int64, limit: Int, cancelled: Bool, columns: [String], rows: [[String]]) {
        self.offset = offset
        self.limit = limit
        self.cancelled = cancelled
        self.columns = columns
        self.rows = rows
    }
}

public enum BrowserSelection: Hashable, Sendable {
    case file(UUID)
    case column(UUID, Int)
    case rowGroup(UUID, Int)
}

public enum ParquetBrowserError: Error, LocalizedError, Equatable, Sendable {
    case bridge(String)
    case invalidResponse(String)
    case unsupportedFile(URL)

    public var errorDescription: String? {
        switch self {
        case .bridge(let message):
            return message
        case .invalidResponse(let message):
            return "Unable to decode Parquet response: \(message)"
        case .unsupportedFile(let url):
            return "\(url.lastPathComponent) is not a .parquet file."
        }
    }
}
