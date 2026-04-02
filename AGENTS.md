# Repository Guidelines

## Project Structure & Module Organization
`ShortcutField` is a Swift Package for macOS. Library sources live in `Sources/ShortcutField/`; keep public API types small and focused, with related behavior split into extension files such as `Shortcut+Matching.swift` and `Shortcut+KeyMapping.swift`. Tests live in `Tests/ShortcutFieldTests/` and mirror the library surface with focused suites like `ShortcutTests.swift` and `ShortcutSequenceTests.swift`. The manual demo app is in `Example/ShortcutFieldExample/`. Design notes and implementation plans belong in `docs/`.

## Build, Test, and Development Commands
Use `just` for the common workflow:

- `just build` builds the Swift package with `swift build`.
- `just test` runs the full test suite with `swift test`.
- `just lint` checks style with SwiftLint.
- `just format` formats the repository with SwiftFormat.
- `just example` builds and launches the example macOS app from `Example/`.

Run `just lint-fix` before submitting when SwiftLint can auto-correct issues.

## Coding Style & Naming Conventions
This package targets Swift 6.2 and macOS 13+. Follow the existing style: 4-space indentation, 120-character line width, and `Sendable`-safe code for new types and concurrency-sensitive changes. Use UpperCamelCase for types (`ShortcutRecorderView`), lowerCamelCase for properties and methods (`displayString`), and keep file names aligned with the primary type or extension they contain.

## Testing Guidelines
Tests use the Swift Testing framework, not XCTest. Prefer `@Test` and `#expect` and keep one responsibility per test file or suite. Name tests after observable behavior, for example `ShortcutMatchingTests.swift` or `ShortcutRecorderFieldTests.swift`. Run `just test` locally before opening a PR; add or update tests for every public API or matching/recording behavior change.

## Commit & Pull Request Guidelines
Recent history uses short conventional prefixes such as `docs:`, `chore:`, and `fix:`. Keep commit subjects imperative and scoped, for example `fix: handle tab matching in recorder`. Pull requests should include a clear summary, linked issue or plan when relevant, and screenshots or screen recordings for UI changes in `Example/`. Mention any lint, format, or test commands you ran.

## Agent Notes
Do not overwrite unrelated user changes in the working tree. Prefer minimal, targeted edits and update docs or the example app when public behavior changes.
