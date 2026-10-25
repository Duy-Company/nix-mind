#!/usr/bin/env python3
"""Generate the Xcode project with a pinned Sparkle package. No third-party generators required."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parent.parent
sources = sorted((root / 'NixMind').glob('*.swift'))
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def ref(name): return uid(name)
objects = []
def obj(name, value): objects.append(f'{ref(name)} = {{ {value} }};')
for file in sources:
    obj(file.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file.name}; sourceTree = "<group>";')
    obj('build-'+file.name, f'isa = PBXBuildFile; fileRef = {ref(file.name)};')
obj('Info.plist', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";')
obj('AppIcon.icns', 'isa = PBXFileReference; lastKnownFileType = image.icns; path = AppIcon.icns; sourceTree = "<group>";')
obj('build-icon', f'isa = PBXBuildFile; fileRef = {ref("AppIcon.icns")};')
obj('Sparkle-LICENSE.txt', 'isa = PBXFileReference; lastKnownFileType = text; path = "Sparkle-LICENSE.txt"; sourceTree = "<group>";')
obj('build-license', f'isa = PBXBuildFile; fileRef = {ref("Sparkle-LICENSE.txt")};')
obj('app', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "Nix Mind.app"; sourceTree = BUILT_PRODUCTS_DIR;')
obj('source-group', f'isa = PBXGroup; children = ({",".join(ref(s.name) for s in sources)},{ref("Info.plist")},{ref("AppIcon.icns")},{ref("Sparkle-LICENSE.txt")},); path = NixMind; sourceTree = "<group>";')
obj('products', f'isa = PBXGroup; children = ({ref("app")},); name = Products; sourceTree = "<group>";')
obj('main', f'isa = PBXGroup; children = ({ref("source-group")},{ref("products")},); sourceTree = "<group>";')
obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(ref("build-"+s.name) for s in sources)},); runOnlyForDeploymentPostprocessing = 0;')
obj('sparkle-package', 'isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/sparkle-project/Sparkle"; requirement = { kind = exactVersion; version = 2.10.0; };')
obj('sparkle-product', f'isa = XCSwiftPackageProductDependency; package = {ref("sparkle-package")}; productName = Sparkle;')
obj('sparkle-link', f'isa = PBXBuildFile; productRef = {ref("sparkle-product")};')
obj('frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({ref("sparkle-link")},); runOnlyForDeploymentPostprocessing = 0;')
obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({ref("build-icon")},{ref("build-license")},); runOnlyForDeploymentPostprocessing = 0;')
for scope in ['project','target']:
    for config in ['Debug','Release']:
        settings = 'CLANG_ENABLE_MODULES = YES; MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; SWIFT_VERSION = 5.0;'
        if scope == 'target': settings += ' PRODUCT_NAME = "Nix Mind"; PRODUCT_BUNDLE_IDENTIFIER = com.nixmind.mac; INFOPLIST_FILE = NixMind/Info.plist; GENERATE_INFOPLIST_FILE = NO; CODE_SIGN_STYLE = Automatic; CODE_SIGN_IDENTITY = "-"; COMBINE_HIDPI_IMAGES = YES; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks"; ENABLE_APP_SANDBOX = NO;'
        settings += ' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf;' if config == 'Debug' else ' SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
        obj(scope+config, f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {config};')
    obj(scope+'configs', f'isa = XCConfigurationList; buildConfigurations = ({ref(scope+"Debug")},{ref(scope+"Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {ref("targetconfigs")}; buildPhases = ({ref("sources")},{ref("frameworks")},{ref("resources")},); buildRules = (); dependencies = (); packageProductDependencies = ({ref("sparkle-product")},); name = NixMind; productName = "Nix Mind"; productReference = {ref("app")}; productType = "com.apple.product-type.application";')
obj('project', f'isa = PBXProject; attributes = {{ LastSwiftUpdateCheck = 2630; LastUpgradeCheck = 2630; }}; buildConfigurationList = {ref("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base,); mainGroup = {ref("main")}; productRefGroup = {ref("products")}; packageReferences = ({ref("sparkle-package")},); projectDirPath = ""; projectRoot = ""; targets = ({ref("target")},);')
(root / 'NixMind.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {ref("project")}; }}\n')
(root / 'NixMind.xcodeproj/xcshareddata/xcschemes/NixMind.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2630" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref('target')}" BuildableName="Nix Mind.app" BlueprintName="NixMind" ReferencedContainer="container:NixMind.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref('target')}" BuildableName="Nix Mind.app" BlueprintName="NixMind" ReferencedContainer="container:NixMind.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
