#import "WebServerManager.h"
#import <GCDWebServers/GCDWebsocketServer.h>
#import <GCDWebServers/GCDWebServerDataResponse.h>
#import <GCDWebServers/GCDWebServerDataRequest.h>
#import <GCDWebServers/GCDWebServerErrorResponse.h>
#import "AppScopeManager.h"

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
    // 保存选中应用
    [webServer addHandlerForMethod:@"POST"
                              path:@"/saveScopePreferences"
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
                              path:@"/loadScopePreferences"
                      requestClass:[GCDWebServerRequest class] 
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        NSMutableSet *scopeSet = [[AppScopeManager sharedManager] loadPreferences];

        // NSString *res = runCommand(cmd);
        return dataResponse(@{
            @"status": @"success",
            @"data": [scopeSet allObjects]
        });
    }];
    
}
@end