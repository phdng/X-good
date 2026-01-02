#import "WebServerManager.h"
#import <GCDWebServers/GCDWebsocketServer.h>
#import <GCDWebServers/GCDWebServerDataResponse.h>
#import <GCDWebServers/GCDWebServerDataRequest.h>
#import <GCDWebServers/GCDWebServerErrorResponse.h>
#import "AppScopeManager.h"
#import "PhoneInfo.h"
#import "DaemonApi.h"
#import "DataGenManager.h"
#import "ActionManager.h"
#import "ProfileManager.h"

NSDictionary* getJsonBody(GCDWebServerDataRequest *request,NSError *jsonError)
{
    return [NSJSONSerialization JSONObjectWithData:request.data
                                                        options:kNilOptions
                                                            error:&jsonError];
}
NSMutableSet * getSet(GCDWebServerDataRequest *request, NSError *error) 
{
    id jsonObject = [NSJSONSerialization JSONObjectWithData:request.data 
                                                    options:kNilOptions 
                                                      error:&error];
    if (error) return nil;
    
    if ([jsonObject isKindOfClass:[NSArray class]]) {
        return [NSMutableSet setWithArray:(NSArray *)jsonObject];
    } 
    
    return nil;
}

GCDWebServerDataResponse* dataResponse(NSDictionary *jsonData)
{
    GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:jsonData];
    [response setValue:@"*" forAdditionalHeader:@"Access-Control-Allow-Origin"];       
    [response setValue:@"Content-Type" forAdditionalHeader:@"Access-Control-Allow-Headers"];   
    return response;
}
GCDWebServerDataResponse* staticSuccessResponse()
{
    NSDictionary *jsonData = @{
        @"status": @"success"
    };                      
    return dataResponse(jsonData);
}
GCDWebServerErrorResponse* missingParamResponse()
{
    GCDWebServerErrorResponse *response = [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest
                                                        message:@"Missing parameter"];
    [response setValue:@"*" forAdditionalHeader:@"Access-Control-Allow-Origin"];       
    [response setValue:@"Content-Type" forAdditionalHeader:@"Access-Control-Allow-Headers"];
    return response;                                   
}
GCDWebServerErrorResponse* jsonFormatErrorResponse()
{
    GCDWebServerErrorResponse* response = [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest
                                                            message:@"Invalid JSON"];
    [response setValue:@"*" forAdditionalHeader:@"Access-Control-Allow-Origin"];       
    [response setValue:@"Content-Type" forAdditionalHeader:@"Access-Control-Allow-Headers"];
    return response;   
}
@implementation WebServerManager

+(void) startWebServer{
    static GCDWebServer *webServer = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        webServer = [[GCDWebServer alloc] init];
        [WebServerManager initHandle:webServer];
        [webServer startWithPort:8888 bonjourName:nil];
    });
}
+(void) initHandle:(GCDWebsocketServer *)webServer
{
    [webServer addHandlerForMethod:@"GET"
                              path:NEW_PHONE
                      requestClass:[GCDWebServerDataRequest class] // 必须是 DataRequest 才能读取 Body
                      processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request) {

        [[ActionManager sharedManager] newPhone];
        NSMutableSet *scopeSet = [[AppScopeManager sharedManager] loadPreferences];
        return dataResponse(@{
            @"status": @"success",
            @"data": [scopeSet allObjects]
        });
    }];

    // 保存选中应用
    [webServer addHandlerForMethod:@"POST"
                              path:SAVE_SCOPE_APPS
                      requestClass:[GCDWebServerDataRequest class] // 必须是 DataRequest 才能读取 Body
                      processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request) {

        NSError *error;
        NSMutableSet *scopeSet = getSet(request,error);
        if (error && scopeSet) {
            return jsonFormatErrorResponse();
        }
        [[AppScopeManager sharedManager] savePreferences:scopeSet];
        return staticSuccessResponse();
    }];

    [webServer addHandlerForMethod:@"GET"
                              path:GET_SCOPE_APPS
                      requestClass:[GCDWebServerRequest class] 
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        NSMutableSet *scopeSet = [[AppScopeManager sharedManager] loadPreferences];

        return dataResponse(@{
            @"status": @"success",
            @"data": [scopeSet allObjects]
        });
    }];

    [webServer addHandlerForMethod:@"GET"
                              path:GET_PHONE_INFO
                      requestClass:[GCDWebServerRequest class] 
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        PhoneInfo * phoneInfo = [PhoneInfo loadFromPrefs];
        return dataResponse([phoneInfo toDictionary]);
    }];

    [webServer addHandlerForMethod:@"POST"
                              path:SAVE_PHONE_INFO
                   requestClass:[GCDWebServerDataRequest class] 
                      processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request){

        NSError *error;
        NSDictionary *dict = getJsonBody(request,error);
        if (error && dict) {
            return jsonFormatErrorResponse();
        }
       
        BOOL success = [PhoneInfo saveDictionary:dict];
        if(success){
            return staticSuccessResponse();
        }else{
            return dataResponse(@{
                @"status": @"error"
            });
        }
    }];

    [webServer addHandlerForMethod:@"POST"
                              path:REMOVE_BACKUP
                        requestClass:[GCDWebServerDataRequest class] 
                        processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request){
                NSError *error;
        NSDictionary *dict = getJsonBody(request,error);
        if (error && dict) {
            return jsonFormatErrorResponse();
        }
        [[ActionManager sharedManager] removeBackup:dict[@"id"]];
        return staticSuccessResponse();
    }];
    [webServer addHandlerForMethod:@"POST"
                              path:RENAME_BACKUP
                        requestClass:[GCDWebServerDataRequest class] 
                        processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request){
        NSError *error;
        NSDictionary *dict = getJsonBody(request,error);
        if (error && dict) {
            return jsonFormatErrorResponse();
        }
        [[ProfileManager sharedManager] renameProfile:dict[@"id"] to:dict[@"name"]];
        return staticSuccessResponse();
    }];

    [webServer addHandlerForMethod:@"POST"
                              path:SWITCH_BACKUP
                        requestClass:[GCDWebServerDataRequest class] 
                        processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request){
        NSError *error;
        NSDictionary *dict = getJsonBody(request,error);
        if (error && dict) {
            return jsonFormatErrorResponse();
        }
        [[ActionManager sharedManager] switchBackup:dict[@"id"]];
        return staticSuccessResponse();
    }];
}
+(void) load{
    // 检查默认PhoneInf是否存在
    PhoneInfo * phoneInfo = [PhoneInfo loadFromPrefs];
    if(!phoneInfo){
        phoneInfo = [[DataGenManager sharedManager] generatePhoneInfo];
        [phoneInfo saveToPrefs];
    }
}
@end