/******************************************************************************
 *
 * Copyright (C) 2013 T Dispatch Ltd
 *
 * Licensed under the GPL License, Version 3.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.gnu.org/licenses/gpl-3.0.html
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 ******************************************************************************
 *
 * @author Marcin Orlowski <marcin.orlowski@webnet.pl>
 *
 ****/

#import <CoreLocation/CoreLocation.h>

#import "NetworkEngine.h"
#import "MKNetworkKit.h"
#import "UserSettings.h"
#import "CreditCard.h"

#define PASSENGER_SERVER_URL @"api.tdispatch.com"
#error "add your api key/secret/id here"
#define FLEET_API_KEY @"YOUR API KEY"
#define PASSENGER_CLIENT_ID @"YOUR CLIENT ID@tdispatch.com"
#define PASSENGER_CLIENT_SECRET @"YOUR SECRET"

#define PASSENGER_AUTH_URL @"http://api.tdispatch.com/passenger/oauth2/auth"
#define PASSENGER_TOKEN_URL @"http://api.tdispatch.com/passenger/oauth2/token"

#define USE_SSL NO

// API
#define PASSENGER_API_PATH @"passenger/v1"

@interface NetworkEngine()
{
    NSString *_accessToken;
    NSDateFormatter* _dateFormatter;
}

@end

@implementation NetworkEngine

+ (NetworkEngine *)getInstance
{
	static NetworkEngine *ineInstance;
	
	@synchronized(self)
	{
		if (!ineInstance)
		{
			ineInstance = [[NetworkEngine alloc] initWithHostName:PASSENGER_SERVER_URL
                                                          apiPath:PASSENGER_API_PATH
                                               customHeaderFields:@{@"Accept-Encoding" : @"gzip"}
                           ];
		}
		return ineInstance;
	}
}

- (id)initWithHostName:(NSString *)hostName apiPath:(NSString *)apiPath customHeaderFields:(NSDictionary *)headers {
    self = [super initWithHostName:hostName apiPath:apiPath customHeaderFields:headers];
    if (self) {
        _dateFormatter = [[NSDateFormatter alloc] init];
        [_dateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ssZZZZZ"];
        //    dateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        _dateFormatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
        NSLocale* locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        [_dateFormatter setLocale:locale];
    }
    return self;
}

- (NSString *)formatDate:(NSDate *)date {
    NSString* str = [_dateFormatter stringFromDate:date];
    return [str stringByReplacingOccurrencesOfString:@"GMT" withString:@""];;
}

- (NSString*)redirectUrl
{
    return @"http://127.0.0.1";
}

- (NSString*)authUrl
{
    NSString* url = [NSString stringWithFormat:@"%@?response_type=code&client_id=%@&redirect_uri=%@&scope=&key=%@", PASSENGER_AUTH_URL, PASSENGER_CLIENT_ID, [self redirectUrl], FLEET_API_KEY];
    return [url stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
}


- (void)getRefreshToken:(NSString*)authorizationCode
        completionBlock:(NetworkEngineCompletionBlock)completionBlock
           failureBlock:(NetworkEngineFailureBlock)failureBlock
{
    MKNetworkOperation *op = [self operationWithURLString:PASSENGER_TOKEN_URL
                                                   params:@{@"code":authorizationCode,
                                                            @"client_id":PASSENGER_CLIENT_ID,
                                                            @"client_secret":PASSENGER_CLIENT_SECRET,
                                                            @"redirect_url":@"",
                                                            @"grant_type":@"authorization_code"}
                                               httpMethod:@"POST"];
    
    [op setPostDataEncoding:MKNKPostDataEncodingTypeJSON];
    
    [op addCompletionHandler:^(MKNetworkOperation *operation) {
        NSDictionary* response = operation.responseJSON;

        _accessToken = response[@"access_token"];
        [UserSettings setRefreshToken:response[@"refresh_token"]];
        completionBlock(nil);
        
    } errorHandler:^(MKNetworkOperation *errorOp, NSError* error) {
        failureBlock([NSError errorFromAPIResponse:errorOp.responseJSON andError:error]);
    }];
    
    [self enqueueOperation:op];
}

- (void)getAccessTokenForRefreshToken:(NSString*)token
                      completionBlock:(NetworkEngineCompletionBlock)completionBlock
                         failureBlock:(NetworkEngineFailureBlock)failureBlock
{
    MKNetworkOperation *op = [self operationWithURLString:PASSENGER_TOKEN_URL
                                                   params:@{@"refresh_token":token,
                                                            @"client_id":PASSENGER_CLIENT_ID,
                                                            @"client_secret":PASSENGER_CLIENT_SECRET,
                                                            @"redirect_url":@"",
                                                            @"grant_type":@"refresh_token"}
                                               httpMethod:@"POST"];
    
    [op setPostDataEncoding:MKNKPostDataEncodingTypeJSON];
    
    [op addCompletionHandler:^(MKNetworkOperation *operation) {
        NSDictionary* response = operation.responseJSON;
        _accessToken = response[@"access_token"];
        completionBlock(nil);
    } errorHandler:^(MKNetworkOperation *errorOp, NSError* error) {
        failureBlock([NSError errorFromAPIResponse:errorOp.responseJSON andError:error]);
    }];
    
    [self enqueueOperation:op];
}

- (void)createAccount:(NSString *)firstName
             lastName:(NSString *)lastName
                email:(NSString *)email
                phone:(NSString *)phone
             password:(NSString *)password
      completionBlock:(NetworkEngineCompletionBlock)completionBlock
         failureBlock:(NetworkEngineFailureBlock)failureBlock
{
    NSMutableDictionary* params = [[NSMutableDictionary alloc] initWithDictionary:@{
                                        @"first_name": firstName,
                                        @"last_name" : lastName,
                                        @"email" : email,
                                        @"phone" : phone,
                                        @"password" : password,
                                        @"client_id" : PASSENGER_CLIENT_ID
                                   }];
    
    MKNetworkOperation *op = [self operationWithPath:[NSString stringWithFormat:@"accounts?key=%@", FLEET_API_KEY]
                                              params:params
                                          httpMethod:@"POST"
                                                 ssl:USE_SSL];
    
    [op setPostDataEncoding:MKNKPostDataEncodingTypeJSON];
    
    [op addCompletionHandler:^(MKNetworkOperation *operation) {
        NSDictionary* response = operation.responseJSON;
        _accessToken = response[@"passenger"][@"access_token"];
        completionBlock(nil);
    } errorHandler:^(MKNetworkOperation *errorOp, NSError* error) {
        failureBlock([NSError errorFromAPIResponse:errorOp.responseJSON andError:error]);
    }];
    
    [self enqueueOperation:op];
    
}

- (void)getTravelFare:(CLLocationCoordinate2D)start
                   to:(CLLocationCoordinate2D)to
             usingCar:(NSString *)carType
       withPickupTime:(NSDate *)pickupTime
      completionBlock:(NetworkEngineCompletionBlock)completionBlock
         failureBlock:(NetworkEngineFailureBlock)failureBlock
{
    
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    
    params[@"pickup_location"] = @{
              @"lat" : [NSNumber numberWithDouble:start.latitude],
              @"lng" : [NSNumber numberWithDouble:start.longitude]
              };
    params[@"dropoff_location"] =  @{
              @"lat" : [NSNumber numberWithDouble:to.latitude],
              @"lng" : [NSNumber numberWithDouble:to.longitude]
              };

    params[@"pickup_time"] = [self formatDate:pickupTime];
    
    if (carType)
    {
        params[@"car_type"] = carType;
    }
    
    MKNetworkOperation *op = [self operationWithPath:[NSString stringWithFormat:@"%@?access_token=%@", @"locations/fare", _accessToken]
                                              params:params                                          httpMethod:@"POST"
                                                 ssl:USE_SSL];
    
    [op setPostDataEncoding:MKNKPostDataEncodingTypeJSON];
    
    [op addCompletionHandler:^(MKNetworkOperation *operation) {
        NSDictionary* response = operation.responseJSON;
        completionBlock(response);
    } errorHandler:^(MKNetworkOperation *errorOp, NSError* error) {
        failureBlock([NSError errorFromAPIResponse:errorOp.responseJSON andError:error]);
    }];
    
    [self enqueueOperation:op];

}

- (void)getLatestBookings:(NetworkEngineCompletionBlock)completionBlock
             failureBlock:(NetworkEngineFailureBlock)failureBlock
{
    MKNetworkOperation *op = [self operationWithPath:[NSString stringWithFormat:@"%@?order_by=-pickup_time&limit=20&status=incoming,completed,confirmed,active,dispatched&access_token=%@", @"/bookings", _accessToken]
                                              params:nil
                                          httpMethod:@"GET"
                                                 ssl:USE_SSL];
    
    [op addCompletionHandler:^(MKNetworkOperation *operation) {
        NSDictionary* response = operation.responseJSON;
        completionBlock(response[@"bookings"]);
    } errorHandler:^(MKNetworkOperation *errorOp, NSError* error) {
        failureBlock([NSError errorFromAPIResponse:errorOp.responseJSON andError:error]);
    }];
    
    [self enqueueOperation:op];
}

- (void)getAccountPreferences:(NetworkEngineCompletionBlock)completionBlock
                 failureBlock:(NetworkEngineFailureBlock)failureBlock
{

    MKNetworkOperation *op = [self operationWithPath:[NSString stringWithFormat:@"%@?access_token=%@", @"/accounts/preferences", _accessToken]
                                              params:nil
                                          httpMethod:@"GET"
                                                 ssl:USE_SSL];
    
    [op addCompletionHandler:^(MKNetworkOperation *operation) {
        NSDictionary* response = operation.responseJSON;
        self.accountPreferences = response[@"preferences"];
        completionBlock(_accountPreferences);
    } errorHandler:^(MKNetworkOperation *errorOp, NSError* error) {
        failureBlock([NSError errorFromAPIResponse:errorOp.responseJSON andError:error]);
    }];
    
    [self enqueueOperation:op];
}

- (void)getFleetData:(NetworkEngineCompletionBlock)completionBlock
        failureBlock:(NetworkEngineFailureBlock)failureBlock
{
    MKNetworkOperation *op = [self operationWithPath:[NSString stringWithFormat:@"%@?access_token=%@", @"accounts/fleetdata", _accessToken]
                                              params:nil
                                          httpMethod:@"GET"
                                                 ssl:USE_SSL];
    
    [op addCompletionHandler:^(MKNetworkOperation *operation) {
        NSDictionary* response = operation.responseJSON;
        completionBlock(response[@"data"]);
    } errorHandler:^(MKNetworkOperation *errorOp, NSError* error) {
        failureBlock([NSError errorFromAPIResponse:errorOp.responseJSON andError:error]);
    }];
    
    [self enqueueOperation:op];
}

- (void)searchForLocation:(NSString *)location
                     type:(LocationType)type
                    limit:(NSInteger)limit
          completionBlock:(NetworkEngineCompletionBlock)completionBlock
             failureBlock:(NetworkEngineFailureBlock)failureBlock
{
    NSMutableString* path = [[NSMutableString alloc] init];
    
    location = [location stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    [path appendFormat:@"%@?q=%@&limit=%d&access_token=%@", @"/locations/search", location, limit, _accessToken];
    
    if (type == LocationTypePickup)
    {
        [path appendString:@"&type=pickup"];
    }
    
    MKNetworkOperation *op = [self operationWithPath:path
                                              params:nil
                                          httpMethod:@"GET"
                                                 ssl:USE_SSL];
    
    [op addCompletionHandler:^(MKNetworkOperation *operation) {
        NSDictionary* response = operation.responseJSON;
        completionBlock(response[@"locations"]);
    } errorHandler:^(MKNetworkOperation *errorOp, NSError* error) {
        failureBlock([NSError errorFromAPIResponse:errorOp.responseJSON andError:error]);
    }];
    
    [self enqueueOperation:op];
}

- (void)getDirectionsFrom:(CLLocationCoordinate2D)start
                       to:(CLLocationCoordinate2D)to
          completionBlock:(NetworkEngineCompletionBlock)completionBlock
             failureBlock:(NetworkEngineFailureBlock)failureBlock
{
    NSMutableString* urlString = [[NSMutableString alloc] init];
    [urlString appendString:@"http://maps.googleapis.com/maps/api/directions/json"];
    [urlString appendFormat:@"?origin=%f,%f", start.latitude, start.longitude];
    [urlString appendFormat:@"&destination=%f,%f", to.latitude, to.longitude];
    [urlString appendString:@"&sensor=false&units=metric&mode=driving"];

    MKNetworkOperation *op = [self operationWithURLString:urlString
                                                   params:nil
                                               httpMethod:@"GET"];
    
    [op addCompletionHandler:^(MKNetworkOperation *operation) {
        NSDictionary* response = operation.responseJSON;
        
        NSMutableArray* pointsToDraw = nil;

        NSArray* routes = response[@"routes"];
        if (routes && routes.count)
        {
            NSString* points = routes[0][@"overview_polyline"][@"points"];
            pointsToDraw = [[NSMutableArray alloc] init];
        
            int len = points.length;
            int index = 0;
            int lat = 0;
            int lng = 0;
            
            while( index < len ) {
                int b;
                int shift = 0;
                int result = 0;
                do {
                    b = [points characterAtIndex:index] - 63;
                    index++;
                    result |= (b & 0x1f) << shift;
                    shift += 5;
                } while( b >= 0x20 );
                int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
                lat += dlat;
                
                shift = 0;
                result = 0;
                do {
                    b = [points characterAtIndex:index] - 63;
                    index++;
                    result |= (b & 0x1f) << shift;
                    shift += 5;
                } while( b >= 0x20 );
                int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
                lng += dlng;
                
                CLLocation* location = [[CLLocation alloc] initWithLatitude:lat / 1E5 longitude:lng / 1E5];
                [pointsToDraw addObject:location];
            }
        }
        
        completionBlock(pointsToDraw);
        
    } errorHandler:^(MKNetworkOperation *errorOp, NSError* error) {
        failureBlock(error);
    }];
    
    [self enqueueOperation:op];

}

- (void)cancelReverseForLocationOperations
{
    [MKNetworkEngine cancelOperationsContainingURLString:@"http://maps.googleapis.com/maps/api/geocode/"];
}

- (void)getReverseForLocation:(CLLocationCoordinate2D)location
              completionBlock:(NetworkEngineCompletionBlock)completionBlock
                 failureBlock:(NetworkEngineFailureBlock)failureBlock
{
    NSMutableString* urlString = [[NSMutableString alloc] init];
    [urlString appendString:@"http://maps.googleapis.com/maps/api/geocode/json?latlng="];
    [urlString appendFormat:@"%f,%f", location.latitude, location.longitude];
    [urlString appendFormat:@"&sensor=true"];
    
    MKNetworkOperation *op = [self operationWithURLString:urlString
                                                   params:nil
                                               httpMethod:@"GET"];
    
    [op addCompletionHandler:^(MKNetworkOperation *operation) {
        NSDictionary* response = operation.responseJSON;
        
        NSString *status = response[@"status"];
        if ([status isEqualToString:@"OK"])
        {
            completionBlock(response[@"results"]);
        }
        else
        {
            failureBlock([NSError errorWithDescription:[NSString stringWithFormat:@"status: %@", status]]);
        }
    } errorHandler:^(MKNetworkOperation *errorOp, NSError* error) {
        failureBlock(error);
    }];
    
    [self enqueueOperation:op];
}

- (void)setValueOrEmptyString:(NSString *)value forKey:(NSString *)key inDictionary:(NSMutableDictionary *)passenger
{
    if (IS_NULL(value))
    {
        passenger[key] = @"";
    }
    else
    {
        passenger[key] = value;
    }
}

- (void)createBooking:(NSString *)pickupName
        pickupZipCode:(NSString *)pickupZipCode
       pickupLocation:(CLLocationCoordinate2D)pickupLocation
          dropoffName:(NSString *)dropoffName
       dropoffZipCode:(NSString *)dropoffZipCode
      dropoffLocation:(CLLocationCoordinate2D)dropoffLocation
           pickupDate:(NSDate *)pickupDate
              carType:(NSString *)carType
                 card:(CreditCard *)card
      completionBlock:(NetworkEngineCompletionBlock)completionBlock
         failureBlock:(NetworkEngineFailureBlock)failureBlock

{
    NSMutableDictionary* params = [[NSMutableDictionary alloc] initWithDictionary:@{
                                                                                  @"pickup_location": @{
                                   @"postcode" : pickupZipCode ? pickupZipCode : @"",
                                   @"address" : pickupName ? pickupName : @"",
                                                                                          @"location" : @{
                                                                                                  @"lat" : [NSNumber numberWithFloat:pickupLocation.latitude],
                                                                                                  @"lng" : [NSNumber numberWithFloat:pickupLocation.longitude]
                                                                                                  }
                                                                                          }
                                  }];
    
    if (dropoffName)
    {
        [params addEntriesFromDictionary:@{
                                            @"dropoff_location": @{
         @"postcode" : dropoffZipCode ? dropoffZipCode : @"",
                                                @"address" : dropoffName,
                                                @"location" : @{
                                                    @"lat" : [NSNumber numberWithFloat:dropoffLocation.latitude],
                                                    @"lng" : [NSNumber numberWithFloat:dropoffLocation.longitude]
                                                }
                                            }
                                        }];
    }
    
    if (pickupDate) {
        params[@"pickup_time"] = [self formatDate:pickupDate];
    }
    
    NSMutableDictionary *passenger = [[NSMutableDictionary alloc] initWithCapacity:3];
    NSString* firstName = _accountPreferences[@"first_name"];
    NSString* lastName = _accountPreferences[@"last_name"];
    
    NSMutableString* fullName = [[NSMutableString alloc] initWithCapacity:64];
    if (!IS_NULL(firstName))
    {
        [fullName appendString:firstName];
    }
    
    if (!IS_NULL(lastName))
    {
        if (fullName.length)
        {
            [fullName appendString:@" "];
        }
        [fullName appendString:lastName];
    }
    
    NSString* phone = _accountPreferences[@"phone"];
    NSString* email = _accountPreferences[@"email"];
    [self setValueOrEmptyString:fullName forKey:@"name" inDictionary:passenger];
    [self setValueOrEmptyString:phone forKey:@"phone" inDictionary:passenger];
    [self setValueOrEmptyString:email forKey:@"email" inDictionary:passenger];
    params[@"passenger"] = passenger;
    
    
    if (card) {
        params[@"status"] = @"draft";
        params[@"pre_paid"] = @YES;
        params[@"payment_method"] = @"credit-card";
    } else {
        params[@"status"] = @"incoming";
    }
    
    if (carType) {
        params[@"vehicle_type"] = carType;
    }
    
    MKNetworkOperation *op = [self operationWithPath:[NSString stringWithFormat:@"%@?access_token=%@", @"bookings", _accessToken]
                                              params:params
                                          httpMethod:@"POST"
                                                 ssl:USE_SSL];
    
    [op setPostDataEncoding:MKNKPostDataEncodingTypeJSON];
    
    [op addCompletionHandler:^(MKNetworkOperation *operation) {
        NSDictionary* response = operation.responseJSON;
        completionBlock(response[@"booking"]);
    } errorHandler:^(MKNetworkOperation *errorOp, NSError* error) {
        failureBlock([NSError errorFromAPIResponse:errorOp.responseJSON andError:error]);
    }];
    
    [self enqueueOperation:op];

}

- (void)cancelBooking:(NSString *)pk
   cancellationReason:(NSString *)reason
      completionBlock:(NetworkEngineCompletionBlock)completionBlock
         failureBlock:(NetworkEngineFailureBlock)failureBlock
{
    NSDictionary *params = nil;
    
    if (reason.length) {
        params =  @{@"description" : reason};
    }

    MKNetworkOperation *op = [self operationWithPath:[NSString stringWithFormat:@"bookings/%@/cancel?access_token=%@", pk, _accessToken]
                                              params:params
                                          httpMethod:@"POST"
                                                 ssl:USE_SSL];
    
    [op setPostDataEncoding:MKNKPostDataEncodingTypeJSON];
    
    [op addCompletionHandler:^(MKNetworkOperation *operation) {
        completionBlock(nil);
    } errorHandler:^(MKNetworkOperation *errorOp, NSError* error) {
        failureBlock([NSError errorFromAPIResponse:errorOp.responseJSON andError:error]);
    }];
    
    [self enqueueOperation:op];

}

- (void)updateBooking:(NSString *)pk
        transactionId:(NSString *)transactionId
           amountPaid:(NSNumber *)amount
      completionBlock:(NetworkEngineCompletionBlock)completionBlock
         failureBlock:(NetworkEngineFailureBlock)failureBlock
{
    MKNetworkOperation *op = [self operationWithPath:[NSString stringWithFormat:@"bookings/%@?access_token=%@", pk, _accessToken]
                                              params:@{
                                                       @"status" : @"incoming",
                                                       @"is_paid" : @YES,
                                                       @"payment_ref" : transactionId,
                                                       @"payment_method" : @"credit-card",
                                                       @"paid_value" : amount
                                                       }
                                          httpMethod:@"POST"
                                                 ssl:USE_SSL];
    
    [op setPostDataEncoding:MKNKPostDataEncodingTypeJSON];
    
    [op addCompletionHandler:^(MKNetworkOperation *operation) {
        NSDictionary* response = operation.responseJSON;
        completionBlock(response[@"booking"]);
    } errorHandler:^(MKNetworkOperation *errorOp, NSError* error) {
        failureBlock([NSError errorFromAPIResponse:errorOp.responseJSON andError:error]);
    }];
    
    [self enqueueOperation:op];
    
}

- (void)getNearbyCabs:(CLLocationCoordinate2D )location
      completionBlock:(NetworkEngineCompletionBlock)completionBlock
         failureBlock:(NetworkEngineFailureBlock)failureBlock
{
    NSMutableDictionary* params = [[NSMutableDictionary alloc] initWithDictionary:@{
                                    @"limit" : @15,
                                    @"radius" : @10,
                                    @"offset" : @0,
                                    @"location" : @{
                                        @"lng" : [NSNumber numberWithDouble:location.longitude],
                                        @"lat" : [NSNumber numberWithDouble:location.latitude]
                                    }
                                   }];

    MKNetworkOperation *op = [self operationWithPath:[NSString stringWithFormat:@"%@?access_token=%@", @"drivers/nearby", _accessToken]
                                              params:params
                                          httpMethod:@"POST"
                                                 ssl:USE_SSL];
    
    [op setPostDataEncoding:MKNKPostDataEncodingTypeJSON];
    
    [op addCompletionHandler:^(MKNetworkOperation *operation) {
        completionBlock(operation.responseJSON[@"drivers"]);
    } errorHandler:^(MKNetworkOperation *errorOp, NSError* error) {
        failureBlock([NSError errorFromAPIResponse:errorOp.responseJSON andError:error]);
    }];
    
    [self enqueueOperation:op];    
}

- (void)getVehicles:(NetworkEngineCompletionBlock)completionBlock
       failureBlock:(NetworkEngineFailureBlock)failureBlock
{
    MKNetworkOperation *op = [self operationWithPath:[NSString stringWithFormat:@"%@?access_token=%@", @"vehicletypes", _accessToken]
                                              params:nil
                                          httpMethod:@"GET"
                                                 ssl:USE_SSL];
    
    [op addCompletionHandler:^(MKNetworkOperation *operation) {
        completionBlock(operation.responseJSON[@"vehicle_types"]);
    } errorHandler:^(MKNetworkOperation *errorOp, NSError* error) {
        failureBlock([NSError errorFromAPIResponse:errorOp.responseJSON andError:error]);
    }];
    
    [self enqueueOperation:op];    
    
}

@end
