//
//  MKNetworkRequest.m
//  MKNetworkKit
//
//  Created by Mugunth Kumar (@mugunthkumar) on 23/06/14.
//  Copyright (C) 2011-2020 by Steinlogic Consulting and Training Pte Ltd

//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "MKNetworkRequest.h"

#import "NSDictionary+MKNKRequestEncoding.h"

@import CoreImage;
@import ImageIO;

static NSInteger numberOfRunningOperations;

@interface MKNetworkRequest (/*Private Methods*/)

@property NSString *urlString;
@property NSData *bodyData;
@property NSString *httpMethod;

@property (readwrite) NSHTTPURLResponse *response;
@property (readwrite) NSData *responseData;
@property (readwrite) NSError *error;
@property (readwrite) NSURLSessionTask *task;
@property (readwrite) CGFloat progress;

@property NSMutableDictionary *parameters;
@property NSMutableDictionary *headers;

@property NSMutableArray *completionHandlers;
@property NSMutableArray *uploadProgressChangedHandlers;
@property NSMutableArray *downloadProgressChangedHandlers;
@end

@implementation MKNetworkRequest

#pragma mark -
#pragma mark Designated Initializer

- (instancetype)initWithURLString:(NSString *) aURLString
                           params:(NSDictionary*) params
                         bodyData:(NSData *) bodyData
                       httpMethod:(NSString *) httpMethod {
  
  if(self = [super init]) {
    
    self.urlString = aURLString;
    if(params) {
      self.parameters = params.mutableCopy;
    } else {
      self.parameters = [NSMutableDictionary dictionary];
    }
    
    self.bodyData = bodyData;
    self.httpMethod = httpMethod;
    
    self.headers = [NSMutableDictionary dictionary];
    
    self.completionHandlers = [NSMutableArray array];
    self.uploadProgressChangedHandlers = [NSMutableArray array];
    self.downloadProgressChangedHandlers = [NSMutableArray array];
  }
  
  return self;
}

#pragma mark -
#pragma mark Lazy request creator

-(NSMutableURLRequest*) request {
  
  NSURL *url = nil;
  if (([self.httpMethod.uppercaseString isEqual:@"GET"] ||
       [self.httpMethod.uppercaseString isEqual:@"DELETE"] ||
       [self.httpMethod.uppercaseString isEqual:@"HEAD"]) &&
      (self.parameters.count > 0)) {
    
    url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?%@", self.urlString,
                                [self.parameters urlEncodedKeyValueString]]];
  } else {
    url = [NSURL URLWithString:self.urlString];
  }
  
  if(url == nil) {
    
    NSLog(@"Unable to create request %@ %@ with parameters %@", self.httpMethod, self.urlString, self.parameters);
    return nil;
  }
  
  NSMutableURLRequest *createdRequest = [NSMutableURLRequest requestWithURL:url];
  [createdRequest setAllHTTPHeaderFields:self.headers];
  [createdRequest setHTTPMethod:self.httpMethod];
  
  NSString *bodyStringFromParameters = nil;
  NSString *charset = (__bridge NSString *)CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(self.parameterEncoding));
  
  switch (self.parameterEncoding) {
      
    case MKNKParameterEncodingURL: {
      [createdRequest setValue:
       [NSString stringWithFormat:@"application/x-www-form-urlencoded; charset=%@", charset]
            forHTTPHeaderField:@"Content-Type"];
      bodyStringFromParameters = [self.parameters urlEncodedKeyValueString];
    }
      break;
    case MKNKParameterEncodingJSON: {
      [createdRequest setValue:
       [NSString stringWithFormat:@"application/json; charset=%@", charset]
            forHTTPHeaderField:@"Content-Type"];
      bodyStringFromParameters = [self.parameters jsonEncodedKeyValueString];
    }
      break;
    case MKNKParameterEncodingPlist: {
      [createdRequest setValue:
       [NSString stringWithFormat:@"application/x-plist; charset=%@", charset]
            forHTTPHeaderField:@"Content-Type"];
      bodyStringFromParameters = [self.parameters plistEncodedKeyValueString];
    }
  }
  
  
  if (!([self.httpMethod.uppercaseString isEqual:@"GET"] ||
        [self.httpMethod.uppercaseString isEqual:@"DELETE"] ||
        [self.httpMethod.uppercaseString isEqual:@"HEAD"])) {
    
    [createdRequest setHTTPBody:[bodyStringFromParameters dataUsingEncoding:NSUTF8StringEncoding]];
  }
  
  if(self.bodyData) {
    [createdRequest setHTTPBody:self.bodyData];
  }
  
  return createdRequest;
}

#pragma mark -
#pragma mark Network response caching related helper methods

-(BOOL) cacheable {
  
  NSString *requestMethod = self.httpMethod.uppercaseString;
  if(![requestMethod isEqual:@"GET"]) return NO;
  
  if(self.doNotCache) return NO;
  
  if(self.username != nil || self.password != nil ||
     self.clientCertificate != nil || self.clientCertificatePassword != nil ||
     [self.request.URL.scheme.lowercaseString isEqual:@"https"]) {
    return self.alwaysCache;
  } else {
    return YES;
  }
}

-(NSString*) uniqueIdentifier {
  
  NSMutableString *str = [NSMutableString stringWithFormat:@"%@ %@", self.httpMethod.uppercaseString, self.request.URL.absoluteString];
  
  if(self.username || self.password) {
    
    [str appendFormat:@" [%@:%@]",
     self.username ? self.username : @"",
     self.password ? self.password : @""];
  }
  
  return str;
}

#pragma mark -
#pragma mark Methods to customize your network request after initialization

-(void) addCompletionHandler:(MKNKHandler) completionHandler {
  
  [self.completionHandlers addObject:completionHandler];
}

-(void) addUploadProgressChangedHandler:(MKNKHandler) uploadProgressChangedHandler {
  
  [self.uploadProgressChangedHandlers addObject:uploadProgressChangedHandler];
}

-(void) addDownloadProgressChangedHandler:(MKNKHandler) downloadProgressChangedHandler {
  
  [self.downloadProgressChangedHandlers addObject:downloadProgressChangedHandler];
}

-(void) addParameters:(NSDictionary*) paramsDictionary {
  
  [self.parameters addEntriesFromDictionary:paramsDictionary];
}

-(void) addHeaders:(NSDictionary*) headersDictionary {
  
  [self.headers addEntriesFromDictionary:headersDictionary];
}

-(void) setAuthorizationHeaderValue:(NSString*) token forAuthType:(NSString*) authType {
  
  self.headers[@"Authorization"] = [NSString stringWithFormat:@"%@ %@", authType, token];
}

#pragma mark -
#pragma mark Display Helpers

-(NSString*) description {
  
  NSMutableString *displayString = [NSMutableString stringWithFormat:@"%@\nRequest\n-------\n%@",
                                    [[NSDate date] descriptionWithLocale:[NSLocale currentLocale]],
                                    [self curlCommandLineString]];
  
  NSString *responseString = self.responseAsString;
  if([responseString length] > 0) {
    [displayString appendFormat:@"\n--------\nResponse\n--------\n%@\n", responseString];
  }
  
  return displayString;
}

-(NSString*) curlCommandLineString
{
  NSMutableURLRequest *request = self.request;
  
  __block NSMutableString *displayString = [NSMutableString stringWithFormat:@"curl -X %@", request.HTTPMethod];
  
  // FIX ME
  //  if([self.filesToBePosted count] == 0 && [self.dataToBePosted count] == 0) {
  //    [[self.request allHTTPHeaderFields] enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *stop)
  //     {
  //       [displayString appendFormat:@" -H \'%@: %@\'", key, val];
  //     }];
  //  }
  
  [displayString appendFormat:@" \'%@\'",  request.URL.absoluteString];
  
  if ([request.HTTPMethod isEqualToString:@"POST"] ||
      [request.HTTPMethod isEqualToString:@"PUT"] ||
      [request.HTTPMethod isEqualToString:@"PATCH"]) {
    
    NSString *option = self.parameters.count == 0 ? @"-d" : @"-F";
    if(self.parameterEncoding == MKNKParameterEncodingURL) {
      [self.parameters enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        
        [displayString appendFormat:@" %@ \'%@=%@\'", option, key, obj];
      }];
    } else {
      [displayString appendFormat:@" -d \'%@\'",
       [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding]];
    }
    
    // FIX ME
    //
    //    [self.filesToBePosted enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    //
    //      NSDictionary *thisFile = (NSDictionary*) obj;
    //      [displayString appendFormat:@" -F \'%@=@%@;type=%@\'", thisFile[@"name"],
    //       thisFile[@"filepath"], thisFile[@"mimetype"]];
    //    }];
    
    /* Not sure how to do this via curl
     [self.dataToBePosted enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
     
     NSDictionary *thisData = (NSDictionary*) obj;
     [displayString appendFormat:@" --data-binary \"%@\"", [thisData objectForKey:@"data"]];
     }];*/
  }
  
  return displayString;
}

#pragma mark -
#pragma mark Completion triggers

-(void) incrementRunningOperations {
  
#ifdef TARGET_OS_IPHONE
  dispatch_async(dispatch_get_main_queue(), ^{
    
    numberOfRunningOperations ++;
    if(numberOfRunningOperations > 0)
      [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
  });
#endif
}

-(void) decrementRunningOperations {
  
#ifdef TARGET_OS_IPHONE
  dispatch_async(dispatch_get_main_queue(), ^{
    
    numberOfRunningOperations --;
    if(numberOfRunningOperations == 0)
      [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    if(numberOfRunningOperations < 0) {
      NSLog(@"Number of operations is below zero. Something wrong at %@ [%d]", self, self.state); // FIX ME
    }
    
  });
#endif
}

-(BOOL) isCachedResponse {
  
  return self.state == MKNKRequestStateResponseAvailableFromCache;
}

-(void) cancel {
  
  if(self.state == MKNKRequestStateStarted) {
    [self.task cancel];
    self.state = MKNKRequestStateCancelled;
  }
}

-(void) setState:(MKNKRequestState)state {
  
  _state = state;
  switch (state) {
    case MKNKRequestStateStarted: {
      
      [self.task resume];
      [self incrementRunningOperations];
    }
      break;
      
    case MKNKRequestStateCompleted:
    case MKNKRequestStateCancelled:
    case MKNKRequestStateError:
      [self decrementRunningOperations];
      
    case MKNKRequestStateResponseAvailableFromCache: {
      
      [self.completionHandlers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        
        MKNKHandler handler = obj;
        handler(self);
      }];
    }
      
      break;
  }  
}

#pragma mark -
#pragma mark Response formatting helpers

#if TARGET_OS_IPHONE
-(UIImage*) responseAsImage {
  
  static CGFloat scale = 2.0f;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    scale = [UIScreen mainScreen].scale;
  });
  return [UIImage imageWithData:self.responseData scale:scale];
}

-(UIImage*) decompressedResponseImageOfSize:(CGSize) size {

  CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)(self.responseData), NULL);
  CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, 0, (__bridge CFDictionaryRef)(@{(id)kCGImageSourceShouldCache:@(YES)}));
  UIImage *decompressedImage = [UIImage imageWithCGImage:cgImage];
  if(source)
    CFRelease(source);
  if(cgImage)
    CGImageRelease(cgImage);

  return decompressedImage;
}

#elif TARGET_OS_MAC
-(NSImage*) responseAsImage {
  
  return [[NSImage alloc] initWithData:self.data];
}

-(NSXMLDocument*) responseXML {
  
  return [[NSXMLDocument alloc] initWithData:self.data options:0 error:nil];
}
#endif

-(id) responseAsJSON {
  
  if(self.responseData == nil) return nil;
  NSError *error = nil;
  id returnValue = [NSJSONSerialization JSONObjectWithData:self.responseData options:0 error:&error];
  if(!returnValue) NSLog(@"JSON Parsing Error: %@", error);
  return returnValue;
}

-(NSString*) responseAsString {
  
  return [[NSString alloc] initWithData:self.responseData encoding:NSUTF8StringEncoding];
}

-(void) setProgressValue:(CGFloat) updatedValue {
  
  self.progress = updatedValue;

  [self.downloadProgressChangedHandlers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    
    MKNKHandler handler = obj;
    handler(self);
  }];
}

@end
