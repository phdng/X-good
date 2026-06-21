# Tài liệu Agent - Dự án ProjectX (Kiến trúc Chi tiết & Toàn diện)

Tài liệu này cung cấp cái nhìn chi tiết về kiến trúc mã nguồn, phân loại chức năng và vị trí chính xác của các thành phần trong dự án ProjectX (WeaponX).

## 1. Hệ thống Giả lập Định danh (Identifier Spoofing Framework)
Thành phần trung tâm quản lý việc tạo, lưu trữ và cung cấp các giá trị giả lập cho thiết bị.

- **Quản lý logic chính:** `common/IdentifierManager.m`
- **Định danh cơ bản:**
  - IDFA: `common/IDFAManager.m`
  - IDFV: `common/IDFVManager.m`
  - Số Serial: `common/SerialNumberManager.m`
  - Tên thiết bị: `common/DeviceNameManager.m`
- **Thông tin thiết bị & Phần cứng:**
  - Model Manager: `common/DeviceModelManager.m`
  - Cơ sở dữ liệu Model: `common/IPhoneModelDB.m` (Lưu ý chữ hoa: **IPhone**)
- **Nhóm quản lý định danh UUID (Đầy đủ):**
  - Hệ thống (System): `common/SystemUUIDManager.m`
  - Keychain: `common/KeychainUUIDManager.m`
  - Nhóm ứng dụng (App Group): `common/AppGroupUUIDManager.m`
  - Container ứng dụng: `common/AppContainerUUIDManager.m`
  - Cài đặt (Install): `common/AppInstallUUIDManager.m`
  - Core Data: `common/CoreDataUUIDManager.m`
  - Dyld Cache: `common/DyldCacheUUIDManager.m`
  - Bảng nhớ tạm (Pasteboard): `common/PasteboardUUIDManager.m`
  - User Defaults: `common/UserDefaultsUUIDManager.m`
- **Quản lý Phiên bản & Thời gian:**
  - Thông tin iOS: `common/IOSVersionInfo.m`
  - Cơ sở dữ liệu Build iOS: `common/IOSBuildDB.m`
  - Logic so sánh phiên bản: `common/VersionCompare.m`
  - Thời gian hoạt động (Uptime/BootTime): `common/UptimeManager.m`

## 2. Công cụ Hooking và Can thiệp Hệ thống (System Hooking Engine)
Hệ thống can thiệp API hệ thống tại runtime sử dụng Substrate/ElleKit.

- **Hạ tầng Hooking cốt lõi (Kiến trúc quan trọng):**
  - `ProjectXTweak/MethodSwizzler.m` (và `.h`)
  - `ProjectXTweak/PXScope.m` (và `.h`)
  - `ProjectXTweak/HookOwnership.h`
  - `ProjectXTweak/MobileGestalt.h`
- **Logic Hooking thực tế (Các module đã hoàn thiện):**
  - Khởi tạo chính: `ProjectXTweak/Tweak.x`
  - Phiên bản iOS: `ProjectXTweak/IOSVersionHooks.x`
  - Phiên bản App: `ProjectXTweak/AppVersionHooks.x`
  - Bypass phát hiện Jailbreak: `ProjectXTweak/JailbreakBypassHooks.x`
  - Dữ liệu người dùng: `ProjectXTweak/UserDefaultsHooks.x`
  - Pin/Năng lượng: `ProjectXTweak/BatteryHooks.x`
  - Cấu hình thiết bị: `ProjectXTweak/DeviceSpecHooks.x`
  - Mạng/WiFi: `ProjectXTweak/WiFiHook.x`, `ProjectXTweak/NetworkConnectionTypeHooks.x`
  - Dấu vân tay Canvas: `ProjectXTweak/CanvasFingerprintHooks.x`
  - Thời gian khởi động: `ProjectXTweak/BootTimeHooks.x`
  - Ngôn ngữ & Múi giờ: `ProjectXTweak/LocaleTimeZoneHooks.x`
  - Model thiết bị: `ProjectXTweak/DeviceModelHooks.x`
  - Chặn tên miền: `ProjectXTweak/DomainBlockingHooks.x`
  - Bảng nhớ tạm (Pasteboard): `ProjectXTweak/PasteboardHooks.x`
  - Hệ thống lưu trữ: `ProjectXTweak/StorageHooks.x`
  - Chủ đề (Theme): `ProjectXTweak/ThemeHooks.x`
  - Các loại UUID: `ProjectXTweak/UUIDHooks.x`
  - Giả lập bổ sung: `ProjectXTweak/MissingSpoofHooks.x`
  - Hook khởi chạy SpringBoard: `ProjectXTweak/SpringBoardLaunchHook.x`
  - Vô hiệu hóa Firebase Perf: `ProjectXTweak/FirebasePerfDisableScoped.x`
  - Bảo vệ lớp ObjC: `ProjectXTweak/ObjcClassPairGuard.x`
- **File rỗng / Placeholder (Chưa triển khai logic):**
  - `ProjectXTweak/KeychainHooks.x` ⚠️
  - `ProjectXTweak/AppContainerHooks.x` ⚠️
  - `ProjectXTweak/AppGroupHooks.x` ⚠️
  - `ProjectXTweak/AppInstallHooks.x` ⚠️
  - `ProjectXTweak/CoreDataHooks.x` ⚠️
  - `ProjectXTweak/VPNDetectionBypass.x` ⚠️

## 3. Giả lập Vị trí và Cảm biến (Location & Sensor Spoofing)
- **Quản lý GPS:** `common/LocationSpoofingManager.m`
- **Hook Cảm biến (Phân tán):** `ProjectXTweak/BatteryHooks.x`, `ProjectXTweak/DeviceSpecHooks.x` (Thay đổi thông tin pin, phần cứng).

## 4. Cô lập Sandbox và Điều hướng Đường dẫn (Path Redirection)
- **Logic chuyển hướng chính:** `ContainerManager.m` (Nằm ở Root)
- **Quản lý lưu trữ:** `common/StorageManager.m`
- **Placeholder (Chưa triển khai):** `ProjectXTweak/AppContainerHooks.x` ⚠️

## 5. Quản lý Vòng đời Profile (Profile Lifecycle Management)
- **Logic nghiệp vụ:** `common/ProfileManager.m`
- **Hiển thị trạng thái:** `common/ProfileIndicatorView.m`
- **Giao diện quản lý (UI - Nằm ở Root):**
  - Màn hình tạo Profile: `ProfileCreationViewController.m`
  - Màn hình quản lý danh sách: `ProfileManagerViewController.m`
  - View các nút chức năng: `ProfileButtonsView.m`

## 6. Làm sạch Dữ liệu Nâng cao (Advanced Data Cleaning)
- **Thành phần chính:** `AppDataCleaner.m` (Nằm ở Root)
- **Cơ chế phối hợp:** Liên kết trực tiếp với `ContainerManager.m` để xóa thư mục profile và các module dọn dẹp Keychain chuyên sâu.

## 7. Hệ thống Sao lưu và Phục hồi (Backup & Restore System)
- **Logic quản lý file:** `AppDataBackupManager.m` (Root)
- **Trợ giúp Keychain:** `KeychainHelper/KeychainBackupHelper.m`, `KeychainHelper/backup_helper.m`
- **Script hệ thống:** `scripts/keychain_backup.sh`
- **Giao diện quản lý (UI - Nằm ở Root):**
  - Màn hình chính Sao lưu/Phục hồi: `AppDataBackupRestoreViewController.m`
  - Màn hình quản lý nhóm Keychain: `BackupKeychainGroupsViewController.m`

## 8. Daemon và Thành phần Duy trì Trạng thái
- **System Daemon:** `WeaponXMountDaemon/WeaponXDaemon.m`
- **App Guardian (Bảo vệ ứng dụng):** `WeaponXGuardian.m`
- **Cầu nối Keychain:** `WeaponXKeychainBridge/Tweak.m`

## 9. Giám sát Mạng (Network Monitoring)
- **URL Monitor:** `URLMonitor.m`, `ProjectXTweak/UberURLHooks.x`
- **Quản lý kết nối & IP:** `common/NetworkManager.m`, `common/IPMonitorService.m`

## 10. Giao diện Người dùng và Công cụ Điều khiển
- **Màn hình chính ứng dụng:** `ProjectXViewController.m`
- **Phân tích Quyền hạn:** `AppEntitlementsReader.m` (Dùng ldid phân tích entitlements của app mục tiêu)

---