#!/bin/bash
# Runs the Swift Testing suite.
#
# A full Xcode installation makes Testing.framework available automatically.
# With only the Command Line Tools, the framework ships in a developer
# directory that SwiftPM does not search by default, so we add it explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."

clt_frameworks="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
developer_dir="$(xcode-select -p 2>/dev/null || true)"

if [[ "$developer_dir" == *CommandLineTools* && -d "$clt_frameworks/Testing.framework" ]]; then
    exec swift test -Xswiftc -F -Xswiftc "$clt_frameworks" "$@"
fi

exec swift test "$@"
