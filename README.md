<p align="center">
  <img src="Assets/icon.png?v=2" width="128" height="128" alt="Reframe icon">
</p>

<h1 align="center">Reframe</h1>

<p align="center">
  <strong>Open-source face-centering virtual camera for macOS</strong><br>
  Center Stage for any webcam.
</p>

<p align="center">
  <a href="#features">Features</a> &bull;
  <a href="#installation">Installation</a> &bull;
  <a href="#usage">Usage</a> &bull;
  <a href="#how-it-works">How it works</a> &bull;
  <a href="#building-from-source">Building from source</a> &bull;
  <a href="#contributing">Contributing</a> &bull;
  <a href="#license">License</a>
</p>

---

Reframe reads frames from any USB or built-in webcam, detects your face with Apple's on-device Vision framework, and outputs a smoothly reframed stream as a virtual camera that works in Zoom, Meet, Teams, FaceTime, and every other app that reads from a camera.

No cloud. No subscription. No tracking. Just better framing.

## Features

- **Works with any camera** — USB webcams, monitors with built-in cameras, capture cards
- **Virtual camera output** — shows up as "Reframe" in Zoom, Meet, Teams, FaceTime, OBS, etc.
- **Smart framing** — face detection + smooth crop with proper headroom (rule-of-thirds positioning)
- **Asymmetric smoothing** — zoom-in is snappy, zoom-out is gentle, inspired by Apple's Center Stage behavior
- **Comfort zone** — small movements don't trigger reframing; only meaningful motion causes a pan
- **Lost-face fallback** — holds framing briefly when you look away, then smoothly widens back
- **Hardware Center Stage aware** — if your camera already has hardware Center Stage, Reframe backs off instead of double-framing
- **Preset framing modes** — Tight, Medium, Wide
- **Adjustable controls** — Follow smoothness, Zoom strength
- **CLI tool** — headless camera discovery and configuration
- **Native Swift** — no Electron, no bridge layers, minimal resource usage
- **Privacy-first** — all processing is on-device via Apple Vision; no data leaves your Mac

## Requirements

- macOS 13.0+
- A physical camera (USB webcam, built-in, or capture card)
- Xcode 15+ (for building from source)

## Installation

### Download

Pre-built releases will be available on the [Releases](https://github.com/thalysguimaraes/reframe/releases) page.

### Homebrew (coming soon)

```bash
brew install --cask reframe
```

## Usage

1. **Launch Reframe** and grant camera access when prompted
2. **Select your source camera** from the dropdown
3. **Enable tracking** — your face will be centered automatically
4. **Install the virtual camera** — click "Install Virtual Camera" to register the system extension
5. **Select "Reframe"** as your camera in Zoom, Meet, Teams, or any video app

### Controls

| Control | What it does |
|---------|-------------|
| **Source camera** | Which physical camera to read from |
| **Output** | 720p or 1080p output resolution |
| **Preset** | Tight / Medium / Wide framing |
| **Follow smoothness** | How smoothly the crop tracks your face (higher = smoother but laggier) |
| **Zoom strength** | How aggressively to zoom in on your face |
| **Tracking enabled** | Toggle face tracking on/off |

### CLI

```bash
reframe list-cameras
reframe start --camera "Logitech C920" --preset medium --output 1080p
reframe set --smoothing 0.82 --zoom-strength 0.6
reframe print-stats
reframe stop
```

## How it works

```
Physical Camera
    |
[AVCaptureSession] — captures raw frames
    |
[Vision Framework] — on-device face detection (every Nth frame)
    |
[FaceObservationStabilizer] — temporal smoothing of face bounding boxes
    |
[CropEngine] — computes smooth crop rect with:
    |   - zoom-factor model (face size → zoom level)
    |   - rule-of-thirds headroom positioning
    |   - asymmetric smoothing (fast zoom-in, slow zoom-out)
    |   - comfort zone dead-band stabilization
    |   - lost-face hold + gradual fallback
    |
[PixelBufferReframer] — CoreImage crop + scale to output resolution
    |
[Virtual Camera] — CoreMediaIO system extension
    |
Zoom / Meet / Teams / FaceTime
```

The framing algorithm was developed by studying Apple's Center Stage implementation in `AVFCapture.framework` to match the behavior users expect from hardware face-tracking cameras.

## Building from source

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen

git clone https://github.com/thalysguimaraes/reframe.git
cd reframe
xcodegen generate
open AutoFrameCam.xcodeproj
```

Before trying to install the virtual camera, create the App Group `group.dev.autoframe.cam` in Apple Developer and attach it to both `dev.autoframe.AutoFrameCam` and `dev.autoframe.AutoFrameCam.CameraExtension`. The generated provisioning profiles must include that exact App Group value, and the camera extension's `CMIOExtensionMachServiceName` must match it exactly for Core Media I/O validation to pass.

### Terminal build

```bash
xcodegen generate
xcodebuild -scheme "AutoFrame Cam" -configuration Release build
```

### Run tests

```bash
xcodebuild -scheme "AutoFrame Cam" test
```

## Project structure

```
Sources/
  Core/           — shared capture, detection, crop, and persistence logic
  App/            — SwiftUI control surface and extension installer
  CameraExtension/ — CoreMediaIO virtual camera system extension
  CLI/            — command-line tool
Tests/
  AutoFrameCoreTests/ — crop engine and stabilizer tests
Config/           — entitlements and Info.plist templates
Assets/           — app icon
project.yml       — XcodeGen project specification
```

## Contributing

Contributions are welcome. Please open an issue first to discuss what you'd like to change.

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-change`)
3. Make your changes and add tests
4. Run the test suite (`xcodebuild -scheme "AutoFrame Cam" test`)
5. Open a pull request

### Areas where help is appreciated

- Multi-person framing support
- Background blur / replacement
- MediaPipe integration for faster/better face detection
- Homebrew cask formula
- Localization

## License

MIT License. See [LICENSE](LICENSE) for details.

---

<p align="center">
  Built with Swift, Vision, CoreMediaIO, and reverse-engineered taste.
</p>
