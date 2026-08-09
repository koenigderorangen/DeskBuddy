# Contributing to DeskBuddy

## Local Verification

```sh
swift test --disable-sandbox
./build-app.sh
```

The app is created at `outputs/DeskBuddy.app`.

## Conventional Commits

Use descriptive commits in the format `type(scope): description`:

- `fix: …` creates the next patch version (`0.0.n`).
- `feat: …` creates the next minor version (`0.n.0`).
- `feat!: …` or a `BREAKING CHANGE:` footer creates the next major version (`n.0.0`).
- `docs:`, `chore:`, `test:`, `refactor:`, and `ci:` do not trigger a release on their own.

When a release contains multiple commits, the highest change category wins. Every release build runs only after the test suite succeeds and lists all relevant commits since the previous tag in the release notes.
