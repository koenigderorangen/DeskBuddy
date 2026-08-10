# Contributing to DeskBuddy

## Requirements

- macOS 26 or later
- Xcode with the macOS 26 SDK
- Swift 6.2
- A compatible Bluetooth desk for hardware integration testing

## Development Builds

Use the debug package while developing UI, notifications, Posture Coach behavior, or device detection:

```sh
./build-app.sh --debug
```

The `--debug` flag enables additional settings that are not present in release builds:

- **Posture Coach → Developer Testing** can send a notification, trigger an automatic-movement countdown, and check live camera and microphone activity.
- **Diagnostics → Panel Size** can resize and reset the menu panel for layout testing.

The app is written to `outputs/DeskBuddy.app`. Packaging again replaces that bundle, so quit a running copy before opening the newly built app.

For release-equivalent packaging, use either command:

```sh
./build-app.sh
./build-app.sh --release
```

Both commands create the production configuration used by CI and omit all `#if DEBUG` controls.

## Local Verification

```sh
swift test --disable-sandbox
swift build -c release --disable-sandbox
./build-app.sh --release
```

Run the focused debug build first while iterating, then complete the release build and package checks before opening a pull request. When testing physical movement, keep the desk area clear and verify that DeskBuddy and the physical paddle can stop movement immediately.

Pull requests also run `swift test --disable-sandbox` on the macOS 26 CI runner.

## Conventional Commits

Use descriptive commits in the format `type(scope): description`:

- `fix: …` creates the next patch version (`0.0.n`).
- `feat: …` creates the next minor version (`0.n.0`).
- `feat!: …` or a `BREAKING CHANGE:` footer creates the next major version (`n.0.0`).
- `docs:`, `chore:`, `test:`, `refactor:`, and `ci:` do not trigger a release on their own.

When a release contains multiple commits, the highest change category wins. Every release build runs only after the test suite succeeds and lists all relevant commits since the previous tag in the release notes.
