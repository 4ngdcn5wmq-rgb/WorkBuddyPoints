#!/usr/bin/env python3
"""生成完整的 WorkBuddyPoints.xcodeproj 工程包（不依赖 XcodeGen / macOS）。

产出三件套（缺任何一件，xcodebuild 都会判工程损坏、拒绝读取）：
    - project.pbxproj                                工程主体
    - project.xcworkspace/contents.xcworkspacedata    -project 构建的必需文件
    - xcshareddata/xcschemes/<name>.xcscheme          让 -scheme 无需依赖自动创建

用法：
    python3 scripts/gen_xcode_project.py            # 生成工程
    python3 scripts/gen_xcode_project.py --check    # 只校验已生成的工程

工程规格：
    - 单一 iOS App target，SwiftUI + AppIntents + BackgroundTasks，部署目标 iOS 16.0
    - 自定义 Info.plist（含 BGTaskSchedulerPermittedIdentifiers / UIBackgroundModes=fetch）
    - 未签名产物由 scripts/build-ipa.sh 打包

重要：project.pbxproj 采用 **XML plist 格式**（而不是 Xcode 默认的老式 OpenStep 格式）。
    依据（Stack Overflow 官方确认）：工程文件的表面语法只是「旧式 plist」，Xcode 的
    plist 加载器对 XML / binary / OpenStep 三种格式完全等价；「Xcode 会读取 XML 表示，
    打开工程后再转回旧式格式」——以 XML 格式调用 xcodebuild / xcrun 没有任何问题。
    老式 OpenStep 的手写语法存在 CoreFoundation 才有的严格性（第三方解析器全部放行、
    Apple 自家解析器拒收），在非 macOS 环境无法复现；XML 格式则由 plistlib 保证合法，
    plutil -lint 可直接验证，从根上消灭这一整类问题。
"""
from __future__ import annotations

import os
import plistlib
import re
import sys

PROJECT_NAME = "WorkBuddyPoints"
BUNDLE_ID = "com.wbpoints.daily"
DEPLOYMENT_TARGET = "16.0"
SWIFT_VERSION = "5.0"
MARKETING_VERSION = "1.0.0"
CURRENT_PROJECT_VERSION = "1"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, PROJECT_NAME)
SRC_DIR_NAME = PROJECT_NAME
PROJECT_DIR = os.path.join(ROOT, PROJECT_NAME + ".xcodeproj")
PBXPROJ = os.path.join(PROJECT_DIR, "project.pbxproj")

# .xcodeproj 本质是目录 bundle。Xcode 生成的工程除 project.pbxproj 外还一定带
# 下面两个文件；手写工程若只产 pbxproj，xcodebuild -project 会直接报
# "Unable to read project ... damaged ... parse error"（读不到 workspace 文件）。
WORKSPACE_PATH = os.path.join(PROJECT_DIR, "project.xcworkspace", "contents.xcworkspacedata")
SCHEME_PATH = os.path.join(PROJECT_DIR, "xcshareddata", "xcschemes", PROJECT_NAME + ".xcscheme")

# 工程内置 workspace：self: 指向 .xcodeproj 自身（Xcode 自己也是这么写的）
WORKSPACE_DATA = """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:%s.xcodeproj">
   </FileRef>
</Workspace>
""" % PROJECT_NAME

# 共享 scheme：-scheme 参数直接可用，不依赖 xcodebuild 自动创建
SCHEME_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Prefer Architecture with fewest variants">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "%(target)s"
               BuildableName = "%(name)s.app"
               BlueprintName = "%(name)s"
               ReferencedContainer = "container:%(name)s.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersion = "1"
      debugServiceVersion = "1"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "%(target)s"
            BuildableName = "%(name)s.app"
            BlueprintName = "%(name)s"
            ReferencedContainer = "container:%(name)s.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersion = "1">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "%(target)s"
            BuildableName = "%(name)s.app"
            BlueprintName = "%(name)s"
            ReferencedContainer = "container:%(name)s.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


class IDs:
    """确定性 24 位大写十六进制对象 ID"""

    def __init__(self) -> None:
        self.counter = 0
        self.used: set[str] = set()

    def new(self) -> str:
        while True:
            self.counter += 1
            value = ("CAFEBABE1234" + "%012X" % self.counter)[-24:]
            if value not in self.used:
                self.used.add(value)
                return value


def collect_sources() -> tuple[list[str], list[str], bool]:
    """收集源文件：返回 (swift 相对路径, 特殊文件相对路径, 是否有 Assets.xcassets)"""
    swift_files: list[str] = []
    special_files: list[str] = []
    has_assets = False
    for current, dirs, files in os.walk(SRC_DIR):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        if os.path.basename(current) == SRC_DIR_NAME and "Assets.xcassets" in dirs:
            has_assets = True
        for name in sorted(files):
            if name.startswith("."):
                continue
            full = os.path.join(current, name)
            rel = os.path.relpath(full, SRC_DIR).replace(os.sep, "/")
            if name.endswith(".swift"):
                swift_files.append(rel)
            elif name in ("Info.plist", f"{PROJECT_NAME}.entitlements"):
                special_files.append(rel)
    return sorted(swift_files), sorted(special_files), has_assets


def gen_project_tree(swift_files: list[str], special_files: list[str],
                     has_assets: bool) -> tuple[dict, str]:
    """构建完整工程 plist 树；返回 (树, native target 对象 ID)。

    模型规则与 Xcode 生成的工程完全一致：
      - 所有对象都放在 objects 字典里，键是 24 位十六进制 ID；
      - 每个对象都有 isa 标明类型；
      - 对象之间的引用就是 ID 字符串；
      - 数值字段（archiveVersion / buildActionMask 等）保持数字——
        老式 OpenStep 里未加引号的数字本来就会被解析成 NSNumber。
    """
    ids = IDs()
    basename = lambda rel: rel.split("/")[-1]  # noqa: E731

    objects: dict[str, dict] = {}

    # --- 文件引用与构建文件 ID ---
    file_ref: dict[str, str] = {}
    build_file: dict[str, str] = {}
    for rel in swift_files:
        file_ref[rel] = ids.new()
        build_file[rel] = ids.new()
    for rel in special_files:
        file_ref[rel] = ids.new()
    assets_ref = ids.new() if has_assets else None
    assets_build = ids.new() if has_assets else None

    # --- 组 ID（含所有中间目录）---
    folders: set[str] = {""}
    for rel in list(file_ref) + (["Assets.xcassets"] if has_assets else []):
        parts = rel.split("/")[:-1]
        for i in range(1, len(parts) + 1):
            folders.add("/".join(parts[:i]))
    group_id = {folder: ids.new() for folder in sorted(folders)}

    products_group = ids.new()
    product_ref = ids.new()
    sources_phase = ids.new()
    frameworks_phase = ids.new()
    resources_phase = ids.new()
    target = ids.new()
    project = ids.new()
    proj_cfg_list = ids.new()
    tgt_cfg_list = ids.new()
    cfg = {name: ids.new() for name in ("projDebug", "projRelease", "tgtDebug", "tgtRelease")}

    # --- PBXBuildFile ---
    for rel in swift_files:
        objects[build_file[rel]] = {
            "isa": "PBXBuildFile",
            "fileRef": file_ref[rel],
        }
    if has_assets:
        objects[assets_build] = {
            "isa": "PBXBuildFile",
            "fileRef": assets_ref,
        }

    # --- PBXFileReference ---
    for rel in swift_files:
        objects[file_ref[rel]] = {
            "isa": "PBXFileReference",
            "explicitFileType": "sourcecode.swift",
            "fileEncoding": 4,
            "includeInIndex": 0,
            "path": basename(rel),
            "sourceTree": "<group>",
        }
    for rel in special_files:
        kind = "text.plist.xml" if rel.endswith(".plist") else "text.plist.entitlements"
        objects[file_ref[rel]] = {
            "isa": "PBXFileReference",
            "fileEncoding": 4,
            "lastKnownFileType": kind,
            "path": basename(rel),
            "sourceTree": "<group>",
        }
    if has_assets:
        objects[assets_ref] = {
            "isa": "PBXFileReference",
            "lastKnownFileType": "folder.assetcatalog",
            "path": "Assets.xcassets",
            "sourceTree": "<group>",
        }
    objects[product_ref] = {
        "isa": "PBXFileReference",
        "explicitFileType": "wrapper.application",
        "includeInIndex": 0,
        "path": f"{PROJECT_NAME}.app",
        "sourceTree": "BUILT_PRODUCTS_DIR",
    }

    # --- PBXGroup（按目录深度从深到浅、同深度按字典序输出，保证确定性）---
    all_files = sorted(list(file_ref) + (["Assets.xcassets"] if has_assets else []),
                       key=lambda r: (r.rsplit("/", 1)[0] if "/" in r else "", basename(r)))
    for folder in sorted(folders, key=lambda f: (-len(f.split("/")) if f else 99, f)):
        children: list[str] = []
        for sub in sorted(f for f in folders if f.startswith(folder)
                          and f != folder and ("/" not in f[len(folder) + 1:])):
            children.append(group_id[sub])
        for rel in all_files:
            parent = rel.rsplit("/", 1)[0] if "/" in rel else ""
            if parent != folder:
                continue
            children.append(assets_ref if rel == "Assets.xcassets" else file_ref[rel])
        name = folder.split("/")[-1] if folder else PROJECT_NAME
        objects[group_id[folder]] = {
            "isa": "PBXGroup",
            "children": children,
            "name": name,
            "sourceTree": "<group>",
        }
    objects[products_group] = {
        "isa": "PBXGroup",
        "children": [product_ref],
        "name": "Products",
        "sourceTree": "<group>",
    }

    # --- PBXNativeTarget ---
    objects[target] = {
        "isa": "PBXNativeTarget",
        "buildConfigurationList": tgt_cfg_list,
        "buildPhases": [sources_phase, frameworks_phase, resources_phase],
        "buildRules": [],
        "dependencies": [],
        "name": PROJECT_NAME,
        "productName": PROJECT_NAME,
        "productReference": product_ref,
        "productType": "com.apple.product-type.application",
    }

    # --- PBXProject ---
    objects[project] = {
        "isa": "PBXProject",
        "attributes": {
            "BuildIndependentTargetsInParallel": 1,
            "LastSwiftUpdateCheck": 1500,
            "LastUpgradeCheck": 1500,
            "TargetAttributes": {
                target: {"CreatedOnToolsVersion": "15.0"},
            },
        },
        "buildConfigurationList": proj_cfg_list,
        "compatibilityVersion": "Xcode 14.0",
        "developmentRegion": "zh_CN",
        "hasScannedForEncodings": 0,
        "knownRegions": ["zh_CN", "Base"],
        "mainGroup": group_id[""],
        "productRefGroup": products_group,
        "projectDirPath": "",
        "projectRoot": "",
        "targets": [target],
    }

    # --- 构建阶段 ---
    objects[resources_phase] = {
        "isa": "PBXResourcesBuildPhase",
        "buildActionMask": 2147483647,
        "files": [assets_build] if has_assets else [],
        "runOnlyForDeploymentPostprocessing": 0,
    }
    objects[sources_phase] = {
        "isa": "PBXSourcesBuildPhase",
        "buildActionMask": 2147483647,
        "files": [build_file[rel] for rel in swift_files],
        "runOnlyForDeploymentPostprocessing": 0,
    }
    objects[frameworks_phase] = {
        "isa": "PBXFrameworksBuildPhase",
        "buildActionMask": 2147483647,
        "files": [],
        "runOnlyForDeploymentPostprocessing": 0,
    }

    # --- 构建配置 ---
    def project_settings(suffix: str) -> dict:
        settings: dict[str, object] = {
            "ALWAYS_SEARCH_USER_PATHS": "NO",
            "CLANG_ANALYZER_NONNULL": "YES",
            "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
            "CLANG_ENABLE_MODULES": "YES",
            "CLANG_ENABLE_OBJC_ARC": "YES",
            "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym" if suffix == "Release" else "dwarf",
            "ENABLE_STRICT_OBJC_MSGSEND": "YES",
            "ENABLE_TESTABILITY": "YES" if suffix == "Debug" else "NO",
            "GCC_C_LANGUAGE_STANDARD": "gnu17",
            "GCC_DYNAMIC_NO_PIC": "NO",
            "GCC_OPTIMIZATION_LEVEL": "0" if suffix == "Debug" else "s",
            "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
            "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE" if suffix == "Debug" else "NO",
            "SDKROOT": "iphoneos",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if suffix == "Debug" else "-O",
            "SWIFT_VERSION": SWIFT_VERSION,
            "TARGETED_DEVICE_FAMILY": "1",
            "VALIDATE_PRODUCT": "YES" if suffix == "Release" else "NO",
        }
        if suffix == "Debug":
            settings["GCC_PREPROCESSOR_DEFINITIONS"] = ["DEBUG=1", "$(inherited)"]
            settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
        return settings

    def target_settings(suffix: str) -> dict:
        return {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "CODE_SIGN_ENTITLEMENTS": f"{PROJECT_NAME}/{PROJECT_NAME}.entitlements",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": CURRENT_PROJECT_VERSION,
            "DEVELOPMENT_TEAM": "",
            "ENABLE_PREVIEWS": "YES",
            "GENERATE_INFOPLIST_FILE": "NO",
            "INFOPLIST_FILE": f"{PROJECT_NAME}/Info.plist",
            "INFOPLIST_KEY_CFBundleDisplayName": "积分助手",
            "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
            "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
            "MARKETING_VERSION": MARKETING_VERSION,
            "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "SWIFT_STRICT_CONCURRENCY": "minimal",
            "SWIFT_VERSION": SWIFT_VERSION,
            "TARGETED_DEVICE_FAMILY": "1",
        }

    for key, name, is_project, suffix in (
        (cfg["projDebug"], "Debug", True, "Debug"),
        (cfg["projRelease"], "Release", True, "Release"),
        (cfg["tgtDebug"], "Debug", False, "Debug"),
        (cfg["tgtRelease"], "Release", False, "Release"),
    ):
        objects[key] = {
            "isa": "XCBuildConfiguration",
            "buildSettings": project_settings(suffix) if is_project else target_settings(suffix),
            "name": name,
        }

    # --- XCConfigurationList ---
    objects[proj_cfg_list] = {
        "isa": "XCConfigurationList",
        "buildConfigurations": [cfg["projDebug"], cfg["projRelease"]],
        "defaultConfigurationIsVisible": 0,
        "defaultConfigurationName": "Release",
    }
    objects[tgt_cfg_list] = {
        "isa": "XCConfigurationList",
        "buildConfigurations": [cfg["tgtDebug"], cfg["tgtRelease"]],
        "defaultConfigurationIsVisible": 0,
        "defaultConfigurationName": "Release",
    }

    tree = {
        "archiveVersion": 1,
        "classes": {},
        "objectVersion": 56,
        "objects": objects,
        "rootObject": project,
    }
    return tree, target


def validate(tree: dict) -> None:
    """语义自校验：产出不合法就当场失败，绝不让坏文件流到下一步。

    plistlib 解析本身就是最强校验（XML 结构 + plist 模型）；
    这里再做工程语义层面的检查：
      1. archiveVersion / objectVersion / rootObject 齐全
      2. rootObject 必须在 objects 里
      3. 必需对象类型齐全（target / project / 配置列表 / 三个构建阶段）
      4. 所有被引用的 24 位 ID 都有定义（引用闭合）
    """
    def fail(reason: str) -> None:
        raise SystemExit(f"校验失败：{reason}\n"
                         f"（常见原因：scripts/gen_xcode_project.py 上传时不完整，"
                         f"请重新完整上传该文件）")

    if tree.get("archiveVersion") not in (1, "1"):
        fail(f"archiveVersion 异常：{tree.get('archiveVersion')!r}")
    objects = tree.get("objects")
    if not isinstance(objects, dict) or not objects:
        fail("objects 段缺失或为空")
    root = tree.get("rootObject")
    if not root or root not in objects:
        fail(f"rootObject {root!r} 不在 objects 里")
    if objects[root].get("isa") != "PBXProject":
        fail("rootObject 不是 PBXProject")

    # 必需对象类型
    by_isa: dict[str, list[str]] = {}
    for obj_id, obj in objects.items():
        by_isa.setdefault(obj.get("isa", "?"), []).append(obj_id)
    for cls, minimum in (("PBXNativeTarget", 1), ("PBXProject", 1),
                         ("XCBuildConfiguration", 4), ("XCConfigurationList", 2),
                         ("PBXSourcesBuildPhase", 1), ("PBXFrameworksBuildPhase", 1),
                         ("PBXResourcesBuildPhase", 1), ("PBXGroup", 1)):
        if len(by_isa.get(cls, [])) < minimum:
            fail(f"缺少对象类型 {cls}")

    # 引用闭合：所有形如 24 位十六进制的字符串都必须是已定义的对象 ID
    defined = set(objects)
    referenced: set[str] = set()

    def walk(value) -> None:
        if isinstance(value, str):
            if re.fullmatch(r"[0-9A-F]{24}", value):
                referenced.add(value)
        elif isinstance(value, dict):
            for k, v in value.items():
                walk(k)
                walk(v)
        elif isinstance(value, (list, tuple)):
            for item in value:
                walk(item)

    walk(tree)
    missing = referenced - defined
    if missing:
        fail(f"存在未定义的对象 ID 引用：{sorted(missing)}")

    # scheme 用的 target ID 必须真实存在
    targets = by_isa.get("PBXNativeTarget", [])
    if len(targets) != 1:
        fail(f"应有且仅有 1 个 native target，实际 {len(targets)} 个")

    print(f"校验通过：{len(objects)} 个对象，引用全部闭合，"
          f"类型分布 {sorted(by_isa)}")


def main() -> None:
    if "--check" in sys.argv:
        if not os.path.exists(PBXPROJ):
            raise SystemExit("尚未生成工程，请先运行 python3 scripts/gen_xcode_project.py")
        with open(PBXPROJ, "rb") as handle:
            tree = plistlib.load(handle)
        validate(tree)
        return

    swift_files, special_files, has_assets = collect_sources()
    if not swift_files:
        raise SystemExit(f"未在 {SRC_DIR} 找到任何 Swift 源文件")

    tree, target_id = gen_project_tree(swift_files, special_files, has_assets)
    validate(tree)
    os.makedirs(PROJECT_DIR, exist_ok=True)
    with open(PBXPROJ, "wb") as handle:
        plistlib.dump(tree, handle, fmt=plistlib.FMT_XML, sort_keys=False)
    print(f"已生成 {PROJECT_NAME}.xcodeproj/project.pbxproj（XML plist 格式）")
    print(f"  Swift 源文件：{len(swift_files)} 个")
    print(f"  特殊文件：{', '.join(special_files) or '无'}")
    print(f"  Assets.xcassets：{'包含' if has_assets else '缺失'}")

    # .xcodeproj 是 bundle：除 pbxproj 外，内置 workspace 与共享 scheme
    # 同样是 xcodebuild 的必需项，缺一个整个工程就读不进来。
    os.makedirs(os.path.dirname(WORKSPACE_PATH), exist_ok=True)
    with open(WORKSPACE_PATH, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(WORKSPACE_DATA)
    os.makedirs(os.path.dirname(SCHEME_PATH), exist_ok=True)
    with open(SCHEME_PATH, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(SCHEME_TEMPLATE % {"target": target_id, "name": PROJECT_NAME})
    print("已生成 project.xcworkspace/contents.xcworkspacedata（xcodebuild -project 必需）")
    print(f"已生成 xcshareddata/xcschemes/{PROJECT_NAME}.xcscheme（-scheme 直接可用）")


if __name__ == "__main__":
    main()
