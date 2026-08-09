# DeskBuddy

A compact, native macOS menu bar controller for IKEA IDÅSEN and compatible LINAK Bluetooth desks.

## Features

- Bluetooth discovery, connection, and automatic reconnection
- Live height in centimeters or inches
- Safe manual movement: press and hold to move, release to stop
- Sitting, standing, minimum, maximum, and custom saved positions
- Global keyboard shortcuts and Shortcuts/Siri integration
- Fixed IDÅSEN limits of 62–127 cm and a 30-second safety stop
- Posture Coach with gentle reminders and optional automatic movement after a cancel countdown
- Optional launch at login
- Native Liquid Glass interface for macOS 26 and later

## Local Build

```sh
chmod +x build-app.sh
./build-app.sh
```

The finished app is created at `outputs/DeskBuddy.app`.

## First Hardware Test

1. Quit any other desk-control apps and disconnect the desk from them.
2. Hold the Bluetooth button under the desk for about three seconds until the LED flashes blue.
3. Launch DeskBuddy and choose “Search for New Desks.”
4. Verify the live height before moving the desk.
5. Briefly press and hold Move Up and Move Down, releasing each control to stop.
6. Test a saved position only after manual movement works correctly.

If the desk moves unexpectedly, use the red Stop button or the physical desk control immediately.

## Protocol

The implementation uses the publicly documented LINAK/IDÅSEN GATT protocol. It does not include components, artwork, or source code from any commercial app.

## Releases

Pull requests run the Swift test suite on GitHub’s macOS 26 runner. On `main`, Conventional Commits determine the next version, run the tests again, build the app, and publish it as a ZIP archive in a GitHub Release. See [CONTRIBUTING.md](CONTRIBUTING.md) for the supported commit types.
