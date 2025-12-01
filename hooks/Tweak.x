#import "ProjectX.h"
#import "IdentifierManager.h"
#import "AppScopeManager.h"
#import <AdSupport/ASIdentifierManager.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "ProjectXLogging.h"
#import <mach-o/dyld.h>
#import <ifaddrs.h>
#import <string.h>
#import <net/if.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <IOKit/IOKitLib.h>
#import <sys/sysctl.h>  // For sysctlbyname hooks
#import <dirent.h>     // For DIR type
#import <sys/mount.h>  // For statfs
#import "ProfileManager.h" // For accessing current profile
#import <substrate.h>
#import <sys/utsname.h>
#import <Security/Security.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreMotion/CoreMotion.h> // Import CoreMotion framework for sensor spoofing
#import "LocationSpoofingManager.h" // Import location spoofing manager

// Forward declarations for classes we need to hook
@interface SBScreenshotManager : NSObject
- (void)saveScreenshotsWithCompletion:(id)completion;
- (void)saveScreenshots;
@end

@interface UIImage (WeaponXScreenshot)
- (UIImage *)weaponx_addProfileIndicator;
- (UIImage *)weaponx_removeNavigationBar;
@end

// Cache for values
static NSMutableDictionary *valueCache;




// Define hook group for location spoofing
%group LocationSpoofing

// Hook CLLocationManager to intercept location updates
%hook CLLocationManager

- (void)setDelegate:(id)delegate {
    // First, pass through to the original implementation
    %orig;
    
    @try {
        // Only log spoofing info for non-Apple apps, and avoid excessive logging
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            // Get the manager instance outside the synchronized block to prevent deadlocks
            LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
            
            // Log only on the first delegation or periodically (using a static variable)
            static NSMutableSet *handledDelegates = nil;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                handledDelegates = [NSMutableSet set];
            });
            
            @synchronized(handledDelegates) {
                // Create identifier for this delegate/manager pair
                NSString *delegateID = [NSString stringWithFormat:@"%p-%p", delegate, self];
                
                // Only log if we haven't seen this delegate before
                if (![handledDelegates containsObject:delegateID]) {
                    [handledDelegates addObject:delegateID];
                    
                    if (manager && bundleID) {
                        double lat = [manager getSpoofedLatitude];
                        double lon = [manager getSpoofedLongitude];
                        PXLog(@"[WeaponX] GPS spoofing is enabled for %@. Using: %.6f, %.6f", 
                                bundleID, lat, lon);
                        // In iOS 15+, make sure position variations are enabled
                        if (manager.jitterEnabled) {
                            // Set position variations to match jitter setting for consistency
                            manager.positionVariationsEnabled = YES;
                        }
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        // Just log the exception and don't interfere with normal operation
        PXLog(@"[WeaponX] Exception in CLLocationManager.setDelegate: %@", exception);
    }
}

// Hook location accuracy settings
- (void)setDesiredAccuracy:(CLLocationAccuracy)accuracy {
    // Check if we should modify accuracy
    @try {
        // Ensure high accuracy for our spoofed locations
        PXLog(@"[WeaponX] App requested accuracy %.1f, ensuring best accuracy for spoofing", 
                accuracy);
        
        // Override with best accuracy
        %orig(kCLLocationAccuracyBest);
        return;
        
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in setDesiredAccuracy: %@", exception);
    }
    
    // Default behavior
    %orig;
}

// Monitor when location updates are started
- (void)startUpdatingLocation {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ started location updates", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in startUpdatingLocation: %@", exception);
    }
    
    %orig;
}

// Monitor when location updates are stopped
- (void)stopUpdatingLocation {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ stopped location updates", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in stopUpdatingLocation: %@", exception);
    }
    
    %orig;
}

%end

// Hook CLLocation to modify coordinate with improved thread safety
%hook CLLocation

- (CLLocationCoordinate2D)coordinate {
    // Get the original coordinate
    CLLocationCoordinate2D originalCoordinate = %orig;
    
    // Use thread-local storage to prevent recursive calls
    static NSString * const kRecursionGuardKey = @"CLLocationCoordinateRecursionGuard";
    NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
    if ([threadDictionary[kRecursionGuardKey] boolValue]) {
        return originalCoordinate;
    }
    
    // Set recursion guard
    threadDictionary[kRecursionGuardKey] = @YES;
    
    @try {
        // Performance optimization: throttle location checks
        static NSTimeInterval lastProcessTime = 0;
        static CLLocationCoordinate2D lastReturnedCoordinate = {0, 0};
        
        // Thread-safe time check
        NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
        BOOL shouldThrottle = NO;
        
        @synchronized([self class]) {
            shouldThrottle = (currentTime - lastProcessTime < 0.2);
            
            if (!shouldThrottle) {
                lastProcessTime = currentTime;
            }
        }
        
        if (shouldThrottle) {
            // Return the last spoofed coordinates if they were set and valid
            if (CLLocationCoordinate2DIsValid(lastReturnedCoordinate) && 
                (lastReturnedCoordinate.latitude != 0.0 || lastReturnedCoordinate.longitude != 0.0)) {
                threadDictionary[kRecursionGuardKey] = nil;
                return lastReturnedCoordinate;
            }
            threadDictionary[kRecursionGuardKey] = nil;
            return originalCoordinate;
        }
             
        
        // Use modifySpoofedLocation method which properly handles position variations
        // Create a temporary CLLocation with the original coordinates to modify
        CLLocation *tempLocation = [[CLLocation alloc] initWithLatitude:originalCoordinate.latitude
                                                             longitude:originalCoordinate.longitude];
        
        // Get a properly spoofed location with all variations applied
        LocationSpoofingManager * manager = [LocationSpoofingManager sharedManager];
        CLLocation *spoofedLocation = [manager modifySpoofedLocation:tempLocation];
        if (!spoofedLocation) {
            threadDictionary[kRecursionGuardKey] = nil;
            return originalCoordinate;
        }
        
        // Get the spoofed coordinates with variations applied
        CLLocationCoordinate2D spoofedCoordinate = spoofedLocation.coordinate;
        
        // Store the spoofed coordinate for throttled requests in thread-safe way
        @synchronized([self class]) {
            lastReturnedCoordinate = spoofedCoordinate;
        }
        
        // Only log occasionally to reduce spam
        static NSTimeInterval lastLogTime = 0;
        if (currentTime - lastLogTime > 30.0) {
            @synchronized([self class]) {
                if (currentTime - lastLogTime > 30.0) {
                    PXLog(@"[WeaponX] Using spoofed location for : (%.6f, %.6f) with variations", 
                         spoofedCoordinate.latitude, spoofedCoordinate.longitude);
                    lastLogTime = currentTime;
                }
            }
        }
        
        threadDictionary[kRecursionGuardKey] = nil;
        return spoofedCoordinate;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception while spoofing location: %@", exception);
        threadDictionary[kRecursionGuardKey] = nil;
        return originalCoordinate;
    }
}

%end

// Hook -[CLLocationManager locationManagerDidUpdateLocations:] delegate method
%hook NSObject

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    // First check if this is actually a CLLocationManagerDelegate
    if (![self respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        %orig;
        return;
    }
    
    if (!manager || !locations || locations.count == 0) {
        %orig;
        return;
    }
    

    @try {
        // Create array of spoofed locations
        NSMutableArray *spoofedLocations = [NSMutableArray arrayWithCapacity:locations.count];
        
        // Apply proper position variations to each location using modifySpoofedLocation
        for (CLLocation *originalLocation in locations) {
            // Get a properly spoofed location with all variations applied
            LocationSpoofingManager * spoofManager = [LocationSpoofingManager sharedManager];

            CLLocation *spoofedLocation = [spoofManager modifySpoofedLocation:originalLocation];
            
            if (spoofedLocation) {
                [spoofedLocations addObject:spoofedLocation];
            } else {
                // If spoofing fails, use original location
                [spoofedLocations addObject:originalLocation];
            }
        }
        
        // Replace original locations with spoofed ones
        if (spoofedLocations.count > 0) {
            %orig(manager, spoofedLocations);
            return;
        }
        
        // If no spoofed locations were created, use original
        %orig;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in locationManager:didUpdateLocations: %@", exception);
        %orig; // Pass through original on exception
    }
}

// Add hook for the legacy location update method
- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation {
    // First check if this is actually a CLLocationManagerDelegate
    if (![self respondsToSelector:@selector(locationManager:didUpdateToLocation:fromLocation:)]) {
        %orig;
        return;
    }
    
    if (!manager || !newLocation) {
        %orig;
        return;
    }
     
    @try {
        // Performance optimization: throttle excessive legacy updates
        static NSTimeInterval lastLegacyUpdateTime = 0;
        NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
        if (currentTime - lastLegacyUpdateTime < 0.3) { // Max ~3 updates per second
            static int legacySkipCounter = 0;
            if (++legacySkipCounter % 3 != 0) { // Process only every 3rd rapid update
                %orig;
                return;
            }
        }
        lastLegacyUpdateTime = currentTime;
        LocationSpoofingManager * spoofManager = [LocationSpoofingManager sharedManager];
        
        // Get spoofed location with position variations applied
        CLLocation *spoofedLocation = [spoofManager modifySpoofedLocation:newLocation];
        
        if (spoofedLocation) {
            // Only log occasionally
            static NSTimeInterval lastLogTime = 0;
            if (currentTime - lastLogTime > 30.0) {
                PXLog(@"[WeaponX] Using pinned location with variations for (legacy method)");
                lastLogTime = currentTime;
            }
            
            // Call original with spoofed location
            %orig(manager, spoofedLocation, oldLocation);
        } else {
            // If spoofing fails, use original
            %orig;
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in legacy location method: %@", exception);
        %orig; // Pass through original on exception
    }
}

%end

// Additional CLLocationManager hooks for special methods
%hook CLLocationManager

// Hook for one-time location requests
- (void)requestLocation {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ requested one-time location", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in requestLocation: %@", exception);
    }
    
    %orig;
}

// Hook for significant location monitoring
- (void)startMonitoringSignificantLocationChanges {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ started monitoring significant location changes", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in startMonitoringSignificantLocationChanges: %@", exception);
    }
    
    %orig;
}

- (void)stopMonitoringSignificantLocationChanges {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ stopped monitoring significant location changes", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in stopMonitoringSignificantLocationChanges: %@", exception);
    }
    
    %orig;
}

// Hook for deferred location updates
- (void)allowDeferredLocationUpdatesUntilTraveled:(CLLocationDistance)distance timeout:(NSTimeInterval)timeout {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ requested deferred location updates (distance: %.2f, timeout: %.2f)", 
                  bundleID, distance, timeout);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in allowDeferredLocationUpdatesUntilTraveled: %@", exception);
    }
    
    %orig;
}

- (void)disallowDeferredLocationUpdates {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ disallowed deferred location updates", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in disallowDeferredLocationUpdates: %@", exception);
    }
    
    %orig;
}

// Hook for heading updates
- (void)startUpdatingHeading {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ started heading updates", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in startUpdatingHeading: %@", exception);
    }
    
    %orig;
}

- (void)stopUpdatingHeading {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ stopped heading updates", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in stopUpdatingHeading: %@", exception);
    }
    
    %orig;
}

// Hook for geofencing
- (void)startMonitoringForRegion:(CLRegion *)region {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ started monitoring for region: %@", bundleID, region.identifier);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in startMonitoringForRegion: %@", exception);
    }
    
    %orig;
}

- (void)stopMonitoringForRegion:(CLRegion *)region {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ stopped monitoring for region: %@", bundleID, region.identifier);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in stopMonitoringForRegion: %@", exception);
    }
    
    %orig;
}

- (void)requestStateForRegion:(CLRegion *)region {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ requested state for region: %@", bundleID, region.identifier);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in requestStateForRegion: %@", exception);
    }
    
    %orig;
}

// Hook for visit monitoring
- (void)startMonitoringVisits {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ started monitoring visits", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in startMonitoringVisits: %@", exception);
    }
    
    %orig;
}

- (void)stopMonitoringVisits {
    @try {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && ![bundleID hasPrefix:@"com.apple."]) {
            PXLog(@"[WeaponX] App %@ stopped monitoring visits", bundleID);
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in stopMonitoringVisits: %@", exception);
    }
    
    %orig;
}

%end

// Hook CLLocation additional properties
%hook CLLocation

- (CLLocationSpeed)speed {
    // Return a reasonable speed value (walking pace)
    return 1.5;
}

- (CLLocationDirection)course {
    // Return a fixed direction (North = 0 degrees)
    return 0.0;
}

%end

// Add more delegate method hooks to NSObject
%hook NSObject

// Regional monitoring delegate methods
- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region {
    // First check if this is actually a CLLocationManagerDelegate
    if (![self respondsToSelector:@selector(locationManager:didEnterRegion:)]) {
        %orig;
        return;
    }
    
    
    @try {
        // Log the interception
        PXLog(@"[WeaponX] Intercepted region entry for app , region: %@", region.identifier);
        
        // We suppress region events when spoofing is active since our location isn't actually moving
        // This prevents apps from getting confusing region notifications
        
        // Do not call %orig to suppress the notification
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in locationManager:didEnterRegion: %@", exception);
        %orig;
    }
}

- (void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region {
    // First check if this is actually a CLLocationManagerDelegate
    if (![self respondsToSelector:@selector(locationManager:didExitRegion:)]) {
        %orig;
        return;
    }
    
    
    @try {
        // Log the interception
        PXLog(@"[WeaponX] Intercepted region exit for app, region: %@", region.identifier);
        
        // Suppress region exit events when spoofing is active
        // Do not call %orig to suppress the notification
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in locationManager:didExitRegion: %@", exception);
        %orig;
    }
}

// Heading update delegate method
- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading {
    // First check if this is actually a CLLocationManagerDelegate
    if (![self respondsToSelector:@selector(locationManager:didUpdateHeading:)]) {
        %orig;
        return;
    }
    
    
    @try {
        // Create a spoofed heading pointing north
        // This would require creating a custom CLHeading, which is complex
        // For now, we'll just pass through the original heading
        PXLog(@"[WeaponX] Passing through heading update for app");
        %orig;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in locationManager:didUpdateHeading: %@", exception);
        %orig;
    }
}

%end

// Hook for MKMapView to handle map-specific location display
%hook MKMapView

- (MKUserLocation *)userLocation {
    MKUserLocation *originalUserLocation = %orig;
    
    @try {
        
        // Since we can't directly modify MKUserLocation's coordinate (it's read-only),
        // we rely on our CLLocation hook to handle this
        // The coordinate is ultimately provided by CLLocationManager
        
        // Just log the request
        static NSTimeInterval lastLogTime = 0;
        NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
        if (currentTime - lastLogTime > 30.0) {
            PXLog(@"[WeaponX] App requested map user location");
            lastLogTime = currentTime;
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in MKMapView userLocation: %@", exception);
    }
    
    return originalUserLocation;
}

%end

// Hook for MKUserLocation to ensure map display is spoofed
%hook MKUserLocation

- (CLLocationCoordinate2D)coordinate {
    CLLocationCoordinate2D originalCoordinate = %orig;
    
    @try {
        LocationSpoofingManager * manager = [LocationSpoofingManager sharedManager];
        // Get spoofed coordinates
        double latitude = [manager getSpoofedLatitude];
        double longitude = [manager getSpoofedLongitude];
        
        // Validation
        if (latitude == 0.0 && longitude == 0.0) {
            return originalCoordinate;
        }
        
        // Create and return spoofed coordinate
        CLLocationCoordinate2D spoofedCoordinate = CLLocationCoordinate2DMake(latitude, longitude);
        
        // Log occasionally
        static NSTimeInterval lastLogTime = 0;
        NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
        if (currentTime - lastLogTime > 30.0) {
            PXLog(@"[WeaponX] Using spoofed coordinate for map display: (%.6f, %.6f)", 
                  spoofedCoordinate.latitude, spoofedCoordinate.longitude);
            lastLogTime = currentTime;
        }
        
        return spoofedCoordinate;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in MKUserLocation coordinate: %@", exception);
        return originalCoordinate;
    }
}

%end

// Hook CLGeocoder for geocoding services
%hook CLGeocoder

- (void)reverseGeocodeLocation:(CLLocation *)location completionHandler:(void (^)(NSArray<CLPlacemark *> *placemarks, NSError *error))completionHandler {
    @try {
        LocationSpoofingManager * manager = [LocationSpoofingManager sharedManager];

        // Create a spoofed location
        CLLocation *spoofedLocation = [manager modifySpoofedLocation:location];
        if (!spoofedLocation) {
            %orig;
            return;
        }
        
        // Log the reverseGeocoding request
        PXLog(@"[WeaponX] App requested reverse geocoding, using spoofed location");
        
        // Create a copy of the completion handler to ensure it stays alive
        void (^wrappedHandler)(NSArray<CLPlacemark *> *, NSError *) = [completionHandler copy];
        
        // Call original with our spoofed location and copied handler
        %orig(spoofedLocation, wrappedHandler);
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in reverseGeocodeLocation: %@", exception);
        %orig;
    }
}

// Add forward geocoding method
- (void)geocodeAddressString:(NSString *)addressString completionHandler:(void (^)(NSArray<CLPlacemark *> *placemarks, NSError *error))completionHandler {
    @try {
        
        // Log the forward geocoding request
        PXLog(@"[WeaponX] App requested forward geocoding for address: %@", addressString);
        
        // Create a copy of the completion handler to ensure it stays alive
        void (^wrappedHandler)(NSArray<CLPlacemark *> *, NSError *) = [completionHandler copy];
        
        // Use a simpler implementation to avoid syntax errors
        void (^monitorBlock)(NSArray<CLPlacemark *> *, NSError *) = ^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
            if (placemarks.count > 0) {
                PXLog(@"[WeaponX] Forward geocoding returned %lu placemarks for %@", 
                      (unsigned long)placemarks.count, addressString);
            }
            
            // Call original completion handler
            wrappedHandler(placemarks, error);
        };
        
        %orig(addressString, monitorBlock);
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in geocodeAddressString: %@", exception);
        %orig;
    }
}

%end

%end // End of LocationSpoofing group

// Add new group for sensor data integration
%group SensorSpoofing

// Hook for accelerometer data
%hook CMMotionManager

- (CMAccelerometerData *)accelerometerData {
    @try {
        LocationSpoofingManager * manager = [LocationSpoofingManager sharedManager];

        // Get the last spoofed location data
        double speed = manager.lastReportedSpeed;
        double course = manager.lastReportedCourse;
        
        // Create synthetic accelerometer data based on movement
        CMAccelerometerData *data = %orig;
        if (!data) {
            data = [[objc_getClass("CMAccelerometerData") alloc] init];
        }
        
        // Calculate appropriate accelerometer values
        double xAccel = 0.0, yAccel = 0.0, zAccel = -1.0; // Default gravity
        
        // Modify based on movement
        if (speed > 0) {
            // Convert course to radians
            double courseRad = course * M_PI / 180.0;
            
            // Add movement component
            double movementFactor = MIN(speed * 0.01, 0.2); // Scale with speed
            xAccel += cos(courseRad) * movementFactor;
            yAccel += sin(courseRad) * movementFactor;
            
            // Add slight vibration for realism
            xAccel += ((arc4random() % 100) - 50) / 1000.0;
            yAccel += ((arc4random() % 100) - 50) / 1000.0;
            zAccel += ((arc4random() % 100) - 50) / 1000.0;
        }
        
        // Set the accelerometer values safely with exception handling
        @try {
            [data setValue:@(xAccel) forKey:@"x"];
            [data setValue:@(yAccel) forKey:@"y"];
            [data setValue:@(zAccel) forKey:@"z"];
        } @catch (NSException *exception) {
            PXLog(@"[WeaponX] Exception setting accelerometer data: %@", exception);
            // Return original data if there's an error setting values
            return %orig;
        }
        
        return data;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in accelerometerData: %@", exception);
        return %orig;
    }
}

// Add gyroscope data spoofing for complete motion data
- (CMGyroData *)gyroData {
    @try {
        LocationSpoofingManager * manager = [LocationSpoofingManager sharedManager];

        // Get the last spoofed location data
        double speed = manager.lastReportedSpeed;
        double course = manager.lastReportedCourse;
        
        // Create synthetic gyroscope data
        CMGyroData *data = %orig;
        if (!data) {
            data = [[objc_getClass("CMGyroData") alloc] init];
        }
        
        // Calculate gyroscope values based on movement and course
        double xRotation = 0.0, yRotation = 0.0, zRotation = 0.0;
        
        // Add slight rotation based on course changes (would be more sophisticated in real implementation)
        if (speed > 0) {
            // Calculate small rotations that align with course
            // In a real implementation this would track course changes over time
            
            // Use the course value to add a slight rotation based on direction
            double courseRad = course * M_PI / 180.0;
            zRotation = ((arc4random() % 100) - 50) / 1000.0; // Small rotation around Z axis for turning
            
            // Add small course-based rotation to make movements more realistic
            xRotation += sin(courseRad) * 0.01;
            yRotation += cos(courseRad) * 0.01;
            LocationSpoofingManager * manager = [LocationSpoofingManager sharedManager];
            
            // Add transportation mode specific movements
            if (manager.transportationMode == TransportationModeDriving) {
                // Driving has more yaw (z-axis rotation) for turns
                zRotation *= 2.5;
            } else if (manager.transportationMode == TransportationModeWalking) {
                // Walking has more pitch/roll (x/y-axis rotation) for steps
                xRotation += sin(CACurrentMediaTime() * 2.0) * 0.05; // Simulate walking motion
                yRotation += sin(CACurrentMediaTime() * 2.0 + M_PI_2) * 0.02;
            }
        }
        
        // Set the gyroscope values safely with exception handling
        @try {
            [data setValue:@(xRotation) forKey:@"x"];
            [data setValue:@(yRotation) forKey:@"y"];
            [data setValue:@(zRotation) forKey:@"z"];
        } @catch (NSException *exception) {
            PXLog(@"[WeaponX] Exception setting gyroscope data: %@", exception);
            // Return original data if there's an error setting values
            return %orig;
        }
        
        return data;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in gyroData: %@", exception);
        return %orig;
    }
}

// Add magnetometer (compass) data spoofing to align with GPS course
- (CMMagnetometerData *)magnetometerData {
    @try {
        LocationSpoofingManager * manager = [LocationSpoofingManager sharedManager];
        // Get the course from the last spoofed location
        double course = manager.lastReportedCourse;
        
        // Create synthetic magnetometer data
        CMMagnetometerData *data = %orig;
        if (!data) {
            data = [[objc_getClass("CMMagnetometerData") alloc] init];
        }
        
        // Convert course to radians
        double courseRad = course * M_PI / 180.0;
        
        // Calculate magnetometer values that would point to the course direction
        // This is a simplified model - real magnetometer data would be more complex
        double magneticField = 30.0; // Approximate strength of Earth's magnetic field
        
        // Simplified magnetic field components based on course
        double xField = magneticField * cos(courseRad);
        double yField = magneticField * sin(courseRad);
        double zField = 0.0; // Simplified - assume device is flat
        
        // Add some realistic noise
        xField += ((arc4random() % 100) - 50) / 50.0;
        yField += ((arc4random() % 100) - 50) / 50.0;
        zField += ((arc4random() % 100) - 50) / 50.0;
        
        // Set the magnetometer values safely with exception handling
        @try {
            [data setValue:@(xField) forKey:@"x"];
            [data setValue:@(yField) forKey:@"y"];
            [data setValue:@(zField) forKey:@"z"];
        } @catch (NSException *exception) {
            PXLog(@"[WeaponX] Exception setting magnetometer data: %@", exception);
            // Return original data if there's an error setting values
            return %orig;
        }
        
        return data;
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in magnetometerData: %@", exception);
        return %orig;
    }
}

%end // End CMMotionManager hook

// Add barometer/altitude data spoofing
%hook CMAltimeter

- (void)startRelativeAltitudeUpdatesToQueue:(NSOperationQueue *)queue withHandler:(void (^)(CMAltitudeData *altitudeData, NSError *error))handler {
    @try {

        
        
        // Instead of calling original, we'll handle the queue operations ourselves
        [self stopRelativeAltitudeUpdates]; // Stop any existing updates
        
        // Create a strong reference to the handler to prevent it from being deallocated
        void (^strongHandler)(CMAltitudeData *, NSError *) = [handler copy];
        
        // Keep a reference to the timer in an associated object to prevent it from being deallocated
        static char kAltimeterTimerKey;
        
        // Create our own timer to simulate altitude updates
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            // Create a timer for regular updates
            NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
                @try {
                    // Create synthetic altitude data
                    CMAltitudeData *altData = [[objc_getClass("CMAltitudeData") alloc] init];
                    
                    // Get current transportation mode and simulate appropriate pressure changes
                    double relativeAltitude = 0.0;
                    double pressure = 1013.25; // Standard pressure at sea level in hPa
                    LocationSpoofingManager * manager = [LocationSpoofingManager sharedManager];
                    
                    // Adjust based on transportation mode
                    if (manager.transportationMode == TransportationModeDriving) {
                        // More altitude variations for driving
                        relativeAltitude = ((arc4random() % 100) - 50) / 10.0; // ±5 meters
                    } else if (manager.transportationMode == TransportationModeWalking) {
                        // Slight variations for walking
                        relativeAltitude = ((arc4random() % 50) - 25) / 10.0; // ±2.5 meters
                    } else {
                        // Minimal variations for stationary
                        relativeAltitude = ((arc4random() % 20) - 10) / 10.0; // ±1 meter
                    }
                    
                    // Calculate pressure from altitude (simplified model)
                    // Standard formula: P = P0 * exp(-g * M * h / (R * T))
                    // Simplified for small changes: approximately -0.12 hPa per meter of height
                    pressure = 1013.25 - (relativeAltitude * 0.12);
                    
                    // Set the values using KVC safely
                    @try {
                        [altData setValue:@(relativeAltitude) forKey:@"relativeAltitude"];
                        [altData setValue:@(pressure) forKey:@"pressure"];
                    } @catch (NSException *exception) {
                        PXLog(@"[WeaponX] Exception setting altitude data values: %@", exception);
                    }
                    
                    // Queue operation to deliver update
                    if (queue && strongHandler) {
                        [queue addOperationWithBlock:^{
                            strongHandler(altData, nil);
                        }];
                    }
                } @catch (NSException *exception) {
                    PXLog(@"[WeaponX] Exception in altimeter update timer: %@", exception);
                }
            }];
            
            // Store the timer as an associated object on self to keep it alive
            objc_setAssociatedObject(self, &kAltimeterTimerKey, timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            
            // Run the timer on the current runloop
            NSRunLoop *currentRunLoop = [NSRunLoop currentRunLoop];
            [currentRunLoop addTimer:timer forMode:NSDefaultRunLoopMode];
            
            // Keep the runloop alive - this will block this thread
            // We're using a separate dispatch_async so this is okay
            CFRunLoopRun();
        });
        
        PXLog(@"[WeaponX] Started custom altitude updates");
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in startRelativeAltitudeUpdatesToQueue: %@", exception);
        %orig; // Fall back to original implementation
    }
}

// Add a hook for stopRelativeAltitudeUpdates to properly clean up our timer
- (void)stopRelativeAltitudeUpdates {
    @try {
        // Clean up our custom timer if it exists
        static char kAltimeterTimerKey;
        NSTimer *timer = objc_getAssociatedObject(self, &kAltimeterTimerKey);
        if (timer) {
            [timer invalidate];
            objc_setAssociatedObject(self, &kAltimeterTimerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            PXLog(@"[WeaponX] Stopped custom altitude updates");
        }
    } @catch (NSException *exception) {
        PXLog(@"[WeaponX] Exception in stopRelativeAltitudeUpdates: %@", exception);
    }
    
    // Call original implementation to ensure proper cleanup
    %orig;
}

%end

%end  // End of SensorSpoofing group


// Hook IOKit's IORegistryEntryCreateCFProperty for serial number
static CFTypeRef (*orig_IORegistryEntryCreateCFProperty)(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options);

CFTypeRef hook_IORegistryEntryCreateCFProperty(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) {
    // Null checks to prevent crashes
    if (!entry || !key) {
        return NULL;
    }
    
    // Get manager and check if identifier spoofing is enabled
    @try {
 
        
        IdentifierManager *manager = [IdentifierManager sharedManager];
        NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
        
        // Skip spoofing for system processes or if application isn't enabled
        if (!IsScope()) {
            return orig_IORegistryEntryCreateCFProperty(entry, key, allocator, options);
        }
        
        // Convert CoreFoundation key to NSString for easier handling
        NSString *keyString = (__bridge NSString *)key;
        
        // Serial Number
        if ([keyString isEqualToString:@"IOPlatformSerialNumber"]) {
            // Special case for Filza and ADManager
            if ([currentBundleID isEqualToString:@"com.tigisoftware.Filza"] || 
                [currentBundleID isEqualToString:@"com.tigisoftware.ADManager"]) {
                NSString *hardcodedSerial = @"FCCC15Q4HG04";
                PXLog(@"[WeaponX] 📱 Spoofing IOPlatformSerialNumber with hardcoded value for %@: %@", 
                     currentBundleID, hardcodedSerial);
                return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)hardcodedSerial);
            }
            
            if ([manager isIdentifierEnabled:@"SerialNumber"]) {
                NSString *spoofedSerial = [manager getValueForType:@"SerialNumber"];
                if (spoofedSerial) {
                    PXLog(@"Spoofing IOPlatformSerialNumber with: %@", spoofedSerial);
                    // Ensure proper memory management with CoreFoundation objects
                    return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)spoofedSerial);
                }
            }
        }
        
        
        // IMEI for cellular devices
        if ([keyString isEqualToString:@"kIMEIKey"] && [manager isIdentifierEnabled:@"IMEI"]) {
            NSString *spoofedIMEI = [manager getValueForType:@"IMEI"];
            if (spoofedIMEI) {
                PXLog(@"Spoofing IMEI with: %@", spoofedIMEI);
                return CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)spoofedIMEI);
            }
        }
        

    } @catch (NSException *exception) {
        PXLog(@"Exception in IORegistryEntryCreateCFProperty hook: %@", exception);
    }
    
    // For all other cases, pass through to the original function
    return orig_IORegistryEntryCreateCFProperty(entry, key, allocator, options);
}

// Hook private API GSSystemGetSerialNo
static char* (*orig_GSSystemGetSerialNo)(void);

static char* hook_GSSystemGetSerialNo(void) {
    IdentifierManager *manager = [IdentifierManager sharedManager];
    NSString *currentBundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    PXLog(@"GSSystemGetSerialNo requested by app: %@", currentBundleID);
    
    // Special case for Filza and ADManager
    if ([currentBundleID isEqualToString:@"com.tigisoftware.Filza"] || 
        [currentBundleID isEqualToString:@"com.tigisoftware.ADManager"]) {
        NSString *hardcodedSerial = @"FCCC15Q4HG04";
        PXLog(@"[WeaponX] 📱 Spoofing GSSystemGetSerialNo with hardcoded value for %@: %@", 
             currentBundleID, hardcodedSerial);
        
        // Convert NSString to char* that will persist
        char *serialStr = strdup([hardcodedSerial UTF8String]);
        return serialStr;
    }
    
    
    if ([manager isIdentifierEnabled:@"SerialNumber"]) {
        NSString *spoofedSerial = [manager getValueForType:@"SerialNumber"];
        if (spoofedSerial) {
            PXLog(@"Spoofing GSSystemGetSerialNo with: %@", spoofedSerial);
            
            // Convert NSString to char* that will persist
            // Note: This will leak a small amount of memory but it's necessary
            // since we can't free the memory after returning it
            char *serialStr = strdup([spoofedSerial UTF8String]);
            return serialStr;
        }
    }
    
    return orig_GSSystemGetSerialNo();
}

// Constructor
%ctor {
    if(!IsScope()) return;
    
    PXLog(@"ProjectX tweak initializing...");


    // Detect iOS version
    NSOperatingSystemVersion osVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    PXLog(@"Detected iOS version: %ld.%ld.%ld", 
          (long)osVersion.majorVersion, 
          (long)osVersion.minorVersion, 
          (long)osVersion.patchVersion);
          
    // Special handling for iOS 16+
    if (osVersion.majorVersion >= 16) {
        PXLog(@"iOS 16+ detected, enabling compatibility mode");
    }
    

    
    // Initialize value cache
    valueCache = [NSMutableDictionary dictionary];
    
    // Load saved settings and ensure synchronization
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // Load security settings
    NSUserDefaults *securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
    [securitySettings synchronize]; // Force synchronization to get the latest settings
    
    
    
    // Hook IOKit for serial number spoofing
    void *IOKitHandle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (IOKitHandle) {
        void *IORegEntryCreateCFPropertyPtr = dlsym(IOKitHandle, "IORegistryEntryCreateCFProperty");
        if (IORegEntryCreateCFPropertyPtr) {
            PXLog(@"Hooking IORegistryEntryCreateCFProperty for serial number spoofing");
            MSHookFunction(IORegEntryCreateCFPropertyPtr, (void *)hook_IORegistryEntryCreateCFProperty, 
                            (void **)&orig_IORegistryEntryCreateCFProperty);
        }
        dlclose(IOKitHandle);
    }
    
    // Hook GSSystemGetSerialNo for serial number access through GS framework
    void *GSHandle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_NOW);
    if (GSHandle) {
        void *GSSystemGetSerialNoPtr = dlsym(GSHandle, "GSSystemGetSerialNo");
        if (GSSystemGetSerialNoPtr) {
            PXLog(@"Hooking GSSystemGetSerialNo for serial number spoofing");
            MSHookFunction(GSSystemGetSerialNoPtr, (void *)hook_GSSystemGetSerialNo, 
                            (void **)&orig_GSSystemGetSerialNo);
            
        }
        dlclose(GSHandle);
    }
    
    LocationSpoofingManager *manager = [LocationSpoofingManager sharedManager];
    if([manager isSpoofingEnabled]){
        // Initialize the location spoofing hooks
        %init(LocationSpoofing);
        
        // Initialize sensor data spoofing hooks
        %init(SensorSpoofing);
    }

    
    PXLog(@"[WeaponX] Location and sensor spoofing hooks initialized");
}
