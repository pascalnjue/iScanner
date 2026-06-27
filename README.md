# iScanner

A fast, native iOS barcode and QR code scanner that can send scanned text
directly to your Mac — acting like a wireless keyboard.

Scan a code on your phone, and the text appears in whatever field is focused
on your Mac. No cloud, no accounts, just your local WiFi.

## Features

- **All major barcode types** — QR, EAN-8/13, UPC-E, Code 39/93/128, PDF417,
  Aztec, Data Matrix, Interleaved 2 of 5, ITF-14
- **Live camera preview** with real-time scanning
- **Scan history** with copy-to-clipboard per item
- **Send to Computer** — types scanned text into the focused input field on
  your Mac over local WiFi (see Companion below)
- **Scan deduplication** — 2-second cooldown prevents repeat captures
- **Zero cloud dependencies** — everything stays on your local network

## Requirements

- iOS 27.0+ (built with Xcode 26 beta)
- iPhone or iPad with a camera

## Setup

1. Clone the repo
2. Open `iScanner.xcodeproj` in Xcode
3. Select your development team under Signing & Capabilities
4. Build and run on your device

## Companion (Mac)

The companion is a tiny Python HTTP server that receives scanned text from
the iOS app and types it into the focused field on your Mac.

### Start the companion

```bash
python3 Companion/scanner_companion.py
```

It prints the IP address to use. Enter that IP in the iScanner app's
Settings (gear icon in the top-right).

### First-run permissions

On first use, macOS will ask for Accessibility permission so the companion
can simulate keystrokes. Grant it once and you're set.

**No external dependencies** — uses only Python's standard library and
AppleScript.

## How it works

```
┌──────────┐    HTTP POST     ┌──────────────┐    AppleScript     ┌──────────┐
│  iPhone  │ ───────────────→ │  Companion   │ ────────────────→ │   Mac    │
│  Scan    │   {"text":"..."} │  (Python)    │   keystroke(...)  │  Input   │
└──────────┘                  └──────────────┘                   └──────────┘
```

## Project structure

```
iScanner/
├── iScanner.xcodeproj/        # Xcode project
├── iScanner/                  # App source
│   ├── iScannerApp.swift      # @main entry point
│   ├── ContentView.swift      # Root view
│   ├── ScannerView.swift      # Main scanning UI
│   ├── ScannerViewModel.swift # Camera + barcode detection
│   └── CameraPreview.swift    # UIViewRepresentable for camera
└── Companion/                 # Mac keyboard companion
    └── scanner_companion.py   # HTTP server + AppleScript keystrokes
```

## License

MIT
