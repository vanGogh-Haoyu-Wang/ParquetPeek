import CParquetBridge
import Foundation
import ParquetPeekCore

struct ArrowParquetService: ParquetService {
    func openFile(at url: URL) async throws -> Int64 {
        guard url.pathExtension.lowercased() == "parquet" else {
            throw ParquetBrowserError.unsupportedFile(url)
        }

        return try await Task.detached(priority: .userInitiated) {
            let handle = prq_open_file(url.path)
            if handle == 0 {
                throw bridgeError()
            }
            return Int64(handle)
        }.value
    }

    func loadMetadata(handle: Int64) async throws -> ParquetMetadata {
        try await decodeBridgeResponse(handle: handle, call: prq_load_metadata)
    }

    func loadSchema(handle: Int64) async throws -> [ParquetColumn] {
        try await decodeBridgeResponse(handle: handle, call: prq_load_schema)
    }

    func readRows(handle: Int64, offset: Int64, limit: Int, columns: [String]) async throws -> RowPage {
        try await Task.detached(priority: .userInitiated) {
            let csv = columns.joined(separator: ",")
            guard let pointer = prq_read_rows(PRQHandle(handle), offset, Int32(limit), csv) else {
                throw bridgeError()
            }
            defer { prq_free_string(pointer) }
            let data = Data(String(cString: pointer).utf8)
            do {
                return try JSONDecoder().decode(RowPage.self, from: data)
            } catch {
                throw ParquetBrowserError.invalidResponse(error.localizedDescription)
            }
        }.value
    }

    func cancel(handle: Int64) {
        prq_cancel(PRQHandle(handle))
    }

    func closeFile(handle: Int64) {
        prq_close_file(PRQHandle(handle))
    }

    private func decodeBridgeResponse<T: Decodable & Sendable>(
        handle: Int64,
        call: @escaping @Sendable (PRQHandle) -> UnsafeMutablePointer<CChar>?
    ) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            guard let pointer = call(PRQHandle(handle)) else {
                throw bridgeError()
            }
            defer { prq_free_string(pointer) }
            let data = Data(String(cString: pointer).utf8)
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw ParquetBrowserError.invalidResponse(error.localizedDescription)
            }
        }.value
    }
}

private func bridgeError() -> ParquetBrowserError {
    if let message = prq_last_error(), !String(cString: message).isEmpty {
        return .bridge(String(cString: message))
    }
    return .bridge("The Parquet reader failed without a detailed error.")
}
