#!/usr/bin/env bash
# 在 macOS 上编译并打包「未签名 IPA」。
# 用法：bash scripts/build-ipa.sh
# 注意：不启用 set -u —— CI 环境里可选变量未定义时不应直接中断。
set -eo pipefail
cd "$(dirname "$0")/.."

PROJECT="WorkBuddyPoints.xcodeproj"
SCHEME="WorkBuddyPoints"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/WorkBuddyPoints.xcarchive"
IPA_NAME="WorkBuddyPoints-unsigned.ipa"

if [ ! -d "$PROJECT" ]; then
  echo "==> 未找到 $PROJECT，先生成工程"
  python3 scripts/gen_xcode_project.py
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> 编译（$CONFIGURATION，generic/platform=iOS，跳过签名）"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  -hideShellScriptEnvironment || {
    echo "!! xcodebuild archive 失败，请向上查看日志"
    exit 1
  }

APP_PATH="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' | head -n 1)"
if [ -z "$APP_PATH" ]; then
  echo "!! 归档里没有找到 .app：$ARCHIVE_PATH/Products/Applications"
  exit 1
fi

echo "==> 组装未签名 IPA：$APP_PATH"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"
( cd "$BUILD_DIR" && zip -qry "$IPA_NAME" Payload )

echo "==> 完成：$(pwd)/$BUILD_DIR/$IPA_NAME"
ls -la "$BUILD_DIR/$IPA_NAME"
