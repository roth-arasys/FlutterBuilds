# FlutterBuilds

> ⚠️ **Maintenance Status**: *This project is provided as-is as a community utility and is not actively maintained. Issues are disabled on this repository.*

`FlutterBuilds` is a lightweight macOS utility and build pipeline that resolves iOS/macOS build failures for Flutter projects hosted within cloud-synchronized directories (such as Microsoft OneDrive via the macOS FileProvider framework).

---

## The Problem

### Root Cause: FileProvider Metadata & `codesign` Rejection
When a Flutter project is located in a folder managed by macOS FileProvider (e.g. OneDrive), the sync engine automatically attaches extended file attributes and metadata (such as `com.apple.FinderInfo` or resource forks) to newly created build artifacts inside the `build/` directory.

During iOS code signing, `codesign` rejects `Flutter.framework` and app binaries with the error:
```
resource fork, Finder information, or similar detritus not allowed
```

### Misleading Error Output
Flutter CLI and Xcode hide this root cause behind an opaque generic status code:
```
Uncategorized (Xcode): Exited with status code 255
```
This happens because the failure occurs in an Xcode scheme pre-action script, which is not captured in standard `.xcresult` bundle logs.

### How to Diagnose
To expose the true `codesign` error, execute the build command with verbose logging enabled:
```bash
flutter build ios --simulator -v
```

For further context, see [flutter/flutter#123583](https://github.com/flutter/flutter/issues/123583).

---

## The Solution: APFS Volume Mounts

`FlutterBuilds` mounts an individual APFS volume onto each discovered project's `build/` directory. All volumes live inside a single APFS container stored within a single Sparse Bundle Image in `~/Library/Application Support/FlutterBuilds/FlutterBuilds.sparsebundle`. This allows all project volumes to dynamically share disk space.

### Why Mounts are Superior to Symlinks

1. **Immunity to `flutter clean`**: Running `flutter clean` attempts to wipe the `build/` directory. When `build/` is an active APFS mount point, `rm -rf` fails with `EBUSY`, keeping the mount intact. A symlink would be permanently deleted by `flutter clean`.
2. **Sync Client Isolation**: The OneDrive / FileProvider sync client does not traverse external volume mount points, preventing metadata detritus from ever being written to build outputs.
3. **Zero In-Project Configuration**: No modifications or symlink files are required inside your git repositories.

---

## Architectural & Safety Invariants

- **Payload Outside Bundle**: Application state, logs, and the Sparse Bundle Image live strictly in `~/Library/Application Support/FlutterBuilds/`. Writing inside the `.app` bundle invalidates the ad-hoc code signature and breaks TCC (Full Disk Access) permissions tied to code identity.
- **Deterministic Volume Names**: Volume names are derived from project paths relative to `~/Library/CloudStorage` (slashes replaced with `_`, suffixed with `-build`). This guarantees unique volume names across multiple cloud accounts without requiring a central database.
- **Unmounted Purge Guard**: Cleaning shadowed cloud files (`purge_shadowed`) only occurs when volumes are unmounted. Executing a purge while mounted would erase active volume contents instead of stale cloud leftovers.
- **Boot-Time Compaction**: Sparse Bundle Images only shrink when completely detached. `FlutterBuilds` compacts the image automatically during system startup (`boot` mode).
- **Empty-Discovery Safety Guard**: Obsolete volume cleanup (`drop_obsolete`) is aborted if no projects are discovered. This protects against accidental volume deletion in case of TCC denials or OneDrive sync delays.

---

## Automatic OneDrive Discovery & Configuration

By default, `FlutterBuilds` automatically discovers any OneDrive directory located in `~/Library/CloudStorage/` (e.g. `OneDrive-Personal`, `OneDrive-Shared`, or enterprise accounts).

If you wish to specify custom directory paths manually, set the `FLUTTERBUILDS_CLOUD_DIR` environment variable. Multiple paths can be passed separated by colons (`:`):
```bash
export FLUTTERBUILDS_CLOUD_DIR="$HOME/MyCloudStorage/FlutterProjects:$HOME/SecondaryCloud/Projects"
```

---

## Required macOS Permissions (Full Disk Access)

Because `FlutterBuilds` scans your cloud storage folder and mounts APFS volumes, you must grant `FlutterBuilds.app` Full Disk Access:

1. Open **System Settings** > **Privacy & Security** > **Full Disk Access**.
2. Add and enable **`FlutterBuilds.app`** (located in `~/Applications/`).

---

## Repository Structure

```
flutterbuilds/
├── README.md                # Primary documentation (English)
├── README-DE.md             # Documentation (German)
├── Makefile                 # Build, install, uninstall, sign, verify, clean
├── src/
│   ├── mount.sh             # Mount orchestration script (zsh)
│   └── main.applescript     # UI wrapper source (AppleScript)
├── assets/
│   └── app_icon_1024.png    # Master 1024x1024 icon PNG
├── scripts/
│   ├── build.sh             # Compiles FlutterBuilds.app into ./build/
│   ├── install.sh           # Installs to ~/Applications and sets Login Item
│   └── make-icns.sh         # Generates applet.icns (10 icon sizes)
└── .gitignore               # Excludes build/, *.icns, .DS_Store
```

---

## Usage & Development Commands

### Building and Verifying

```bash
# Build app in ./build/FlutterBuilds.app
make build

# Run automated integrity & signature checks
make verify
```

### Installation & Uninstallation

```bash
# Install to ~/Applications/ and register Login Item (does NOT touch existing user data)
make install

# Uninstall app and remove Login Item
make uninstall
```

### Script Modes (`src/mount.sh`)

- **`mount.sh boot`**: Runs during login. Compacts the sparse bundle image (if detached) and mounts all project volumes.
- **`mount.sh mount`**: Discovers Flutter projects and mounts APFS volumes (idempotent).
- **`mount.sh unmount`**: Safely unmounts all active project volumes.
- **`mount.sh clean`**: Unmounts, drops obsolete volumes, purges shadowed cloud leftovers, compacts the image, and remounts.

---

## Trademark & Legal Disclaimer

*Flutter and the Flutter logo are trademarks of Google LLC. FlutterBuilds is an independent open-source community project and is not affiliated with, sponsored by, or endorsed by Google LLC.*
