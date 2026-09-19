# RetroDashboard
macOS native dashboard written in Swift + AppKit, no Xcode required.

## Run
Run these commands from the project folder:
```bash
killall -9 RetroDashboard 2>/dev/null || true
swift run
```

The app has no normal document window. Press `Option + Space` to show or hide the dashboard, and `Esc` to close it.

## Develop
Requirement：Only Command Line Tools（No Xcode）
```bash
# run directly
swift run

# debug with VSCode(F5)
# build release binary
swift build -c release