#!/usr/bin/env bash
# TestFlight 업로드 한 번에: 테스트 → 아카이브 → App Store Connect 업로드.
#   ./scripts/testflight.sh            iOS
#   ./scripts/testflight.sh macos      macOS (App Store Connect 앱에 macOS 플랫폼을 먼저 추가해야 해요)
#   SKIP_TESTS=1 ./scripts/testflight.sh
# 서명은 Xcode에 로그인된 계정의 자동 서명을 써요. 비밀값은 이 스크립트에 넣지 않아요.
set -euo pipefail

cd "$(dirname "$0")/.."
PLATFORM="${1:-ios}"
case "$PLATFORM" in
  ios)   DESTINATION="generic/platform=iOS" ;;
  macos) DESTINATION="generic/platform=macOS" ;;
  *) echo "사용법: $0 [ios|macos]" >&2; exit 2 ;;
esac

# 빌드 번호는 올라가기만 해야 해요. 브랜치 · 스쿼시 머지와 상관없이 늘어나게 시각(yyMMddHHmm)을 써요.
BUILD_NUMBER="$(date +%y%m%d%H%M)"
ARCHIVE="build/archives/Daisy-${PLATFORM}-${BUILD_NUMBER}.xcarchive"
EXPORT_OPTIONS="build/ExportOptions-testflight.plist"

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  echo "▶ 테스트"
  xcodebuild test -project Daisy.xcodeproj -scheme Daisy -destination 'platform=macOS' -quiet
fi

echo "▶ 아카이브 ($PLATFORM, 빌드 $BUILD_NUMBER)"
xcodebuild archive -project Daisy.xcodeproj -scheme Daisy -configuration Release \
  -destination "$DESTINATION" -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" -allowProvisioningUpdates -quiet

cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>upload</string>
	<key>signingStyle</key><string>automatic</string>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "▶ 업로드"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "build/export-${PLATFORM}" -allowProvisioningUpdates

echo "✅ 업로드 완료: $(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE/Info.plist") ($BUILD_NUMBER). App Store Connect 처리에 10~30분 걸려요."
