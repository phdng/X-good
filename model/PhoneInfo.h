#import <Foundation/Foundation.h>

// StorageInfo.h 或同一个文件顶部先声明 StorageInfo
@class StorageInfo;  // 前向声明，解决循环依赖
@class BatteryInfo;
@class WifiInfo;
@class IosVersion;
@class UpTimeInfo;
@class DeviceModel;
@class WebGLInfo;

@interface PhoneInfo : NSObject

// 设备标识信息
@property (nonatomic, copy) NSString *idfa;
@property (nonatomic, copy) NSString *idfv;
@property (nonatomic, copy) NSString *deviceName;
@property (nonatomic, copy) NSString *serialNumber;
@property (nonatomic, copy) NSString *IMEI;
@property (nonatomic, copy) NSString *MEID;
@property (nonatomic, strong) IosVersion *iosVersion;

// UUID 信息
@property (nonatomic, copy) NSString *systemBootUUID;
@property (nonatomic, copy) NSString *dyldCacheUUID;
@property (nonatomic, copy) NSString *pasteboardUUID;
@property (nonatomic, copy) NSString *keychainUUID;
@property (nonatomic, copy) NSString *userDefaultsUUID;
@property (nonatomic, copy) NSString *appGroupUUID;
@property (nonatomic, copy) NSString *coreDataUUID;
@property (nonatomic, copy) NSString *appInstallUUID;
@property (nonatomic, copy) NSString *appContainerUUID;

// 存储信息 - 使用强引用
@property (nonatomic, strong) StorageInfo *storageInfo;

@property (nonatomic, strong) BatteryInfo *batteryInfo;

@property (nonatomic, strong) WifiInfo *wifiInfo;
@property (nonatomic, strong) DeviceModel *deviceModel;


// 启动时间
@property (nonatomic, strong) UpTimeInfo *upTimeInfo;
// JSON 序列化和反序列化方法
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;

// 文件存储方法
- (BOOL)saveToFile:(NSString *)filePath;
+ (instancetype)loadFromFile:(NSString *)filePath;

// 静态方法：直接保存 NSDictionary 到文件
+ (BOOL)saveDictionary:(NSDictionary *)dict toFile:(NSString *)filePath;

// 静态方法：从文件读取并返回 NSDictionary
+ (NSDictionary *)loadDictionaryFromFile:(NSString *)filePath;

@end

@interface IosVersion : NSObject
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *build;
@property (nonatomic, copy) NSString *kernelVersion;
@property (nonatomic, copy) NSString *darwin;
@property (nonatomic, copy) NSString *xnu;
- (NSString *) versionAndBuild;
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
@end

@interface StorageInfo : NSObject

// 存储容量通常使用数值类型而不是字符串
@property (nonatomic, copy) NSString * totalStorage;  // 字节数
@property (nonatomic, copy) NSString * freeStorage;   // 字节数
@property (nonatomic, copy) NSString *filesystemType;
- (NSString *) showInfo;
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
@end

@interface BatteryInfo : NSObject
@property (nonatomic, copy) NSString *batteryLevel;
@property (nonatomic, copy) NSNumber * batteryPercentage;
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
@end

@interface WifiInfo: NSObject
@property (nonatomic, copy) NSString *ssid;
@property (nonatomic, copy) NSString *bssid;
@property (nonatomic, copy) NSString *networkType;
@property (nonatomic, copy) NSString *wifiStandard;
@property (nonatomic, assign) BOOL autoJoin;
@property (nonatomic, strong) NSDate *lastConnectionTime;
- (NSString *) showInfo;
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
@end


@interface UpTimeInfo : NSObject
@property (nonatomic, assign) NSTimeInterval upTime;
@property (nonatomic, strong) NSDate * bootTime;
- (NSString *)upTimeStr;
- (NSString *)bootTimeStr;
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
@end

@interface DeviceModel : NSObject
@property (nonatomic, copy) NSString *modelName;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *resolution;
@property (nonatomic, copy) NSString *viewportResolution;
@property (nonatomic, copy) NSNumber *devicePixelRatio;
@property (nonatomic, copy) NSNumber *screenDensity;
@property (nonatomic, copy) NSString *cpuArchitecture;
@property (nonatomic, copy) NSString *boardId;
@property (nonatomic, copy) NSString *hwModel;
@property (nonatomic, copy) NSString *gpuFamily;
@property (nonatomic, copy) NSString *metalFeatureSet;
@property (nonatomic, copy) NSNumber *deviceMemory;
@property (nonatomic, copy) NSNumber *cpuCoreCount;
@property (nonatomic, strong) WebGLInfo *webGLInfo;
- (NSString *) showInfo;
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
@end

@interface WebGLInfo : NSObject
@property (nonatomic, copy) NSString *unmaskedVendor;
@property (nonatomic, copy) NSString *unmaskedRenderer;
@property (nonatomic, copy) NSString *webglVendor;
@property (nonatomic, copy) NSString *webglRenderer;
@property (nonatomic, copy) NSString *webglVersion;
@property (nonatomic, copy) NSNumber *maxTextureSize;
@property (nonatomic, copy) NSNumber *maxRenderBufferSize;
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
@end