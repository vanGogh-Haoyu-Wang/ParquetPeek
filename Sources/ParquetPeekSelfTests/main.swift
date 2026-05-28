import Foundation
import ParquetPeekCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAILED: \(message)\n", stderr)
        exit(1)
    }
}

func pageOffsetMathClampsAtZero() {
    expect(PageMath.previousOffset(current: 0, pageSize: 1000) == 0, "previous page clamps at zero")
    expect(PageMath.previousOffset(current: 500, pageSize: 1000) == 0, "partial previous page clamps at zero")
}

func pageOffsetMathAdvancesWithoutCrossingEnd() {
    expect(PageMath.nextOffset(current: 0, pageSize: 1000, totalRows: 10_000) == 1000, "next page advances")
    expect(PageMath.nextOffset(current: 9_500, pageSize: 1000, totalRows: 10_000) == 9_999, "next page clamps at end")
}

func rowPageDecoding() throws {
    let json = """
    {
      "offset": 0,
      "limit": 2,
      "cancelled": false,
      "columns": ["id", "name"],
      "rows": [["1", "Ada"], ["2", "Grace"]]
    }
    """
    let page = try JSONDecoder().decode(RowPage.self, from: Data(json.utf8))
    expect(page.rows.count == 2, "row page decodes row count")
    expect(page.columns == ["id", "name"], "row page decodes columns")
}

func unsupportedFileErrorIsReadable() {
    let url = URL(filePath: "/tmp/example.csv")
    let error = ParquetBrowserError.unsupportedFile(url)
    expect(error.localizedDescription == "example.csv is not a .parquet file.", "unsupported file error is readable")
}

do {
    pageOffsetMathClampsAtZero()
    pageOffsetMathAdvancesWithoutCrossingEnd()
    try rowPageDecoding()
    unsupportedFileErrorIsReadable()
    print("ParquetPeekSelfTests passed")
} catch {
    fputs("FAILED: \(error.localizedDescription)\n", stderr)
    exit(1)
}
