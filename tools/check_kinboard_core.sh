#!/usr/bin/env bash
# Compiles Kinboard's Core/ folder (plain Foundation, no SwiftUI) with a Linux or macOS
# Swift toolchain and runs the same self-checks the app runs from Settings.
#
#   tools/check_kinboard_core.sh                 # run the checks
#   tools/check_kinboard_core.sh --show-sample   # also print suggestions found in the sample messages
#
# Set SWIFT=/path/to/swift if swift isn't on PATH.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
swift="${SWIFT:-swift}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/Sources/KinboardCoreChecks"
cp "$repo"/Kinboard.swiftpm/Core/*.swift "$work/Sources/KinboardCoreChecks/"
cp "$repo"/tools/kinboard-core-checks/*.swift "$work/Sources/KinboardCoreChecks/"
cat > "$work/Package.swift" <<'PKG'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "KinboardCoreChecks",
    targets: [.executableTarget(name: "KinboardCoreChecks")]
)
PKG

"$swift" build --package-path "$work" -c debug 2>&1 | grep -vE '^\[[0-9]+/[0-9]+\]|^Building|^Compiling|^Write|^Linking|^Planning|^Build complete' || true
"$work/.build/debug/KinboardCoreChecks" "$@"
