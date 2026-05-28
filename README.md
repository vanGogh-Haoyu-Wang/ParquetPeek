# ParquetPeek

ParquetPeek is a native macOS SwiftUI reader for Parquet files. It opens local
`.parquet` files, shows schema and row group metadata, and pages through rows
without loading the whole file into Swift memory.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain
- Apache Arrow C++ from Homebrew:

```bash
brew install apache-arrow
```

## Installation

Download the latest `.dmg` from Releases.

1. Download `ParquetPeek.dmg`
2. Drag ParquetPeek into Applications
3. Launch the app