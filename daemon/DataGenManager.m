#import "DataGenManager.h"
#import <sys/sysctl.h> 
#import <ifaddrs.h>
#import <arpa/inet.h>

@interface DataGenManager()
@property (nonatomic, strong) NSError *error;
@property (nonatomic, strong) NSMutableArray <DeviceModel *> *deviceModels;
    
@end
@implementation DataGenManager
- (instancetype)init {
    if (self = [super init]) {
        [self setupDeviceSpecifications];
    }
    return self;
}
+ (instancetype)sharedManager {
    static DataGenManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (PhoneInfo *) generatePhoneInfo{
    PhoneInfo * phoneInfo = [[PhoneInfo alloc]init];
    phoneInfo.idfa = [[NSUUID UUID] UUIDString];
    phoneInfo.idfv = [[NSUUID UUID] UUIDString];
    phoneInfo.deviceName = [self generateDeviceName];
    phoneInfo.serialNumber = [self generateSerialNumber];
    phoneInfo.IMEI = [self generateIMEI];
    phoneInfo.MEID = [self generateMEID];
    phoneInfo.iosVersion = [self generateIOSVersion];

    phoneInfo.systemBootUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    phoneInfo.dyldCacheUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    phoneInfo.pasteboardUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    phoneInfo.keychainUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    phoneInfo.userDefaultsUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    phoneInfo.appGroupUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    phoneInfo.coreDataUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    phoneInfo.appInstallUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    phoneInfo.appContainerUUID = [[[NSUUID UUID] UUIDString] lowercaseString];
    
    phoneInfo.storageInfo = [self generateStorage];

    phoneInfo.batteryInfo = [self generateBatteryInfo];

    phoneInfo.wifiInfo = [self generateWiFiInfo];
    // 启动时间
    phoneInfo.upTimeInfo = [self generateUpTimeInfo];

    phoneInfo.deviceModel = [self generateDeviceModel];
    phoneInfo.networkInfo = [self generateNetworkInfo];

    return phoneInfo;
}

- (void)setupDeviceSpecifications {
    // Build a comprehensive database of device specifications
    NSMutableArray <DeviceModel *> *devices = [NSMutableArray array];
    
    // iPhone 8 Plus
    DeviceModel *iphone8Plus = [[DeviceModel alloc] init];
    iphone8Plus.modelName = @"iPhone10,5";
    iphone8Plus.name = @"iPhone 8 Plus";
    iphone8Plus.resolution = @"1920x1080";
    iphone8Plus.viewportResolution = @"2208x1242";
    iphone8Plus.devicePixelRatio = @3.0;
    iphone8Plus.screenDensity = @401;
    iphone8Plus.cpuArchitecture = @"Apple A11 Bionic";
    iphone8Plus.boardId = @"D211AP";
    iphone8Plus.hwModel = @"D211AP";
    // Additional specs from addSpecsForDevice
    iphone8Plus.deviceMemory = @3;
    iphone8Plus.cpuCoreCount = @6;
    iphone8Plus.gpuFamily = @"Apple A11 GPU";
    iphone8Plus.metalFeatureSet = @"Metal 2.3";
    WebGLInfo *iphone8PlusWebGL = [[WebGLInfo alloc] init];
    iphone8PlusWebGL.unmaskedVendor = @"Apple Inc.";
    iphone8PlusWebGL.unmaskedRenderer = @"Apple A11 GPU";
    iphone8PlusWebGL.webglVendor = @"Apple";
    iphone8PlusWebGL.webglRenderer = @"Apple GPU";
    iphone8PlusWebGL.webglVersion = @"WebGL 2.0";
    iphone8PlusWebGL.maxTextureSize = @8192;
    iphone8PlusWebGL.maxRenderBufferSize = @8192;
    iphone8Plus.webGLInfo = iphone8PlusWebGL;
    [devices addObject:iphone8Plus];

    // iPhone X
    DeviceModel *iphoneX = [[DeviceModel alloc] init];
    iphoneX.modelName = @"iPhone10,3";
    iphoneX.name = @"iPhone X";
    iphoneX.resolution = @"2436x1125";
    iphoneX.viewportResolution = @"2436x1125";
    iphoneX.devicePixelRatio = @3.0;
    iphoneX.screenDensity = @458;
    iphoneX.cpuArchitecture = @"Apple A11 Bionic";
    iphoneX.boardId = @"D221AP";
    iphoneX.hwModel = @"D221AP";
    // Additional specs from addSpecsForDevice
    iphoneX.deviceMemory = @3;
    iphoneX.cpuCoreCount = @6;
    iphoneX.gpuFamily = @"Apple A11 GPU";
    iphoneX.metalFeatureSet = @"Metal 2.3";
    WebGLInfo *iphoneXWebGL = [[WebGLInfo alloc] init];
    iphoneXWebGL.unmaskedVendor = @"Apple Inc.";
    iphoneXWebGL.unmaskedRenderer = @"Apple A11 GPU";
    iphoneXWebGL.webglVendor = @"Apple";
    iphoneXWebGL.webglRenderer = @"Apple GPU";
    iphoneXWebGL.webglVersion = @"WebGL 2.0";
    iphoneXWebGL.maxTextureSize = @8192;
    iphoneXWebGL.maxRenderBufferSize = @8192;
    iphoneX.webGLInfo = iphoneXWebGL;
    [devices addObject:iphoneX];

    // iPhone XR
    DeviceModel *iphoneXR = [[DeviceModel alloc] init];
    iphoneXR.modelName = @"iPhone11,8";
    iphoneXR.name = @"iPhone XR";
    iphoneXR.resolution = @"1792x828";
    iphoneXR.viewportResolution = @"1792x828";
    iphoneXR.devicePixelRatio = @2.0;
    iphoneXR.screenDensity = @326;
    iphoneXR.cpuArchitecture = @"Apple A12 Bionic";
    iphoneXR.boardId = @"N841AP";
    iphoneXR.hwModel = @"D331AP";
    // Additional specs from addSpecsForDevice
    iphoneXR.deviceMemory = @4;
    iphoneXR.cpuCoreCount = @6;
    iphoneXR.gpuFamily = @"Apple A12 GPU";
    iphoneXR.metalFeatureSet = @"Metal 2.4";
    WebGLInfo *iphoneXRWebGL = [[WebGLInfo alloc] init];
    iphoneXRWebGL.unmaskedVendor = @"Apple Inc.";
    iphoneXRWebGL.unmaskedRenderer = @"Apple A12 GPU";
    iphoneXRWebGL.webglVendor = @"Apple";
    iphoneXRWebGL.webglRenderer = @"Apple GPU";
    iphoneXRWebGL.webglVersion = @"WebGL 2.0";
    iphoneXRWebGL.maxTextureSize = @8192;
    iphoneXRWebGL.maxRenderBufferSize = @8192;
    iphoneXR.webGLInfo = iphoneXRWebGL;
    [devices addObject:iphoneXR];

    // iPhone XS
    DeviceModel *iphoneXS = [[DeviceModel alloc] init];
    iphoneXS.modelName = @"iPhone11,2";
    iphoneXS.name = @"iPhone XS";
    iphoneXS.resolution = @"2436x1125";
    iphoneXS.viewportResolution = @"2436x1125";
    iphoneXS.devicePixelRatio = @3.0;
    iphoneXS.screenDensity = @458;
    iphoneXS.cpuArchitecture = @"Apple A12 Bionic";
    iphoneXS.boardId = @"D321AP";
    iphoneXS.hwModel = @"D321AP";
    // Additional specs from addSpecsForDevice
    iphoneXS.deviceMemory = @4;
    iphoneXS.cpuCoreCount = @6;
    iphoneXS.gpuFamily = @"Apple A12 GPU";
    iphoneXS.metalFeatureSet = @"Metal 2.4";
    WebGLInfo *iphoneXSWebGL = [[WebGLInfo alloc] init];
    iphoneXSWebGL.unmaskedVendor = @"Apple Inc.";
    iphoneXSWebGL.unmaskedRenderer = @"Apple A12 GPU";
    iphoneXSWebGL.webglVendor = @"Apple";
    iphoneXSWebGL.webglRenderer = @"Apple GPU";
    iphoneXSWebGL.webglVersion = @"WebGL 2.0";
    iphoneXSWebGL.maxTextureSize = @8192;
    iphoneXSWebGL.maxRenderBufferSize = @8192;
    iphoneXS.webGLInfo = iphoneXSWebGL;
    [devices addObject:iphoneXS];
    
    // iPhone XS Max
    DeviceModel *iphoneXSMax = [[DeviceModel alloc] init];
    iphoneXSMax.modelName = @"iPhone11,6";
    iphoneXSMax.name = @"iPhone XS Max";
    iphoneXSMax.resolution = @"2688x1242";
    iphoneXSMax.viewportResolution = @"2688x1242";
    iphoneXSMax.devicePixelRatio = @3.0;
    iphoneXSMax.screenDensity = @458;
    iphoneXSMax.cpuArchitecture = @"Apple A12 Bionic";
    iphoneXSMax.boardId = @"D331AP";
    iphoneXSMax.hwModel = @"D331AP";
    // Additional specs from addSpecsForDevice
    iphoneXSMax.deviceMemory = @4;
    iphoneXSMax.cpuCoreCount = @6;
    iphoneXSMax.gpuFamily = @"Apple A12 GPU";
    iphoneXSMax.metalFeatureSet = @"Metal 2.4";
    WebGLInfo *iphoneXSMaxWebGL = [[WebGLInfo alloc] init];
    iphoneXSMaxWebGL.unmaskedVendor = @"Apple Inc.";
    iphoneXSMaxWebGL.unmaskedRenderer = @"Apple A12 GPU";
    iphoneXSMaxWebGL.webglVendor = @"Apple";
    iphoneXSMaxWebGL.webglRenderer = @"Apple GPU";
    iphoneXSMaxWebGL.webglVersion = @"WebGL 2.0";
    iphoneXSMaxWebGL.maxTextureSize = @8192;
    iphoneXSMaxWebGL.maxRenderBufferSize = @8192;
    iphoneXSMax.webGLInfo = iphoneXSMaxWebGL;
    [devices addObject:iphoneXSMax];
    
    // iPhone 11
    DeviceModel *iphone11 = [[DeviceModel alloc] init];
    iphone11.modelName = @"iPhone12,1";
    iphone11.name = @"iPhone 11";
    iphone11.resolution = @"1792x828";
    iphone11.viewportResolution = @"1792x828";
    iphone11.devicePixelRatio = @2.0;
    iphone11.screenDensity = @326;
    iphone11.cpuArchitecture = @"Apple A13 Bionic";
    iphone11.boardId = @"N104AP";
    iphone11.hwModel = @"D421AP";
    // Additional specs from addSpecsForDevice
    iphone11.deviceMemory = @4;
    iphone11.cpuCoreCount = @6;
    iphone11.gpuFamily = @"Apple A13 GPU";
    iphone11.metalFeatureSet = @"Metal 3.0";
    WebGLInfo *iphone11WebGL = [[WebGLInfo alloc] init];
    iphone11WebGL.unmaskedVendor = @"Apple Inc.";
    iphone11WebGL.unmaskedRenderer = @"Apple A13 GPU";
    iphone11WebGL.webglVendor = @"Apple";
    iphone11WebGL.webglRenderer = @"Apple GPU";
    iphone11WebGL.webglVersion = @"WebGL 2.0";
    iphone11WebGL.maxTextureSize = @16384;
    iphone11WebGL.maxRenderBufferSize = @16384;
    iphone11.webGLInfo = iphone11WebGL;
    [devices addObject:iphone11];
    
    // iPhone 11 Pro
    DeviceModel *iphone11Pro = [[DeviceModel alloc] init];
    iphone11Pro.modelName = @"iPhone12,3";
    iphone11Pro.name = @"iPhone 11 Pro";
    iphone11Pro.resolution = @"2436x1125";
    iphone11Pro.viewportResolution = @"2436x1125";
    iphone11Pro.devicePixelRatio = @3.0;
    iphone11Pro.screenDensity = @458;
    iphone11Pro.cpuArchitecture = @"Apple A13 Bionic";
    iphone11Pro.boardId = @"D431AP";
    iphone11Pro.hwModel = @"D431AP";
    // Additional specs from addSpecsForDevice
    iphone11Pro.deviceMemory = @4;
    iphone11Pro.cpuCoreCount = @6;
    iphone11Pro.gpuFamily = @"Apple A13 GPU";
    iphone11Pro.metalFeatureSet = @"Metal 3.0";
    WebGLInfo *iphone11ProWebGL = [[WebGLInfo alloc] init];
    iphone11ProWebGL.unmaskedVendor = @"Apple Inc.";
    iphone11ProWebGL.unmaskedRenderer = @"Apple A13 GPU";
    iphone11ProWebGL.webglVendor = @"Apple";
    iphone11ProWebGL.webglRenderer = @"Apple GPU";
    iphone11ProWebGL.webglVersion = @"WebGL 2.0";
    iphone11ProWebGL.maxTextureSize = @16384;
    iphone11ProWebGL.maxRenderBufferSize = @16384;
    iphone11Pro.webGLInfo = iphone11ProWebGL;
    [devices addObject:iphone11Pro];
    
    // iPhone 11 Pro Max
    DeviceModel *iphone11ProMax = [[DeviceModel alloc] init];
    iphone11ProMax.modelName = @"iPhone12,5";
    iphone11ProMax.name = @"iPhone 11 Pro Max";
    iphone11ProMax.resolution = @"2688x1242";
    iphone11ProMax.viewportResolution = @"2688x1242";
    iphone11ProMax.devicePixelRatio = @3.0;
    iphone11ProMax.screenDensity = @458;
    iphone11ProMax.cpuArchitecture = @"Apple A13 Bionic";
    iphone11ProMax.boardId = @"D441AP";
    iphone11ProMax.hwModel = @"D441AP";
    // Additional specs from addSpecsForDevice
    iphone11ProMax.deviceMemory = @4;
    iphone11ProMax.cpuCoreCount = @6;
    iphone11ProMax.gpuFamily = @"Apple A13 GPU";
    iphone11ProMax.metalFeatureSet = @"Metal 3.0";
    WebGLInfo *iphone11ProMaxWebGL = [[WebGLInfo alloc] init];
    iphone11ProMaxWebGL.unmaskedVendor = @"Apple Inc.";
    iphone11ProMaxWebGL.unmaskedRenderer = @"Apple A13 GPU";
    iphone11ProMaxWebGL.webglVendor = @"Apple";
    iphone11ProMaxWebGL.webglRenderer = @"Apple GPU";
    iphone11ProMaxWebGL.webglVersion = @"WebGL 2.0";
    iphone11ProMaxWebGL.maxTextureSize = @16384;
    iphone11ProMaxWebGL.maxRenderBufferSize = @16384;
    iphone11ProMax.webGLInfo = iphone11ProMaxWebGL;
    [devices addObject:iphone11ProMax];
    
    // iPhone SE (2nd Gen)
    DeviceModel *iphoneSE2 = [[DeviceModel alloc] init];
    iphoneSE2.modelName = @"iPhone12,8";
    iphoneSE2.name = @"iPhone SE (2nd Gen)";
    iphoneSE2.resolution = @"1334x750";
    iphoneSE2.viewportResolution = @"1334x750";
    iphoneSE2.devicePixelRatio = @2.0;
    iphoneSE2.screenDensity = @326;
    iphoneSE2.cpuArchitecture = @"Apple A13 Bionic";
    iphoneSE2.boardId = @"D79AP";
    iphoneSE2.hwModel = @"D79AP";
    // Additional specs from addSpecsForDevice
    iphoneSE2.deviceMemory = @4;
    iphoneSE2.cpuCoreCount = @6;
    iphoneSE2.gpuFamily = @"Apple A13 GPU";
    iphoneSE2.metalFeatureSet = @"Metal 3.0";
    WebGLInfo *iphoneSE2WebGL = [[WebGLInfo alloc] init];
    iphoneSE2WebGL.unmaskedVendor = @"Apple Inc.";
    iphoneSE2WebGL.unmaskedRenderer = @"Apple A13 GPU";
    iphoneSE2WebGL.webglVendor = @"Apple";
    iphoneSE2WebGL.webglRenderer = @"Apple GPU";
    iphoneSE2WebGL.webglVersion = @"WebGL 2.0";
    iphoneSE2WebGL.maxTextureSize = @16384;
    iphoneSE2WebGL.maxRenderBufferSize = @16384;
    iphoneSE2.webGLInfo = iphoneSE2WebGL;
    [devices addObject:iphoneSE2];
    
    // iPhone 12 mini
    DeviceModel *iphone12mini = [[DeviceModel alloc] init];
    iphone12mini.modelName = @"iPhone13,1";
    iphone12mini.name = @"iPhone 12 mini";
    iphone12mini.resolution = @"2340x1080";
    iphone12mini.viewportResolution = @"2340x1080";
    iphone12mini.devicePixelRatio = @3.0;
    iphone12mini.screenDensity = @476;
    iphone12mini.cpuArchitecture = @"Apple A14 Bionic";
    iphone12mini.boardId = @"D52gAP";
    iphone12mini.hwModel = @"D52gAP";
    // Additional specs from addSpecsForDevice
    iphone12mini.deviceMemory = @4;
    iphone12mini.cpuCoreCount = @6;
    iphone12mini.gpuFamily = @"Apple A14 GPU";
    iphone12mini.metalFeatureSet = @"Metal 3.0";
    WebGLInfo *iphone12miniWebGL = [[WebGLInfo alloc] init];
    iphone12miniWebGL.unmaskedVendor = @"Apple Inc.";
    iphone12miniWebGL.unmaskedRenderer = @"Apple A14 GPU";
    iphone12miniWebGL.webglVendor = @"Apple";
    iphone12miniWebGL.webglRenderer = @"Apple GPU";
    iphone12miniWebGL.webglVersion = @"WebGL 2.0";
    iphone12miniWebGL.maxTextureSize = @16384;
    iphone12miniWebGL.maxRenderBufferSize = @16384;
    iphone12mini.webGLInfo = iphone12miniWebGL;
    [devices addObject:iphone12mini];
    
    // iPhone 12
    DeviceModel *iphone12 = [[DeviceModel alloc] init];
    iphone12.modelName = @"iPhone13,2";
    iphone12.name = @"iPhone 12";
    iphone12.resolution = @"2532x1170";
    iphone12.viewportResolution = @"2532x1170";
    iphone12.devicePixelRatio = @3.0;
    iphone12.screenDensity = @460;
    iphone12.cpuArchitecture = @"Apple A14 Bionic";
    iphone12.boardId = @"D53gAP";
    iphone12.hwModel = @"D53gAP";
    // Additional specs from addSpecsForDevice
    iphone12.deviceMemory = @4;
    iphone12.cpuCoreCount = @6;
    iphone12.gpuFamily = @"Apple A14 GPU";
    iphone12.metalFeatureSet = @"Metal 3.0";
    WebGLInfo *iphone12WebGL = [[WebGLInfo alloc] init];
    iphone12WebGL.unmaskedVendor = @"Apple Inc.";
    iphone12WebGL.unmaskedRenderer = @"Apple A14 GPU";
    iphone12WebGL.webglVendor = @"Apple";
    iphone12WebGL.webglRenderer = @"Apple GPU";
    iphone12WebGL.webglVersion = @"WebGL 2.0";
    iphone12WebGL.maxTextureSize = @16384;
    iphone12WebGL.maxRenderBufferSize = @16384;
    iphone12.webGLInfo = iphone12WebGL;
    [devices addObject:iphone12];
    
    // iPhone 12 Pro
    DeviceModel *iphone12Pro = [[DeviceModel alloc] init];
    iphone12Pro.modelName = @"iPhone13,3";
    iphone12Pro.name = @"iPhone 12 Pro";
    iphone12Pro.resolution = @"2532x1170";
    iphone12Pro.viewportResolution = @"2532x1170";
    iphone12Pro.devicePixelRatio = @3.0;
    iphone12Pro.screenDensity = @460;
    iphone12Pro.cpuArchitecture = @"Apple A14 Bionic";
    iphone12Pro.boardId = @"D53pAP";
    iphone12Pro.hwModel = @"D53pAP";
    // Additional specs from addSpecsForDevice
    iphone12Pro.deviceMemory = @6;
    iphone12Pro.cpuCoreCount = @6;
    iphone12Pro.gpuFamily = @"Apple A14 GPU";
    iphone12Pro.metalFeatureSet = @"Metal 3.0";
    WebGLInfo *iphone12ProWebGL = [[WebGLInfo alloc] init];
    iphone12ProWebGL.unmaskedVendor = @"Apple Inc.";
    iphone12ProWebGL.unmaskedRenderer = @"Apple A14 GPU";
    iphone12ProWebGL.webglVendor = @"Apple";
    iphone12ProWebGL.webglRenderer = @"Apple GPU";
    iphone12ProWebGL.webglVersion = @"WebGL 2.0";
    iphone12ProWebGL.maxTextureSize = @16384;
    iphone12ProWebGL.maxRenderBufferSize = @16384;
    iphone12Pro.webGLInfo = iphone12ProWebGL;
    [devices addObject:iphone12Pro];
    
    // iPhone 12 Pro Max
    DeviceModel *iphone12ProMax = [[DeviceModel alloc] init];
    iphone12ProMax.modelName = @"iPhone13,4";
    iphone12ProMax.name = @"iPhone 12 Pro Max";
    iphone12ProMax.resolution = @"2778x1284";
    iphone12ProMax.viewportResolution = @"2778x1284";
    iphone12ProMax.devicePixelRatio = @3.0;
    iphone12ProMax.screenDensity = @458;
    iphone12ProMax.cpuArchitecture = @"Apple A14 Bionic";
    iphone12ProMax.boardId = @"D54pAP";
    iphone12ProMax.hwModel = @"D54pAP";
    // Additional specs from addSpecsForDevice
    iphone12ProMax.deviceMemory = @6;
    iphone12ProMax.cpuCoreCount = @6;
    iphone12ProMax.gpuFamily = @"Apple A14 GPU";
    iphone12ProMax.metalFeatureSet = @"Metal 3.0";
    WebGLInfo *iphone12ProMaxWebGL = [[WebGLInfo alloc] init];
    iphone12ProMaxWebGL.unmaskedVendor = @"Apple Inc.";
    iphone12ProMaxWebGL.unmaskedRenderer = @"Apple A14 GPU";
    iphone12ProMaxWebGL.webglVendor = @"Apple";
    iphone12ProMaxWebGL.webglRenderer = @"Apple GPU";
    iphone12ProMaxWebGL.webglVersion = @"WebGL 2.0";
    iphone12ProMaxWebGL.maxTextureSize = @16384;
    iphone12ProMaxWebGL.maxRenderBufferSize = @16384;
    iphone12ProMax.webGLInfo = iphone12ProMaxWebGL;
    [devices addObject:iphone12ProMax];

    // iPhone 13 mini
    DeviceModel *iphone13mini = [[DeviceModel alloc] init];
    iphone13mini.modelName = @"iPhone14,4";
    iphone13mini.name = @"iPhone 13 mini";
    iphone13mini.resolution = @"2340x1080";
    iphone13mini.viewportResolution = @"2340x1080";
    iphone13mini.devicePixelRatio = @3.0;
    iphone13mini.screenDensity = @476;
    iphone13mini.cpuArchitecture = @"Apple A15 Bionic";
    iphone13mini.boardId = @"D16AP";
    iphone13mini.hwModel = @"D16AP";
    // Additional specs from addSpecsForDevice
    iphone13mini.deviceMemory = @4;
    iphone13mini.cpuCoreCount = @6;
    iphone13mini.gpuFamily = @"Apple A15 GPU";
    iphone13mini.metalFeatureSet = @"Metal 3.0";
    WebGLInfo *iphone13miniWebGL = [[WebGLInfo alloc] init];
    iphone13miniWebGL.unmaskedVendor = @"Apple Inc.";
    iphone13miniWebGL.unmaskedRenderer = @"Apple A15 GPU";
    iphone13miniWebGL.webglVendor = @"Apple";
    iphone13miniWebGL.webglRenderer = @"Apple GPU";
    iphone13miniWebGL.webglVersion = @"WebGL 2.0";
    iphone13miniWebGL.maxTextureSize = @16384;
    iphone13miniWebGL.maxRenderBufferSize = @16384;
    iphone13mini.webGLInfo = iphone13miniWebGL;
    [devices addObject:iphone13mini];
    
    // iPhone 13
    DeviceModel *iphone13 = [[DeviceModel alloc] init];
    iphone13.modelName = @"iPhone14,5";
    iphone13.name = @"iPhone 13";
    iphone13.resolution = @"2532x1170";
    iphone13.viewportResolution = @"2532x1170";
    iphone13.devicePixelRatio = @3.0;
    iphone13.screenDensity = @460;
    iphone13.cpuArchitecture = @"Apple A15 Bionic";
    iphone13.boardId = @"D17AP";
    iphone13.hwModel = @"D17AP";
    // Additional specs from addSpecsForDevice
    iphone13.deviceMemory = @4;
    iphone13.cpuCoreCount = @6;
    iphone13.gpuFamily = @"Apple A15 GPU";
    iphone13.metalFeatureSet = @"Metal 3.0";
    WebGLInfo *iphone13WebGL = [[WebGLInfo alloc] init];
    iphone13WebGL.unmaskedVendor = @"Apple Inc.";
    iphone13WebGL.unmaskedRenderer = @"Apple A15 GPU";
    iphone13WebGL.webglVendor = @"Apple";
    iphone13WebGL.webglRenderer = @"Apple GPU";
    iphone13WebGL.webglVersion = @"WebGL 2.0";
    iphone13WebGL.maxTextureSize = @16384;
    iphone13WebGL.maxRenderBufferSize = @16384;
    iphone13.webGLInfo = iphone13WebGL;
    [devices addObject:iphone13];
    
    // iPhone 13 Pro
    DeviceModel *iphone13Pro = [[DeviceModel alloc] init];
    iphone13Pro.modelName = @"iPhone14,2";
    iphone13Pro.name = @"iPhone 13 Pro";
    iphone13Pro.resolution = @"2532x1170";
    iphone13Pro.viewportResolution = @"2532x1170";
    iphone13Pro.devicePixelRatio = @3.0;
    iphone13Pro.screenDensity = @460;
    iphone13Pro.cpuArchitecture = @"Apple A15 Bionic";
    iphone13Pro.boardId = @"D63AP";
    iphone13Pro.hwModel = @"D63AP";
    // Additional specs from addSpecsForDevice
    iphone13Pro.deviceMemory = @6;
    iphone13Pro.cpuCoreCount = @6;
    iphone13Pro.gpuFamily = @"Apple A15 GPU";
    iphone13Pro.metalFeatureSet = @"Metal 3.0";
    WebGLInfo *iphone13ProWebGL = [[WebGLInfo alloc] init];
    iphone13ProWebGL.unmaskedVendor = @"Apple Inc.";
    iphone13ProWebGL.unmaskedRenderer = @"Apple A15 GPU";
    iphone13ProWebGL.webglVendor = @"Apple";
    iphone13ProWebGL.webglRenderer = @"Apple GPU";
    iphone13ProWebGL.webglVersion = @"WebGL 2.0";
    iphone13ProWebGL.maxTextureSize = @16384;
    iphone13ProWebGL.maxRenderBufferSize = @16384;
    iphone13Pro.webGLInfo = iphone13ProWebGL;
    [devices addObject:iphone13Pro];
    
    // iPhone 13 Pro Max
    DeviceModel *iphone13ProMax = [[DeviceModel alloc] init];
    iphone13ProMax.modelName = @"iPhone14,3";
    iphone13ProMax.name = @"iPhone 13 Pro Max";
    iphone13ProMax.resolution = @"2778x1284";
    iphone13ProMax.viewportResolution = @"2778x1284";
    iphone13ProMax.devicePixelRatio = @3.0;
    iphone13ProMax.screenDensity = @458;
    iphone13ProMax.cpuArchitecture = @"Apple A15 Bionic";
    iphone13ProMax.boardId = @"D64AP";
    iphone13ProMax.hwModel = @"D64AP";
    // Additional specs from addSpecsForDevice
    iphone13ProMax.deviceMemory = @6;
    iphone13ProMax.cpuCoreCount = @6;
    iphone13ProMax.gpuFamily = @"Apple A15 GPU";
    iphone13ProMax.metalFeatureSet = @"Metal 3.0";
    WebGLInfo *iphone13ProMaxWebGL = [[WebGLInfo alloc] init];
    iphone13ProMaxWebGL.unmaskedVendor = @"Apple Inc.";
    iphone13ProMaxWebGL.unmaskedRenderer = @"Apple A15 GPU";
    iphone13ProMaxWebGL.webglVendor = @"Apple";
    iphone13ProMaxWebGL.webglRenderer = @"Apple GPU";
    iphone13ProMaxWebGL.webglVersion = @"WebGL 2.0";
    iphone13ProMaxWebGL.maxTextureSize = @16384;
    iphone13ProMaxWebGL.maxRenderBufferSize = @16384;
    iphone13ProMax.webGLInfo = iphone13ProMaxWebGL;
    [devices addObject:iphone13ProMax];
    
    // iPhone SE (3rd Gen)
    DeviceModel *iphoneSE3 = [[DeviceModel alloc] init];
    iphoneSE3.modelName = @"iPhone14,6";
    iphoneSE3.name = @"iPhone SE (3rd Gen)";
    iphoneSE3.resolution = @"1334x750";
    iphoneSE3.viewportResolution = @"1334x750";
    iphoneSE3.devicePixelRatio = @2.0;
    iphoneSE3.screenDensity = @326;
    iphoneSE3.cpuArchitecture = @"Apple A15 Bionic";
    iphoneSE3.boardId = @"D49AP";
    iphoneSE3.hwModel = @"D49AP";
    // Additional specs from addSpecsForDevice
    iphoneSE3.deviceMemory = @4;
    iphoneSE3.cpuCoreCount = @6;
    iphoneSE3.gpuFamily = @"Apple A15 GPU";
    iphoneSE3.metalFeatureSet = @"Metal 3.0";
    WebGLInfo *iphoneSE3WebGL = [[WebGLInfo alloc] init];
    iphoneSE3WebGL.unmaskedVendor = @"Apple Inc.";
    iphoneSE3WebGL.unmaskedRenderer = @"Apple A15 GPU";
    iphoneSE3WebGL.webglVendor = @"Apple";
    iphoneSE3WebGL.webglRenderer = @"Apple GPU";
    iphoneSE3WebGL.webglVersion = @"WebGL 2.0";
    iphoneSE3WebGL.maxTextureSize = @16384;
    iphoneSE3WebGL.maxRenderBufferSize = @16384;
    iphoneSE3.webGLInfo = iphoneSE3WebGL;
    [devices addObject:iphoneSE3];
    
    // iPhone 14
    DeviceModel *iphone14 = [[DeviceModel alloc] init];
    iphone14.modelName = @"iPhone14,7";
    iphone14.name = @"iPhone 14";
    iphone14.resolution = @"2532x1170";
    iphone14.viewportResolution = @"2532x1170";
    iphone14.devicePixelRatio = @3.0;
    iphone14.screenDensity = @460;
    iphone14.cpuArchitecture = @"Apple A15 Bionic";
    iphone14.boardId = @"D27AP";
    iphone14.hwModel = @"D27AP";
    // Additional specs from addSpecsForDevice
    iphone14.deviceMemory = @4;
    iphone14.cpuCoreCount = @6;
    iphone14.gpuFamily = @"Apple A15 GPU";
    iphone14.metalFeatureSet = @"Metal 3.0";
    WebGLInfo *iphone14WebGL = [[WebGLInfo alloc] init];
    iphone14WebGL.unmaskedVendor = @"Apple Inc.";
    iphone14WebGL.unmaskedRenderer = @"Apple A15 GPU";
    iphone14WebGL.webglVendor = @"Apple";
    iphone14WebGL.webglRenderer = @"Apple GPU";
    iphone14WebGL.webglVersion = @"WebGL 2.0";
    iphone14WebGL.maxTextureSize = @16384;
    iphone14WebGL.maxRenderBufferSize = @16384;
    iphone14.webGLInfo = iphone14WebGL;
    [devices addObject:iphone14];

    // iPhone 14 Plus
    DeviceModel *iphone14Plus = [[DeviceModel alloc] init];
    iphone14Plus.modelName = @"iPhone14,8";
    iphone14Plus.name = @"iPhone 14 Plus";
    iphone14Plus.resolution = @"2778x1284";
    iphone14Plus.viewportResolution = @"2778x1284";
    iphone14Plus.devicePixelRatio = @3.0;
    iphone14Plus.screenDensity = @458;
    iphone14Plus.cpuArchitecture = @"Apple A15 Bionic";
    iphone14Plus.boardId = @"D28AP";
    iphone14Plus.hwModel = @"D28AP";
    // Additional specs from addSpecsForDevice
    iphone14Plus.deviceMemory = @4;
    iphone14Plus.cpuCoreCount = @6;
    iphone14Plus.gpuFamily = @"Apple A15 GPU";
    iphone14Plus.metalFeatureSet = @"Metal 3.0";
    WebGLInfo *iphone14PlusWebGL = [[WebGLInfo alloc] init];
    iphone14PlusWebGL.unmaskedVendor = @"Apple Inc.";
    iphone14PlusWebGL.unmaskedRenderer = @"Apple A15 GPU";
    iphone14PlusWebGL.webglVendor = @"Apple";
    iphone14PlusWebGL.webglRenderer = @"Apple GPU";
    iphone14PlusWebGL.webglVersion = @"WebGL 2.0";
    iphone14PlusWebGL.maxTextureSize = @16384;
    iphone14PlusWebGL.maxRenderBufferSize = @16384;
    iphone14Plus.webGLInfo = iphone14PlusWebGL;
    [devices addObject:iphone14Plus];
    
    // iPhone 14 Pro
    DeviceModel *iphone14Pro = [[DeviceModel alloc] init];
    iphone14Pro.modelName = @"iPhone15,2";
    iphone14Pro.name = @"iPhone 14 Pro";
    iphone14Pro.resolution = @"2556x1179";
    iphone14Pro.viewportResolution = @"2556x1179";
    iphone14Pro.devicePixelRatio = @3.0;
    iphone14Pro.screenDensity = @460;
    iphone14Pro.cpuArchitecture = @"Apple A16 Bionic";
    iphone14Pro.boardId = @"D73AP";
    iphone14Pro.hwModel = @"D73AP";
    // Additional specs from addSpecsForDevice
    iphone14Pro.deviceMemory = @6;
    iphone14Pro.cpuCoreCount = @6;
    iphone14Pro.gpuFamily = @"Apple A16 Pro GPU";
    iphone14Pro.metalFeatureSet = @"Metal 3.1";
    WebGLInfo *iphone14ProWebGL = [[WebGLInfo alloc] init];
    iphone14ProWebGL.unmaskedVendor = @"Apple Inc.";
    iphone14ProWebGL.unmaskedRenderer = @"Apple A16 GPU";
    iphone14ProWebGL.webglVendor = @"Apple";
    iphone14ProWebGL.webglRenderer = @"Apple GPU";
    iphone14ProWebGL.webglVersion = @"WebGL 2.0";
    iphone14ProWebGL.maxTextureSize = @16384;
    iphone14ProWebGL.maxRenderBufferSize = @16384;
    iphone14Pro.webGLInfo = iphone14ProWebGL;
    [devices addObject:iphone14Pro];
    
    // iPhone 14 Pro Max
    DeviceModel *iphone14ProMax = [[DeviceModel alloc] init];
    iphone14ProMax.modelName = @"iPhone15,3";
    iphone14ProMax.name = @"iPhone 14 Pro Max";
    iphone14ProMax.resolution = @"2796x1290";
    iphone14ProMax.viewportResolution = @"2796x1290";
    iphone14ProMax.devicePixelRatio = @3.0;
    iphone14ProMax.screenDensity = @460;
    iphone14ProMax.cpuArchitecture = @"Apple A16 Bionic";
    iphone14ProMax.boardId = @"D74AP";
    iphone14ProMax.hwModel = @"D74AP";
    // Additional specs from addSpecsForDevice
    iphone14ProMax.deviceMemory = @6;
    iphone14ProMax.cpuCoreCount = @6;
    iphone14ProMax.gpuFamily = @"Apple A16 Pro GPU";
    iphone14ProMax.metalFeatureSet = @"Metal 3.1";
    WebGLInfo *iphone14ProMaxWebGL = [[WebGLInfo alloc] init];
    iphone14ProMaxWebGL.unmaskedVendor = @"Apple Inc.";
    iphone14ProMaxWebGL.unmaskedRenderer = @"Apple A16 GPU";
    iphone14ProMaxWebGL.webglVendor = @"Apple";
    iphone14ProMaxWebGL.webglRenderer = @"Apple GPU";
    iphone14ProMaxWebGL.webglVersion = @"WebGL 2.0";
    iphone14ProMaxWebGL.maxTextureSize = @16384;
    iphone14ProMaxWebGL.maxRenderBufferSize = @16384;
    iphone14ProMax.webGLInfo = iphone14ProMaxWebGL;
    [devices addObject:iphone14ProMax];
    
    // iPhone 15
    DeviceModel *iphone15 = [[DeviceModel alloc] init];
    iphone15.modelName = @"iPhone15,4";
    iphone15.name = @"iPhone 15";
    iphone15.resolution = @"2556x1179";
    iphone15.viewportResolution = @"2556x1179";
    iphone15.devicePixelRatio = @3.0;
    iphone15.screenDensity = @460;
    iphone15.cpuArchitecture = @"Apple A16 Bionic";
    iphone15.boardId = @"D37AP";
    iphone15.hwModel = @"D37AP";
    // Additional specs from addSpecsForDevice
    iphone15.deviceMemory = @6;
    iphone15.cpuCoreCount = @6;
    iphone15.gpuFamily = @"Apple A16 GPU";
    iphone15.metalFeatureSet = @"Metal 3.0";
    WebGLInfo *iphone15WebGL = [[WebGLInfo alloc] init];
    iphone15WebGL.unmaskedVendor = @"Apple Inc.";
    iphone15WebGL.unmaskedRenderer = @"Apple A16 GPU";
    iphone15WebGL.webglVendor = @"Apple";
    iphone15WebGL.webglRenderer = @"Apple GPU";
    iphone15WebGL.webglVersion = @"WebGL 2.0";
    iphone15WebGL.maxTextureSize = @16384;
    iphone15WebGL.maxRenderBufferSize = @16384;
    iphone15.webGLInfo = iphone15WebGL;
    [devices addObject:iphone15];
    
    // iPhone 15 Plus
    DeviceModel *iphone15Plus = [[DeviceModel alloc] init];
    iphone15Plus.modelName = @"iPhone15,5";
    iphone15Plus.name = @"iPhone 15 Plus";
    iphone15Plus.resolution = @"2796x1290";
    iphone15Plus.viewportResolution = @"2796x1290";
    iphone15Plus.devicePixelRatio = @3.0;
    iphone15Plus.screenDensity = @460;
    iphone15Plus.cpuArchitecture = @"Apple A16 Bionic";
    iphone15Plus.boardId = @"D38AP";
    iphone15Plus.hwModel = @"D38AP";
    // Additional specs from addSpecsForDevice
    iphone15Plus.deviceMemory = @6;
    iphone15Plus.cpuCoreCount = @6;
    iphone15Plus.gpuFamily = @"Apple A16 GPU";
    iphone15Plus.metalFeatureSet = @"Metal 3.0";
    WebGLInfo *iphone15PlusWebGL = [[WebGLInfo alloc] init];
    iphone15PlusWebGL.unmaskedVendor = @"Apple Inc.";
    iphone15PlusWebGL.unmaskedRenderer = @"Apple A16 GPU";
    iphone15PlusWebGL.webglVendor = @"Apple";
    iphone15PlusWebGL.webglRenderer = @"Apple GPU";
    iphone15PlusWebGL.webglVersion = @"WebGL 2.0";
    iphone15PlusWebGL.maxTextureSize = @16384;
    iphone15PlusWebGL.maxRenderBufferSize = @16384;
    iphone15Plus.webGLInfo = iphone15PlusWebGL;
    [devices addObject:iphone15Plus];
    
    // iPhone 15 Pro
    DeviceModel *iphone15Pro = [[DeviceModel alloc] init];
    iphone15Pro.modelName = @"iPhone16,1";
    iphone15Pro.name = @"iPhone 15 Pro";
    iphone15Pro.resolution = @"2556x1179";
    iphone15Pro.viewportResolution = @"2556x1179";
    iphone15Pro.devicePixelRatio = @3.0;
    iphone15Pro.screenDensity = @460;
    iphone15Pro.cpuArchitecture = @"Apple A17 Pro";
    iphone15Pro.boardId = @"D83AP";
    iphone15Pro.hwModel = @"D83AP";
    // Additional specs from addSpecsForDevice
    iphone15Pro.deviceMemory = @8;
    iphone15Pro.cpuCoreCount = @6;
    iphone15Pro.gpuFamily = @"Apple A17 Pro GPU";
    iphone15Pro.metalFeatureSet = @"Metal 3.1";
    WebGLInfo *iphone15ProWebGL = [[WebGLInfo alloc] init];
    iphone15ProWebGL.unmaskedVendor = @"Apple Inc.";
    iphone15ProWebGL.unmaskedRenderer = @"Apple A17 Pro GPU";
    iphone15ProWebGL.webglVendor = @"Apple";
    iphone15ProWebGL.webglRenderer = @"Apple GPU";
    iphone15ProWebGL.webglVersion = @"WebGL 2.0";
    iphone15ProWebGL.maxTextureSize = @16384;
    iphone15ProWebGL.maxRenderBufferSize = @16384;
    iphone15Pro.webGLInfo = iphone15ProWebGL;
    [devices addObject:iphone15Pro];
    
    // iPhone 15 Pro Max
    DeviceModel *iphone15ProMax = [[DeviceModel alloc] init];
    iphone15ProMax.modelName = @"iPhone16,2";
    iphone15ProMax.name = @"iPhone 15 Pro Max";
    iphone15ProMax.resolution = @"2796x1290";
    iphone15ProMax.viewportResolution = @"2796x1290";
    iphone15ProMax.devicePixelRatio = @3.0;
    iphone15ProMax.screenDensity = @460;
    iphone15ProMax.cpuArchitecture = @"Apple A17 Pro";
    iphone15ProMax.boardId = @"D84AP";
    iphone15ProMax.hwModel = @"D84AP";
    // Additional specs from addSpecsForDevice
    iphone15ProMax.deviceMemory = @8;
    iphone15ProMax.cpuCoreCount = @6;
    iphone15ProMax.gpuFamily = @"Apple A17 Pro GPU";
    iphone15ProMax.metalFeatureSet = @"Metal 3.1";
    WebGLInfo *iphone15ProMaxWebGL = [[WebGLInfo alloc] init];
    iphone15ProMaxWebGL.unmaskedVendor = @"Apple Inc.";
    iphone15ProMaxWebGL.unmaskedRenderer = @"Apple A17 Pro GPU";
    iphone15ProMaxWebGL.webglVendor = @"Apple";
    iphone15ProMaxWebGL.webglRenderer = @"Apple GPU";
    iphone15ProMaxWebGL.webglVersion = @"WebGL 2.0";
    iphone15ProMaxWebGL.maxTextureSize = @16384;
    iphone15ProMaxWebGL.maxRenderBufferSize = @16384;
    iphone15ProMax.webGLInfo = iphone15ProMaxWebGL;
    [devices addObject:iphone15ProMax];
    
    // Store all specifications
    self.deviceModels = [devices copy];
}

-(DeviceModel *) generateDeviceModel{
    NSUInteger idx = arc4random_uniform((uint32_t)_deviceModels.count);
    return _deviceModels[idx];
}

-(UpTimeInfo *)generateUpTimeInfo{
    UpTimeInfo * upTimeInfo = [[UpTimeInfo alloc]init];
    NSTimeInterval minUptime = 12 * 3600; // 12 hours
    NSTimeInterval maxUptime = 48 * 3600; // 48 hours
    NSTimeInterval uptimeRange = maxUptime - minUptime;
    NSTimeInterval randomPart = arc4random_uniform((uint32_t)uptimeRange);
    NSTimeInterval extraSeconds = arc4random_uniform(60 * 45);
    NSTimeInterval uptime = minUptime + randomPart + extraSeconds;
    
    // Check real uptime to ensure spoofed value isn't higher
    struct timeval boottv = {0};
    size_t sz = sizeof(boottv);
    int mib[2] = {CTL_KERN, KERN_BOOTTIME};
    int sysctlResult = sysctl(mib, 2, &boottv, &sz, NULL, 0);
    if (sysctlResult == 0) {
        NSDate *realBoot = [NSDate dateWithTimeIntervalSince1970:boottv.tv_sec];
        NSTimeInterval realUptime = [[NSDate date] timeIntervalSinceDate:realBoot];
        if (uptime > realUptime - 60) {
            uptime = realUptime - 60;
        }
        if (uptime < minUptime) uptime = minUptime;
    }
    
    // Also save to system_uptime.plist for apps that might look there
    // NSString *uptimeString = [NSString stringWithFormat:@"%.0f", uptime];

    upTimeInfo.upTime = uptime;

    // Calculate boot time based on generated uptime
    NSDate *bootTime = [NSDate dateWithTimeIntervalSinceNow:-uptime];
    upTimeInfo.bootTime = bootTime;   
    return upTimeInfo;
}

- (WifiInfo *)generateWiFiInfo {
    self.error = nil;
    
    // Generate random US-style WiFi network information

    // US ISP providers
    NSArray *usProviders = @[
        // Major national ISPs
        @"Xfinity", @"Spectrum", @"ATT", @"Verizon", @"CenturyLink", @"Cox", @"Frontier",
        @"Optimum", @"Suddenlink", @"WOW", @"Mediacom", @"Windstream", @"Sparklight",
        // Regional ISPs
        @"RCN", @"Grande", @"Wave", @"Armstrong", @"WideOpenWest", @"MetroNet", @"Ziply",
        @"Sonic", @"Earthlink", @"HughesNet", @"TDS", @"Consolidated", @"Fairpoint",
        // Cable providers
        @"Comcast", @"TimeWarner", @"Charter", @"BrightHouse", @"Cablevision", @"GCI",
        // Fiber/specialized providers
        @"GoogleFiber", @"FiOS", @"AT&T-Fiber", @"CenturyLink-Fiber", @"Webpass",
        // Mobile hotspot providers
        @"TMobile", @"Sprint", @"USCellular", @"Cricket", @"MetroPCS", @"Boost"
    ];
    
    // US WiFi suffixes and modifiers
    NSArray *usSuffixes = @[
        // Empty/standard
        @"", @"WiFi", @"WLAN", @"Net", @"Network", @"Internet",
        // Band identifiers
        @"-5G", @"-5GHz", @"-2G", @"-2.4", @"-2.4GHz", @"-6G", @"-6GHz", @"_5G", @"_2G",
        // Location/purpose
        @"-Home", @"-Office", @"-Guest", @"-IoT", @"-ExtWifi", @"-Mesh", @"-Basement", 
        @"-Upstairs", @"-Kitchen", @"-Backyard", @"-Patio", @"-Garage", @"-Private", 
        @"-Family", @"-Apartment", @"-Condo", @"-Suite", @"-Lobby",
        // Security identifiers
        @"_Secure", @"-Secure", @"-Protected", @"-WPA2", @"-WPA3", @"_EXT", @"-EXT",
        // Dynamic additions
        @"-MESH", @"-AP", @"-Hub", @"-NODE1", @"-POD", @"-REPEATER", @"-EXTENDER"
    ];
    
    // Router brand names popular in the US
    NSArray *routerBrands = @[
        @"NETGEAR", @"Linksys", @"TP-Link", @"ASUS", @"ORBI", @"Eero", @"Google-WiFi",
        @"Nest-WiFi", @"Nighthawk", @"Apple", @"Amazon", @"ARRIS", @"Motorola", @"Ubiquiti",
        @"AmpliFi", @"D-Link", @"Belkin", @"Buffalo", @"Cisco", @"EnGenius", @"Tenda"
    ];
    
    // Common US last names
    NSArray *commonLastNames = @[
        @"Smith", @"Johnson", @"Williams", @"Jones", @"Brown", @"Miller", @"Davis",
        @"Wilson", @"Anderson", @"Thomas", @"Taylor", @"Moore", @"White", @"Harris",
        @"Martin", @"Thompson", @"Garcia", @"Martinez", @"Robinson", @"Clark", @"Rodriguez",
        @"Lewis", @"Lee", @"Walker", @"Hall", @"Allen", @"Young", @"King", @"Wright",
        @"Scott", @"Green", @"Baker", @"Adams", @"Nelson", @"Hill", @"Ramirez", @"Campbell",
        @"Mitchell", @"Roberts", @"Carter", @"Phillips", @"Evans", @"Turner", @"Torres"
    ];
    
    // Creative network names popular in the US
    NSArray *creativeNames = @[
        @"HideYoKids", @"HideYoWiFi", @"ItHurtsWhenIP", @"PrettyFlyForAWiFi",
        @"WiFiAintGonnaBreadItself", @"ThePromisedLAN", @"WhyFi", @"WiFiDoYouLoveMe",
        @"LANDownUnder", @"TheLANBeforeTime", @"WuTangLAN", @"ThisLANIsMyLAN", 
        @"BillWiTheScienceFi", @"TellMyWiFiLoveHer", @"NachoWiFi", @"GetOffMyLAN", 
        @"TheInternetBox", @"Series-of-Tubes", @"FBI-Surveillance", @"NSA-Van", 
        @"Area51", @"DEA-Monitoring", @"CIA-Spy-Van", @"NoWiFiForYou", 
        @"Password123", @"NotTheWiFiYoureLookingFor", @"VirusInfectedWiFi",
        @"PayMeToConnect", @"ICanHearYouHavingSex", @"WifiSoFastUCantSeeThis", 
        @"YourNeighborHasABetterRouter", @"WinternetIsComing", @"TwoGirlsOneRouter",
        @"DropItLikeItsHotspot", @"99ProblemsButWiFiAintOne", @"ThePasswordIsPASSWORD",
        @"Mom-Click-Here-For-Internet", @"ShoutingInTernetConspiracyTheories", 
        @"AllYourBandwidthAreBelongToUs", @"NewEnglandClamRouter", @"RouterIHardlyKnowHer"
    ];
    
    // Generate random SSID using one of three methods
    NSString *ssid;
    int networkStyle = arc4random_uniform(100);
    
    if (networkStyle < 45) {
        // ISP style (45% chance)
        NSString *provider = usProviders[arc4random_uniform((uint32_t)usProviders.count)];
        NSString *suffix = usSuffixes[arc4random_uniform((uint32_t)usSuffixes.count)];
        
        if ([suffix length] > 0) {
            ssid = [NSString stringWithFormat:@"%@%@", provider, suffix];
        } else {
            ssid = provider;
        }
        
        // Sometimes add numbers for uniqueness
        if (arc4random_uniform(100) < 40) {
            ssid = [ssid stringByAppendingFormat:@"-%d", arc4random_uniform(999) + 1];
        }
    } 
    else if (networkStyle < 70) {
        // Router brand style (25% chance)
        NSString *brand = routerBrands[arc4random_uniform((uint32_t)routerBrands.count)];
        NSString *suffix = usSuffixes[arc4random_uniform((uint32_t)usSuffixes.count)];
        
        if ([suffix length] > 0) {
            ssid = [NSString stringWithFormat:@"%@%@", brand, suffix];
        } else {
            ssid = brand;
        }
        
        // More likely to add model numbers for router brands
        if (arc4random_uniform(100) < 70) {
            // Different formats for model numbers
            int format = arc4random_uniform(5);
            if (format == 0) {
                ssid = [ssid stringByAppendingFormat:@"_%d", arc4random_uniform(1000)];
            } else if (format == 1) {
                ssid = [ssid stringByAppendingFormat:@"-%c%d", 'A' + arc4random_uniform(26), arc4random_uniform(100)];
            } else if (format == 2) {
                ssid = [ssid stringByAppendingFormat:@"_%dGHZ", (arc4random_uniform(2) == 0) ? 2 : 5];
            } else if (format == 3) {
                ssid = [ssid stringByAppendingFormat:@"-AC%d", 1000 + arc4random_uniform(9000)];
            } else {
                ssid = [ssid stringByAppendingFormat:@"_%X%X%X", arc4random_uniform(16), arc4random_uniform(16), arc4random_uniform(16)];
            }
        }
    }
    else {
        // Personal style (30% chance)
        int personalType = arc4random_uniform(100);
        NSString *base;
        
        if (personalType < 50) {
            // Family/Last name (50% of personal)
            base = commonLastNames[arc4random_uniform((uint32_t)commonLastNames.count)];
            
            // Add common variations
            int variation = arc4random_uniform(7);
            if (variation == 0) {
                base = [base stringByAppendingString:@"-Home"];
            } else if (variation == 1) {
                base = [base stringByAppendingString:@"-WiFi"];
            } else if (variation == 2) {
                base = [base stringByAppendingString:@"-Net"];
            } else if (variation == 3) {
                base = [base stringByAppendingString:@"Family"];
            } else if (variation == 4) {
                base = [base stringByAppendingString:@"House"];
            } else if (variation == 5) {
                base = [NSString stringWithFormat:@"The%@s", base];
            }
            // Otherwise leave as just the name
        } else {
            // Creative name (50% of personal)
            base = creativeNames[arc4random_uniform((uint32_t)creativeNames.count)];
        }
        
        // Sometimes add numbers for uniqueness
        if (arc4random_uniform(100) < 40) {
            ssid = [base stringByAppendingFormat:@"%d", arc4random_uniform(999) + 1];
        } else {
            ssid = base;
        }
    }
    
    // Generate random but valid BSSID (MAC address)
    // Common US router manufacturers OUIs (first 3 bytes)
    NSArray *commonOUIs = @[
        // Cisco/Linksys (popular in US)
        @"00:18:F8", // Cisco-Linksys
        @"00:1D:7E", // Cisco-Linksys
        @"00:23:69", // Cisco-Linksys
        @"E4:95:6E", // Cisco
        @"58:6D:8F", // Cisco-Linksys
        @"C8:BE:19", // Cisco-Linksys
        
        // NETGEAR (very popular in US market)
        @"00:14:6C", // NETGEAR
        @"00:26:F2", // NETGEAR
        @"08:BD:43", // NETGEAR
        @"20:E5:2A", // NETGEAR
        @"28:C6:8E", // NETGEAR
        @"3C:37:86", // NETGEAR
        @"D8:6C:63", // NETGEAR
        
        // Arris/Motorola (common in US cable modems)
        @"00:1A:DE", // Arris
        @"00:26:36", // Arris
        @"E4:64:E9", // Arris
        @"00:01:E3", // Motorola
        @"00:24:37", // Motorola
        
        // Comcast/Xfinity (US-specific)
        @"00:11:AE", // Xfinity
        @"00:14:6C", // Xfinity
        @"E4:64:E9", // Xfinity
        @"F8:F1:B6", // Xfinity
        
        // Charter/Spectrum (US-specific)
        @"68:A4:0E", // Spectrum
        @"00:FC:8D", // Spectrum
        
        // Apple (popular in US homes)
        @"00:1C:B3", // Apple WiFi
        @"88:41:FC", // Apple AirPort
        @"AC:BC:32", // Apple
        
        // Google/Nest (US market)
        @"F4:F5:D8", // Google WiFi
        @"F8:8F:CA", // Google Nest
        
        // Amazon/Eero (US market)
        @"04:F0:21", // Eero
        @"F8:BB:BF", // Eero
        @"FC:65:DE", // Amazon
        
        // TP-Link (common in US budget market)
        @"0C:80:63", // TP-Link
        @"54:A7:03", // TP-Link
        @"F8:1A:67", // TP-Link
        
        // ASUS (popular in US gaming/high-end)
        @"00:0C:6E", // ASUS
        @"30:85:A9", // ASUS
        @"AC:9E:17", // ASUS
        
        // Ubiquiti (popular for prosumers in US)
        @"44:E9:DD", // Ubiquiti
        @"78:8A:20", // Ubiquiti
        @"FC:EC:DA", // Ubiquiti
        
        // Belkin (common US brand)
        @"08:86:3B", // Belkin
        @"14:91:82", // Belkin
        @"94:10:3E", // Belkin
        
        // D-Link (budget US market)
        @"00:26:5A", // D-Link
        @"C0:A0:BB", // D-Link
        
        // Cable modems/gateways used by US ISPs
        @"00:90:D0", // Thomson/RCA (Spectrum)
        @"7C:BF:B1", // ARRIS (Comcast)
        @"00:15:63", // CableMatrix (various US cable)
        @"00:22:10"  // Motorola Solutions (US cable)
    ];
    
    // Select appropriate OUI based on SSID when possible
    NSString *oui = nil;
    
    // Match SSID provider with appropriate manufacturer
    if ([ssid containsString:@"Apple"] || [ssid containsString:@"Airport"]) {
        int appleIdx = 26 + arc4random_uniform(3);
        oui = commonOUIs[appleIdx]; // Apple OUIs
    } 
    else if ([ssid containsString:@"Google"] || [ssid containsString:@"Nest"]) {
        int googleIdx = 29 + arc4random_uniform(2);
        oui = commonOUIs[googleIdx]; // Google OUIs
    }
    else if ([ssid containsString:@"Linksys"] || [ssid containsString:@"Cisco"]) {
        int ciscoIdx = arc4random_uniform(6);
        oui = commonOUIs[ciscoIdx]; // Cisco OUIs (indices 0-5)
    }
    else if ([ssid containsString:@"NETGEAR"] || [ssid containsString:@"Nighthawk"]) {
        int netgearIdx = 6 + arc4random_uniform(7);
        oui = commonOUIs[netgearIdx]; // NETGEAR OUIs (indices 6-12)
    }
    else if ([ssid containsString:@"Motorola"] || [ssid containsString:@"ARRIS"]) {
        int arrisIdx = 13 + arc4random_uniform(5);
        oui = commonOUIs[arrisIdx]; // Arris OUIs (indices 13-17)
    }
    else if ([ssid containsString:@"Xfinity"] || [ssid containsString:@"Comcast"]) {
        int xfinityIdx = 18 + arc4random_uniform(4);
        oui = commonOUIs[xfinityIdx]; // Xfinity OUIs (indices 18-21)
    }
    else if ([ssid containsString:@"Spectrum"] || [ssid containsString:@"Charter"]) {
        int spectrumIdx = 22 + arc4random_uniform(2);
        oui = commonOUIs[spectrumIdx]; // Spectrum OUIs (indices 22-23)
    }
    else if ([ssid containsString:@"Eero"] || [ssid containsString:@"Amazon"]) {
        int eeroIdx = 31 + arc4random_uniform(3);
        oui = commonOUIs[eeroIdx]; // Eero/Amazon OUIs (indices 31-33)
    }
    else if ([ssid containsString:@"TP-Link"] || [ssid containsString:@"TPLink"]) {
        int tplinkIdx = 34 + arc4random_uniform(3);
        oui = commonOUIs[tplinkIdx]; // TP-Link OUIs (indices 34-36)
    }
    else if ([ssid containsString:@"ASUS"]) {
        int asusIdx = 37 + arc4random_uniform(3);
        oui = commonOUIs[asusIdx]; // ASUS OUIs (indices 37-39)
    }
    else if ([ssid containsString:@"Ubiquiti"] || [ssid containsString:@"UBNT"] || [ssid containsString:@"AmpliFi"]) {
        int ubiquitiIdx = 40 + arc4random_uniform(3);
        oui = commonOUIs[ubiquitiIdx]; // Ubiquiti OUIs (indices 40-42)
    }
    else if ([ssid containsString:@"Belkin"]) {
        int belkinIdx = 43 + arc4random_uniform(3);
        oui = commonOUIs[belkinIdx]; // Belkin OUIs (indices 43-45)
    }
    else if ([ssid containsString:@"DLink"] || [ssid containsString:@"D-Link"]) {
        int dlinkIdx = 46 + arc4random_uniform(2);
        oui = commonOUIs[dlinkIdx]; // D-Link OUIs (indices 46-47)
    }
    // ISP-specific cases
    else if ([ssid containsString:@"ATT"] || [ssid containsString:@"AT&T"]) {
        // Use Arris or Cisco (common AT&T suppliers)
        oui = commonOUIs[arc4random_uniform(2) == 0 ? 2 : 14];
    }
    else if ([ssid containsString:@"Verizon"] || [ssid containsString:@"FiOS"]) {
        // Use Actiontec or Motorola (common Verizon suppliers)
        oui = commonOUIs[16 + arc4random_uniform(2)];
    }
    else if ([ssid containsString:@"Cox"]) {
        // Use ARRIS or Cisco (common Cox suppliers)
        oui = commonOUIs[arc4random_uniform(2) == 0 ? 4 : 15];
    }
    else {
        // For all other cases, choose a random OUI
        oui = commonOUIs[arc4random_uniform((uint32_t)commonOUIs.count)];
    }
    
    // Generate the random part of the MAC address
    NSString *bssid = [NSString stringWithFormat:@"%@:%02X:%02X:%02X", 
                       oui,
                       arc4random_uniform(256),
                       arc4random_uniform(256),
                       arc4random_uniform(256)];
    
    // Set network type (usually "Infrastructure" for home networks)
    NSString *networkType = @"Infrastructure";
    
    // Set WiFi standard (802.11ac or 802.11ax most common in US now)
    NSArray *standards = @[@"802.11ax", @"802.11ac", @"802.11n"];
    NSString *wifiStandard = standards[arc4random_uniform(3)]; // Equally likely among the three
    
    // Set auto-join status (usually YES for home networks)
    BOOL autoJoin = YES;
    
    // Set last connection time (typically within the last day)
    NSDate *lastConnectionTime = [NSDate dateWithTimeIntervalSinceNow:-1 * arc4random_uniform(86400)];
    WifiInfo * wifiInfo = [[WifiInfo alloc] init];
    // Store values
    wifiInfo.ssid = ssid;
    wifiInfo.bssid = bssid;
    wifiInfo.networkType = networkType;
    wifiInfo.wifiStandard = wifiStandard;
    wifiInfo.autoJoin = @(autoJoin);
    wifiInfo.lastConnectionTime = lastConnectionTime;
    
    return wifiInfo;
}


- (NSString *)generateDeviceName {
    self.error = nil;
    
    // List of iPhone models from 8 Plus to 15 Pro Max
    NSArray *iPhoneModels = @[
        @"iPhone 8 Plus",
        @"iPhone X",
        @"iPhone XR",
        @"iPhone XS",
        @"iPhone XS Max",
        @"iPhone 11",
        @"iPhone 11 Pro",
        @"iPhone 11 Pro Max",
        @"iPhone 12",
        @"iPhone 12 mini",
        @"iPhone 12 Pro",
        @"iPhone 12 Pro Max",
        @"iPhone 13",
        @"iPhone 13 mini",
        @"iPhone 13 Pro",
        @"iPhone 13 Pro Max",
        @"iPhone 14",
        @"iPhone 14 Plus",
        @"iPhone 14 Pro",
        @"iPhone 14 Pro Max",
        @"iPhone 15",
        @"iPhone 15 Plus",
        @"iPhone 15 Pro",
        @"iPhone 15 Pro Max"
    ];
    
    // Common first names in the USA
    NSArray *usaFirstNames = @[
        @"Michael", @"Christopher", @"Jessica", @"Matthew", @"Ashley", @"Jennifer", 
        @"Joshua", @"Amanda", @"Daniel", @"David", @"James", @"Robert", @"John", 
        @"Joseph", @"Andrew", @"Ryan", @"Brandon", @"Jason", @"Justin", @"Sarah", 
        @"William", @"Jonathan", @"Stephanie", @"Brian", @"Nicole", @"Nicholas", 
        @"Anthony", @"Heather", @"Eric", @"Elizabeth", @"Adam", @"Megan", @"Melissa", 
        @"Kevin", @"Steven", @"Thomas", @"Timothy", @"Christina", @"Kyle", @"Rachel", 
        @"Laura", @"Lauren", @"Amber", @"Brittany", @"Danielle", @"Richard", @"Kimberly", 
        @"Jeffrey", @"Amy", @"Crystal", @"Michelle", @"Tiffany", @"Jeremy", @"Benjamin", 
        @"Mark", @"Emily", @"Aaron", @"Charles", @"Rebecca", @"Jacob", @"Stephen", 
        @"Patrick", @"Sean", @"Erin", @"Zachary", @"Jamie", @"Kelly", @"Samantha", 
        @"Nathan", @"Sara", @"Dustin", @"Paul", @"Angela", @"Tyler", @"Scott", 
        @"Katherine", @"Andrea", @"Gregory", @"Erica", @"Mary", @"Travis", @"Lisa", 
        @"Kenneth", @"Bryan", @"Lindsey", @"Kristen", @"Jose", @"Alexander", @"Jesse", 
        @"Katie", @"Lindsay", @"Shannon", @"Vanessa", @"Courtney", @"Christine", 
        @"Alicia", @"Cody", @"Allison", @"Bradley", @"Samuel", @"Emma", @"Noah", 
        @"Olivia", @"Liam", @"Ava", @"Ethan", @"Sophia", @"Isabella", @"Mason", 
        @"Mia", @"Lucas", @"Charlotte", @"Aiden", @"Harper", @"Elijah", @"Amelia", 
        @"Oliver", @"Abigail", @"Ella", @"Logan", @"Madison", @"Jackson", @"Lily", 
        @"Avery", @"Carter", @"Chloe", @"Grayson", @"Evelyn", @"Leo", @"Sofia", 
        @"Lincoln", @"Hannah", @"Henry", @"Aria", @"Gabriel", @"Grace", @"Owen",
        @"Victoria", @"Zoey", @"Isaac", @"Brooklyn", @"Levi", @"Zoe", @"Julian",
        @"Natalie", @"Caleb", @"Addison", @"Luke", @"Leah", @"Nathan", @"Aubrey", 
        @"Jack", @"Aurora", @"Isaiah", @"Savannah", @"Eli", @"Audrey", @"Dylan"
    ];
    
    // Common last names in the USA
    NSArray *usaLastNames = @[
        @"Smith", @"Johnson", @"Williams", @"Jones", @"Brown", @"Davis", @"Miller", 
        @"Wilson", @"Moore", @"Taylor", @"Anderson", @"Thomas", @"Jackson", @"White", 
        @"Harris", @"Martin", @"Thompson", @"Garcia", @"Martinez", @"Robinson", @"Clark", 
        @"Rodriguez", @"Lewis", @"Lee", @"Walker", @"Hall", @"Allen", @"Young", @"Hernandez", 
        @"King", @"Wright", @"Lopez", @"Hill", @"Scott", @"Green", @"Adams", @"Baker", 
        @"Gonzalez", @"Nelson", @"Carter", @"Mitchell", @"Perez", @"Roberts", @"Turner", 
        @"Phillips", @"Campbell", @"Parker", @"Evans", @"Edwards", @"Collins", @"Stewart", 
        @"Sanchez", @"Morris", @"Rogers", @"Reed", @"Cook", @"Morgan", @"Bell", @"Murphy", 
        @"Bailey", @"Rivera", @"Cooper", @"Richardson", @"Cox", @"Howard", @"Ward", @"Torres", 
        @"Peterson", @"Gray", @"Ramirez", @"James", @"Watson", @"Brooks", @"Kelly", @"Sanders", 
        @"Price", @"Bennett", @"Wood", @"Barnes", @"Ross", @"Henderson", @"Coleman", @"Jenkins", 
        @"Perry", @"Powell", @"Long", @"Patterson", @"Hughes", @"Flores", @"Washington", @"Butler", 
        @"Simmons", @"Foster", @"Gonzales", @"Bryant", @"Alexander", @"Russell", @"Griffin", 
        @"Diaz", @"Hayes"
    ];
    
    // Common US locations/states/cities for naming patterns
    NSArray *usaLocations = @[
        @"NYC", @"LA", @"Chicago", @"Houston", @"Phoenix", @"Philly", @"San Antonio", 
        @"San Diego", @"Dallas", @"Austin", @"Seattle", @"Denver", @"Boston", @"Vegas", 
        @"Miami", @"Oakland", @"Jersey", @"Portland", @"ATL", @"SF", @"NOLA", @"DC", 
        @"Nashville", @"SLC", @"Detroit", @"Columbus", @"Indy", @"Charlotte", @"Memphis", 
        @"AZ", @"CA", @"TX", @"FL", @"NY", @"PA", @"IL", @"OH", @"GA", @"NC", @"MI", 
        @"NJ", @"VA", @"WA", @"MN", @"CO", @"AL", @"SC", @"LA", @"KY", @"OR", @"OK", 
        @"CT", @"UT", @"IA", @"NV", @"AR", @"MS", @"KS", @"NE", @"WV", @"ID", @"HI", 
        @"NH", @"ME", @"MT", @"DE", @"SD", @"ND", @"AK", @"VT", @"WY", @"Home", @"Work", 
        @"Office"
    ];
    
    // Personalized descriptors
    NSArray *personalDescriptors = @[
        @"Personal", @"Pro", @"Work", @"Home", @"Main", @"Family", @"Mobile", @"Primary",
        @"New", @"Travel", @"Gaming", @"Backup", @"Private", @"", @"", @"", @"", @""
    ];
    
    // Generate a random device name
    NSMutableString *deviceName = [NSMutableString string];
    
    // Determine which naming pattern to use
    uint32_t patternSelector;
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(patternSelector), (uint8_t *)&patternSelector) != errSecSuccess) {
        NSLog(@"Failed to generate secure random number");
        return nil;
    }
    
    switch (patternSelector % 5) {
        case 0: { 
            // Pattern: "[First Name]'s iPhone"
            uint32_t nameIndex;
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(nameIndex), (uint8_t *)&nameIndex) != errSecSuccess) {
                // Fall back to a simpler deterministic behavior on error
                nameIndex = (uint32_t)time(NULL);
            }
            NSString *firstName = usaFirstNames[nameIndex % usaFirstNames.count];
            [deviceName appendFormat:@"%@'s iPhone", firstName];
            break;
        }
        case 1: { 
            // Pattern: "iPhone [First Name]" or "iPhone-[First Name]"
            uint32_t nameIndex;
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(nameIndex), (uint8_t *)&nameIndex) != errSecSuccess) {
                nameIndex = (uint32_t)time(NULL);
            }
            NSString *firstName = usaFirstNames[nameIndex % usaFirstNames.count];
            
            uint32_t dashOrSpace;
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(dashOrSpace), (uint8_t *)&dashOrSpace) != errSecSuccess) {
                dashOrSpace = (uint32_t)time(NULL);
            }
            
            if (dashOrSpace % 2 == 0) {
                [deviceName appendFormat:@"iPhone %@", firstName];
            } else {
                [deviceName appendFormat:@"iPhone-%@", firstName];
            }
            break;
        }
        case 2: { 
            // Pattern: "[First Name] [Last Name]'s iPhone"
            uint32_t firstNameIndex, lastNameIndex;
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(firstNameIndex), (uint8_t *)&firstNameIndex) != errSecSuccess) {
                firstNameIndex = (uint32_t)time(NULL);
            }
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(lastNameIndex), (uint8_t *)&lastNameIndex) != errSecSuccess) {
                lastNameIndex = (uint32_t)(time(NULL) + 1);
            }
            
            NSString *firstName = usaFirstNames[firstNameIndex % usaFirstNames.count];
            NSString *lastName = usaLastNames[lastNameIndex % usaLastNames.count];
            
            [deviceName appendFormat:@"%@ %@'s iPhone", firstName, lastName];
            break;
        }
        case 3: { 
            // Pattern: "iPhone [Location/State]"
            uint32_t locationIndex;
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(locationIndex), (uint8_t *)&locationIndex) != errSecSuccess) {
                locationIndex = (uint32_t)time(NULL);
            }
            NSString *location = usaLocations[locationIndex % usaLocations.count];
            
            [deviceName appendFormat:@"iPhone %@", location];
            break;
        }
        case 4: { 
            // Pattern: "[Specific iPhone Model] [Descriptor]"
            uint32_t modelIndex, descriptorIndex;
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(modelIndex), (uint8_t *)&modelIndex) != errSecSuccess) {
                modelIndex = (uint32_t)time(NULL);
            }
            if (SecRandomCopyBytes(kSecRandomDefault, sizeof(descriptorIndex), (uint8_t *)&descriptorIndex) != errSecSuccess) {
                descriptorIndex = (uint32_t)(time(NULL) + 1);
            }
            
            NSString *model = iPhoneModels[modelIndex % iPhoneModels.count];
            NSString *descriptor = personalDescriptors[descriptorIndex % personalDescriptors.count];
            
            if ([descriptor length] > 0) {
                [deviceName appendFormat:@"%@ %@", model, descriptor];
            } else {
                // If we got an empty descriptor, just use the model
                [deviceName appendString:model];
            }
            break;
        }
    }
    
    if ([self isValidDeviceName:deviceName]) {
        return deviceName;
    }
    NSLog(@"Generated device name failed validation");
    return nil;
}

- (NSString *)randomizeBatteryLevel {
    // Algorithm for realistic battery level distribution:
    // - 60% chance of battery level between 30-80%
    // - 20% chance of battery level between 80-100%
    // - 15% chance of battery level between 15-30%
    // - 5% chance of battery level between 5-15%
    
    int randomValue = arc4random_uniform(100);
    float level;
    
    if (randomValue < 60) {
        // 30-80% range (most common)
        level = (30 + arc4random_uniform(51)) / 100.0f;
    } else if (randomValue < 80) {
        // 80-100% range (fully charged state)
        level = (80 + arc4random_uniform(21)) / 100.0f;
    } else if (randomValue < 95) {
        // 15-30% range (low battery state)
        level = (15 + arc4random_uniform(16)) / 100.0f;
    } else {
        // 5-15% range (battery danger zone)
        level = (5 + arc4random_uniform(11)) / 100.0f;
    }
    
    // Format with 2 decimal places
    NSString *levelStr = [NSString stringWithFormat:@"%.2f", level];
    
    return levelStr;
}

- (BatteryInfo *)generateBatteryInfo {
    // Generate battery level first
    NSString *batteryLevel = [self randomizeBatteryLevel];

    
    // Create a dictionary with all battery info
    BatteryInfo *batteryInfo = [[BatteryInfo alloc]init];
    batteryInfo.batteryLevel = batteryLevel;
    batteryInfo.batteryPercentage = @((int)([batteryLevel floatValue] * 100));
    
    return batteryInfo;
}
- (NetworkInfo *) generateNetworkInfo{
    NSArray *carriers = @[
        // Major Carriers
        @{@"name": @"Verizon", @"mcc": @"310", @"mnc": @"004"},
        @{@"name": @"Verizon", @"mcc": @"310", @"mnc": @"010"},
        @{@"name": @"Verizon", @"mcc": @"311", @"mnc": @"480"},
        
        @{@"name": @"AT&T", @"mcc": @"310", @"mnc": @"170"},
        @{@"name": @"AT&T", @"mcc": @"310", @"mnc": @"410"},
        @{@"name": @"AT&T", @"mcc": @"310", @"mnc": @"150"},
        @{@"name": @"AT&T", @"mcc": @"310", @"mnc": @"680"},
        
        @{@"name": @"T-Mobile", @"mcc": @"310", @"mnc": @"260"},
        @{@"name": @"T-Mobile", @"mcc": @"310", @"mnc": @"160"},
        @{@"name": @"T-Mobile", @"mcc": @"310", @"mnc": @"240"},
        @{@"name": @"T-Mobile", @"mcc": @"310", @"mnc": @"800"},
        
        @{@"name": @"Sprint", @"mcc": @"310", @"mnc": @"120"},
        @{@"name": @"Sprint", @"mcc": @"311", @"mnc": @"870"},
        @{@"name": @"Sprint", @"mcc": @"312", @"mnc": @"530"},
        
        // Regional Carriers without spaces
        @{@"name": @"Cellcom", @"mcc": @"311", @"mnc": @"210"}
    ];
    NSUInteger randomIndex = arc4random_uniform((uint32_t)carriers.count);
    NetworkInfo *networkInfo = [[NetworkInfo alloc] init];
    networkInfo.carrierName = carriers[randomIndex][@"name"];
    networkInfo.mcc = carriers[randomIndex][@"mcc"];
    networkInfo.mnc = carriers[randomIndex][@"mnc"];
    networkInfo.localIPAddress = [self generateSpoofedLocalIPAddressFromCurrent];
    networkInfo.localIPv6Address = [self generateSpoofedLocalIPv6AddressFromCurrent];
    // 获取最小值和最大值
    NetworkConnectionType minType = NetworkConnectionTypeAuto;    // 0
    NetworkConnectionType maxType = NetworkConnectionTypeCellular;    // 2

    // 生成随机数（包含 min 和 max）
    NetworkConnectionType randomType = arc4random_uniform(maxType - minType + 1) + minType;
    networkInfo.connectionType = randomType;
    return networkInfo;
}
- (NSString *)getCurrentLocalIPAddress {
    NSString *address = @"192.168.1.1"; // Default fallback
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    
    // Retrieve the current interfaces - returns 0 on success
    if (getifaddrs(&interfaces) == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr->sa_family == AF_INET) {
                // Check if interface is en0 which is the wifi connection on iOS
                if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    // Get NSString from C String
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    
    // Free memory
    freeifaddrs(interfaces);
    
    return address;
}

- (NSString *)generateSpoofedLocalIPAddressFromCurrent {
    NSString *currentIP = [self getCurrentLocalIPAddress];
    NSArray<NSString *> *parts = [currentIP componentsSeparatedByString:@"."];
    if (parts.count == 4) {
        // Change the last octet to a random value (2-253), not the original
        int lastOctet = [parts[3] intValue];
        int newLastOctet = lastOctet;
        int attempts = 0;
        while (newLastOctet == lastOctet && attempts < 10) {
            newLastOctet = 2 + arc4random_uniform(252); // 2-253
            attempts++;
        }
        NSString *spoofedIP = [NSString stringWithFormat:@"%@.%@.%@.%d", parts[0], parts[1], parts[2], newLastOctet];
        return spoofedIP;
    }
    // Fallback to random if parsing fails
    return [self getCurrentLocalIPAddress];
}

- (NSString *)generateSpoofedLocalIPv6AddressFromCurrent {
    NSString *address = nil;
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    if (getifaddrs(&interfaces) == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr && temp_addr->ifa_addr->sa_family == AF_INET6) {
                if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    char ip6[INET6_ADDRSTRLEN];
                    struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)temp_addr->ifa_addr;
                    inet_ntop(AF_INET6, &sin6->sin6_addr, ip6, sizeof(ip6));
                    address = [NSString stringWithUTF8String:ip6];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    if (!address) {
        address = @"fe80::1234:abcd:5678:9abc";
    }
    // Spoof last segment
    NSArray *parts = [address componentsSeparatedByString:@":"];
    if (parts.count >= 2) {
        NSMutableArray *mutableParts = [parts mutableCopy];
        NSString *last = parts.lastObject;
        NSString *spoofedLast = [NSString stringWithFormat:@"%x", arc4random_uniform(0xFFFF)];
        if ([last length] > 0) {
            mutableParts[mutableParts.count-1] = spoofedLast;
        } else if (mutableParts.count > 1) {
            mutableParts[mutableParts.count-2] = spoofedLast;
        }
        return [mutableParts componentsJoinedByString:@":"];
    }
    return address;
}
- (NSString *)generateSerialNumber {

    self.error = nil;
    
    // Add random delay to avoid pattern detection
    usleep(arc4random_uniform(50000));  // 0-50ms delay
    
    // Define valid prefixes for USA-based Apple devices
    NSArray *prefixes = @[@"C02", @"FVF", @"DLXJ", @"GG78", @"HC79"];
    
    // Use pattern variation
    static int patternIndex = 0;
    patternIndex = (patternIndex + 1) % prefixes.count;
    NSString *prefix = prefixes[patternIndex];
    
    // Create a mutable string with the prefix
    NSMutableString *serialNumber = [NSMutableString stringWithString:prefix];
    
    // Generate random alphanumeric characters for the rest
    // Skip I, O, 1, 0 to avoid confusion (common in Apple serial numbers)
    const char *chars = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
    NSInteger remainingLength = (prefix.length == 3) ? 8 : 7;
    
    for (int i = 0; i < remainingLength; i++) {
        uint32_t randomValue;
        if (SecRandomCopyBytes(kSecRandomDefault, sizeof(randomValue), (uint8_t *)&randomValue) == errSecSuccess) {
            [serialNumber appendFormat:@"%c", chars[randomValue % strlen(chars)]];
        } else {
            NSLog(@"Failed to generate secure random number for serial");
            return nil;
        }
    }
    
    // Validate the generated serial number
    if ([self isValidSerialNumber:serialNumber]) {
        return serialNumber;
    }
    NSLog(@"Generated serial number failed validation");
    return nil;
}

- (NSString *)generateIMEI {
    // Use a realistic US iPhone TAC (Type Allocation Code)
    NSArray *usTACs = @[ @"353918", @"356938", @"359254", @"353915", @"353920", @"353929", @"353997", @"354994" ];
    NSString *tac = usTACs[arc4random_uniform((uint32_t)usTACs.count)];
    NSMutableString *imei = [NSMutableString stringWithString:tac];
    // 8 digits for SNR
    for (int i = 0; i < 8; i++) {
        [imei appendFormat:@"%d", arc4random_uniform(10)];
    }
    // Luhn check digit
    int sum = 0;
    for (int i = 0; i < 14; i++) {
        int digit = [imei characterAtIndex:i] - '0';
        if (i % 2 == 1) digit *= 2;
        if (digit > 9) digit -= 9;
        sum += digit;
    }
    int checkDigit = (10 - (sum % 10)) % 10;
    [imei appendFormat:@"%d", checkDigit];
    return imei;
}

- (NSString *)generateMEID {
    // Use a realistic US MEID prefix (A00000, A10000, 990000)
    NSArray *usMEIDPrefixes = @[ @"A00000", @"A10000", @"990000" ];
    NSString *prefix = usMEIDPrefixes[arc4random_uniform((uint32_t)usMEIDPrefixes.count)];
    NSMutableString *meid = [NSMutableString stringWithString:prefix];
    // 8 hex digits for the rest
    for (int i = 0; i < 8; i++) {
        [meid appendFormat:@"%X", arc4random_uniform(16)];
    }
    return meid;
}


-(IosVersion *) generateIOSVersion{
    NSArray * versionBuildPairs = @[
        // iOS 16.x versions (starting from 16.2)
        @{@"version": @"16.2", @"build": @"20C65", 
            @"kernel_version": @"Darwin Kernel Version 22.2.0: Mon Nov 28 20:10:47 PST 2022; root:xnu-8792.72.6~1/RELEASE_ARM64_T8101", 
            @"darwin": @"22.2.0", @"xnu": @"8792.72.6~1"},
        @{@"version": @"16.3", @"build": @"20D47", 
            @"kernel_version": @"Darwin Kernel Version 22.3.0: Wed Jan  4 21:25:36 PST 2023; root:xnu-8792.81.2~2/RELEASE_ARM64_T8101", 
            @"darwin": @"22.3.0", @"xnu": @"8792.81.2~2"},
        @{@"version": @"16.3.1", @"build": @"20D67", 
            @"kernel_version": @"Darwin Kernel Version 22.3.0: Mon Jan 30 20:07:53 PST 2023; root:xnu-8792.81.3~2/RELEASE_ARM64_T8101", 
            @"darwin": @"22.3.0", @"xnu": @"8792.81.3~2"},
        @{@"version": @"16.4", @"build": @"20E247", 
            @"kernel_version": @"Darwin Kernel Version 22.4.0: Wed Mar  8 22:11:50 PST 2023; root:xnu-8796.101.5~1/RELEASE_ARM64_T8101", 
            @"darwin": @"22.4.0", @"xnu": @"8796.101.5~1"},
        @{@"version": @"16.4.1", @"build": @"20E252", 
            @"kernel_version": @"Darwin Kernel Version 22.4.0: Mon Mar 20 22:14:42 PDT 2023; root:xnu-8796.101.5~3/RELEASE_ARM64_T8101", 
            @"darwin": @"22.4.0", @"xnu": @"8796.101.5~3"},
        @{@"version": @"16.5", @"build": @"20F66", 
            @"kernel_version": @"Darwin Kernel Version 22.5.0: Mon Apr 24 20:53:19 PDT 2023; root:xnu-8796.121.2~5/RELEASE_ARM64_T8101", 
            @"darwin": @"22.5.0", @"xnu": @"8796.121.2~5"},
        @{@"version": @"16.5.1", @"build": @"20F75", 
            @"kernel_version": @"Darwin Kernel Version 22.5.0: Thu May 18 20:37:29 PDT 2023; root:xnu-8796.121.3~1/RELEASE_ARM64_T8101", 
            @"darwin": @"22.5.0", @"xnu": @"8796.121.3~1"},
        @{@"version": @"16.6", @"build": @"20G75", 
            @"kernel_version": @"Darwin Kernel Version 22.6.0: Wed Jun 28 20:51:09 PDT 2023; root:xnu-8796.141.3~2/RELEASE_ARM64_T8101", 
            @"darwin": @"22.6.0", @"xnu": @"8796.141.3~2"},
        @{@"version": @"16.6.1", @"build": @"20G81", 
            @"kernel_version": @"Darwin Kernel Version 22.6.0: Mon Jul 24 18:19:54 PDT 2023; root:xnu-8796.141.3~3/RELEASE_ARM64_T8101", 
            @"darwin": @"22.6.0", @"xnu": @"8796.141.3~3"},
        @{@"version": @"16.7", @"build": @"20H19", 
            @"kernel_version": @"Darwin Kernel Version 22.6.0: Wed Aug 9 16:09:21 PDT 2023; root:xnu-8796.141.3~4/RELEASE_ARM64_T8101", 
            @"darwin": @"22.6.0", @"xnu": @"8796.141.3~4"},
        @{@"version": @"16.7.1", @"build": @"20H30", 
            @"kernel_version": @"Darwin Kernel Version 22.6.0: Mon Aug 21 21:16:55 PDT 2023; root:xnu-8796.141.3~5/RELEASE_ARM64_T8101", 
            @"darwin": @"22.6.0", @"xnu": @"8796.141.3~5"},
        @{@"version": @"16.7.2", @"build": @"20H115", 
            @"kernel_version": @"Darwin Kernel Version 22.6.0: Thu Sep 14 16:33:11 PDT 2023; root:xnu-8796.141.3~6/RELEASE_ARM64_T8101", 
            @"darwin": @"22.6.0", @"xnu": @"8796.141.3~6"},
        @{@"version": @"16.7.3", @"build": @"20H232", 
            @"kernel_version": @"Darwin Kernel Version 22.6.0: Mon Oct 23 21:12:11 PDT 2023; root:xnu-8796.141.3~9/RELEASE_ARM64_T8101", 
            @"darwin": @"22.6.0", @"xnu": @"8796.141.3~9"},
        @{@"version": @"16.7.4", @"build": @"20H240", 
            @"kernel_version": @"Darwin Kernel Version 22.6.0: Mon Nov 13 21:07:04 PST 2023; root:xnu-8796.141.3~10/RELEASE_ARM64_T8101", 
            @"darwin": @"22.6.0", @"xnu": @"8796.141.3~10"},
        @{@"version": @"16.7.5", @"build": @"20H307", 
            @"kernel_version": @"Darwin Kernel Version 22.6.0: Mon Dec 11 16:54:15 PST 2023; root:xnu-8796.141.3~11/RELEASE_ARM64_T8101", 
            @"darwin": @"22.6.0", @"xnu": @"8796.141.3~11"},
        @{@"version": @"16.7.6", @"build": @"20H318", 
            @"kernel_version": @"Darwin Kernel Version 22.6.0: Mon Jan 15 20:02:17 PST 2024; root:xnu-8796.141.3~12/RELEASE_ARM64_T8101", 
            @"darwin": @"22.6.0", @"xnu": @"8796.141.3~12"},
        @{@"version": @"16.7.7", @"build": @"20H325", 
            @"kernel_version": @"Darwin Kernel Version 22.6.0: Mon Feb 12 19:59:45 PST 2024; root:xnu-8796.141.3~13/RELEASE_ARM64_T8101", 
            @"darwin": @"22.6.0", @"xnu": @"8796.141.3~13"},
        @{@"version": @"16.7.8", @"build": @"20H400", 
            @"kernel_version": @"Darwin Kernel Version 22.6.0: Thu Mar 7 23:08:41 PST 2024; root:xnu-8796.141.3~15/RELEASE_ARM64_T8101", 
            @"darwin": @"22.6.0", @"xnu": @"8796.141.3~15"},
        
        // iOS 17.x versions
        @{@"version": @"17.0", @"build": @"21A326", 
            @"kernel_version": @"Darwin Kernel Version 23.0.0: Wed Aug 16 17:19:24 PDT 2023; root:xnu-10002.1.13~1/RELEASE_ARM64_T6000", 
            @"darwin": @"23.0.0", @"xnu": @"10002.1.13~1"},
        @{@"version": @"17.0.1", @"build": @"21A340", 
            @"kernel_version": @"Darwin Kernel Version 23.0.0: Wed Aug 30 20:01:05 PDT 2023; root:xnu-10002.1.13~2/RELEASE_ARM64_T6000", 
            @"darwin": @"23.0.0", @"xnu": @"10002.1.13~2"},
        @{@"version": @"17.0.2", @"build": @"21A351", 
            @"kernel_version": @"Darwin Kernel Version 23.0.0: Thu Sep 7 20:57:46 PDT 2023; root:xnu-10002.1.13~3/RELEASE_ARM64_T6000", 
            @"darwin": @"23.0.0", @"xnu": @"10002.1.13~3"},
        @{@"version": @"17.0.3", @"build": @"21A360", 
            @"kernel_version": @"Darwin Kernel Version 23.0.0: Mon Sep 25 21:15:30 PDT 2023; root:xnu-10002.1.13~4/RELEASE_ARM64_T6000", 
            @"darwin": @"23.0.0", @"xnu": @"10002.1.13~4"},
        @{@"version": @"17.1", @"build": @"21B74", 
            @"kernel_version": @"Darwin Kernel Version 23.1.0: Wed Oct 11 17:53:11 PDT 2023; root:xnu-10002.41.9~7/RELEASE_ARM64_T6000", 
            @"darwin": @"23.1.0", @"xnu": @"10002.41.9~7"},
        @{@"version": @"17.1.1", @"build": @"21B91", 
            @"kernel_version": @"Darwin Kernel Version 23.1.0: Thu Oct 26 16:06:36 PDT 2023; root:xnu-10002.41.9~9/RELEASE_ARM64_T6000", 
            @"darwin": @"23.1.0", @"xnu": @"10002.41.9~9"},
        @{@"version": @"17.1.2", @"build": @"21B101", 
            @"kernel_version": @"Darwin Kernel Version 23.1.0: Wed Nov 8 11:56:31 PST 2023; root:xnu-10002.41.9~11/RELEASE_ARM64_T6000", 
            @"darwin": @"23.1.0", @"xnu": @"10002.41.9~11"},
        @{@"version": @"17.2", @"build": @"21C62", 
            @"kernel_version": @"Darwin Kernel Version 23.2.0: Wed Nov 15 21:56:45 PST 2023; root:xnu-10002.61.3~10/RELEASE_ARM64_T6000", 
            @"darwin": @"23.2.0", @"xnu": @"10002.61.3~10"},
        @{@"version": @"17.2.1", @"build": @"21C66", 
            @"kernel_version": @"Darwin Kernel Version 23.2.0: Wed Dec 6 20:07:48 PST 2023; root:xnu-10002.61.3~13/RELEASE_ARM64_T6000", 
            @"darwin": @"23.2.0", @"xnu": @"10002.61.3~13"},
        @{@"version": @"17.3", @"build": @"21D50", 
            @"kernel_version": @"Darwin Kernel Version 23.3.0: Wed Jan 10 18:16:15 PST 2024; root:xnu-10002.81.5~10/RELEASE_ARM64_T6000", 
            @"darwin": @"23.3.0", @"xnu": @"10002.81.5~10"},
        @{@"version": @"17.3.1", @"build": @"21D61", 
            @"kernel_version": @"Darwin Kernel Version 23.3.0: Mon Jan 22 21:19:52 PST 2024; root:xnu-10002.81.5~13/RELEASE_ARM64_T6000", 
            @"darwin": @"23.3.0", @"xnu": @"10002.81.5~13"},
        @{@"version": @"17.4", @"build": @"21E219", 
            @"kernel_version": @"Darwin Kernel Version 23.4.0: Wed Feb 21 15:44:29 PST 2024; root:xnu-10063.101.2~1/RELEASE_ARM64_T6000", 
            @"darwin": @"23.4.0", @"xnu": @"10063.101.2~1"},
        @{@"version": @"17.4.1", @"build": @"21E236", 
            @"kernel_version": @"Darwin Kernel Version 23.4.0: Mon Mar 4 20:10:59 PST 2024; root:xnu-10063.101.2~3/RELEASE_ARM64_T6000", 
            @"darwin": @"23.4.0", @"xnu": @"10063.101.2~3"},
        @{@"version": @"17.5", @"build": @"21F79", 
            @"kernel_version": @"Darwin Kernel Version 23.5.0: Mon Apr 8 21:39:26 PDT 2024; root:xnu-10063.121.1~2/RELEASE_ARM64_T6000", 
            @"darwin": @"23.5.0", @"xnu": @"10063.121.1~2"},
        @{@"version": @"17.5.1", @"build": @"21F90", 
            @"kernel_version": @"Darwin Kernel Version 23.5.0: Tue Apr 23 22:07:16 PDT 2024; root:xnu-10063.121.1~3/RELEASE_ARM64_T6000", 
            @"darwin": @"23.5.0", @"xnu": @"10063.121.1~3"},
        @{@"version": @"17.6", @"build": @"21G83", 
            @"kernel_version": @"Darwin Kernel Version 23.6.0: Tue May 21 19:58:21 PDT 2024; root:xnu-10063.141.2~2/RELEASE_ARM64_T6000", 
            @"darwin": @"23.6.0", @"xnu": @"10063.141.2~2"},
        @{@"version": @"17.6.1", @"build": @"21G91", 
            @"kernel_version": @"Darwin Kernel Version 23.6.0: Tue Jun 11 18:30:45 PDT 2024; root:xnu-10063.141.2~3/RELEASE_ARM64_T6000", 
            @"darwin": @"23.6.0", @"xnu": @"10063.141.2~3"},
        
        // iOS 18.x versions with real corresponding kernel versions
        @{@"version": @"18.0", @"build": @"22A326", 
            @"kernel_version": @"Darwin Kernel Version 24.0.0: Fri Jun 7 20:30:42 PDT 2024; root:xnu-10461.1.13~1/RELEASE_ARM64_T6000", 
            @"darwin": @"24.0.0", @"xnu": @"10461.1.13~1"},
        @{@"version": @"18.0.1", @"build": @"22A340", 
            @"kernel_version": @"Darwin Kernel Version 24.0.0: Thu Jun 20 21:35:16 PDT 2024; root:xnu-10461.1.13~3/RELEASE_ARM64_T6000", 
            @"darwin": @"24.0.0", @"xnu": @"10461.1.13~3"},
        @{@"version": @"18.0.2", @"build": @"22A351", 
            @"kernel_version": @"Darwin Kernel Version 24.0.0: Mon Jul 8 20:21:40 PDT 2024; root:xnu-10461.1.13~5/RELEASE_ARM64_T6000", 
            @"darwin": @"24.0.0", @"xnu": @"10461.1.13~5"},
        @{@"version": @"18.1", @"build": @"22B74", 
            @"kernel_version": @"Darwin Kernel Version 24.1.0: Wed Aug 14 18:43:29 PDT 2024; root:xnu-10461.41.5~1/RELEASE_ARM64_T6000", 
            @"darwin": @"24.1.0", @"xnu": @"10461.41.5~1"},
        @{@"version": @"18.1.1", @"build": @"22B91", 
            @"kernel_version": @"Darwin Kernel Version 24.1.0: Tue Sep 3 19:26:17 PDT 2024; root:xnu-10461.41.5~3/RELEASE_ARM64_T6000", 
            @"darwin": @"24.1.0", @"xnu": @"10461.41.5~3"},
        @{@"version": @"18.2", @"build": @"22C62", 
            @"kernel_version": @"Darwin Kernel Version 24.2.0: Mon Oct 14 20:27:31 PDT 2024; root:xnu-10461.61.1~4/RELEASE_ARM64_T6000", 
            @"darwin": @"24.2.0", @"xnu": @"10461.61.1~4"},
        @{@"version": @"18.3", @"build": @"22D50", 
            @"kernel_version": @"Darwin Kernel Version 24.3.0: Wed Dec 4 22:48:55 PST 2024; root:xnu-10461.81.1~3/RELEASE_ARM64_T6000", 
            @"darwin": @"24.3.0", @"xnu": @"10461.81.1~3"},
        @{@"version": @"18.4", @"build": @"22E219", 
            @"kernel_version": @"Darwin Kernel Version 24.4.0: Mon Feb 10 19:45:22 PST 2025; root:xnu-10461.101.2~4/RELEASE_ARM64_T6000", 
            @"darwin": @"24.4.0", @"xnu": @"10461.101.2~4"},
        @{@"version": @"18.5", @"build": @"22F79", 
            @"kernel_version": @"Darwin Kernel Version 24.5.0: Wed Apr 9 21:24:17 PDT 2025; root:xnu-10461.121.1~2/RELEASE_ARM64_T6000", 
            @"darwin": @"24.5.0", @"xnu": @"10461.121.1~2"}
    ];
    // Generate a random index within the array bounds
    uint32_t randomIndex;
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(randomIndex), (uint8_t *)&randomIndex) != errSecSuccess) {
        NSLog(@"Failed to generate secure random number");
        return nil;
    }
    
    // Get the version at the random index
    NSUInteger index = randomIndex % versionBuildPairs.count;
    NSDictionary *versionInfo = versionBuildPairs[index];
    IosVersion * iosVersion = [[IosVersion alloc]init];
   
    iosVersion.version = versionInfo[@"version"];
    iosVersion.build = versionInfo[@"build"];
    iosVersion.kernelVersion = versionInfo[@"kernel_version"];
    iosVersion.darwin = versionInfo[@"darwin"];
    iosVersion.xnu = versionInfo[@"xnu"];

    return iosVersion;
    
}


- (StorageInfo *)generateStorage{
    // 50% chance for 64GB, 50% for 128GB
    int randomValue = arc4random_uniform(100);
    NSString *capacity;
    if (randomValue < 50) {
        capacity = @"64";
    } else {
        capacity = @"128";
    }

    double totalGB = [capacity doubleValue];
    double freePercent;
    
    // Calculate realistic free space based on capacity
    if (totalGB <= 32) {
        // 64GB devices typically have less free space (15-30%)
        freePercent = (arc4random_uniform(15) + 15) / 100.0;
    } else {
        // 128GB devices (25-40%)
        freePercent = (arc4random_uniform(15) + 25) / 100.0;
    }
    
    double freeGB = totalGB * freePercent;
    
    // Add some variability to the decimal points
    double decimalVariation = (arc4random_uniform(10) / 10.0);
    freeGB = freeGB + decimalVariation;
    
    // Round to one decimal place
    freeGB = round(freeGB * 10) / 10;
    StorageInfo * storageInfo = [[StorageInfo alloc]init];
    storageInfo.totalStorage = capacity;
    storageInfo.freeStorage = [NSString stringWithFormat:@"%.1f", freeGB];
    storageInfo.filesystemType = @"0x1A"; // APFS for modern iOS
    
    return storageInfo;
}

- (BOOL)isValidDeviceName:(NSString *)deviceName {
    if (!deviceName) return NO;
    
    // Basic validation - ensure it's not empty and not too long
    if (deviceName.length == 0 || deviceName.length > 50) {
        return NO;
    }
    
    // Ensure it doesn't contain any invalid characters
    NSCharacterSet *invalidChars = [NSCharacterSet characterSetWithCharactersInString:@"<>:\"/\\|?*"];
    if ([deviceName rangeOfCharacterFromSet:invalidChars].location != NSNotFound) {
        return NO;
    }
    
    return YES;
}


- (BOOL)isValidSerialNumber:(NSString *)serialNumber {
    if (!serialNumber) return NO;
    
    // Check format using regex for various Apple device serial number formats
    // Pattern matches common prefixes followed by 7-8 alphanumeric characters
    NSString *pattern = @"^(C02|FVF|DLXJ|GG78|HC79)[0-9A-Z]{7,8}$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                         options:0
                                                                           error:nil];
    NSUInteger matches = [regex numberOfMatchesInString:serialNumber
                                               options:0
                                                 range:NSMakeRange(0, serialNumber.length)];
    
    return matches == 1;
}


// IMEI validation: 15 digits, Luhn valid, US TAC
- (BOOL)isValidIMEI:(NSString *)imei {
    if (imei.length != 15) return NO;
    if (![self isAllDigits:imei]) return NO;
    // Check TAC
    NSArray *usTACs = @[ @"353918", @"356938", @"359254", @"353915", @"353920", @"353929", @"353997", @"354994" ];
    NSString *tac = [imei substringToIndex:6];
    if (![usTACs containsObject:tac]) return NO;
    // Luhn check
    int sum = 0;
    for (int i = 0; i < 14; i++) {
        int digit = [imei characterAtIndex:i] - '0';
        if (i % 2 == 1) digit *= 2;
        if (digit > 9) digit -= 9;
        sum += digit;
    }
    int checkDigit = (10 - (sum % 10)) % 10;
    return (checkDigit == ([imei characterAtIndex:14] - '0'));
}

// MEID validation: 14 hex digits, US prefix
- (BOOL)isValidMEID:(NSString *)meid {
    if (meid.length != 14) return NO;
    NSArray *usMEIDPrefixes = @[ @"A00000", @"A10000", @"990000" ];
    NSString *prefix = [meid substringToIndex:6];
    if (![usMEIDPrefixes containsObject:prefix]) return NO;
    NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef"];
    for (NSUInteger i = 0; i < meid.length; i++) {
        unichar c = [meid characterAtIndex:i];
        if (![hexSet characterIsMember:c]) return NO;
    }
    return YES;
}

- (BOOL)isAllDigits:(NSString *)string {
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return ([string rangeOfCharacterFromSet:nonDigits].location == NSNotFound);
}

@end