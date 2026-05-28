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

## Run

```bash
./script/build_and_run.sh
```

The app Run action is wired to the same script.

## Package

```bash
./script/package_app.sh
```

The packaging script builds a release `.app`, embeds the app icon and Homebrew
Arrow runtime libraries, applies an ad-hoc local signature, and writes
`release/ParquetPeek.dmg`.
