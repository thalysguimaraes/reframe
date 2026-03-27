import http from 'node:http';
import { once } from 'node:events';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('../build/webrtc-harness/node_modules/playwright-core');

const cdpURL = process.env.CDP_URL ?? 'http://127.0.0.1:9333';
const durationMs = Number(process.env.DURATION_MS ?? '8000');
const targetPatterns = (process.env.TARGET_PATTERNS ?? 'reframe,autoframe cam,auto frame cam')
  .split(',')
  .map((pattern) => pattern.trim().toLowerCase())
  .filter(Boolean);

const server = http.createServer((request, response) => {
  response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
  response.end(`<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Chromium WebRTC Probe</title>
    <style>
      body { font: 14px/1.4 -apple-system, BlinkMacSystemFont, sans-serif; margin: 24px; }
      video { width: 480px; height: 270px; background: #111; display: block; }
      pre { white-space: pre-wrap; }
    </style>
  </head>
  <body>
    <h1>Chromium WebRTC Probe</h1>
    <video id="preview" autoplay playsinline muted></video>
    <pre id="status">booting...</pre>
  </body>
</html>`);
});

server.listen(0, '127.0.0.1');
await once(server, 'listening');

const address = server.address();
if (!address || typeof address === 'string') {
  throw new Error('Failed to bind local probe server.');
}

const origin = `http://127.0.0.1:${address.port}`;
const browser = await chromium.connectOverCDP(cdpURL);
const context = browser.contexts()[0];
if (!context) {
  throw new Error(`No browser context exposed by ${cdpURL}.`);
}

await context.grantPermissions(['camera'], { origin });

const page = await context.newPage();
await page.goto(origin, { waitUntil: 'domcontentloaded' });

const result = await page.evaluate(
  async ({ durationMs, targetPatterns }) => {
    const statusNode = document.getElementById('status');
    const video = document.getElementById('preview');
    if (!(video instanceof HTMLVideoElement) || !(statusNode instanceof HTMLElement)) {
      throw new Error('Probe page failed to initialize.');
    }

    const updateStatus = (message) => {
      statusNode.textContent = message;
    };

    const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
    const waitFor = async (predicate, timeoutMs, label) => {
      const start = performance.now();
      while (!predicate()) {
        if (performance.now() - start > timeoutMs) {
          throw new Error(`Timed out waiting for ${label}.`);
        }
        await sleep(50);
      }
    };

    updateStatus('requesting bootstrap camera permission');
    const bootstrapStream = await navigator.mediaDevices.getUserMedia({
      video: { width: { ideal: 160 }, height: { ideal: 120 }, frameRate: { ideal: 5, max: 5 } },
      audio: false
    });
    bootstrapStream.getTracks().forEach((track) => track.stop());
    await sleep(250);

    const devices = await navigator.mediaDevices.enumerateDevices();
    const videoInputs = devices
      .filter((device) => device.kind === 'videoinput')
      .map((device) => ({ deviceId: device.deviceId, label: device.label, groupId: device.groupId }));

    const targetDevice =
      videoInputs.find((device) => {
        const label = device.label.toLowerCase();
        return targetPatterns.some((pattern) => label.includes(pattern));
      }) ?? null;

    if (!targetDevice) {
      return {
        error: 'virtual-camera-not-found',
        videoInputs
      };
    }

    updateStatus(`opening ${targetDevice.label}`);
    const stream = await navigator.mediaDevices.getUserMedia({
      video: {
        deviceId: { exact: targetDevice.deviceId },
        width: { ideal: 1280 },
        height: { ideal: 720 },
        frameRate: { ideal: 30, max: 60 }
      },
      audio: false
    });

    video.srcObject = stream;
    await video.play();
    await waitFor(() => video.videoWidth > 0 && video.videoHeight > 0, 5000, 'video dimensions');

    const canvas = document.createElement('canvas');
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const context = canvas.getContext('2d', { willReadFrequently: true });
    if (!context) {
      throw new Error('Could not create 2D canvas context.');
    }

    const startedAt = performance.now();
    let framesReceived = 0;
    let firstFrameLatencyMs = null;
    let firstNonDarkFrameLatencyMs = null;
    let minMeanLuma = Number.POSITIVE_INFINITY;
    let maxMeanLuma = 0;
    const uniqueSignatures = new Set();

    while (performance.now() - startedAt < durationMs) {
      context.drawImage(video, 0, 0, canvas.width, canvas.height);
      const { data } = context.getImageData(0, 0, canvas.width, canvas.height);
      let lumaTotal = 0;
      let sampleCount = 0;
      let signature = 1469598103934665603n;
      const rowStride = Math.max(1, Math.floor(canvas.height / 24));
      const colStride = Math.max(1, Math.floor(canvas.width / 24));

      for (let y = 0; y < canvas.height; y += rowStride) {
        for (let x = 0; x < canvas.width; x += colStride) {
          const index = ((y * canvas.width) + x) * 4;
          const blue = data[index] / 255;
          const green = data[index + 1] / 255;
          const red = data[index + 2] / 255;
          const luma = (0.0722 * blue) + (0.7152 * green) + (0.2126 * red);
          lumaTotal += luma;
          sampleCount += 1;

          signature ^= BigInt(data[index]);
          signature *= 1099511628211n;
          signature ^= BigInt(data[index + 1]);
          signature *= 1099511628211n;
          signature ^= BigInt(data[index + 2]);
          signature *= 1099511628211n;
        }
      }

      const meanLuma = sampleCount > 0 ? lumaTotal / sampleCount : 0;
      minMeanLuma = Math.min(minMeanLuma, meanLuma);
      maxMeanLuma = Math.max(maxMeanLuma, meanLuma);
      if (uniqueSignatures.size < 128) {
        uniqueSignatures.add(signature.toString());
      }

      framesReceived += 1;
      if (firstFrameLatencyMs === null) {
        firstFrameLatencyMs = performance.now() - startedAt;
      }
      if (meanLuma > 0.03 && firstNonDarkFrameLatencyMs === null) {
        firstNonDarkFrameLatencyMs = performance.now() - startedAt;
      }

      await sleep(16);
    }

    stream.getTracks().forEach((track) => track.stop());
    updateStatus('completed');

    return {
      deviceLabel: targetDevice.label,
      deviceId: targetDevice.deviceId,
      framesReceived,
      firstFrameLatencyMs,
      firstNonDarkFrameLatencyMs,
      meanLumaRange: [minMeanLuma === Number.POSITIVE_INFINITY ? 0 : minMeanLuma, maxMeanLuma],
      uniqueFrameSignatures: uniqueSignatures.size,
      videoInputs,
      videoSize: { width: video.videoWidth, height: video.videoHeight }
    };
  },
  { durationMs, targetPatterns }
);

await page.close();
await browser.close();
server.close();

console.log(JSON.stringify(result, null, 2));
