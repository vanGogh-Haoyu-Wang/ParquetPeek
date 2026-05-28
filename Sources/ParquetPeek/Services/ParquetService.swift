import Foundation
import ParquetPeekCore

protocol ParquetService: Sendable {
    func openFile(at url: URL) async throws -> Int64
    func loadMetadata(handle: Int64) async throws -> ParquetMetadata
    func loadSchema(handle: Int64) async throws -> [ParquetColumn]
    func readRows(handle: Int64, offset: Int64, limit: Int, columns: [String]) async throws -> RowPage
    func cancel(handle: Int64)
    func closeFile(handle: Int64)
}
