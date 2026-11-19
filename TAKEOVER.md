# TAKEOVER: Startup (Mantra)

## What this repository is
"Startup (Mantra)" is a native Swift macOS utility that manages login/boot startup choice between two voice applications:
1. Voice to Text (Mantra) (`com.mantra.voicetotext`)
2. Speechify (`com.cliffweitzman.speechifymacagent`)

## Public repository notice
Under the Mantra manifest guidelines, public repositories are not promoted externally; this document explains the purpose, architecture, and deployment procedures.

## Behavior
- Registers as a login item via `SMAppService.mainApp.register()`.
- On launch and on toggle change:
  - If the other app is running, terminates it (attempting `terminate()`, then `forceTerminate()` after 2s).
  - If the chosen app is not running, launches it via `NSWorkspace.openApplication`.
  - Leaves the chosen app untouched if already running.
  - If chosen app is not installed, displays a prominent status warning and does not crash.
- Closing the window quits the application (`NSApp.terminate`). No ON/OFF button.
- Title appears only once on the window titlebar.
- Window position autosaved with `setFrameAutosaveName`.

## Architecture & Build
- Pure Swift, swiftc via `build.sh`.
- Compiled and released strictly on GitHub Actions (`macos-15`). No local compilation.

## Follow-up
- Updater kit integration (kits/mac-updater).
