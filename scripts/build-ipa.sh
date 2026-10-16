#!/usr/bin/env bash
# 在 macOS 上编译并打包「未签名 IPA」。
# 用法：bash scripts/build-ipa.sh        （需先运行 python3 scripts/gen_xcode_project.py）
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="WorkBuddyPoints.xcodeproj"
SCHEME="WorkBuddyPoints"
CONFIGURATION="${CONFIGURATION:-Release}"   # 可用环境变量覆盖（CI 里用）
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/WorkBuddyPoints.xcarchive"
IPA_NAME="WorkBuddyPoints-unsigned.ipa"
IPA_PATH="$BUILD_DIR/$IPA_NAME"

if [[ ! -d "$PROJECT" ]]; then
  echo "==> 未找到 $PROJECT，先运行：python3 scripts/gen_xcode_project.py"
  python3 scripts/gen_xcode_project.py
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> 编译（$CONFIGURATION，generic/platform=iOS，跳过签名）"
set +e
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  -quiet
STATUS=$?
set -e
if [[ $STATUS -ne 0 ]]; then
  echo "!! xcodebuild 失败（exit $STATUS），重跑一次带完整日志以便排错："
  xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=""
  exit $STATUS
fi

APP_PATH="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name "*.app" | head -n 1)"
if [[ -z "$APP_PATH" ]]; then
  echo "!! 归档里没有找到 .app"
  exit 1
fi

echo "==> 组装未签名 IPA：$APP_PATH"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"
( cd "$BUILD_DIR" && zip -qry "$IPA_NAME" Payload )

echo "==> 完成：$(pwd)/$IPA_PATH"
unzip -l "$IPA_PATH" | tail -n 3
