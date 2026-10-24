# Clicker, working notes

Remote for Samsung Tizen TVs: an iPhone app (iOS 17+) and a Mac menu bar app (macOS 14+) from one
set of SwiftUI sources, no packages. Read `README.md` for the protocol summary.

## Layout

- `Clicker/App`: `ClickerApp` (iOS entry), `ClickerMacApp` (menu bar entry, Settings scene, Debug render
  to PNG) and `AppModel` (saved TVs, selection, power state, monitor loop, power-on sequence, Debug seeding).
- `Clicker/Samsung`: `SamsungRemote` (WebSocket channel: pair, keys, text, apps), `TVDiscovery`
  (Bonjour `_airplay._tcp` plus the `:8001/api/v2/` check), `TV.swift` (models, status fetch),
  `RemoteKey` (key codes), `WakeOnLAN`.
- `Clicker/HomeAssistant`: optional power fallback through any turn-on-able entity.
- `Clicker/UI`: `RemoteView` (the one screen; keyboard handling on macOS), `DPadView` and `RockerView`,
  `HoldButton` (touch-down firing with hold-to-repeat), sheets (numbers, keyboard, apps), `SettingsView`
  (TVs, add/discover, Home Assistant), `Platform.swift` (the few iOS/macOS differences and the panel
  presenter: a sheet on iOS, an overlay in the popover on macOS).
- `Clicker/Support`: `Keychain`, `Haptics`.

## Rules

- The project file is generated: edit `project.yml`, run `xcodegen generate`, never hand-edit
  `Clicker.xcodeproj` (it is git-ignored).
- Secrets never go in source or git. Pairing tokens live in the Keychain; Debug seeds live in
  `Local.xcconfig` (git-ignored, written by `scripts/seed.py`). Signing (team ID, bundle ID) lives in
  `Signing.xcconfig` (git-ignored). Both are read through `Config/Debug.xcconfig` and `Config/Release.xcconfig`;
  Release never reads `Local.xcconfig`.
- The repo is public (github.com/dcwfz9/clicker). Nothing from a particular home goes in tracked files:
  no LAN addresses, MACs, device IDs, entity names or personal paths.
- xcconfig starts a comment at `//`, so a URL like `http://host` arrives as `http:`. `seed.py` writes
  `//` as `/$()/`; do the same when editing `Local.xcconfig` by hand. Builds seeded with `--ha-config`
  embed the Home Assistant token: never share them. Shared builds are seeded with the TV only.
- Keys fire on touch-down. Keep the remote feeling instant; no confirmations, no spinners on keys.
- One screen, no scrolling. Anything rarer than volume, channel, navigation and power goes in a sheet.
- The UI follows the system appearance and is designed dark-first (slate, no strong hues, see
  `Resources/Assets.xcassets`).
- Simulator builds must be signed for local run (the default). `CODE_SIGNING_ALLOWED=NO` breaks the
  Keychain in the simulator, which looks like "pairing again".
- Mac Debug builds are ad-hoc signed and sandboxed (`network.client`). macOS asks for Local Network
  access on first launch; until the user allows it, every request to the TV just hangs, with no error.
- Debug-only hooks: `-ClickerTestKeys KEY_MUTE` presses keys after connecting (both platforms);
  `-ClickerRenderTo <path>.png` (Mac) writes dark and light renders of the remote. A sandboxed app can
  only write inside its container, e.g. `~/Library/Containers/derekwelty.clicker/Data/tmp/`.
- `debugLog` writes to stderr in Debug builds; run the Mac binary directly from a shell to see it.

## Testing against a real TV

- `curl http://<tv>:8001/api/v2/` shows name, model, MAC, `PowerState` (`on` or `standby`).
- `GET /api/v2/applications/<appId>` is read-only and does not wake anything.
- Every unpaired WebSocket connection pops a 30 s prompt on the TV. Do not loop on it while someone is
  watching unless they are the one trying to accept it.
- The TV's `ed.installedApp.get` has not answered on the QN65Q80D (2024); the app falls back to
  `TVApp.common`.
