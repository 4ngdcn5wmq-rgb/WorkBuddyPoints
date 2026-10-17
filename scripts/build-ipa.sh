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

# 每次都重新生成工程：生成器是确定性的，这样即使仓库里残留旧/坏的
# .xcodeproj（比如早期手动上传的），也绝不会被带进构建。
echo "==> 重新生成 Xcode 工程（确定性重建）"
python3 scripts/gen_xcode_project.py

# 开工前先确认工程文件是完整的，避免带着坏文件跑几分钟才发现
PBXPROJ="$PROJECT/project.pbxproj"
if [ ! -s "$PBXPROJ" ]; then
  echo "!! $PBXPROJ 不存在或为空 —— scripts/gen_xcode_project.py 可能上传不完整，"
  echo "!! 请重新完整上传该文件后重试"
  exit 1
fi
if ! head -n 1 "$PBXPROJ" | grep -q 'UTF8'; then
  echo "!! $PBXPROJ 文件头异常（应为 // !\$*UTF8*\$!），文件可能已损坏"
  exit 1
fi
if ! tail -c 2 "$PBXPROJ" | grep -q '}'; then
  echo "!! $PBXPROJ 未以 } 结尾，文件可能被截断"
  exit 1
fi
echo "==> 工程文件完好：$(wc -l < "$PBXPROJ" | tr -d ' ') 行"
echo "---- 工程文件头 3 行 ----"
head -n 3 "$PBXPROJ"
echo "---- 工程文件尾 3 行 ----"
tail -n 3 "$PBXPROJ"
echo "-----------------------"

# .xcodeproj 是 bundle：除 pbxproj 外，内置 workspace 和共享 scheme 也是
# xcodebuild -project 的必需项，缺一个就报 "Unable to read project"。
BUNDLE_FILES=(
  "$PROJECT/project.pbxproj"
  "$PROJECT/project.xcworkspace/contents.xcworkspacedata"
  "$PROJECT/xcshareddata/xcschemes/$SCHEME.xcscheme"
)
for f in "${BUNDLE_FILES[@]}"; do
  if [ ! -s "$f" ]; then
    echo "!! 工程包缺少 $f —— 请确认 scripts/gen_xcode_project.py 是完整的最新版"
    exit 1
  fi
done
echo "==> 工程包完整：pbxproj + workspace + scheme 三件套齐全"

# plutil 诊断（仅提示，不作为门槛）：
#   - pbxproj 首行 "// !$*UTF8*$!" 是 Xcode 的专属约定，CoreFoundation 老式解析器
#     不认 "//" 行注释 —— 必须剥掉首行再校验，否则误报 "Unexpected character / at line 1"。
#   - workspace / scheme 是 XML plist，可直接校验。
#   - 真正的门槛是下面的 xcodebuild -list：它用的就是 Xcode 自己的工程加载器。
if command -v plutil >/dev/null 2>&1; then
  PBX_TMP="$(mktemp)"
  tail -n +2 "$PBXPROJ" > "$PBX_TMP"
  if plutil -lint "$PBX_TMP" >/dev/null 2>&1; then
    echo "==> plutil 校验通过：pbxproj 语法合法（OpenStep plist）"
  else
    echo "!! plutil 提示 pbxproj 语法可疑（不阻断，仅供参考；报告行号 +1 = 真实行号）："
    plutil -lint "$PBX_TMP" || true
  fi
  rm -f "$PBX_TMP"
  for f in "$PROJECT/project.xcworkspace/contents.xcworkspacedata" "$PROJECT/xcshareddata/xcschemes/$SCHEME.xcscheme"; do
    if ! plutil -lint "$f" >/dev/null 2>&1; then
      echo "!! plutil 提示 $f 语法可疑（不阻断，仅供参考）："
      plutil -lint "$f" || true
    fi
  done
else
  echo "（环境无 plutil，跳过 macOS 原生校验）"
fi

# 快速预检：确认 xcodebuild 能真正读进工程、scheme 可见。
# 工程包缺文件时这里几秒内就会报错，不用等编译跑几分钟才失败。
echo "==> 预检工程可读性（xcodebuild -list）"
xcodebuild -list -project "$PROJECT" || {
  echo "!! xcodebuild 无法读取工程（详见上行输出）"
  exit 1
}

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
