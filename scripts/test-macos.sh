#!/usr/bin/env bash

set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-spurwechsel.xcodeproj}"
SCHEME="${SCHEME:-spurwechsel}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PWD/.build/DerivedData-tests}"
PACKAGE_CACHE_PATH="${PACKAGE_CACHE_PATH:-$PWD/.build/SourcePackages}"
ONLY_TESTING="${ONLY_TESTING:-spurwechselTests}"
RESULT_BUNDLE_PATH="${RESULT_BUNDLE_PATH:-}"

mkdir -p "$DERIVED_DATA_PATH" "$PACKAGE_CACHE_PATH"

COMMON_FLAGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "$DESTINATION"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -clonedSourcePackagesDirPath "$PACKAGE_CACHE_PATH"
  -skipMacroValidation
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=
)

if [[ -n "$ONLY_TESTING" ]]; then
  COMMON_FLAGS+=("-only-testing:$ONLY_TESTING")
fi

if [[ -n "$RESULT_BUNDLE_PATH" ]]; then
  mkdir -p "$(dirname "$RESULT_BUNDLE_PATH")"
  COMMON_FLAGS+=(-resultBundlePath "$RESULT_BUNDLE_PATH")
fi

xcodebuild "${COMMON_FLAGS[@]}" test
