<p align="center">
  <img src="Assets/icon.png?v=2" width="128" height="128" alt="Reframe icon">
</p>

<h1 align="center">Reframe</h1>

<p align="center">
  Open-source virtual camera with smart framing and portrait mode for macOS.<br>
  Center Stage for any webcam.
</p>

---

Reframe reads frames from any USB or built-in webcam, detects your face with Apple's on-device Vision framework, and outputs a smoothly reframed stream as a virtual camera. No cloud, no subscription, no tracking.

## Features

- **Works with any camera** — USB webcams, monitors with built-in cameras, capture cards
- **Virtual camera output** — shows up as "Reframe" in Zoom, Meet, Teams, FaceTime, OBS
- **Smart framing** — face detection + smooth crop with rule-of-thirds positioning
- **Virtual backgrounds** — gradient presets or custom images
- **Portrait mode** — on-device person segmentation with adjustable blur
- **Image adjustments** — exposure, contrast, temperature, tint, vibrance, saturation, sharpness
- **Menu bar mini mode** — live preview and quick controls without the main window
- **CLI tool** — headless camera discovery and configuration via `reframe`
- **Privacy-first** — all processing on-device via Apple Vision

## Install

Download the latest DMG from the [Releases](https://github.com/thalysguimaraes/reframe/releases/latest) page. Requires macOS 13+.

### Build from source

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
git clone https://github.com/thalysguimaraes/reframe.git
cd reframe
xcodegen generate
open Reframe.xcodeproj
```

## Usage

1. Launch Reframe and grant camera access
2. Select your source camera
3. Install the virtual camera (onboarding guides you through system extension approval)
4. Select "Reframe" as your camera in any video app

### CLI

```bash
reframe list-cameras
reframe start --camera "Logitech C920" --preset medium --output 1080p
reframe set --smoothing 0.82 --zoom-strength 0.6
reframe tracking on|off
reframe stop
```

## Built with

Swift, Vision framework, CoreMediaIO

## License

MIT
