#!/bin/bash
# Build TokenBar.app (arm64, ad-hoc signature), TokenBar.zip and SHA256SUMS (TRD Section 13).
# Usage: scripts/build-app.sh [version]. The default version is the latest git tag.
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:-$(git describe --tags --abbrev=0 2>/dev/null || echo 0.0.0)}"
version="${version#v}"

swift build -c release --arch arm64
bin="$(swift build -c release --arch arm64 --show-bin-path)"

app=TokenBar.app
rm -rf "$app" TokenBar.zip SHA256SUMS
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/TokenBar" "$app/Contents/MacOS/"
# Other tasks add resources later. The bundle does not exist before that.
if [ -d "$bin/TokenBar_TokenBar.bundle" ]; then
    cp -R "$bin/TokenBar_TokenBar.bundle" "$app/Contents/Resources/"
fi

cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>TokenBar</string>
    <key>CFBundleIdentifier</key><string>com.patronofalltrades.TokenBar</string>
    <key>CFBundleName</key><string>TokenBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>${version%%-*}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
plutil -lint "$app/Contents/Info.plist"

# One executable, so no --deep (TRD Section 13, step 3).
codesign --force --sign - "$app"
codesign --verify --strict --verbose=2 "$app"

ditto -c -k --keepParent "$app" TokenBar.zip
shasum -a 256 TokenBar.zip > SHA256SUMS
cat SHA256SUMS
