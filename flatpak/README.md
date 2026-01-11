# AgeLapse Flatpak Packaging

This directory contains everything needed to build and publish AgeLapse as a Flatpak.

## Prerequisites (on Linux)

```bash
# Install Flatpak and flatpak-builder
sudo apt install flatpak flatpak-builder

# Add Flathub repo
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Install the SDK and runtime
flatpak install flathub org.freedesktop.Platform//24.08 org.freedesktop.Sdk//24.08

# Install the FFmpeg extension
flatpak install flathub org.freedesktop.Platform.ffmpeg-full//24.08
```

## Building

### Step 1: Build the Flutter app

```bash
cd /path/to/agelapse
flutter build linux --release
```

### Step 2: Copy the bundle to flatpak directory

```bash
cp -r build/linux/x64/release/bundle flatpak/bundle
```

### Step 3: Build the Flatpak

```bash
cd flatpak

# Build (first time takes a while, downloads dependencies)
flatpak-builder --force-clean build-dir com.hugocornellier.agelapse.yaml

# Or with ccache for faster rebuilds:
flatpak-builder --force-clean --ccache build-dir com.hugocornellier.agelapse.yaml
```

### Step 4: Test locally

```bash
# Run directly from build directory
flatpak-builder --run build-dir com.hugocornellier.agelapse.yaml agelapse

# Or install locally for full testing
flatpak-builder --user --install --force-clean build-dir com.hugocornellier.agelapse.yaml
flatpak run com.hugocornellier.agelapse
```

### Step 5: Create distributable bundle (optional)

```bash
# Create a repo
flatpak-builder --repo=repo --force-clean build-dir com.hugocornellier.agelapse.yaml

# Create a single-file bundle
flatpak build-bundle repo agelapse.flatpak com.hugocornellier.agelapse
```

## Publishing to Flathub

1. Fork https://github.com/flathub/flathub
2. Create a new branch
3. Copy `com.hugocornellier.agelapse.yaml` to the repo root
4. Modify paths to use git sources instead of local files
5. Submit a Pull Request
6. Wait for review (typically 1-2 weeks)

### Flathub-specific manifest changes

For Flathub submission, the manifest needs to fetch sources from git/URLs instead of local paths:

```yaml
sources:
  # Replace local bundle with a release tarball or git archive
  - type: archive
    url: https://github.com/hugocornellier/agelapse/releases/download/v2.2.1/agelapse-linux-bundle.tar.gz
    sha256: <calculate-after-upload>
```

## Files in this directory

- `com.hugocornellier.agelapse.yaml` - Main Flatpak manifest
- `com.hugocornellier.agelapse.desktop` - Desktop entry file
- `com.hugocornellier.agelapse.metainfo.xml` - AppStream metadata (for software centers)
- `agelapse.sh` - Wrapper script that sets up FFmpeg paths
- `icons/` - Application icons (128x128, 256x256)
- `bundle/` - Flutter build output (created by build script)

## Testing checklist

- [ ] App launches
- [ ] Camera works (requires real webcam)
- [ ] Can import photos from ~/Pictures
- [ ] Can export video to ~/Downloads
- [ ] FFmpeg encoding works (check logs)
- [ ] HEIC import works
- [ ] Notifications work
- [ ] File picker works

## Troubleshooting

### FFmpeg not found
The FFmpeg extension should be automatically mounted at `/app/lib/ffmpeg`. Check:
```bash
flatpak run --command=ls com.hugocornellier.agelapse /app/lib/ffmpeg/bin/
```

### Permission denied errors
Check that the manifest has the required permissions:
- `--filesystem=xdg-download:rw` for Downloads
- `--device=all` for camera
- `--filesystem=home:ro` for importing photos

### Check app logs
```bash
flatpak run com.hugocornellier.agelapse 2>&1 | tee agelapse.log
```
