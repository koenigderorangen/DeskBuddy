<p align="center">
	<img src="Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png" width="144" alt="DeskBuddy app icon">
</p>

<h1 align="center">DeskBuddy</h1>

<p align="center">
	Native macOS menu bar control for IKEA IDÅSEN and compatible LINAK desks.
</p>

<p align="center">
	Move your desk, save favorite heights, and build healthier sit-stand habits without leaving the menu bar.
</p>

## Your Desk, One Click Away

DeskBuddy keeps everyday desk controls close without turning them into another dashboard. Connect over Bluetooth, see the current height at a glance, and move directly to the position you need.

- **Return to the right height** — Save sitting, standing, minimum, maximum, and custom positions.
- **Tap into position** — Use double up and double down, or build your own physical paddle sequences for any saved position.
- **Stay in your flow** — Use global keyboard shortcuts or actions in Apple Shortcuts without opening the menu.
- **Change posture on time** — See the current and next interval, get reminders, or use cancelable automatic movement.
- **Keep meetings still** — Pause automatic movement while the camera, microphone, or a selected macOS Focus is active.
- **See what matters** — Show the current height in centimeters or inches directly in the menu bar.
- **Feel at home on macOS** — Native SwiftUI, Liquid Glass, launch at login, automatic reconnection, and Sparkle updates.
- **Move manually when needed** — Press and hold to move, release to stop, or stop an active preset movement from the menu.

## Designed Around Your Routine

### Custom paddle gestures

The IDÅSEN normally requires holding its physical paddle until the desk reaches the desired height. DeskBuddy starts with double up and double down, then lets you add, edit, and remove your own multi-tap sequences. Every sequence can target any saved position.

An unambiguous sequence triggers as soon as its final tap ends. If one configured gesture is the beginning of another, DeskBuddy waits for the configurable continuation window before choosing the shorter gesture. A single paddle tap also cancels an active preset movement and immediately rearms gesture recognition.

### Quick movement

Open DeskBuddy from the menu bar and hold the up or down control. Movement continues while pressed and stops when released.

### Saved positions

Create named positions for the heights you use throughout the day. Presets remain editable and can be reordered from their context menu.

### Keyboard and voice

Assign global shortcuts to movement and presets, disable individual shortcuts when they are not needed, or trigger DeskBuddy actions through Apple Shortcuts.

### Posture Coach

Choose separate sitting and standing intervals plus the weekdays and hours when coaching is active. The menu shows the current-to-next posture and time remaining. DeskBuddy can simply remind you or prepare an automatic move with a visible countdown that you can cancel at any time.

Automatic movement can pause while a camera or microphone is in use. You can also add DeskBuddy as a Focus Filter to individual macOS Focus modes: open **System Settings → Focus**, choose a Focus, and add DeskBuddy under **Focus Filters**.

### Updates

DeskBuddy can check for, download, and install signed updates through Sparkle. Automatic checks and downloads are independently configurable in **Settings → About**.

## Privacy

DeskBuddy only queries whether a camera or audio input device is running when meeting-aware movement pause is enabled. It never captures camera frames or microphone audio, cannot identify which app is using a device, and does not request camera or microphone capture access.

## Compatibility

- macOS 26 or later
- IKEA IDÅSEN desks
- Compatible LINAK Bluetooth desk controllers using the same GATT protocol
- Bluetooth access

## Connect Your Desk

On first launch, DeskBuddy guides you through Bluetooth access, optional Posture Coach notifications, startup behavior, and desk connection.

1. Quit other desk-control apps and disconnect the desk from them.
2. Hold the Bluetooth button under the desk for about three seconds, until its LED flashes blue.
3. In onboarding, choose **Find Desks**. You can return to the same controls later in **Settings → Desks**.
4. Select your desk and verify the displayed height before moving it.
5. Test a short manual move before using saved positions.

If the desk moves unexpectedly, use DeskBuddy's red **Stop** button or the physical desk control immediately.

## Build From Source

```sh
./build-app.sh
```

The app bundle is written to `outputs/DeskBuddy.app`. With no flag, the script builds the same release configuration used by CI; `./build-app.sh --release` is the explicit equivalent.

To include development-only notification, Posture Coach, meeting detection, and panel-size testing controls, build with:

```sh
./build-app.sh --debug
```

Install the resulting `outputs/DeskBuddy.app` in the same way. Development requires Xcode with the macOS 26 SDK and Swift 6.2.

See [CONTRIBUTING.md](CONTRIBUTING.md) for verification and commit conventions.

## Protocol and Independence

DeskBuddy uses the publicly documented LINAK/IDÅSEN Bluetooth GATT protocol. It does not include components, artwork, or source code from any commercial desk-control app, and it is not affiliated with IKEA or LINAK.
