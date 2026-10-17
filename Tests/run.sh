#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_build_dir=$(mktemp -d "${TMPDIR:-/tmp}/chatharbor-tests.XXXXXX")
trap 'rm -rf "$test_build_dir"' EXIT
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -module-cache-path "$test_build_dir/cache" \
  ChatHarbor/Services/{LLMProvider,KeychainHelper,CustomEndpointProvider,BrainstormReport}.swift \
  Tests/CoreRegression.swift -o "$test_build_dir/core"
"$test_build_dir/core"
if [[ "${1:-}" == "--core-only" ]]; then exit 0; fi
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -module-cache-path "$test_build_dir/cache" \
  ChatHarbor/Services/BrainstormReport.swift Tests/PDFSmoke.swift -o "$test_build_dir/pdf"
"$test_build_dir/pdf"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -module-cache-path "$test_build_dir/cache" \
  ChatHarbor/Services/LLMProvider.swift ChatHarbor/Models/{BrainstormModels,ChatModels,ShipModels}.swift Tests/DecisionNotesSmoke.swift -o "$test_build_dir/persistence"
"$test_build_dir/persistence"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -module-cache-path "$test_build_dir/cache" \
  ChatHarbor/Models/*.swift ChatHarbor/Services/*.swift Tests/BrainstormRegression.swift -o "$test_build_dir/brainstorm"
"$test_build_dir/brainstorm"

xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -module-cache-path "$test_build_dir/cache" \
  ChatHarbor/Services/LLMProvider.swift ChatHarbor/Models/{BrainstormModels,ChatModels,ShipModels}.swift Tests/HarborRegression.swift -o "$test_build_dir/harbors"
"$test_build_dir/harbors"
