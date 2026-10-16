# WorkBuddyPoints 常用命令（需要 macOS + Xcode）
#
#   make icon      重新生成 App 图标（需 Pillow：python3 -m pip install Pillow）
#   make project   生成 WorkBuddyPoints.xcodeproj（任何平台都能跑）
#   make ipa       编译并打包未签名 IPA 到 build/WorkBuddyPoints-unsigned.ipa
#   make open      用 Xcode 打开工程
#   make clean     清理构建产物

PROJECT := WorkBuddyPoints.xcodeproj
IPA := build/WorkBuddyPoints-unsigned.ipa

.PHONY: icon project build ipa open clean

icon:
	python3 scripts/make_icon.py

project:
	python3 scripts/gen_xcode_project.py

build: project
	bash scripts/build-ipa.sh

ipa: build
	@echo "未签名 IPA：$(CURDIR)/$(IPA)"

open: project
	open $(PROJECT)

clean:
	rm -rf build DerivedData
