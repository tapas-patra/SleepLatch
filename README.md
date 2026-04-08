# SleepLatch

SleepLatch is a lightweight macOS utility for controlling `caffeinate` without leaving forgotten sleep blockers behind.

Current MVP:

- Start a managed keep-awake session for `15m`, `30m`, `1h`, a custom `HH:MM` duration, or until stopped
- Toggle the core `caffeinate` flags before starting a session
- Show current managed state in the menu bar
- Stop the managed session immediately
- Detect and stop external `caffeinate` processes
- Keep managed sessions attached to the app process with native power assertions, so they do not outlive a crash or force-quit

## Run

On this machine, SwiftPM needs a writable module cache path and works best with sandboxing disabled:

```bash
zsh ./scripts/run-sleeplatch.sh
```

## Package As An App

```bash
zsh ./scripts/package-sleeplatch.sh
```

That creates:

```text
./dist/SleepLatch.app
```

The same packaging step also creates:

```text
./dist/SleepLatch.zip
```

## Prepare GitHub Pages Download

To publish a downloadable build from GitHub Pages without tracking the raw `dist/` folder in git:

```bash
zsh ./scripts/prepare-github-pages.sh
```

That updates:

```text
./docs/downloads/SleepLatch.zip
./docs/downloads/SHA256SUMS.txt
```

Then enable GitHub Pages in your repository settings and choose:

- Source: `Deploy from a branch`
- Branch: `main`
- Folder: `/docs`

## Build

```bash
HOME=/tmp/swiftpm-home CLANG_MODULE_CACHE_PATH=/tmp/swift-module-cache swift build --disable-sandbox
```

The built binary lands at:

```text
./.build/debug/SleepLatch
```

## Verify

Run the local smoke checks for session lifecycle and guardrails:

```bash
zsh ./scripts/verify-sleeplatch.sh
```

## Notes

- The app opens a small control window and also installs a menu bar icon.
- Quitting SleepLatch stops the managed session it started.
- External `caffeinate` processes are shown separately so you can clean them up without guessing PIDs.
- Untimed sessions and “stop all external sessions” both require confirmation.
- The `.app` bundle is the better launch path for normal desktop use.
