[private]
default:
    @just --list

build:
    @swift build -Xswiftc -warnings-as-errors

test:
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

# Usage: just tag-release-patch ["Tag message"], likewise for -minor and -major.
# The message defaults to "Release vX.Y.Z".
tag-release-patch message="":
    @just tag-release patch "{{message}}"

tag-release-minor message="":
    @just tag-release minor "{{message}}"

tag-release-major message="":
    @just tag-release major "{{message}}"

tag-release bump message="":
    #!/usr/bin/env bash
    set -euo pipefail
    LATEST_TAG=$(git tag --sort=-v:refname | head -1 | sed 's/^v//')
    if [ -z "$LATEST_TAG" ]; then
        VERSION="0.1.0"
        case "{{bump}}" in
            patch) VERSION="0.0.1" ;;
            minor) VERSION="0.1.0" ;;
            major) VERSION="1.0.0" ;;
        esac
    else
        MAJOR=$(echo "$LATEST_TAG" | cut -d. -f1)
        MINOR=$(echo "$LATEST_TAG" | cut -d. -f2)
        PATCH=$(echo "$LATEST_TAG" | cut -d. -f3)
        case "{{bump}}" in
            patch) PATCH=$((PATCH + 1)) ;;
            minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
            major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
            *) echo "Error: bump must be patch, minor, or major"; exit 1 ;;
        esac
        VERSION="$MAJOR.$MINOR.$PATCH"
    fi
    # Keep the README install snippet in sync; commit it so the tag includes it.
    sed -i '' -E "s|(ShortcutField\", from: \")[0-9]+\.[0-9]+\.[0-9]+|\1${VERSION}|" README.md
    if ! git diff --quiet README.md; then
        git add README.md
        git commit -m "chore: bump README install version to $VERSION"
    fi
    TAG_MESSAGE="{{message}}"
    if [ -z "$TAG_MESSAGE" ]; then
        TAG_MESSAGE="Release v$VERSION"
    fi
    echo "Tagging v$VERSION..."
    # -a because tag.gpgsign makes the tag signed, and a signed tag needs a
    # message or git opens an editor mid-recipe.
    git tag -a "v$VERSION" -m "$TAG_MESSAGE" && git push origin main "v$VERSION" && \
    echo "Tagged and pushed v$VERSION"
