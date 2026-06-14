<h1 align="left">
  <img src="Assets/DepartureBoardSaverIcon.png" alt="DepartureBoardSaver icon" width="64" height="64" style="vertical-align:middle; margin-right:12px;">
  DepartureBoardSaver
</h1>

Built by [Justyn Henman](https://justynhenman.com).

![macOS](https://img.shields.io/badge/macOS-14%2B-lightgrey?style=flat)
![Swift](https://img.shields.io/badge/Swift-6.0-orange?style=flat)
![GitHub release](https://img.shields.io/github/v/release/justynhenman/DepartureBoardSaver)

[![Donate](https://img.shields.io/badge/Donate-%E2%9D%A4-green?style=for-the-badge)](https://ko-fi.com/justynhenman)

This project is a macOS screen saver that displays a real-time UK train departure board! It is modelled on the classic dot-matrix boards found at British railway stations. Inspired and derived from [chrisys/train-departure-display](https://github.com/chrisys/train-departure-display).

Departure data is fetched live from the National Rail OpenLDBWS SOAP API every 60 seconds.

<p align="center">
  <img src="Assets/TestHostScreenshot.png" alt="DepartureBoardSaver screenshot" width="920">
</p>

## Display styles

| Style | Description |
|-------|-------------|
| **Dot Matrix** (default) | Each pixel rendered as a physical amber LED dot with glow, powered by Metal for GPU acceleration |
| **OLED** | Amber on black, teletext style [NO GPU ACCELERATION] |
| **LCD** | White text on dark navy [NO GPU ACCELERATION] |

## Requirements

- macOS 14 Sonoma or later
- Xcode 16 or later
- A free National Rail Darwin API key — register at [realtime trains](https://realtime.nationalrail.co.uk/OpenLDBWSRegistration/)

## Building

1. Clone the repository:
   ```sh
   git clone https://github.com/justynhenman/DepartureBoardSaver.git
   cd DepartureBoardSaver
   ```

2. Open the project in Xcode:
   ```sh
   open DepartureBoardSaver.xcodeproj
   ```

3. Select the **DepartureBoardSaver** scheme and build (`⌘B`). The compiled `.saver` bundle lands in `Products/DepartureBoardSaver.saver`.

   A **DepartureBoardSaverTestHost** scheme is also included — this is a lightweight macOS app that hosts the screen saver view directly, making it easy to iterate without installing the `.saver` bundle each time.

> **Note:** The Release configuration is set up for notarized distribution and requires a **Developer ID Application** certificate. For local development, use the Debug configuration (the default in Xcode). If you want to build Release without a Developer ID, open the target's Signing & Capabilities tab, switch Code Signing Style back to **Automatic**, and select your personal team.

## Installation

Double-click `DepartureBoardSaver.saver` — macOS will prompt you to install it into Screen Saver preferences.

Alternatively, you can copy it manually:

```sh
# current user only
cp -R Products/DepartureBoardSaver.saver ~/Library/Screen\ Savers/

# all users (requires admin)
sudo cp -R Products/DepartureBoardSaver.saver /Library/Screen\ Savers/
```

Then open **System Settings → Wallpaper**, click **Screen Saver**, scroll to the bottom to 'other', select **DepartureBoardSaver**, and click **Options** to enter your API key and station CRS code (e.g. `PAD` for London Paddington).

## Configuration

| Setting | Description |
|---------|-------------|
| API Key | Your National Rail Darwin token |
| Station | Three-letter CRS code (e.g. `PAD`, `WAT`, `MAN`) |
| Display style | Dot Matrix / OLED / LCD |
| Side padding | Percentage of screen width to leave on each side (0–30%) |
| Show station in clock | Toggle the station name in the clock panel |
| Metal rendering | GPU-accelerated dot-matrix mode (enabled by default) |

Settings are stored in `~/Library/Preferences/justynhenman.DepartureBoardSaver.plist`.

## Architecture

| File | Role |
|------|------|
| `DepartureBoardSaverView.swift` | `ScreenSaverView` subclass — animation loop, Metal layer management, drawing dispatch |
| `DepartureBoard.swift` | Layout engine — positions rows, scrolling text, clock |
| `DepartureService.swift` | Async SOAP client for the OpenLDBWS endpoint |
| `DepartureBoardConfig.swift` | Persistent settings via `ScreenSaverDefaults` |
| `DotMatrixMetalRenderer.swift` | GPU renderer — dot glow and grid via Metal |
| `DotMatrixShaders.metal` | Metal shader source |
| `ConfigureSheetController.swift` | Options sheet presented by Screen Saver preferences |
| `BoardFonts.swift` | Dot Matrix font registration helpers |

## Credits

- [chrisys/train-departure-display](https://github.com/chrisys/train-departure-display) — the Raspberry Pi departure board project that inspired this screen saver and provided the foundation for the layout and display logic. Huge thanks to everyone involved in that project, without it this wouldn't exist.
- [DanielHartUK/Dot-Matrix-Typeface](https://github.com/DanielHartUK/Dot-Matrix-Typeface) — the dot-matrix fonts used in this project, painstakingly put together by **DanielHartUK**. A huge thanks for making that resource available!
- [AerialScreensaver/ScreenSaverMinimal](https://github.com/AerialScreensaver/ScreenSaverMinimal) — post-Sonoma `legacyScreenSaver` workarounds (ghost instance detection, `willStop` observer, preview exit logic) ported from this project. The workaround detailed in this project made the screensaver actually usable on newer MacOS versions
