#!/bin/zsh
# Builds Space Juggler.app from the space-juggler package this project depends on (ADR-0017) and prints its path.
# Usage: Scripts/space-juggler.sh [debug|release] OUTPUT-DIRECTORY
# Environment as for space-juggler's Scripts/build-space-juggler.sh: SIGN_IDENTITY, UNIVERSAL=1, TIMESTAMP=1.
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
# Where SwiftPM has the package checked out (or a local override): ask SwiftPM.
PACKAGE="$(swift package show-dependencies --format json | python3 -c '
import json, sys
def find(node):
    for dependency in node.get("dependencies", []):
        if dependency["identity"] == "space-juggler":
            return dependency["path"]
        found = find(dependency)
        if found:
            return found
print(find(json.load(sys.stdin)) or "")')"
[[ -n "$PACKAGE" ]] || { echo "space-juggler not found among the dependencies" >&2; exit 1; }
"$PACKAGE/Scripts/build-space-juggler.sh" "${1:-debug}" "${2:?output directory}" | tail -1
