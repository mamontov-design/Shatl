#!/bin/sh
# SPDX-FileCopyrightText: 2026 Mamontov Design
# SPDX-License-Identifier: GPL-3.0-only
#
# Typesets every Localizable.strings with the rules the tests check
# (Tests/Typography/ShatlTypograph.swift). Pass --check to only report.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

xcrun swiftc -O \
    "$root/Tests/Typography/ShatlTypograph.swift" \
    "$root/Scripts/typograph/main.swift" \
    -o "$build/typograph"

"$build/typograph" "$root" "$@"
