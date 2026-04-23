#!/usr/bin/env python3
"""Generates Sonique.xcodeproj from the Swift source files in this repo."""

import os

# ─── UUID table ──────────────────────────────────────────────────────────────
# Fixed deterministic UUIDs (24 hex chars) — safe to re-run, stable for git.
U = {
    "ROOT_PROJECT":          "3FA000000000000000000001",
    "MAIN_GROUP":            "3FA000000000000000000002",
    "PRODUCTS_GROUP":        "3FA000000000000000000003",
    "APP_GROUP":             "3FA000000000000000000005",
    "VIEWS_GROUP":           "3FA000000000000000000006",
    "MODELS_GROUP":          "3FA000000000000000000007",
    "SERVICES_GROUP":        "3FA000000000000000000008",
    "INTENTS_GROUP":         "3FA000000000000000000009",
    "RESOURCES_GROUP":       "3FA00000000000000000000A",
    "SONIQUE_TARGET":        "3FA00000000000000000000B",
    "SONIQUE_SOURCES":       "3FA00000000000000000000C",
    "SONIQUE_RESOURCES":     "3FA00000000000000000000D",
    "SONIQUE_FRAMEWORKS":    "3FA00000000000000000000E",
    "SONIQUE_CONFIG_LIST":   "3FA00000000000000000000F",
    "SONIQUE_DEBUG":         "3FA000000000000000000010",
    "SONIQUE_RELEASE":       "3FA000000000000000000011",
    "PROJECT_CONFIG_LIST":   "3FA000000000000000000012",
    "PROJECT_DEBUG":         "3FA000000000000000000013",
    "PROJECT_RELEASE":       "3FA000000000000000000014",
    "LIVEKIT_PKG":           "3FA000000000000000000015",
    "LIVEKIT_PRODUCT":       "3FA000000000000000000016",
    "LIVEKIT_BUILD_FILE":    "3FA000000000000000000017",
    "APP_PRODUCT_REF":       "3FA000000000000000000018",
    "ASSETS_REF":            "3FA000000000000000000019",
    "ASSETS_BF":             "3FA00000000000000000001A",
    "INFO_PLIST_REF":        "3FA00000000000000000001B",
    # Source file refs
    "REF_SONIQUEAPP":        "3FA000000000000000000020",
    "REF_CONNECTINTENT":     "3FA000000000000000000021",
    "REF_SESSIONSTATE":      "3FA000000000000000000022",
    "REF_CONNDETAILS":       "3FA000000000000000000023",
    "REF_SESSIONMGR":        "3FA000000000000000000024",
    "REF_SONIQUESET":        "3FA000000000000000000025",
    "REF_DESIGNSYS":         "3FA000000000000000000026",
    "REF_HOMEVIEW":          "3FA000000000000000000027",
    "REF_ONBOARDING":        "3FA000000000000000000028",
    "REF_ORBVIEW":           "3FA000000000000000000029",
    "REF_SETTINGSVIEW":      "3FA00000000000000000002A",
    "REF_ASSTPROFILE":       "3FA00000000000000000002B",
    "REF_QRSCANNER":         "3FA00000000000000000002C",
    # Build file refs
    "BF_SONIQUEAPP":         "3FA000000000000000000030",
    "BF_CONNECTINTENT":      "3FA000000000000000000031",
    "BF_SESSIONSTATE":       "3FA000000000000000000032",
    "BF_CONNDETAILS":        "3FA000000000000000000033",
    "BF_SESSIONMGR":         "3FA000000000000000000034",
    "BF_SONIQUESET":         "3FA000000000000000000035",
    "BF_DESIGNSYS":          "3FA000000000000000000036",
    "BF_HOMEVIEW":           "3FA000000000000000000037",
    "BF_ONBOARDING":         "3FA000000000000000000038",
    "BF_ORBVIEW":            "3FA000000000000000000039",
    "BF_SETTINGSVIEW":       "3FA00000000000000000003A",
    "BF_ASSTPROFILE":        "3FA00000000000000000003B",
    "BF_QRSCANNER":          "3FA00000000000000000003C",
}

# ─── Source file map: (fileRef UUID, buildFile UUID, path, name) ────────────
SOURCES = [
    (U["REF_SONIQUEAPP"],    U["BF_SONIQUEAPP"],    "SoniqueApp/SoniqueApp.swift",                "SoniqueApp.swift"),
    (U["REF_CONNECTINTENT"], U["BF_CONNECTINTENT"], "SoniqueApp/Intents/ConnectIntent.swift",     "ConnectIntent.swift"),
    (U["REF_SESSIONSTATE"],  U["BF_SESSIONSTATE"],  "SoniqueApp/Models/SessionState.swift",       "SessionState.swift"),
    (U["REF_CONNDETAILS"],   U["BF_CONNDETAILS"],   "SoniqueApp/Models/ConnectionDetails.swift",  "ConnectionDetails.swift"),
    (U["REF_SESSIONMGR"],    U["BF_SESSIONMGR"],    "SoniqueApp/Services/SessionManager.swift",   "SessionManager.swift"),
    (U["REF_SONIQUESET"],    U["BF_SONIQUESET"],    "SoniqueApp/Services/SoniqueSettings.swift",  "SoniqueSettings.swift"),
    (U["REF_DESIGNSYS"],     U["BF_DESIGNSYS"],     "SoniqueApp/Views/DesignSystem.swift",        "DesignSystem.swift"),
    (U["REF_HOMEVIEW"],      U["BF_HOMEVIEW"],      "SoniqueApp/Views/HomeView.swift",            "HomeView.swift"),
    (U["REF_ONBOARDING"],    U["BF_ONBOARDING"],    "SoniqueApp/Views/OnboardingView.swift",      "OnboardingView.swift"),
    (U["REF_ORBVIEW"],       U["BF_ORBVIEW"],       "SoniqueApp/Views/OrbView.swift",             "OrbView.swift"),
    (U["REF_SETTINGSVIEW"],  U["BF_SETTINGSVIEW"],  "SoniqueApp/Views/SettingsView.swift",        "SettingsView.swift"),
    (U["REF_QRSCANNER"],    U["BF_QRSCANNER"],    "SoniqueApp/Views/QRScannerView.swift",        "QRScannerView.swift"),
    (U["REF_ASSTPROFILE"],  U["BF_ASSTPROFILE"],  "SoniqueApp/Models/AssistantProfile.swift",    "AssistantProfile.swift"),
]

def pbxproj():
    lines = []
    w = lines.append

    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {")
    w("\t};")
    w("\tobjectVersion = 77;")
    w("\tobjects = {")
    w("")

    # ── PBXBuildFile ─────────────────────────────────────────────────────────
    w("/* Begin PBXBuildFile section */")
    for (ref, bf, path, name) in SOURCES:
        w(f"\t\t{bf} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};")
    w(f"\t\t{U['ASSETS_BF']} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {U['ASSETS_REF']} /* Assets.xcassets */; }};")
    w(f"\t\t{U['LIVEKIT_BUILD_FILE']} /* LiveKit in Frameworks */ = {{isa = PBXBuildFile; productRef = {U['LIVEKIT_PRODUCT']} /* LiveKit */; }};")
    w("/* End PBXBuildFile section */")
    w("")

    # ── PBXFileReference ─────────────────────────────────────────────────────
    w("/* Begin PBXFileReference section */")
    w(f"\t\t{U['APP_PRODUCT_REF']} /* Sonique.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Sonique.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    w(f"\t\t{U['ASSETS_REF']} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};")
    w(f"\t\t{U['INFO_PLIST_REF']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
    for (ref, bf, path, name) in SOURCES:
        ext = "swift"
        w(f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};")
    w("/* End PBXFileReference section */")
    w("")

    # ── PBXFrameworksBuildPhase ───────────────────────────────────────────────
    w("/* Begin PBXFrameworksBuildPhase section */")
    w(f"\t\t{U['SONIQUE_FRAMEWORKS']} /* Frameworks */ = {{")
    w(f"\t\t\tisa = PBXFrameworksBuildPhase;")
    w(f"\t\t\tbuildActionMask = 2147483647;")
    w(f"\t\t\tfiles = (")
    w(f"\t\t\t\t{U['LIVEKIT_BUILD_FILE']} /* LiveKit in Frameworks */,")
    w(f"\t\t\t);")
    w(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w(f"\t\t}};")
    w("/* End PBXFrameworksBuildPhase section */")
    w("")

    # ── PBXGroup ─────────────────────────────────────────────────────────────
    w("/* Begin PBXGroup section */")

    # Main group
    w(f"\t\t{U['MAIN_GROUP']} = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{U['APP_GROUP']} /* SoniqueApp */,")
    w(f"\t\t\t\t{U['PRODUCTS_GROUP']} /* Products */,")
    w(f"\t\t\t);")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Products group
    w(f"\t\t{U['PRODUCTS_GROUP']} /* Products */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{U['APP_PRODUCT_REF']} /* Sonique.app */,")
    w(f"\t\t\t);")
    w(f"\t\t\tname = Products;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # SoniqueApp group
    app_top_sources = [s for s in SOURCES if s[3] == "SoniqueApp.swift"]
    w(f"\t\t{U['APP_GROUP']} /* SoniqueApp */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    for (ref, _, _, name) in app_top_sources:
        w(f"\t\t\t\t{ref} /* {name} */,")
    w(f"\t\t\t\t{U['INTENTS_GROUP']} /* Intents */,")
    w(f"\t\t\t\t{U['MODELS_GROUP']} /* Models */,")
    w(f"\t\t\t\t{U['SERVICES_GROUP']} /* Services */,")
    w(f"\t\t\t\t{U['VIEWS_GROUP']} /* Views */,")
    w(f"\t\t\t\t{U['RESOURCES_GROUP']} /* Resources */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = SoniqueApp;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Intents group
    intent_sources = [s for s in SOURCES if "Intents/" in s[2]]
    w(f"\t\t{U['INTENTS_GROUP']} /* Intents */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    for (ref, _, _, name) in intent_sources:
        w(f"\t\t\t\t{ref} /* {name} */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Intents;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Models group
    model_sources = [s for s in SOURCES if "Models/" in s[2]]
    w(f"\t\t{U['MODELS_GROUP']} /* Models */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    for (ref, _, _, name) in model_sources:
        w(f"\t\t\t\t{ref} /* {name} */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Models;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Services group
    service_sources = [s for s in SOURCES if "Services/" in s[2]]
    w(f"\t\t{U['SERVICES_GROUP']} /* Services */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    for (ref, _, _, name) in service_sources:
        w(f"\t\t\t\t{ref} /* {name} */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Services;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Views group
    view_sources = [s for s in SOURCES if "Views/" in s[2]]
    w(f"\t\t{U['VIEWS_GROUP']} /* Views */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    for (ref, _, _, name) in view_sources:
        w(f"\t\t\t\t{ref} /* {name} */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Views;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    # Resources group
    w(f"\t\t{U['RESOURCES_GROUP']} /* Resources */ = {{")
    w(f"\t\t\tisa = PBXGroup;")
    w(f"\t\t\tchildren = (")
    w(f"\t\t\t\t{U['ASSETS_REF']} /* Assets.xcassets */,")
    w(f"\t\t\t\t{U['INFO_PLIST_REF']} /* Info.plist */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpath = Resources;")
    w(f"\t\t\tsourceTree = \"<group>\";")
    w(f"\t\t}};")

    w("/* End PBXGroup section */")
    w("")

    # ── PBXNativeTarget ───────────────────────────────────────────────────────
    w("/* Begin PBXNativeTarget section */")
    w(f"\t\t{U['SONIQUE_TARGET']} /* Sonique */ = {{")
    w(f"\t\t\tisa = PBXNativeTarget;")
    w(f"\t\t\tbuildConfigurationList = {U['SONIQUE_CONFIG_LIST']} /* Build configuration list for PBXNativeTarget \"Sonique\" */;")
    w(f"\t\t\tbuildPhases = (")
    w(f"\t\t\t\t{U['SONIQUE_SOURCES']} /* Sources */,")
    w(f"\t\t\t\t{U['SONIQUE_FRAMEWORKS']} /* Frameworks */,")
    w(f"\t\t\t\t{U['SONIQUE_RESOURCES']} /* Resources */,")
    w(f"\t\t\t);")
    w(f"\t\t\tbuildRules = (")
    w(f"\t\t\t);")
    w(f"\t\t\tdependencies = (")
    w(f"\t\t\t);")
    w(f"\t\t\tname = Sonique;")
    w(f"\t\t\tpackageDependencies = (")
    w(f"\t\t\t\t{U['LIVEKIT_PRODUCT']} /* LiveKit */,")
    w(f"\t\t\t);")
    w(f"\t\t\tproductName = Sonique;")
    w(f"\t\t\tproductReference = {U['APP_PRODUCT_REF']} /* Sonique.app */;")
    w(f"\t\t\tproductType = \"com.apple.product-type.application\";")
    w(f"\t\t}};")
    w("/* End PBXNativeTarget section */")
    w("")

    # ── PBXProject ────────────────────────────────────────────────────────────
    w("/* Begin PBXProject section */")
    w(f"\t\t{U['ROOT_PROJECT']} /* Project object */ = {{")
    w(f"\t\t\tisa = PBXProject;")
    w(f"\t\t\tattributes = {{")
    w(f"\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    w(f"\t\t\t\tLastSwiftUpdateCheck = 1630;")
    w(f"\t\t\t\tLastUpgradeCheck = 1630;")
    w(f"\t\t\t\tTargetAttributes = {{")
    w(f"\t\t\t\t\t{U['SONIQUE_TARGET']} = {{")
    w(f"\t\t\t\t\t\tCreatedOnToolsVersion = 16.3;")
    w(f"\t\t\t\t\t}};")
    w(f"\t\t\t\t}};")
    w(f"\t\t\t}};")
    w(f"\t\t\tbuildConfigurationList = {U['PROJECT_CONFIG_LIST']} /* Build configuration list for PBXProject \"Sonique\" */;")
    w(f"\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    w(f"\t\t\tdevelopmentRegion = en;")
    w(f"\t\t\thasScannedForEncodings = 0;")
    w(f"\t\t\tknownRegions = (")
    w(f"\t\t\t\ten,")
    w(f"\t\t\t\tBase,")
    w(f"\t\t\t);")
    w(f"\t\t\tmainGroup = {U['MAIN_GROUP']};")
    w(f"\t\t\tpackageReferences = (")
    w(f"\t\t\t\t{U['LIVEKIT_PKG']} /* XCRemoteSwiftPackageReference \"client-sdk-swift\" */,")
    w(f"\t\t\t);")
    w(f"\t\t\tpreferredProjectObjectVersion = 77;")
    w(f"\t\t\tproductRefGroup = {U['PRODUCTS_GROUP']} /* Products */;")
    w(f"\t\t\tprojectDirPath = \"\";")
    w(f"\t\t\tprojectRoot = \"\";")
    w(f"\t\t\ttargets = (")
    w(f"\t\t\t\t{U['SONIQUE_TARGET']} /* Sonique */,")
    w(f"\t\t\t);")
    w(f"\t\t}};")
    w("/* End PBXProject section */")
    w("")

    # ── PBXResourcesBuildPhase ────────────────────────────────────────────────
    w("/* Begin PBXResourcesBuildPhase section */")
    w(f"\t\t{U['SONIQUE_RESOURCES']} /* Resources */ = {{")
    w(f"\t\t\tisa = PBXResourcesBuildPhase;")
    w(f"\t\t\tbuildActionMask = 2147483647;")
    w(f"\t\t\tfiles = (")
    w(f"\t\t\t\t{U['ASSETS_BF']} /* Assets.xcassets in Resources */,")
    w(f"\t\t\t);")
    w(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w(f"\t\t}};")
    w("/* End PBXResourcesBuildPhase section */")
    w("")

    # ── PBXSourcesBuildPhase ──────────────────────────────────────────────────
    w("/* Begin PBXSourcesBuildPhase section */")
    w(f"\t\t{U['SONIQUE_SOURCES']} /* Sources */ = {{")
    w(f"\t\t\tisa = PBXSourcesBuildPhase;")
    w(f"\t\t\tbuildActionMask = 2147483647;")
    w(f"\t\t\tfiles = (")
    for (ref, bf, path, name) in SOURCES:
        w(f"\t\t\t\t{bf} /* {name} in Sources */,")
    w(f"\t\t\t);")
    w(f"\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w(f"\t\t}};")
    w("/* End PBXSourcesBuildPhase section */")
    w("")

    # ── XCBuildConfiguration ──────────────────────────────────────────────────
    w("/* Begin XCBuildConfiguration section */")

    # Project Debug
    w(f"\t\t{U['PROJECT_DEBUG']} /* Debug */ = {{")
    w(f"\t\t\tisa = XCBuildConfiguration;")
    w(f"\t\t\tbuildSettings = {{")
    w(f"\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    w(f"\t\t\t\tASSET_CATALOG_COMPILER_OPTIMIZATION = space;")
    w(f"\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
    w(f"\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";")
    w(f"\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    w(f"\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    w(f"\t\t\t\tCOPY_PHASE_STRIP = NO;")
    w(f"\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;")
    w(f"\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
    w(f"\t\t\t\tENABLE_TESTABILITY = YES;")
    w(f"\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;")
    w(f"\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;")
    w(f"\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;")
    w(f"\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;")
    w(f"\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (\"DEBUG=1\", \"$(inherited)\", );")
    w(f"\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
    w(f"\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;")
    w(f"\t\t\t\tMTL_FAST_MATH = YES;")
    w(f"\t\t\t\tONLY_ACTIVE_ARCH = YES;")
    w(f"\t\t\t\tSDKROOT = iphoneos;")
    w(f"\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
    w(f"\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
    w(f"\t\t\t}};")
    w(f"\t\t\tname = Debug;")
    w(f"\t\t}};")

    # Project Release
    w(f"\t\t{U['PROJECT_RELEASE']} /* Release */ = {{")
    w(f"\t\t\tisa = XCBuildConfiguration;")
    w(f"\t\t\tbuildSettings = {{")
    w(f"\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    w(f"\t\t\t\tASSET_CATALOG_COMPILER_OPTIMIZATION = space;")
    w(f"\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
    w(f"\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";")
    w(f"\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    w(f"\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    w(f"\t\t\t\tCOPY_PHASE_STRIP = NO;")
    w(f"\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";")
    w(f"\t\t\t\tENABLE_NS_ASSERTIONS = NO;")
    w(f"\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
    w(f"\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;")
    w(f"\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;")
    w(f"\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
    w(f"\t\t\t\tMTL_FAST_MATH = YES;")
    w(f"\t\t\t\tSDKROOT = iphoneos;")
    w(f"\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
    w(f"\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";")
    w(f"\t\t\t\tVALIDATE_PRODUCT = YES;")
    w(f"\t\t\t}};")
    w(f"\t\t\tname = Release;")
    w(f"\t\t}};")

    # Target Debug
    w(f"\t\t{U['SONIQUE_DEBUG']} /* Debug */ = {{")
    w(f"\t\t\tisa = XCBuildConfiguration;")
    w(f"\t\t\tbuildSettings = {{")
    w(f"\t\t\t\tASSTETS_CATALOG_COMPILER_APPICON_NAME = AppIcon;")
    w(f"\t\t\t\tCODE_SIGN_ENTITLEMENTS = Sonique.entitlements;")
    w(f"\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    w(f"\t\t\t\tDEVELOPMENT_TEAM = 7NSS5CJL9E;")
    w(f"\t\t\t\tEMBED_PACKAGE_FRAMEWORKS = YES;")
    w(f"\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
    w(f"\t\t\t\tINFOPLIST_FILE = SoniqueApp/Resources/Info.plist;")
    w(f"\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
    w(f"\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\"$(inherited)\", \"@executable_path/Frameworks\", \"@executable_path/PackageFrameworks\", );")
    w(f"\t\t\t\tLE_SWIFT_VERSION = 5.0;")
    w(f"\t\t\t\tMARKETING_VERSION = 1.0;")
    w(f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.seayniclabs.sonique;")
    w(f"\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    w(f"\t\t\t\tSDKROOT = iphoneos;")
    w(f"\t\t\t\tSUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";")
    w(f"\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    w(f"\t\t\t\tSWIFT_VERSION = 5.0;")
    w(f"\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";")
    w(f"\t\t\t}};")
    w(f"\t\t\tname = Debug;")
    w(f"\t\t}};")

    # Target Release
    w(f"\t\t{U['SONIQUE_RELEASE']} /* Release */ = {{")
    w(f"\t\t\tisa = XCBuildConfiguration;")
    w(f"\t\t\tbuildSettings = {{")
    w(f"\t\t\t\tASSTETS_CATALOG_COMPILER_APPICON_NAME = AppIcon;")
    w(f"\t\t\t\tCODE_SIGN_ENTITLEMENTS = Sonique.entitlements;")
    w(f"\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    w(f"\t\t\t\tDEVELOPMENT_TEAM = 7NSS5CJL9E;")
    w(f"\t\t\t\tEMBED_PACKAGE_FRAMEWORKS = YES;")
    w(f"\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
    w(f"\t\t\t\tINFOPLIST_FILE = SoniqueApp/Resources/Info.plist;")
    w(f"\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
    w(f"\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\"$(inherited)\", \"@executable_path/Frameworks\", \"@executable_path/PackageFrameworks\", );")
    w(f"\t\t\t\tLE_SWIFT_VERSION = 5.0;")
    w(f"\t\t\t\tMARKETING_VERSION = 1.0;")
    w(f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.seayniclabs.sonique;")
    w(f"\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    w(f"\t\t\t\tSDKROOT = iphoneos;")
    w(f"\t\t\t\tSUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";")
    w(f"\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    w(f"\t\t\t\tSWIFT_VERSION = 5.0;")
    w(f"\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";")
    w(f"\t\t\t}};")
    w(f"\t\t\tname = Release;")
    w(f"\t\t}};")

    w("/* End XCBuildConfiguration section */")
    w("")

    # ── XCConfigurationList ───────────────────────────────────────────────────
    w("/* Begin XCConfigurationList section */")
    w(f"\t\t{U['PROJECT_CONFIG_LIST']} /* Build configuration list for PBXProject \"Sonique\" */ = {{")
    w(f"\t\t\tisa = XCConfigurationList;")
    w(f"\t\t\tbuildConfigurations = (")
    w(f"\t\t\t\t{U['PROJECT_DEBUG']} /* Debug */,")
    w(f"\t\t\t\t{U['PROJECT_RELEASE']} /* Release */,")
    w(f"\t\t\t);")
    w(f"\t\t\tdefaultConfigurationIsVisible = 0;")
    w(f"\t\t\tdefaultConfigurationName = Release;")
    w(f"\t\t}};")
    w(f"\t\t{U['SONIQUE_CONFIG_LIST']} /* Build configuration list for PBXNativeTarget \"Sonique\" */ = {{")
    w(f"\t\t\tisa = XCConfigurationList;")
    w(f"\t\t\tbuildConfigurations = (")
    w(f"\t\t\t\t{U['SONIQUE_DEBUG']} /* Debug */,")
    w(f"\t\t\t\t{U['SONIQUE_RELEASE']} /* Release */,")
    w(f"\t\t\t);")
    w(f"\t\t\tdefaultConfigurationIsVisible = 0;")
    w(f"\t\t\tdefaultConfigurationName = Release;")
    w(f"\t\t}};")
    w("/* End XCConfigurationList section */")
    w("")

    # ── XCRemoteSwiftPackageReference ─────────────────────────────────────────
    w("/* Begin XCRemoteSwiftPackageReference section */")
    w(f"\t\t{U['LIVEKIT_PKG']} /* XCRemoteSwiftPackageReference \"client-sdk-swift\" */ = {{")
    w(f"\t\t\tisa = XCRemoteSwiftPackageReference;")
    w(f"\t\t\trepositoryURL = \"https://github.com/livekit/client-sdk-swift\";")
    w(f"\t\t\trequirement = {{")
    w(f"\t\t\t\tkind = upToNextMajorVersion;")
    w(f"\t\t\t\tminimumVersion = 2.0.0;")
    w(f"\t\t\t}};")
    w(f"\t\t}};")
    w("/* End XCRemoteSwiftPackageReference section */")
    w("")

    # ── XCSwiftPackageProductDependency ───────────────────────────────────────
    w("/* Begin XCSwiftPackageProductDependency section */")
    w(f"\t\t{U['LIVEKIT_PRODUCT']} /* LiveKit */ = {{")
    w(f"\t\t\tisa = XCSwiftPackageProductDependency;")
    w(f"\t\t\tpackage = {U['LIVEKIT_PKG']} /* XCRemoteSwiftPackageReference \"client-sdk-swift\" */;")
    w(f"\t\t\tproductName = LiveKit;")
    w(f"\t\t}};")
    w("/* End XCSwiftPackageProductDependency section */")
    w("")

    w("\t};")
    w(f"\trootObject = {U['ROOT_PROJECT']} /* Project object */;")
    w("}")

    return "\n".join(lines)


def workspace_data():
    return '''<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
'''


def create_assets_xcassets(base):
    """Create a minimal Assets.xcassets with AppIcon and AccentColor."""
    assets = os.path.join(base, "SoniqueApp", "Resources", "Assets.xcassets")
    os.makedirs(assets, exist_ok=True)
    # Root Contents.json
    with open(os.path.join(assets, "Contents.json"), "w") as f:
        f.write('{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
    # AppIcon
    appicon = os.path.join(assets, "AppIcon.appiconset")
    os.makedirs(appicon, exist_ok=True)
    with open(os.path.join(appicon, "Contents.json"), "w") as f:
        f.write('{\n  "images" : [],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
    # AccentColor
    accent = os.path.join(assets, "AccentColor.colorset")
    os.makedirs(accent, exist_ok=True)
    with open(os.path.join(accent, "Contents.json"), "w") as f:
        f.write('{\n  "colors" : [\n    {\n      "color" : {\n        "colorSpace" : "sRGB",\n        "components" : {\n          "alpha" : "1.000",\n          "blue" : "0.950",\n          "green" : "0.350",\n          "red" : "0.450"\n        }\n      },\n      "idiom" : "universal"\n    }\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')


def main():
    base = os.path.dirname(os.path.abspath(__file__))
    proj_dir = os.path.join(base, "Sonique.xcodeproj")
    ws_dir = os.path.join(proj_dir, "project.xcworkspace")

    os.makedirs(ws_dir, exist_ok=True)

    # project.pbxproj
    pbx_path = os.path.join(proj_dir, "project.pbxproj")
    with open(pbx_path, "w") as f:
        f.write(pbxproj())
    print(f"✓ {pbx_path}")

    # workspace contents
    ws_path = os.path.join(ws_dir, "contents.xcworkspacedata")
    with open(ws_path, "w") as f:
        f.write(workspace_data())
    print(f"✓ {ws_path}")

    # Assets.xcassets
    create_assets_xcassets(base)
    print(f"✓ SoniqueApp/Resources/Assets.xcassets")

    print("\nDone. Open with:")
    print(f"  open {proj_dir}")


if __name__ == "__main__":
    main()
