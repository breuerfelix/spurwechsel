#!/usr/bin/env bash

set -euo pipefail

MODE="${1:-build}"
PROJECT_PATH="${PROJECT_PATH:-spurwechsel.xcodeproj}"
SCHEME="${SCHEME:-spurwechsel}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PWD/.build/DerivedData}"
PACKAGE_CACHE_PATH="${PACKAGE_CACHE_PATH:-$PWD/.build/SourcePackages}"

mkdir -p "$DERIVED_DATA_PATH" "$PACKAGE_CACHE_PATH"

COMMON_FLAGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=macOS"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -clonedSourcePackagesDirPath "$PACKAGE_CACHE_PATH"
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=
)

case "$MODE" in
  build)
    xcodebuild "${COMMON_FLAGS[@]}" build
    ;;
  archive)
    ARCHIVE_PATH="${ARCHIVE_PATH:-$PWD/.build/archive/${SCHEME}.xcarchive}"
    mkdir -p "$(dirname "$ARCHIVE_PATH")"
    xcodebuild "${COMMON_FLAGS[@]}" -archivePath "$ARCHIVE_PATH" archive
    echo "$ARCHIVE_PATH"
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    echo "Usage: $0 [build|archive]" >&2
    exit 1
    ;;
esac
