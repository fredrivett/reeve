# reeve

A macOS menu bar app for monitoring and managing [PM2](https://pm2.keymetrics.io/) processes.

## Features

- 📊 **Monitor processes** — view real-time status, CPU, memory, uptime, and ports for all PM2 processes
- 🎛️ **Manage processes** — restart, stop, or delete individual processes directly from the menu bar
- 🗂️ **Multiple environments** — automatically discovers all PM2 workspaces (`~/.pm2`, `~/.pm2-*`)
- 🔁 **Crash-loop detection** — flags processes that are rapidly restarting and provides debug info
- 🪵 **Live log streaming** — view process logs in real-time with ANSI color stripping
- 🔔 **Desktop notifications** — get alerted when processes crash or restart

## Requirements

- macOS 13+
- Swift 5.9
- [PM2](https://pm2.keymetrics.io/) installed globally (`npm install -g pm2`)

## Getting started

```bash
# Build
swift build

# Run
swift run reeve

# Test
swift test
```

The app runs as a menu bar accessory (no Dock icon). It polls PM2 for process status every 3 seconds by default.

## Configuration

Config is stored at `~/.config/reeve/config.json`:

- `pollIntervalSeconds` — refresh interval for process status (default: `3.0`)
- `collapsedEnvironments` — which environment groups are collapsed in the UI

## Project structure

```
Sources/
├── ReeveApp/          # App entry point, menu bar setup
└── Reeve/             # Main library
    ├── Models/        # PM2Process, PM2Environment, AppConfig
    ├── Services/      # PM2Service, EnvironmentScanner, ConfigService, NotificationService
    └── Views/         # SwiftUI views (ContentView, ProcessRowView, LogPanelView, etc.)
Tests/
└── reeveTests/        # Test suite
```
