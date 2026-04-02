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

example:
    @xcodebuild -project Example/ShortcutFieldExample.xcodeproj \
        -scheme ShortcutFieldExample -configuration Debug \
        -derivedDataPath .build/Example build
    @.build/Example/Build/Products/Debug/ShortcutFieldExample.app/Contents/MacOS/ShortcutFieldExample

clean:
    @rm -rf .build
    @echo "Build directory cleaned."

# Usage: just tag-release-patch, just tag-release-minor, just tag-release-major
tag-release-patch:
    @just tag-release patch

tag-release-minor:
    @just tag-release minor

tag-release-major:
    @just tag-release major

tag-release bump:
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
    echo "Tagging v$VERSION..."
    git tag "v$VERSION" && git push origin main "v$VERSION" && \
    echo "Tagged and pushed v$VERSION"
