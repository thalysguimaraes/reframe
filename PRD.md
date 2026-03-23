# AutoFrame Cam for macOS

Here’s a practical PRD for a software face-centering virtual camera on macOS, assuming your Samsung 5K monitor webcam is a normal fixed USB camera and we’re fine with a processed virtual source.

Apple’s modern path for software cameras on macOS is a Core Media I/O Camera Extension rather than the older DAL plugin model, and Apple positions camera extensions as the secure, system-compatible replacement for legacy plug-ins. OBS’s macOS virtual camera also moved in that direction on newer macOS versions. [Apple Developer][1]

## Product Requirements Document

### Product name

**AutoFrame Cam for macOS**

### Problem

External fixed webcams on macOS do not provide Apple-style face centering unless the hardware itself supports tracking or the camera is Apple-native. With a standard USB webcam, the only general solution is to ingest the original camera, detect the face, crop/reframe digitally, and publish the result as a virtual camera for meeting apps. Apple’s Camera Extension framework is intended for exactly this class of “software camera” use case. [Apple Developer][1]

### Goal

Create a lightweight macOS app that:

- reads frames from a selected physical camera
- detects and tracks the user’s face
- dynamically crops and recenters the frame to keep the face comfortably framed
- outputs the processed stream as a virtual camera
- exposes a minimal UI and optional CLI for control

### Non-goals

- Mechanical pan/tilt control of the hardware camera
- Multi-person framing
- Background blur/replacement in v1
- Native Apple-style menu-bar integration matching the screenshot
- Windows/Linux support in v1

## User story

"As a remote worker using a non-Apple webcam, I want my camera view to keep my face centered during calls without manually repositioning the monitor or camera."

## Success criteria

- User can select `AutoFrame Cam` as a camera in Zoom, Meet, Teams, Slack, or other apps that use macOS camera inputs.
- Face remains within a configurable target region during normal seated movement.
- End-to-end perceived lag stays low enough for meetings.
- CPU usage remains acceptable on a modern Apple Silicon Mac.
- App can be installed and enabled with normal macOS extension permissions.

## Constraints

- Since the webcam has no PTZ, face centering must be digital cropping.
- A virtual camera is required for broad compatibility.
- On macOS, the virtual camera should be implemented as a Camera Extension / CoreMediaIO camera extension rather than old DAL-only plumbing. [Apple Developer][1]

---

## Proposed solution

### High-level architecture

1. **Capture service**

   - Reads frames from the Samsung monitor webcam using AVFoundation or OpenCV.
   - Locks to a chosen input mode, ideally 4K if available, so digital cropping still yields a sharp 1080p output.

2. **Tracking pipeline**

   - Runs face detection on incoming frames.
   - Tracks the primary face across frames.
   - Produces a smoothed target crop rectangle.

3. **Reframing pipeline**

   - Crops around the face with configurable headroom and shoulder room.
   - Applies motion smoothing, dead zone, and zoom limits to avoid jitter.
   - Scales output to a standard meeting resolution such as 1920x1080.

4. **Virtual camera output**

   - Publishes processed frames through a CoreMediaIO Camera Extension.
   - Meeting apps see a normal camera device like `AutoFrame Cam`.

5. **Control surface**

   - Minimal menu bar app or simple window for settings.
   - Optional CLI for power users.

---

## Recommended existing packages / frameworks

### Capture and frame processing

**AVFoundation**

- Best native macOS capture framework.
- Good fit if most of the app is Swift.
- Lets you control input camera enumeration and output formats.

**OpenCV**

- Mature, widely used capture and image-processing toolkit with `VideoCapture` and broad backend support.
- It is a good fit for prototyping and can also handle resize/crop operations. [docs.opencv.org][2]

### Face detection / tracking

**MediaPipe**

- Strong choice for real-time face detection / landmarks and cross-platform vision work.
- Google positions it as a set of reusable on-device ML/vision solutions. [Google AI for Developers][3]

For v1, I would use:

- MediaPipe face detector or face landmark task for robust face box estimation
- Plus a small custom temporal smoother

Alternative:

- Apple Vision framework can also do face detection on macOS, but since you asked for "existing packages," MediaPipe is the most package-oriented answer.

### Virtual camera output

**Core Media I/O Camera Extension**

- Apple’s official framework for software and virtual cameras on macOS.
- Apple explicitly documents creating a camera extension with Core Media I/O, and their WWDC session describes it as the modern replacement for legacy DAL plug-ins. [Apple Developer][1]

### Reference implementation

**OBS virtual camera on macOS**

- Not to embed directly as your UX, but useful as a reference for packaging, install flow, and virtual-camera behavior.
- The older standalone macOS plugin was archived after functionality moved into OBS itself. [GitHub][4]

---

## Recommended tech stack

### Best production stack

- Swift for the app shell, UI, installer flow, and Camera Extension
- AVFoundation for capture
- CoreMediaIO Camera Extension for virtual output
- MediaPipe for face detection, either via:
  - a small local service/process that returns bounding boxes, or
  - a C++ bridge if you want one-process integration

This gives the cleanest macOS product shape.

### Best fast-prototype stack

- Python
- OpenCV
- MediaPipe
- Then later replace only the output side with a Swift Camera Extension

Reason: OpenCV + MediaPipe lets you validate framing behavior quickly, while the Camera Extension is the only part that really wants to be native macOS.

---

## Functional requirements

### FR1: Camera input selection

The app must:

- list available physical cameras
- allow choosing the Samsung 5K monitor webcam
- allow selecting input resolution and frame rate where possible

### FR2: Virtual camera device

The system must expose a camera device named something like:

- `AutoFrame Cam`

Apps should be able to select it as a normal webcam. This is the purpose of the CMIO camera extension. [Apple Developer][1]

### FR3: Face centering

The system must:

- detect the dominant face in each frame
- maintain head near the horizontal center, with configurable headroom
- smoothly follow normal seated motion
- avoid overreacting to small motions

### FR4: Smart crop

The crop engine must support:

- configurable target framing presets: Tight, Medium, Wide
- minimum and maximum digital zoom
- dead zone before movement begins
- damping / smoothing factor
- optional look-ahead margin for motion

### FR5: Fallback behavior

If no face is found:

- hold last crop for N seconds
- then gradually zoom out to a default centered wide frame

### FR6: Performance

At v1 target:

- output 1080p
- target 24–30 fps
- keep processing latency low enough for live calls

### FR7: Controls

Minimal UI must provide:

- source camera picker
- output resolution picker
- framing preset
- sensitivity / smoothing slider
- start/stop virtual camera
- preview window

CLI should support:

- list cameras
- start with config
- set preset
- toggle tracking
- print stats

### FR8: Safety / privacy

- no cloud processing
- all processing local
- no frame recording by default

---

## Non-functional requirements

### Compatibility

- macOS 13+ preferred, because Apple’s modern camera-extension path is the strategic direction on newer macOS. OBS issue discussions also reflect the shift to CMIO camera extension behavior on modern systems. [Apple Developer][5]

### Reliability

- recover from camera disconnect/reconnect
- recover from app sleep/wake
- preserve selected camera if possible

### Installability

- signed app
- system extension installation flow
- clear uninstall path

This matters because macOS camera extensions are system-level components with user approval and lifecycle concerns; OBS issue discussions highlight install/uninstall considerations for the macOS virtual camera path. [GitHub][6]

---

## UX

### Minimal UI

A small app window is enough:

- left: live preview
- right: controls
- footer: status line showing input fps, output fps, face confidence, crop %

### CLI examples

```bash
autoframe-cam list-cameras
autoframe-cam start --camera "Samsung 5K Webcam" --preset medium --output 1080p
autoframe-cam set --smoothing 0.82 --deadzone 0.08
autoframe-cam stop
```

---

## Frame algorithm

### Detection

Use MediaPipe face detection each frame, or detect every few frames and track in between. MediaPipe is designed for real-time, on-device ML tasks and is a strong off-the-shelf basis for this. [Google AI for Developers][3]

### Crop logic

Given a face box:

- compute desired center as face center shifted slightly upward for headroom
- compute desired crop size based on preset and detected face size
- clamp crop within source frame bounds
- smooth crop rect over time with exponential smoothing

### Stabilization rules

- dead zone: ignore tiny motion
- max step per frame: prevent snap jumps
- confidence gating: only accept detections above threshold
- lost-face fallback: hold then widen

---

## Output formats

### Input

- Prefer 4K input when available from the monitor webcam

### Output

- 1920x1080 default
- optional 1280x720
- maybe 30 fps default

Reasoning: digital reframing works best when source resolution is materially larger than output resolution.

---

## Milestones

### Milestone 1: Prototype

Build a local preview app, no virtual camera yet.

- OpenCV/AVFoundation capture
- MediaPipe face detection
- on-screen crop preview
- tune smoothing and presets

### Milestone 2: Virtual camera MVP

- Swift app + CMIO Camera Extension
- publish reframed 1080p feed
- simple controls
- Zoom/Meet/Teams validation

### Milestone 3: Usability polish

- menu bar app
- per-camera saved presets
- better reconnect handling
- installer / uninstaller polish

---

## Risks

### Risk 1: Camera extension complexity

The hardest part is not detection; it is making a robust virtual camera that behaves well across apps. Apple’s Camera Extension framework is the official route, but it adds native macOS packaging and extension lifecycle complexity. [Apple Developer][1]

### Risk 2: Performance

Running face detection on every frame at high resolution can be expensive. Mitigation:

- downscale for detection
- detect at lower cadence
- track between detections
- output fixed 1080p

### Risk 3: Install friction

System extensions can be more finicky than regular apps, and install/uninstall flow needs care. OBS issue history is a good reminder here. [GitHub][6]

---

## Final recommendation

For your case, I would build it like this:

**v1 architecture**

- Swift macOS app
- AVFoundation capture
- MediaPipe for face box detection
- simple crop/smoothing engine
- CoreMediaIO Camera Extension virtual camera output

**prototype shortcut**

- Python + OpenCV + MediaPipe for the crop logic first
- then port only the delivery layer to Swift + CMIO Camera Extension

That is the lowest-risk path using existing packages while still landing as a real product.

I can turn this into an even more concrete engineering spec next, with module boundaries, package choices, and a 2-week implementation plan.

[1]: https://developer.apple.com/documentation/coremediaio/creating-a-camera-extension-with-core-media-i-o "Creating a camera extension with Core Media I/O"
[2]: https://docs.opencv.org/4.x/dd/d43/tutorial_py_video_display.html "Getting Started with Videos"
[3]: https://ai.google.dev/edge/mediapipe/solutions/guide "MediaPipe Solutions guide | Google AI Edge"
[4]: https://github.com/johnboiles/obs-mac-virtualcam "OBS (macOS) Virtual Camera (ARCHIVED)"
[5]: https://developer.apple.com/videos/play/wwdc2022/10022/ "Create camera extensions with Core Media IO - WWDC22"
[6]: https://github.com/obsproject/obs-studio/issues/9714 "mac-virtualcam: No easy way to uninstall system extension"

