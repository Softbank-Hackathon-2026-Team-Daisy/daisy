#!/usr/bin/env bash
# Mac 앱 DMG 한 번에 (웹 W-14 "Mac 앱 받기"용): 테스트 → 아카이브 → Developer ID 서명 · Apple 공증 → 스테이플 → DMG.
#   ./scripts/mac-dmg.sh                       새로 아카이브해서 만들기
#   ARCHIVE=build/archives/X.xcarchive ./scripts/mac-dmg.sh   이미 있는 macOS 아카이브로 만들기
#   SKIP_TESTS=1 ./scripts/mac-dmg.sh
# 서명 · 공증은 Xcode에 로그인된 계정(팀 X5F5WM2H6M)으로 해요. 비밀번호 · API 키는 쓰지 않아요.
set -euo pipefail

cd "$(dirname "$0")/.."
TEAM_ID="X5F5WM2H6M"
BUILD_NUMBER="$(date +%y%m%d%H%M)"
ARCHIVE="${ARCHIVE:-build/archives/Daisy-macos-${BUILD_NUMBER}.xcarchive}"

if [[ ! -d "$ARCHIVE" ]]; then
  if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
    echo "▶ 테스트"
    xcodebuild test -project Daisy.xcodeproj -scheme Daisy -destination 'platform=macOS' -quiet
  fi
  echo "▶ 아카이브 (macOS, 빌드 $BUILD_NUMBER)"
  xcodebuild archive -project Daisy.xcodeproj -scheme Daisy -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" -allowProvisioningUpdates -quiet
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$ARCHIVE/Info.plist")"
OPTIONS="build/ExportOptions-developer-id.plist"
cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>developer-id</string>
	<key>destination</key><string>upload</string>
	<key>signingStyle</key><string>automatic</string>
	<key>teamID</key><string>${TEAM_ID}</string>
</dict>
</plist>
PLIST

echo "▶ Developer ID 서명 · 공증 제출"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" \
  -exportPath build/export-devid -allowProvisioningUpdates -quiet

echo "▶ 공증 기다리는 중 (보통 1~10분)"
rm -rf build/notarized
for i in $(seq 1 40); do
  if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath build/notarized >/dev/null 2>&1; then
    break
  fi
  [[ $i -eq 40 ]] && { echo "공증이 20분 안에 끝나지 않았어요. Xcode Organizer에서 상태를 확인해 주세요." >&2; exit 1; }
  sleep 30
done
APP="build/notarized/Daisy.app"

echo "▶ 검증"
codesign --verify --deep --strict "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute "$APP"

echo "▶ DMG"
DMG="build/Daisy-${VERSION}-${BUILD}.dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Daisy" -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGE"

echo "✅ $DMG ($(du -h "$DMG" | cut -f1), sha256 $(shasum -a 256 "$DMG" | cut -d' ' -f1))"
echo "   앱은 Developer ID 서명 + Apple 공증 + 스테이플 완료. 다운로드한 Mac에서 경고 없이 열려요."
