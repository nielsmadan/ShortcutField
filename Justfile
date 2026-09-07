[private]
default:
    @just --list

# Prepare this checkout for work: dependencies, hooks, then verify.
setup:
    @swift package resolve
    @lefthook install
    @just doctor

# Verify the tools and checkout state this repo needs.
doctor:
    #!/usr/bin/env bash
    set -uo pipefail
    fail=0
    need() {
        if command -v "$1" >/dev/null 2>&1; then
            printf '  ok       %s\n' "$1"
        else
            printf '  MISSING  %-12s install: %s\n' "$1" "$2"; fail=1
        fi
    }
    need python3 "brew install python"
    need swift "xcode-select --install"
    need swiftformat "brew install swiftformat"
    need swiftlint "brew install swiftlint"
    need xcodebuild "install Xcode from the App Store"
    need lefthook "brew install lefthook"
    if [ -f "$(git rev-parse --git-path hooks/pre-commit)" ]; then
        printf '  ok       git hooks\n'
    else
        printf '  MISSING  %-12s run: just setup\n' 'git hooks'; fail=1
    fi
    [ "$fail" -eq 0 ] && printf 'Everything in place.\n'
    exit $fail

build:
    @swift build -Xswiftc -warnings-as-errors

test:
    @swift test

# Format check, lint, strict build and tests. The pre-push gate.
check:
    @python3 -B -m unittest discover -s scripts -p 'test_release*.py'
    @swiftformat --lint .
    @swiftlint --strict .
    @swift build -Xswiftc -warnings-as-errors
    @swift test

lint *files:
    @swiftlint --strict {{ if files == "" { "." } else { files } }}

lint-fix *files:
    @swiftlint --fix {{ if files == "" { "." } else { files } }}

format *files:
    @swiftformat {{ if files == "" { "." } else { files } }}

# Build DocC docs and fail on any diagnostic (e.g. unresolved symbol links).
# `xcodebuild docbuild` exits 0 even on warnings, so inspect the diagnostics file.
docs:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf .build/docc
    xcodebuild docbuild -scheme ShortcutField -destination 'platform=macOS' -derivedDataPath .build/docc
    DIAG=$(find .build/docc -name '*-diagnostics.json' | head -1)
    if [ -z "$DIAG" ]; then
        echo "error: no DocC diagnostics file found — docc did not run" >&2
        exit 1
    fi
    COUNT=$(python3 -c "import json; print(len(json.load(open('$DIAG'))['diagnostics']))")
    if [ "$COUNT" -ne 0 ]; then
        echo "error: DocC reported $COUNT diagnostic(s):" >&2
        python3 -c "import json; [print('  -', x.get('summary', '')) for x in json.load(open('$DIAG'))['diagnostics']]" >&2
        exit 1
    fi
    echo "DocC: no diagnostics."

example:
    @xcodebuild -project Example/ShortcutFieldExample.xcodeproj \
        -scheme ShortcutFieldExample -configuration Debug \
        -derivedDataPath .build/Example build
    @.build/Example/Build/Products/Debug/ShortcutFieldExample.app/Contents/MacOS/ShortcutFieldExample

clean:
    @rm -rf .build
    @echo "Build directory cleaned."

[positional-arguments]
release *args:
    python3 scripts/release.py "$@"
