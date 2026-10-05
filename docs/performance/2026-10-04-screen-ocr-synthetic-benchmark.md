# Screen OCR synthetic benchmark

Date: 2026-10-04

## Setup

- No desktop screenshot was captured. The benchmark rendered synthetic Japanese, Simplified Chinese, Traditional Chinese, and Korean lines into a Core Graphics image.
- Image size was 1814 × 1178 pixels, matching the current display's 1512 × 982 point frame at 2× scale with the app's 0.6 screen capture scale.
- Vision used accurate recognition, language correction, automatic language detection, and the same preferred OCR languages as the app.
- The image contained 34 text lines. Measurements below used an optimized native benchmark build after the first Vision warm-up run.

## Results

| Operation | Median | Samples |
| --- | ---: | --- |
| Image normalization copy | 1.00 ms | 8 |
| 512 × 288 frame fingerprint | 1.40 ms | 8 |
| Vision accurate OCR | 489.72 ms | 4 |

Vision returned 34 text observations in each measured run. One earlier cold run had a 29.6 second first OCR call followed by approximately 0.5 second calls; that startup outlier did not repeat in the subsequent process run, so it needs a separate cold-start investigation before drawing a conclusion.

## Decision

- Keep the image normalization path unchanged: its measured cost is about 0.2% of warm OCR time.
- Keep the reduced frame fingerprint check: it costs about 1.4 ms and lets the screen mode skip a roughly 490 ms Vision request when the sampled frame is identical.
- The benchmark does not measure ScreenCaptureKit latency or OCR on real text layouts. In the screen mode, the app now reports average and maximum full-display capture latency in groups of ten frames, reports normalization and Vision latency at the info level, and reports a summary after every ten unchanged-frame OCR skips. A real-mode sample is still pending.
- Screen mode removes same-language, same-text OCR observations when their boxes overlap by at least 72% of the smaller box, preventing duplicate patches for a single visible block while preserving separate repeated occurrences.
- The screen loop polls every 180 ms. Between full OCR passes, Vision's `VNTrackObjectRequest` updates recognized block positions and sizes from captured frames. Text recognition is refreshed after four seconds, on display changes, or immediately when tracking confidence is lost. Tracked font size follows the observed box height; OCR remains the source of text and language decisions.
- Tracking is capped at 64 blocks per frame. Screen resizing and real applications have not been exercised by this agent; the feature must be visually checked in the app before relying on tracking accuracy.
- The in-memory translation cache now lasts 15 minutes, survives screen-mode stop/start, and holds at most 2,000 entries. Japanese and Chinese keys ignore OCR-inserted whitespace and punctuation; Korean keys collapse whitespace and punctuation. The overlay keeps its hosting view and avoids rewriting unchanged attributed text while blocks move.
