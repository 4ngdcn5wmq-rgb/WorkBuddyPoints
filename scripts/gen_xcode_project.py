#!/usr/bin/env python3
"""生成 WorkBuddyPoints.xcodeproj/project.pbxproj（不依赖 XcodeGen / macOS）。

用法：
    python3 scripts/gen_xcode_project.py            # 生成工程
    python3 scripts/gen_xcode_project.py --check    # 只校验已生成的工程

工程规格：
    - 单一 iOS App target，SwiftUI + AppIntents + BackgroundTasks，部署目标 iOS 16.0
    - 自定义 Info.plist（含 BGTaskSchedulerPermittedIdentifiers / UIBackgroundModes=fetch）
    - 未签名产物由 scripts/build-ipa.sh 打包
"""
from __future__ import annotations

import os
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


def build_tree(swift_files: list[str], special_files: list[str], has_assets: bool) -> dict:
    """把相对路径组织成 {目录: [文件]} 的树（用于生成 PBXGroup）"""
    tree: dict[str, list[str]] = {}
    for rel in swift_files + special_files + (["Assets.xcassets"] if has_assets else []):
        parts = rel.split("/")
        folder = "/".join(parts[:-1])
        tree.setdefault(folder, []).append(parts[-1])
    return tree


def gen_pbxproj(swift_files: list[str], special_files: list[str], has_assets: bool) -> str:
    ids = IDs()
    basename = lambda rel: rel.split("/")[-1]  # noqa: E731

    # 文件引用与构建文件 ID
    file_ref: dict[str, str] = {}
    build_file: dict[str, str] = {}
    for rel in swift_files:
        file_ref[rel] = ids.new()
        build_file[rel] = ids.new()
    for rel in special_files:
        file_ref[rel] = ids.new()
    assets_ref = ids.new() if has_assets else None
    assets_build = ids.new() if has_assets else None

    # 组 ID（含所有中间目录）
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

    # --- PBXBuildFile / PBXFileReference ---
    lines: list[str] = []

    lines.append("/* Begin PBXBuildFile section */")
    for rel in swift_files:
        lines.append(f"\t\t{build_file[rel]} /* {basename(rel)} in Sources */ "
                     f"= {{isa = PBXBuildFile; fileRef = {file_ref[rel]} /* {basename(rel)} */ }};")
    if has_assets:
        lines.append(f"\t\t{assets_build} /* Assets.xcassets in Resources */ "
                     f"= {{isa = PBXBuildFile; fileRef = {assets_ref} /* Assets.xcassets */ }};")
    lines.append("/* End PBXBuildFile section */")
    lines.append("")

    lines.append("/* Begin PBXFileReference section */")
    for rel in swift_files:
        lines.append(f"\t\t{file_ref[rel]} /* {basename(rel)} */ "
                     f"= {{isa = PBXFileReference; explicitFileType = sourcecode.swift; "
                     f"fileEncoding = 4; includeInIndex = 0; path = {basename(rel)}; "
                     f"sourceTree = \"<group>\"; }};")
    for rel in special_files:
        kind = ("text.plist.xml" if rel.endswith(".plist") else "text.plist.entitlements")
        lines.append(f"\t\t{file_ref[rel]} /* {basename(rel)} */ "
                     f"= {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = {kind}; "
                     f"path = {basename(rel)}; sourceTree = \"<group>\"; }};")
    if has_assets:
        lines.append(f"\t\t{assets_ref} /* Assets.xcassets */ "
                     f"= {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; "
                     f"path = Assets.xcassets; sourceTree = \"<group>\"; }};")
    lines.append(f"\t\t{product_ref} /* {PROJECT_NAME}.app */ "
                 f"= {{isa = PBXFileReference; explicitFileType = wrapper.application; "
                 f"includeInIndex = 0; path = \"{PROJECT_NAME}.app\"; sourceTree = BUILT_PRODUCTS_DIR; }};")
    lines.append("/* End PBXFileReference section */")
    lines.append("")

    # --- 组树 ---
    def group_children(folder: str) -> list[str]:
        children: list[str] = []
        for sub in sorted(f for f in folders if f.startswith(folder)
                          and f != folder and ("/" not in f[len(folder) + 1:])):
            children.append(f"{group_id[sub]} /* {sub.split('/')[-1]} */")
        files = sorted(list(file_ref) + (["Assets.xcassets"] if has_assets else []),
                       key=lambda r: (r.rsplit("/", 1)[0] if "/" in r else "", basename(r)))
        for rel in files:
            parent = rel.rsplit("/", 1)[0] if "/" in rel else ""
            if parent != folder:
                continue
            if rel == "Assets.xcassets":
                children.append(f"{assets_ref} /* Assets.xcassets */")
            else:
                children.append(f"{file_ref[rel]} /* {basename(rel)} */")
        return children

    lines.append("/* Begin PBXGroup section */")
    # 按目录深度从深到浅、同深度按字典序输出 —— 保证每次生成的 ID 分配完全一致
    # （避免 set 迭代顺序受 PYTHONHASHSEED 影响导致产物不确定）
    for folder in sorted(folders, key=lambda f: (-len(f.split("/")) if f else 99, f)):
        name = folder.split("/")[-1] if folder else PROJECT_NAME
        children = group_children(folder)
        body = ", ".join(children)
        lines.append(f"\t\t{group_id[folder]} /* {name} */ = {{")
        lines.append("\t\t\tisa = PBXGroup;")
        lines.append("\t\t\tchildren = (")
        for child in children:
            lines.append(f"\t\t\t\t{child},")
        lines.append("\t\t\t);")
        lines.append(f"\t\t\tname = {name};")
        lines.append("\t\t\tsourceTree = \"<group>\";")
        lines.append("\t\t};")
    lines.append(f"\t\t{products_group} /* Products */ = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    lines.append(f"\t\t\t\t{product_ref} /* {PROJECT_NAME}.app */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tname = Products;")
    lines.append("\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t};")
    lines.append("/* End PBXGroup section */")
    lines.append("")

    # 主组：把 Products 组挂到根
    lines.append("/* Begin PBXNativeTarget section */")
    lines.append(f"\t\t{target} /* {PROJECT_NAME} */ = {{")
    lines.append("\t\t\tisa = PBXNativeTarget;")
    lines.append(f"\t\t\tbuildConfigurationList = {tgt_cfg_list} /* Build configuration list for PBXNativeTarget \"{PROJECT_NAME}\" */;")
    lines.append("\t\t\tbuildPhases = (")
    lines.append(f"\t\t\t\t{sources_phase} /* Sources */,")
    lines.append(f"\t\t\t\t{frameworks_phase} /* Frameworks */,")
    lines.append(f"\t\t\t\t{resources_phase} /* Resources */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tbuildRules = ();")
    lines.append("\t\t\tdependencies = ();")
    lines.append(f"\t\t\tname = {PROJECT_NAME};")
    lines.append(f"\t\t\tproductName = {PROJECT_NAME};")
    lines.append(f"\t\t\tproductReference = {product_ref} /* {PROJECT_NAME}.app */;")
    lines.append("\t\t\tproductType = \"com.apple.product-type.application\";")
    lines.append("\t\t};")
    lines.append("/* End PBXNativeTarget section */")
    lines.append("")

    lines.append("/* Begin PBXProject section */")
    lines.append(f"\t\t{project} /* Project object */ = {{")
    lines.append("\t\t\tisa = PBXProject;")
    lines.append("\t\t\tattributes = {")
    lines.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    lines.append("\t\t\t\tLastSwiftUpdateCheck = 1500;")
    lines.append("\t\t\t\tLastUpgradeCheck = 1500;")
    lines.append("\t\t\t\tTargetAttributes = {")
    lines.append(f"\t\t\t\t\t{target} = {{")
    lines.append("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
    lines.append("\t\t\t\t\t};")
    lines.append("\t\t\t\t};")
    lines.append("\t\t\t};")
    lines.append(f"\t\t\tbuildConfigurationList = {proj_cfg_list} /* Build configuration list for PBXProject \"{PROJECT_NAME}\" */;")
    lines.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    lines.append("\t\t\tdevelopmentRegion = zh_CN;")
    lines.append("\t\t\thasScannedForEncodings = 0;")
    lines.append("\t\t\tknownRegions = (")
    lines.append("\t\t\t\tzh_CN,")
    lines.append("\t\t\t\tBase,")
    lines.append("\t\t\t);")
    lines.append(f"\t\t\tmainGroup = {group_id['']};")
    lines.append(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
    lines.append("\t\t\tprojectDirPath = \"\";")
    lines.append("\t\t\tprojectRoot = \"\";")
    lines.append("\t\t\ttargets = (")
    lines.append(f"\t\t\t\t{target} /* {PROJECT_NAME} */,")
    lines.append("\t\t\t);")
    lines.append("\t\t};")
    lines.append("/* End PBXProject section */")
    lines.append("")

    lines.append("/* Begin PBXResourcesBuildPhase section */")
    lines.append(f"\t\t{resources_phase} /* Resources */ = {{")
    lines.append("\t\t\tisa = PBXResourcesBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    if has_assets:
        lines.append(f"\t\t\t\t{assets_build} /* Assets.xcassets in Resources */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
    lines.append("/* End PBXResourcesBuildPhase section */")
    lines.append("")

    lines.append("/* Begin PBXSourcesBuildPhase section */")
    lines.append(f"\t\t{sources_phase} /* Sources */ = {{")
    lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    for rel in swift_files:
        lines.append(f"\t\t\t\t{build_file[rel]} /* {basename(rel)} in Sources */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
    lines.append("/* End PBXSourcesBuildPhase section */")
    lines.append("")

    lines.append("/* Begin PBXFrameworksBuildPhase section */")
    lines.append(f"\t\t{frameworks_phase} /* Frameworks */ = {{")
    lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = ();")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
    lines.append("/* End PBXFrameworksBuildPhase section */")
    lines.append("")

    # --- 构建配置 ---
    def project_settings(suffix: str) -> list[str]:
        return [
            "ALWAYS_SEARCH_USER_PATHS = NO;",
            "CLANG_ANALYZER_NONNULL = YES;",
            "CLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";",
            "CLANG_ENABLE_MODULES = YES;",
            "CLANG_ENABLE_OBJC_ARC = YES;",
            "DEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";" if suffix == "Release"
            else "DEBUG_INFORMATION_FORMAT = dwarf;",
            "ENABLE_STRICT_OBJC_MSGSEND = YES;",
            "ENABLE_TESTABILITY = YES;" if suffix == "Debug" else "ENABLE_TESTABILITY = NO;",
            "GCC_C_LANGUAGE_STANDARD = gnu17;",
            "GCC_DYNAMIC_NO_PIC = NO;",
            "GCC_OPTIMIZATION_LEVEL = 0;" if suffix == "Debug" else "GCC_OPTIMIZATION_LEVEL = s;",
            "GCC_PREPROCESSOR_DEFINITIONS = (\"DEBUG=1\", \"$(inherited)\");" if suffix == "Debug" else "",
            "IPHONEOS_DEPLOYMENT_TARGET = " + DEPLOYMENT_TARGET + ";",
            "MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;" if suffix == "Debug"
            else "MTL_ENABLE_DEBUG_INFO = NO;",
            "SDKROOT = iphoneos;",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS = \"$(inherited) DEBUG\";" if suffix == "Debug" else "",
            "SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";" if suffix == "Debug"
            else "SWIFT_OPTIMIZATION_LEVEL = \"-O\";",
            "SWIFT_VERSION = " + SWIFT_VERSION + ";",
            "TARGETED_DEVICE_FAMILY = 1;",
            "VALIDATE_PRODUCT = YES;" if suffix == "Release" else "",
        ]

    def target_settings(suffix: str) -> list[str]:
        return [
            "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
            "CODE_SIGN_ENTITLEMENTS = " + PROJECT_NAME + "/" + PROJECT_NAME + ".entitlements;",
            "CODE_SIGN_STYLE = Automatic;",
            "CURRENT_PROJECT_VERSION = " + CURRENT_PROJECT_VERSION + ";",
            "DEVELOPMENT_TEAM = \"\";",
            "ENABLE_PREVIEWS = YES;",
            "GENERATE_INFOPLIST_FILE = NO;",
            "INFOPLIST_FILE = " + PROJECT_NAME + "/Info.plist;",
            # 注意：pbxproj 里非 ASCII 值必须加引号，否则 Apple 的解析器会拒收
            'INFOPLIST_KEY_CFBundleDisplayName = "积分助手";',
            "INFOPLIST_KEY_UILaunchScreen_Generation = YES;",
            "IPHONEOS_DEPLOYMENT_TARGET = " + DEPLOYMENT_TARGET + ";",
            "LD_RUNPATH_SEARCH_PATHS = (\"$(inherited)\", \"@executable_path/Frameworks\");",
            "MARKETING_VERSION = " + MARKETING_VERSION + ";",
            "PRODUCT_BUNDLE_IDENTIFIER = " + BUNDLE_ID + ";",
            "PRODUCT_NAME = \"$(TARGET_NAME)\";",
            "SWIFT_EMIT_LOC_STRINGS = YES;",
            "SWIFT_STRICT_CONCURRENCY = minimal;",
            "SWIFT_VERSION = " + SWIFT_VERSION + ";",
            "TARGETED_DEVICE_FAMILY = 1;",
        ]

    def emit_config(obj_id: str, name: str, is_project: bool, suffix: str) -> None:
        settings = [s for s in (project_settings(suffix) if is_project else target_settings(suffix)) if s]
        lines.append(f"\t\t{obj_id} /* {name} */ = {{")
        lines.append("\t\t\tisa = XCBuildConfiguration;")
        lines.append("\t\t\tbuildSettings = {")
        for setting in settings:
            lines.append(f"\t\t\t\t{setting}")
        lines.append("\t\t\t};")
        lines.append(f"\t\t\tname = {name};")
        lines.append("\t\t};")
        lines.append("")

    lines.append("/* Begin XCBuildConfiguration section */")
    emit_config(cfg["projDebug"], "Debug", True, "Debug")
    emit_config(cfg["projRelease"], "Release", True, "Release")
    emit_config(cfg["tgtDebug"], "Debug", False, "Debug")
    emit_config(cfg["tgtRelease"], "Release", False, "Release")
    lines.append("/* End XCBuildConfiguration section */")
    lines.append("")

    lines.append("/* Begin XCConfigurationList section */")
    lines.append(f"\t\t{proj_cfg_list} /* Build configuration list for PBXProject \"{PROJECT_NAME}\" */ = {{")
    lines.append("\t\t\tisa = XCConfigurationList;")
    lines.append("\t\t\tbuildConfigurations = (")
    lines.append(f"\t\t\t\t{cfg['projDebug']} /* Debug */,")
    lines.append(f"\t\t\t\t{cfg['projRelease']} /* Release */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    lines.append("\t\t\tdefaultConfigurationName = Release;")
    lines.append("\t\t};")
    lines.append(f"\t\t{tgt_cfg_list} /* Build configuration list for PBXNativeTarget \"{PROJECT_NAME}\" */ = {{")
    lines.append("\t\t\tisa = XCConfigurationList;")
    lines.append("\t\t\tbuildConfigurations = (")
    lines.append(f"\t\t\t\t{cfg['tgtDebug']} /* Debug */,")
    lines.append(f"\t\t\t\t{cfg['tgtRelease']} /* Release */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    lines.append("\t\t\tdefaultConfigurationName = Release;")
    lines.append("\t\t};")
    lines.append("/* End XCConfigurationList section */")

    objects = "\n".join(lines)

    header = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{
"""
    footer = f"""\t}};
\trootObject = {project} /* Project object */;
}}
"""
    return header + objects + footer


def validate(content: str) -> None:
    """结构自校验：产出不合法就当场失败，绝不让空/截断的文件流到下一步。

    校验项：
      1. 必须以 // !$*UTF8*$! 开头（pbxproj 的强制文件头）
      2. 必须以 } 结尾（防止上传/写入截断）
      3. 必须含 objects 段与 rootObject
      4. 大括号配平
      5. 对象定义数（isa = 出现次数）与对象收尾数（\\n\\t}; ）一致
      6. 若环境里有 openstep_parser，用真实 OpenStep 解析器做终极校验
    """
    def fail(reason: str) -> None:
        raise SystemExit(f"校验失败：{reason}\n"
                         f"（常见原因：scripts/gen_xcode_project.py 上传时不完整，"
                         f"请重新完整上传该文件）")

    if not content.startswith("// !$*UTF8*$!"):
        fail("文件头不是 // !$*UTF8*$!，内容为空或已损坏")
    if not content.rstrip("\n").endswith("}"):
        fail("文件未以 } 结尾，内容可能被截断")
    if "objects = {" not in content:
        fail("缺少 objects 段")
    if "rootObject = " not in content:
        fail("缺少 rootObject")
    if content.count("{") != content.count("}"):
        fail(f"大括号不配平（{{ x{content.count('{')} vs }} x{content.count('}')}）")
    object_count = content.count("isa = ")
    # 每个对象都由「\\t\\t + 24位十六进制ID + 空格」开头定义，二者数量必须一致
    defined = re.findall(r"^\t\t[0-9A-F]{24} ", content, re.M)
    if object_count == 0 or object_count != len(defined):
        fail(f"对象定义({object_count})与对象声明行({len(defined)})数量不一致")
    # 所有被引用的 ID 都必须有定义（引用闭合）
    referenced = set(re.findall(r"\b[0-9A-F]{24}\b", content)) - set(defined)
    root = re.search(r"rootObject = ([0-9A-F]{24})", content)
    if not root:
        fail("rootObject 行格式异常")
    referenced.add(root.group(1))
    missing = referenced - set(i.strip() for i in defined)
    if missing:
        fail(f"存在未定义的对象 ID {sorted(missing)}")
    for section in ("PBXBuildFile", "PBXFileReference", "PBXGroup", "PBXNativeTarget",
                    "PBXProject", "PBXResourcesBuildPhase", "PBXSourcesBuildPhase",
                    "PBXFrameworksBuildPhase", "XCBuildConfiguration", "XCConfigurationList"):
        if f"/* Begin {section} section */" not in content:
            fail(f"缺少 section {section}")
    try:
        from openstep_parser import OpenStepDecoder  # type: ignore
        OpenStepDecoder.ParseFromString(content)
        print(f"OpenStep 解析校验通过")
    except ImportError:
        print("（未安装 openstep_parser，跳过终极解析校验）")
    print(f"校验通过：{object_count} 个对象，引用全部闭合")


def main() -> None:
    if "--check" in sys.argv:
        if not os.path.exists(PBXPROJ):
            raise SystemExit("尚未生成工程，请先运行 python3 scripts/gen_xcode_project.py")
        validate(open(PBXPROJ, encoding="utf-8").read())
        return

    swift_files, special_files, has_assets = collect_sources()
    if not swift_files:
        raise SystemExit(f"未在 {SRC_DIR} 找到任何 Swift 源文件")

    content = gen_pbxproj(swift_files, special_files, has_assets)
    validate(content)
    os.makedirs(PROJECT_DIR, exist_ok=True)
    with open(PBXPROJ, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(content)
    print(f"已生成 {PROJECT_NAME}.xcodeproj/project.pbxproj")
    print(f"  Swift 源文件：{len(swift_files)} 个")
    print(f"  特殊文件：{', '.join(special_files) or '无'}")
    print(f"  Assets.xcassets：{'包含' if has_assets else '缺失'}")


if __name__ == "__main__":
    main()
