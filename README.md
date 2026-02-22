# LoginShot

LoginShot is a macOS background agent that captures a webcam snapshot when your **user session opens** (agent starts after login) and when the session is **unlocked**, then stores the image (plus metadata) into a configurable local folder (e.g. Dropbox/Google Drive sync folder) so you keep an audit trail of who used the machine.

> **Privacy notice**
> This tool records images from your Mac’s camera. Use it only on devices you own/administer, and only in compliance with applicable laws and policies. In many places you must disclose camera-based monitoring.

## v1 Scope

### Included
- macOS agent app (no Dock icon)
- Triggers:
  - **session-open** (agent start after user login)
  - **unlock** (session becomes active/unlocked)
- One-shot snapshot using AVFoundation
- Store image + sidecar metadata file (JSON)
- YAML configuration file
- Optional menu bar icon (can be disabled by config)

### Not included (for now)
- Cloud upload via Dropbox/Google Drive APIs
- Face recognition / “is this me?” alerts
- Notarization / signing (future)
- Retention policy (no deletion)

## Requirements
- macOS 13+ recommended
- Xcode 15+ recommended
- Camera permission granted to the app (macOS will prompt at first run)

## Installation (developer mode)

1. Clone:
   ```bash
   git clone https://github.com/pruiz/LoginShot.git
   cd LoginShot
   ```

2. Open in Xcode once the project exists (`LoginShot.xcodeproj`).

3. Build & run once from Xcode:
   - macOS will request Camera permission.
   - Grant it when prompted.

4. Create a config file (see Configuration below).

5. Enable autostart on login:
   - **Planned for v1:** a LaunchAgent plist installer in this repo.
   - During development, you can run from Xcode or manually launch the built app.

## Configuration (YAML)

LoginShot reads configuration from (first found wins):

1. `~/.config/LoginShot/config.yml`
2. `~/Library/Application Support/LoginShot/config.yml`

### YAML example
```yaml
output:
  directory: "~/Library/CloudStorage/Dropbox/LoginShot"
  format: "jpg"          # v1: "jpg" only (future: "heic")
  maxWidth: 1280         # 0 or null = keep original size
  jpegQuality: 0.85      # 0.0 - 1.0

triggers:
  onSessionOpen: true    # agent start after login
  onUnlock: true

metadata:
  writeSidecar: true     # write a .json next to each image

ui:
  menuBarIcon: true      # can be disabled for headless mode

capture:
  silent: true           # suppress simulated shutter sound
  debounceSeconds: 3
```

## Output files

Images are saved with a timestamp and event tag:

- `2026-02-22T00-15-03-session-open.jpg`
- `2026-02-22T08-41-10-unlock.jpg`

If enabled, a sidecar metadata JSON is also written:

- `2026-02-22T08-41-10-unlock.json`

### Sidecar JSON schema (draft)
```json
{
  "timestamp": "2026-02-22T08:41:10.123Z",
  "event": "unlock",
  "hostname": "MBP-Pablo",
  "username": "pablo",
  "outputPath": "/Users/pablo/Library/CloudStorage/Dropbox/LoginShot/2026-02-22T08-41-10-unlock.jpg",
  "app": {
    "bundleId": "dev.pruiz.LoginShot",
    "version": "0.1.0",
    "build": "1"
  },
  "camera": {
    "deviceName": "FaceTime HD Camera",
    "position": "front"
  }
}
```

## Troubleshooting
- **No camera prompt / capture fails**
  - System Settings → Privacy & Security → Camera → enable LoginShot.
- **Unlock capture doesn’t trigger**
  - Unlock signals vary by macOS version. We may combine NSWorkspace + distributed notifications to make this robust.
- **Cloud folder path**
  - Prefer the real local sync path (e.g. `~/Library/CloudStorage/...`) over symlinks.

## Roadmap
- v1: local snapshots (session-open + unlock), YAML config, sidecar JSON metadata, optional menu bar icon
- v1.1: LaunchAgent installer script + sample config generator
- v2: optional Dropbox/Drive API upload
- v3: optional collector service
- v4: optional face verification + alerting

## Security notes
- v1 is local-only (no network required).
- Consider encrypting your disk or the target folder if images are sensitive.

## License
[MIT](LICENSE)
