<p align="center">
  <img src="Assets/icon.png?v=2" width="128" height="128" alt="Reframe icon">
</p>

<h1 align="center">Reframe</h1>

<p align="center">
  <strong>Open-source virtual camera with smart framing, virtual backgrounds, and portrait mode for macOS</strong><br>
  Center Stage for any webcam.
</p>

<p align="center">
  <a href="https://github.com/thalysguimaraes/reframe/releases/latest">Download</a> &bull;
  <a href="#features">Features</a> &bull;
  <a href="#usage">Usage</a> &bull;
  <a href="#how-it-works">How it works</a> &bull;
  <a href="#building-from-source">Building from source</a> &bull;
  <a href="#license">License</a>
</p>

---

Reframe reads frames from any USB or built-in webcam, detects your face with Apple's on-device Vision framework, and outputs a smoothly reframed stream as a virtual camera that works in Zoom, Meet, Teams, FaceTime, and every other app that reads from a camera.

No cloud. No subscription. No tracking. Just better framing.

## Features

- **Works with any camera** — USB webcams, monitors with built-in cameras, capture cards
- **Virtual camera output** — shows up as "Reframe" in Zoom, Meet, Teams, FaceTime, OBS, etc.
- **Smart framing** — face detection + smooth crop with proper headroom (rule-of-thirds positioning)
- **Virtual backgrounds** — replace your background with gradient presets or your own images
- **Portrait mode** — on-device person segmentation with adjustable background blur
- **Image adjustments** — exposure, contrast, temperature, tint, vibrance, saturation, sharpness
- **Menu bar mini mode** — live preview and quick controls without opening the main window
- **Asymmetric smoothing** — zoom-in is snappy, zoom-out is gentle, inspired by Apple's Center Stage behavior
- **Comfort zone** — small movements don't trigger reframing; only meaningful motion causes a pan
- **Lost-face fallback** — holds framing briefly when you look away, then smoothly widens back
- **Hardware Center Stage aware** — if your camera already has hardware Center Stage, Reframe backs off instead of double-framing
- **Preset framing modes** — Tight, Medium, Wide with adjustable zoom strength
- **CLI tool** — headless camera discovery and configuration via `reframe`
- **Native Swift** — no Electron, no bridge layers, minimal resource usage
- **Privacy-first** — all processing is on-device via Apple Vision; no data leaves your Mac

## Installation

Download the latest DMG from the [Releases](https://github.com/thalysguimaraes/reframe/releases/latest) page, open it, and drag **Reframe** to Applications.

Requires macOS 13+.

## Usage

1. **Launch Reframe** and grant camera access when prompted
2. **Select your source camera** from the dropdown
3. **Install the virtual camera** — the onboarding will guide you through the system extension approval
4. **Select "Reframe"** as your camera in Zoom, Meet, Teams, or any video app

### Controls

| Control | What it does |
|---------|-------------|
| **Source camera** | Which physical camera to read from |
| **Output** | 720p or 1080p output resolution |
| **Framing preset** | Tight / Medium / Wide |
| **Smoothness** | How smoothly the crop tracks your face |
| **Zoom strength** | How aggressively to zoom in on your face |
| **Portrait mode** | Background blur with adjustable strength |
| **Virtual background** | Replace background with gradients or custom images |
| **Adjustments** | Exposure, contrast, temperature, tint, vibrance, saturation, sharpness |

### CLI

```bash
reframe list-cameras
reframe start --camera "Logitech C920" --preset medium --output 1080p
reframe set --smoothing 0.82 --zoom-strength 0.6
reframe tracking on|off
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
[ImageAdjustmentCompositor] — exposure, contrast, white balance, sharpness
    |
[PortraitCompositor / VirtualBackgroundCompositor]
    |   - VNGeneratePersonSegmentationRequest for person mask
    |   - CIBlendWithMask compositing (blur or background replacement)
    |
[Virtual Camera] — CoreMediaIO system extension
    |
Zoom / Meet / Teams / FaceTime
```

## Building from source

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen

git clone https://github.com/thalysguimaraes/reframe.git
cd reframe
xcodegen generate
open Reframe.xcodeproj
```

Before installing the virtual camera from a local build, create the App Group `group.dev.autoframe.cam` in Apple Developer and attach it to both `dev.autoframe.AutoFrameCam` and `dev.autoframe.AutoFrameCam.CameraExtension`. The generated provisioning profiles must include that exact App Group value.

### Terminal build

```bash
xcodegen generate
xcodebuild -project Reframe.xcodeproj -scheme "Reframe" -configuration Release build
```

### Run tests

```bash
xcodebuild -project Reframe.xcodeproj -scheme "Reframe" test
```

## Project structure

```
Sources/
  Core/           — shared capture, detection, crop, compositing, and persistence
  App/            — SwiftUI control surface and extension installer
  CameraExtension/ — CoreMediaIO virtual camera system extension
  CLI/            — command-line tool
Tests/
  AutoFrameCoreTests/ — crop engine, stabilizer, settings, and compositor tests
Config/           — entitlements and Info.plist templates
Assets/           — app icon and menu bar icon
project.yml       — XcodeGen project specification
```

## Contributing

Contributions are welcome. Please open an issue first to discuss what you'd like to change.

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-change`)
3. Make your changes and add tests
4. Run the test suite (`xcodebuild -scheme "Reframe" test`)
5. Open a pull request

## License

MIT License. See [LICENSE](LICENSE) for details.

---

<p align="center">
  Built with Swift, Vision, CoreMediaIO, and reverse-engineered taste.
</p>
