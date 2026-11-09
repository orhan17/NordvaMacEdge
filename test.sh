#!/bin/bash
# У Command Line Tools без Xcode модуль Testing лежит вне стандартного пути,
# поэтому его надо указать явно. С полным Xcode хватает просто swift test.
set -euo pipefail
cd "$(dirname "$0")"

flags=()
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools ]]; then
    frameworks=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
    flags=(
        -Xswiftc -F -Xswiftc "$frameworks"
        -Xlinker -F -Xlinker "$frameworks"
        -Xlinker -rpath -Xlinker "$frameworks"
    )
fi
swift test ${flags[@]+"${flags[@]}"}
