// Deterministic, dependency-free Xcode project generator.
import fs from 'node:fs';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '..');
let serial = 1;
const objects = {};
const add = value => { const id = (serial++).toString(16).toUpperCase().padStart(24, '0'); objects[id] = value; return id; };
const file = (p, type) => add({isa:'PBXFileReference', lastKnownFileType:type, path:p, sourceTree:'SOURCE_ROOT'});
const signingConfig = file('Config/Signing.xcconfig','text.xcconfig');
const walk = dir => fs.readdirSync(path.join(root, dir), {withFileTypes:true}).flatMap(e => e.isDirectory() ? walk(`${dir}/${e.name}`) : [`${dir}/${e.name}`]);
const mainSources = walk('Inkflow').filter(p=>p.endsWith('.swift')).map(p=>file(p,'sourcecode.swift'));
const shareSources = walk('ShareExtension').filter(p=>p.endsWith('.swift')).map(p=>file(p,'sourcecode.swift'));
const widgetSources = walk('WidgetExtension').filter(p=>p.endsWith('.swift')).map(p=>file(p,'sourcecode.swift'));
const widgetShared = mainSources.filter(id => ['Inkflow/Core/WidgetSnapshot.swift','Inkflow/Core/WidgetRoute.swift','Inkflow/App/InkflowMark.swift'].includes(objects[id].path));
const assets = file('Inkflow/Assets.xcassets','folder.assetcatalog');
const brandAssets = file('BrandAssets.xcassets','folder.assetcatalog');
const privacy = file('Inkflow/PrivacyInfo.xcprivacy','text.xml');
const appProduct = add({isa:'PBXFileReference', explicitFileType:'wrapper.application', path:'Inkflow.app', sourceTree:'BUILT_PRODUCTS_DIR'});
const shareProduct = add({isa:'PBXFileReference', explicitFileType:'wrapper.app-extension', path:'InkflowShare.appex', sourceTree:'BUILT_PRODUCTS_DIR'});
const localProduct = add({isa:'PBXFileReference', explicitFileType:'wrapper.application', path:'InkflowLocal.app', sourceTree:'BUILT_PRODUCTS_DIR'});
const widgetProduct = add({isa:'PBXFileReference', explicitFileType:'wrapper.app-extension', path:'InkflowWidget.appex', sourceTree:'BUILT_PRODUCTS_DIR'});
const localWidgetProduct = add({isa:'PBXFileReference', explicitFileType:'wrapper.app-extension', path:'InkflowLocalWidget.appex', sourceTree:'BUILT_PRODUCTS_DIR'});
const products = add({isa:'PBXGroup', children:[appProduct,shareProduct,localProduct,widgetProduct,localWidgetProduct], name:'Products', sourceTree:'<group>'});
const group = add({isa:'PBXGroup', children:[...mainSources,...shareSources,...widgetSources,assets,brandAssets,privacy,signingConfig,products], sourceTree:'<group>'});
const buildFile = ref => add({isa:'PBXBuildFile',fileRef:ref});
const phase = (isa, refs=[]) => add({isa,buildActionMask:2147483647,files:refs.map(buildFile),runOnlyForDeploymentPostprocessing:0});
const base = {
    CLANG_ENABLE_MODULES:'YES', SWIFT_VERSION:'5.0', IPHONEOS_DEPLOYMENT_TARGET:'17.0',
    SDKROOT:'iphoneos', TARGETED_DEVICE_FAMILY:'1,2', SUPPORTS_MACCATALYST:'YES',
    SUPPORTED_PLATFORMS:['iphoneos','iphonesimulator'],
    SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD:'YES', CODE_SIGN_STYLE:'Automatic',
    DEVELOPMENT_TEAM:'$(QDTH_FULL_DEVELOPMENT_TEAM)',
    GENERATE_INFOPLIST_FILE:'YES', CURRENT_PROJECT_VERSION:'6', MARKETING_VERSION:'1.2.3',
    ENABLE_USER_SCRIPT_SANDBOXING:'YES', SWIFT_EMIT_LOC_STRINGS:'YES'
};
function configList(settings, project=false) {
    const ids = ['Debug','Release'].map(name=>add({isa:'XCBuildConfiguration',name,
        ...(project ? {baseConfigurationReference:signingConfig} : {}),buildSettings:{
        ...(project ? {CLANG_ENABLE_MODULES:'YES', SWIFT_VERSION:'5.0', SDKROOT:'iphoneos', IPHONEOS_DEPLOYMENT_TARGET:'17.0'} : base), ...settings,
        SWIFT_OPTIMIZATION_LEVEL:name==='Debug'?'-Onone':'-O',
        DEBUG_INFORMATION_FORMAT:name==='Debug'?'dwarf':'dwarf-with-dsym',
        SWIFT_ACTIVE_COMPILATION_CONDITIONS:['$(inherited)',...(name==='Debug'?['DEBUG']:[]),...(settings.SWIFT_ACTIVE_COMPILATION_CONDITIONS ?? [])],
        ...(name==='Debug'?{ENABLE_TESTABILITY:'YES'}:{})
    }}));
    return add({isa:'XCConfigurationList',buildConfigurations:ids,defaultConfigurationIsVisible:0,defaultConfigurationName:'Release'});
}
const shareTarget = add({isa:'PBXNativeTarget',name:'InkflowShare',productName:'InkflowShare',productReference:shareProduct,
    productType:'com.apple.product-type.app-extension',buildConfigurationList:configList({
        PRODUCT_BUNDLE_IDENTIFIER:'com.qdth.inkflow.share',PRODUCT_NAME:'$(TARGET_NAME)',
        INFOPLIST_FILE:'ShareExtension/Info.plist',CODE_SIGN_ENTITLEMENTS:'ShareExtension/ShareExtension.entitlements',
        APPLICATION_EXTENSION_API_ONLY:'YES',SKIP_INSTALL:'YES',
        LD_RUNPATH_SEARCH_PATHS:['$(inherited)','@executable_path/Frameworks','@executable_path/../../Frameworks']
    }), buildPhases:[phase('PBXSourcesBuildPhase',shareSources),phase('PBXFrameworksBuildPhase')],buildRules:[],dependencies:[]});
const projectID = add({});
function makeWidget(name, product, local) {
    return add({isa:'PBXNativeTarget',name,productName:name,productReference:product,
        productType:'com.apple.product-type.app-extension',buildConfigurationList:configList({
            DEVELOPMENT_TEAM:local?'$(QDTH_LOCAL_DEVELOPMENT_TEAM)':'$(QDTH_FULL_DEVELOPMENT_TEAM)',
            PRODUCT_BUNDLE_IDENTIFIER:local?'com.wssxzzzz.quandaotiehe.local.widget':'com.qdth.inkflow.widget',
            PRODUCT_NAME:'$(TARGET_NAME)',INFOPLIST_FILE:'WidgetExtension/Info.plist',
            CODE_SIGN_ENTITLEMENTS:local?'WidgetExtension/Local.entitlements':'WidgetExtension/Widget.entitlements',
            SWIFT_ACTIVE_COMPILATION_CONDITIONS:local?['LOCAL_ONLY']:[], SUPPORTS_MACCATALYST:local?'NO':'YES',
            APPLICATION_EXTENSION_API_ONLY:'YES',SKIP_INSTALL:'YES',
            LD_RUNPATH_SEARCH_PATHS:['$(inherited)','@executable_path/Frameworks','@executable_path/../../Frameworks']
        }),buildPhases:[phase('PBXSourcesBuildPhase',[...widgetSources,...widgetShared]),phase('PBXFrameworksBuildPhase'),phase('PBXResourcesBuildPhase',[privacy,brandAssets])],buildRules:[],dependencies:[]});
}
const widgetTarget = makeWidget('InkflowWidget',widgetProduct,false);
const localWidgetTarget = makeWidget('InkflowLocalWidget',localWidgetProduct,true);
function targetDependency(target, name) {
    const proxy = add({isa:'PBXContainerItemProxy',containerPortal:projectID,proxyType:1,remoteGlobalIDString:target,remoteInfo:name});
    return add({isa:'PBXTargetDependency',target,targetProxy:proxy});
}
const widgetDependency = targetDependency(widgetTarget,'InkflowWidget');
const localWidgetDependency = targetDependency(localWidgetTarget,'InkflowLocalWidget');
const proxy = add({isa:'PBXContainerItemProxy',containerPortal:projectID,proxyType:1,remoteGlobalIDString:shareTarget,remoteInfo:'InkflowShare'});
const dependency = add({isa:'PBXTargetDependency',target:shareTarget,targetProxy:proxy});
const embedBuild = add({isa:'PBXBuildFile',fileRef:shareProduct,settings:{ATTRIBUTES:['RemoveHeadersOnCopy']}});
const widgetEmbedBuild = add({isa:'PBXBuildFile',fileRef:widgetProduct,settings:{ATTRIBUTES:['RemoveHeadersOnCopy']}});
const localWidgetEmbedBuild = add({isa:'PBXBuildFile',fileRef:localWidgetProduct,settings:{ATTRIBUTES:['RemoveHeadersOnCopy']}});
const embed = add({isa:'PBXCopyFilesBuildPhase',buildActionMask:2147483647,dstPath:'',dstSubfolderSpec:13,files:[embedBuild,widgetEmbedBuild],name:'Embed App Extensions',runOnlyForDeploymentPostprocessing:0});
const localEmbed = add({isa:'PBXCopyFilesBuildPhase',buildActionMask:2147483647,dstPath:'',dstSubfolderSpec:13,files:[localWidgetEmbedBuild],name:'Embed Widget Extension',runOnlyForDeploymentPostprocessing:0});
const mainTarget = add({isa:'PBXNativeTarget',name:'Inkflow',productName:'Inkflow',productReference:appProduct,
    productType:'com.apple.product-type.application',buildConfigurationList:configList({
        PRODUCT_BUNDLE_IDENTIFIER:'com.qdth.inkflow',PRODUCT_NAME:'$(TARGET_NAME)',
        INFOPLIST_FILE:'Inkflow/Info.plist',CODE_SIGN_ENTITLEMENTS:'Inkflow/Inkflow.entitlements',
        ASSETCATALOG_COMPILER_APPICON_NAME:'AppIcon',LD_RUNPATH_SEARCH_PATHS:['$(inherited)','@executable_path/Frameworks']
    }),buildPhases:[phase('PBXSourcesBuildPhase',mainSources),phase('PBXFrameworksBuildPhase'),phase('PBXResourcesBuildPhase',[assets,privacy,brandAssets]),embed],buildRules:[],dependencies:[dependency,widgetDependency]});
const localTarget = add({isa:'PBXNativeTarget',name:'InkflowLocal',productName:'InkflowLocal',productReference:localProduct,
    productType:'com.apple.product-type.application',buildConfigurationList:configList({
        DEVELOPMENT_TEAM:'$(QDTH_LOCAL_DEVELOPMENT_TEAM)',
        PRODUCT_BUNDLE_IDENTIFIER:'com.wssxzzzz.quandaotiehe.local',PRODUCT_NAME:'$(TARGET_NAME)',
        INFOPLIST_FILE:'Inkflow/LocalInfo.plist',CODE_SIGN_ENTITLEMENTS:'Inkflow/Local.entitlements',
        SWIFT_ACTIVE_COMPILATION_CONDITIONS:['LOCAL_ONLY'], SUPPORTS_MACCATALYST:'NO',
        ASSETCATALOG_COMPILER_APPICON_NAME:'AppIcon',LD_RUNPATH_SEARCH_PATHS:['$(inherited)','@executable_path/Frameworks']
    }),buildPhases:[phase('PBXSourcesBuildPhase',mainSources),phase('PBXFrameworksBuildPhase'),phase('PBXResourcesBuildPhase',[assets,privacy,brandAssets]),localEmbed],buildRules:[],dependencies:[localWidgetDependency]});
objects[projectID] = {isa:'PBXProject',attributes:{BuildIndependentTargetsInParallel:'YES',LastUpgradeCheck:'2610',
    TargetAttributes:{[mainTarget]:{SystemCapabilities:{'com.apple.iCloud':{enabled:1},'com.apple.Push':{enabled:1},'com.apple.BackgroundModes':{enabled:1},'com.apple.ApplicationGroups.iOS':{enabled:1}}},
    ...Object.fromEntries([shareTarget,localTarget,widgetTarget,localWidgetTarget].map(id => [id,{SystemCapabilities:{'com.apple.ApplicationGroups.iOS':{enabled:1}}}]))}},
    buildConfigurationList:configList({},true),compatibilityVersion:'Xcode 14.0',developmentRegion:'zh_CN',hasScannedForEncodings:0,
    knownRegions:['zh_CN','en','Base'],mainGroup:group,productRefGroup:products,projectDirPath:'',projectRoot:'',targets:[localTarget,mainTarget,shareTarget,localWidgetTarget,widgetTarget]};
const format = value => Array.isArray(value) ? `(${value.map(format).join(', ')})` : value && typeof value==='object' ? `{\n${Object.entries(value).map(([k,v])=>`${JSON.stringify(k)} = ${format(v)};`).join('\n')}\n}` : typeof value==='number'?String(value):JSON.stringify(value);
const projectPath = path.join(root,'Inkflow.xcodeproj');
fs.mkdirSync(path.join(projectPath,'xcshareddata/xcschemes'),{recursive:true});
fs.writeFileSync(path.join(projectPath,'project.pbxproj'),'// !$*UTF8*$!\n'+format({archiveVersion:1,classes:{},objectVersion:56,objects,rootObject:projectID})+'\n');
function writeScheme(name, target) {
fs.writeFileSync(path.join(projectPath,`xcshareddata/xcschemes/${name}.xcscheme`),`<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2610" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${target}" BuildableName="${name}.app" BlueprintName="${name}" ReferencedContainer="container:Inkflow.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${target}" BuildableName="${name}.app" BlueprintName="${name}" ReferencedContainer="container:Inkflow.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${target}" BuildableName="${name}.app" BlueprintName="${name}" ReferencedContainer="container:Inkflow.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>`);
}
writeScheme('Inkflow', mainTarget);
writeScheme('InkflowLocal', localTarget);
console.log('Generated Inkflow.xcodeproj');
