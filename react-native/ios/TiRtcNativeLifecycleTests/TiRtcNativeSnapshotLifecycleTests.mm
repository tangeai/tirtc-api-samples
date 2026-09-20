#import <XCTest/XCTest.h>

#import <TiRTC/TiRTC-Swift.h>
#import <UIKit/UIKit.h>

#import "../../../ios/TiRtcReactNative.h"
#import "../../../ios/TiRtcReactNativeErrors.h"
#import "../../../ios/TiRtcReactNativeRegistry.h"

static NSString* const TiRtcNativeSnapshotMarker =
    @"rn-native-snapshot-lifecycle-rtc-cloud-no-frame-late-success-invalidate-reinit-v1";
static NSString* const TiRtcNativeSnapshotFileMarker =
    @"rn-native-snapshot-file-registration-late-delete-reinit-v1";
static NSString* const TiRtcNativeCloudConcurrentDisposeMarker =
    @"rn-native-cloud-concurrent-double-dispose";
static NSString* const TiRtcNativeCloudUpdateDisposeMarker =
    @"rn-native-cloud-update-token-dispose-race";
static NSString* const TiRtcNativeCloudReplayDisposeMarker =
    @"rn-native-cloud-replay-control-dispose-race";
static NSString* const TiRtcNativeCloudLazyStoreDisposeMarker =
    @"rn-native-cloud-lazy-store-update-dispose-race";
static NSString* const TiRtcNativeCloudLazyReplayDisposeMarker =
    @"rn-native-cloud-lazy-replay-control-dispose-race";
static NSString* const TiRtcNativeCloudConcurrencyCleanupMarker =
    @"rn-native-cloud-concurrency-final-release-shutdown";

@interface TiRtcReactNative (TiRtcNativeSnapshotLifecycleTestSurface)
- (NSDictionary*)createVideoOutput;
- (void)videoOutputTakeSnapshot:(double)objectId
                         resolve:(void (^)(id result))resolve
                          reject:(void (^)(NSString* code, NSString* message, NSError* error))reject;
- (NSNumber*)videoOutputDispose:(double)objectId;
- (NSDictionary*)tiCloudStorageCreateVideoOutput;
- (void)tiCloudStorageVideoOutputTakeSnapshot:(double)objectId
                                       resolve:(void (^)(id result))resolve
                                        reject:(void (^)(NSString* code, NSString* message, NSError* error))reject;
- (NSNumber*)tiCloudStorageVideoOutputDispose:(double)objectId;
- (NSDictionary*)tiCloudStorageCreate:(NSString*)token;
- (NSNumber*)tiCloudStorageUpdateToken:(double)objectId token:(NSString*)token;
- (NSNumber*)tiCloudStorageDispose:(double)objectId;
- (NSDictionary*)tiCloudStorageCreateReplay:(double)objectId;
- (NSNumber*)tiCloudStorageReplaySetSpeed:(double)objectId speed:(double)speed;
- (NSNumber*)tiCloudStorageReplayDispose:(double)objectId;
- (NSDictionary*)snapshotResultWithCode:(int32_t)code file:(id)file;
@end

@interface TiRtcNativeSnapshotTestFile : NSObject
@property(nonatomic, copy) NSString* path;
@property(nonatomic, copy) void (^onDelete)(void);
@end

@implementation TiRtcNativeSnapshotTestFile
- (void)deleteWithCompletion:(void (^)(int32_t code))completion {
  if (self.onDelete != nil) self.onDelete();
  completion(0);
}
@end

@interface TiRtcNativeSnapshotLifecycleTests : XCTestCase
@end

@implementation TiRtcNativeSnapshotLifecycleTests

- (void)testRtcAndCloudNoFrameSnapshotLifecycleThroughModuleInvalidation {
  XCTAssertFalse([[TiRtcReactNativeRegistry sharedRegistry] hasLiveObjects]);

  [self exerciseRtcSnapshotLifecycle];
  [self exerciseCloudSnapshotLifecycle];

  XCTAssertFalse([[TiRtcReactNativeRegistry sharedRegistry] hasLiveObjects]);
  fprintf(stdout, "TiRtcRnNative marker=%s\n", TiRtcNativeSnapshotMarker.UTF8String);
  fflush(stdout);
}

- (void)testSuccessfulSnapshotFilesAreOwnedAcrossModuleInvalidation {
  TiRtcInitOptions* options = [[TiRtcInitOptions alloc] initWithAppId:@"rn-native-snapshot-files"];
  options.consoleLogEnabled = NO;
  XCTAssertEqual([TiRtc initialize:options], 0);

  TiRtcReactNative* module = [TiRtcReactNative new];
  XCTestExpectation* registeredDeleted =
      [self expectationWithDescription:@"registered snapshot file deleted during invalidation"];
  TiRtcNativeSnapshotTestFile* registered = [TiRtcNativeSnapshotTestFile new];
  registered.path = @"/tmp/rn-native-snapshot-registered";
  registered.onDelete = ^{ [registeredDeleted fulfill]; };
  NSDictionary* registeredResult = [module snapshotResultWithCode:0 file:registered];
  XCTAssertEqualObjects(registeredResult[@"code"], @0);
  XCTAssertEqualObjects(registeredResult[@"filePath"], registered.path);
  NSNumber* registeredId = registeredResult[@"fileId"];
  XCTAssertNotEqualObjects(registeredId, NSNull.null);
  XCTAssertEqualObjects(
      [[TiRtcReactNativeRegistry sharedRegistry] transientObjectForId:registeredId.integerValue],
      registered);

  [module invalidate];

  XCTestExpectation* lateResolved =
      [self expectationWithDescription:@"late successful snapshot callback resolved"];
  XCTestExpectation* lateDeleted =
      [self expectationWithDescription:@"late successful snapshot file deleted"];
  __block NSDictionary* lateResult = nil;
  TiRtcNativeSnapshotTestFile* late = [TiRtcNativeSnapshotTestFile new];
  late.path = @"/tmp/rn-native-snapshot-late";
  late.onDelete = ^{ [lateDeleted fulfill]; };
  dispatch_async(dispatch_get_main_queue(), ^{
    lateResult = [module snapshotResultWithCode:0 file:late];
    [lateResolved fulfill];
  });

  [self waitForExpectations:@[ registeredDeleted, lateResolved, lateDeleted ] timeout:5];
  XCTAssertEqualObjects(lateResult[@"code"], @(TiRtcReactNativeErrorObjectReleased));
  XCTAssertEqualObjects(lateResult[@"fileId"], NSNull.null);
  XCTAssertEqualObjects(lateResult[@"filePath"], NSNull.null);
  XCTAssertEqual([[TiRtcReactNativeRegistry sharedRegistry] drainTransientObjects].count, 0);
  [self waitForRtcReinitialize];
  fprintf(stdout, "TiRtcRnNative marker=%s\n", TiRtcNativeSnapshotFileMarker.UTF8String);
  fflush(stdout);
}

- (void)exerciseRtcSnapshotLifecycle {
  TiRtcInitOptions* options = [[TiRtcInitOptions alloc] initWithAppId:@"rn-native-snapshot-rtc"];
  options.consoleLogEnabled = NO;
  XCTAssertEqual([TiRtc initialize:options], 0);

  TiRtcReactNative* module = [TiRtcReactNative new];
  NSDictionary* output = [module createVideoOutput];
  XCTAssertEqualObjects(output[@"code"], @0);
  NSNumber* outputId = output[@"objectId"];
  TiRtcVideoOutput* nativeOutput =
      [[TiRtcReactNativeRegistry sharedRegistry] objectForId:outputId.integerValue];
  XCTAssertNotNil(nativeOutput);
  XCTAssertEqual([nativeOutput setOptions:[TiRtcVideoOutputOptions new]], 0);
  nativeOutput = nil;

  __block NSDictionary* firstResult = nil;
  __block NSDictionary* repeatedResult = nil;
  __block NSInteger firstCount = 0;
  __block NSInteger repeatedCount = 0;
  XCTestExpectation* first = [self expectationWithDescription:@"RTC no-frame snapshot"];
  XCTestExpectation* repeated = [self expectationWithDescription:@"RTC repeated snapshot"];
  first.assertForOverFulfill = YES;
  repeated.assertForOverFulfill = YES;

  [module videoOutputTakeSnapshot:outputId.doubleValue
                          resolve:^(id result) {
                            firstCount += 1;
                            XCTAssertTrue(NSThread.isMainThread);
                            firstResult = result;
                            [first fulfill];
                          }
                           reject:^(NSString* code, NSString* message, NSError* error) {
                             XCTFail(@"RTC snapshot rejected: %@ %@ %@", code, message, error);
                           }];
  [module videoOutputTakeSnapshot:outputId.doubleValue
                          resolve:^(id result) {
                            repeatedCount += 1;
                            XCTAssertTrue(NSThread.isMainThread);
                            repeatedResult = result;
                            [repeated fulfill];
                          }
                           reject:^(NSString* code, NSString* message, NSError* error) {
                             XCTFail(@"RTC repeated snapshot rejected: %@ %@ %@", code, message, error);
                           }];
  dispatch_async(dispatch_get_main_queue(), ^{
    XCTAssertEqualObjects([module videoOutputDispose:outputId.doubleValue],
                          @([TiCloudStorageErrorCode inUse]));
    [module invalidate];
  });

  [self waitForExpectations:@[ first, repeated ] timeout:5];
  XCTAssertEqual(firstCount, 1);
  XCTAssertEqual(repeatedCount, 1);
  XCTAssertEqualObjects(firstResult[@"code"], @([TiCloudStorageErrorCode noFrame]));
  XCTAssertEqualObjects(firstResult[@"fileId"], NSNull.null);
  XCTAssertEqualObjects(firstResult[@"filePath"], NSNull.null);
  XCTAssertEqualObjects(repeatedResult[@"code"], @([TiCloudStorageErrorCode inUse]));
  XCTAssertEqualObjects(repeatedResult[@"fileId"], NSNull.null);
  XCTAssertEqualObjects(repeatedResult[@"filePath"], NSNull.null);
  XCTAssertNil([[TiRtcReactNativeRegistry sharedRegistry] objectForId:outputId.integerValue]);
  XCTAssertEqual([[TiRtcReactNativeRegistry sharedRegistry] drainTransientObjects].count, 0);

  module = nil;
  XCTAssertEqualObjects(firstResult[@"code"], @([TiCloudStorageErrorCode noFrame]));
  [self waitForRtcReinitialize];
}

- (void)exerciseCloudSnapshotLifecycle {
  XCTAssertEqual([TiCloudStorage initializeWithAppId:@"rn-native-snapshot-cloud"
                                             endpoint:@""
                                    consoleLogEnabled:NO],
                 0);

  TiRtcReactNative* module = [TiRtcReactNative new];
  NSDictionary* output = [module tiCloudStorageCreateVideoOutput];
  XCTAssertEqualObjects(output[@"code"], @0);
  NSNumber* outputId = output[@"objectId"];
  TiCloudStorageVideoOutput* nativeOutput =
      [[TiRtcReactNativeRegistry sharedRegistry] objectForId:outputId.integerValue];
  XCTAssertNotNil(nativeOutput);
  UIView* primingView = [UIView new];
  XCTAssertEqual([nativeOutput attachView:primingView], 0);
  XCTAssertEqual([nativeOutput detachView], 0);
  primingView = nil;
  nativeOutput = nil;

  __block NSDictionary* firstResult = nil;
  __block NSDictionary* repeatedResult = nil;
  __block NSInteger firstCount = 0;
  __block NSInteger repeatedCount = 0;
  XCTestExpectation* first = [self expectationWithDescription:@"Cloud no-frame snapshot"];
  XCTestExpectation* repeated = [self expectationWithDescription:@"Cloud repeated snapshot"];
  first.assertForOverFulfill = YES;
  repeated.assertForOverFulfill = YES;

  [module tiCloudStorageVideoOutputTakeSnapshot:outputId.doubleValue
                                         resolve:^(id result) {
                                           firstCount += 1;
                                           XCTAssertTrue(NSThread.isMainThread);
                                           firstResult = result;
                                           [first fulfill];
                                         }
                                          reject:^(NSString* code, NSString* message, NSError* error) {
                                            XCTFail(@"Cloud snapshot rejected: %@ %@ %@", code, message, error);
                                          }];
  [module tiCloudStorageVideoOutputTakeSnapshot:outputId.doubleValue
                                         resolve:^(id result) {
                                           repeatedCount += 1;
                                           XCTAssertTrue(NSThread.isMainThread);
                                           repeatedResult = result;
                                           [repeated fulfill];
                                         }
                                          reject:^(NSString* code, NSString* message, NSError* error) {
                                            XCTFail(@"Cloud repeated snapshot rejected: %@ %@ %@", code, message, error);
                                          }];
  dispatch_async(dispatch_get_main_queue(), ^{
    XCTAssertEqualObjects([module tiCloudStorageVideoOutputDispose:outputId.doubleValue],
                          @([TiCloudStorageErrorCode inUse]));
    [module invalidate];
  });

  [self waitForExpectations:@[ first, repeated ] timeout:5];
  XCTAssertEqual(firstCount, 1);
  XCTAssertEqual(repeatedCount, 1);
  XCTAssertEqualObjects(firstResult[@"code"], @([TiCloudStorageErrorCode noFrame]));
  XCTAssertEqualObjects(firstResult[@"fileId"], NSNull.null);
  XCTAssertEqualObjects(firstResult[@"filePath"], NSNull.null);
  XCTAssertEqualObjects(repeatedResult[@"code"], @([TiCloudStorageErrorCode inUse]));
  XCTAssertEqualObjects(repeatedResult[@"fileId"], NSNull.null);
  XCTAssertEqualObjects(repeatedResult[@"filePath"], NSNull.null);
  XCTAssertNil([[TiRtcReactNativeRegistry sharedRegistry] objectForId:outputId.integerValue]);
  XCTAssertEqual([[TiRtcReactNativeRegistry sharedRegistry] drainTransientObjects].count, 0);

  module = nil;
  XCTAssertEqualObjects(firstResult[@"code"], @([TiCloudStorageErrorCode noFrame]));
  [self waitForCloudReinitialize];
}

- (void)waitForRtcReinitialize {
  XCTestExpectation* reinitialized = [self expectationWithDescription:@"RTC reinitialized"];
  NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  __block void (^attempt)(void);
  attempt = ^{
    TiRtcInitOptions* changed = [[TiRtcInitOptions alloc] initWithAppId:@"rn-native-snapshot-rtc-reinit"];
    changed.consoleLogEnabled = YES;
    int32_t code = [TiRtc initialize:changed];
    if (code == 0) {
      XCTAssertEqual([TiRtc shutdown], 0);
      [reinitialized fulfill];
      attempt = nil;
      return;
    }
    if ([deadline timeIntervalSinceNow] <= 0) {
      XCTFail(@"RTC did not shut down for changed-config reinitialization; last code=%d", code);
      [reinitialized fulfill];
      attempt = nil;
      return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), attempt);
  };
  dispatch_async(dispatch_get_main_queue(), attempt);
  [self waitForExpectations:@[ reinitialized ] timeout:5];
}

- (void)waitForCloudReinitialize {
  XCTestExpectation* reinitialized = [self expectationWithDescription:@"Cloud reinitialized"];
  NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  __block void (^attempt)(void);
  attempt = ^{
    int32_t code = [TiCloudStorage initializeWithAppId:@"rn-native-snapshot-cloud-reinit"
                                               endpoint:@""
                                      consoleLogEnabled:YES];
    if (code == 0) {
      XCTAssertEqual([TiCloudStorage shutdown], 0);
      [reinitialized fulfill];
      attempt = nil;
      return;
    }
    if ([deadline timeIntervalSinceNow] <= 0) {
      XCTFail(@"Cloud did not shut down for changed-config reinitialization; last code=%d", code);
      [reinitialized fulfill];
      attempt = nil;
      return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), attempt);
  };
  dispatch_async(dispatch_get_main_queue(), attempt);
  [self waitForExpectations:@[ reinitialized ] timeout:5];
}

@end

@interface TiRtcNativeCloudConcurrencyTests : XCTestCase
@end

@implementation TiRtcNativeCloudConcurrencyTests

- (void)testCloudStorageConcurrentDisposeMatrixThroughReactNativeRegistry {
  XCTAssertFalse([[TiRtcReactNativeRegistry sharedRegistry] hasLiveObjects]);
  XCTAssertEqual([TiCloudStorage shutdown], 0);
  XCTAssertEqual([TiCloudStorage initializeWithAppId:@"rn-native-cloud-concurrency"
                                             endpoint:@""
                                    consoleLogEnabled:NO],
                 0);

  TiRtcReactNative* module = [TiRtcReactNative new];
  [self exerciseConcurrentStoreDispose:module];
  [self emitMarker:TiRtcNativeCloudConcurrentDisposeMarker];
  [self exerciseUpdateTokenDisposeRace:module lazy:NO];
  [self emitMarker:TiRtcNativeCloudUpdateDisposeMarker];
  [self exerciseReplayControlDisposeRace:module lazy:NO];
  [self emitMarker:TiRtcNativeCloudReplayDisposeMarker];
  [self exerciseUpdateTokenDisposeRace:module lazy:YES];
  [self emitMarker:TiRtcNativeCloudLazyStoreDisposeMarker];
  [self exerciseReplayControlDisposeRace:module lazy:YES];
  [self emitMarker:TiRtcNativeCloudLazyReplayDisposeMarker];

  XCTAssertFalse([[TiRtcReactNativeRegistry sharedRegistry] hasLiveObjects]);
  XCTAssertEqual([TiCloudStorage shutdown], 0);
  [self emitMarker:TiRtcNativeCloudConcurrencyCleanupMarker];
}

- (void)exerciseConcurrentStoreDispose:(TiRtcReactNative*)module {
  NSNumber* objectId = [self createStore:module token:@"double-dispose-token"];
  if (objectId == nil) return;
  XCTAssertEqualObjects([module tiCloudStorageUpdateToken:objectId.doubleValue
                                                    token:@"double-dispose-created"],
                        @0);
  NSArray<NSNumber*>* results = [self runConcurrently:^{
    return [module tiCloudStorageDispose:objectId.doubleValue];
  } right:^{
    return [module tiCloudStorageDispose:objectId.doubleValue];
  }];
  if (results.count != 2) return;
  NSInteger left = results[0].integerValue;
  NSInteger right = results[1].integerValue;
  NSArray<NSNumber*>* allowed = @[@0, @([TiCloudStorageErrorCode inUse]),
                                   @(TiRtcReactNativeErrorObjectReleased)];
  XCTAssertTrue([allowed containsObject:@(left)]);
  XCTAssertTrue([allowed containsObject:@(right)]);
  XCTAssertTrue(left == 0 || right == 0);
  XCTAssertNil([[TiRtcReactNativeRegistry sharedRegistry] objectForId:objectId.integerValue]);
}

- (void)exerciseUpdateTokenDisposeRace:(TiRtcReactNative*)module lazy:(BOOL)lazy {
  NSString* token = lazy ? @"lazy-store-token" : @"created-store-token";
  NSNumber* objectId = [self createStore:module token:token];
  if (objectId == nil) return;
  if (!lazy) {
    XCTAssertEqualObjects([module tiCloudStorageUpdateToken:objectId.doubleValue
                                                      token:@"created-store-prime"],
                          @0);
  }
  NSArray<NSNumber*>* results = [self runConcurrently:^{
    return [module tiCloudStorageUpdateToken:objectId.doubleValue
                                       token:(lazy ? @"lazy-store-use" : @"created-store-race")];
  } right:^{
    return [module tiCloudStorageDispose:objectId.doubleValue];
  }];
  if (results.count != 2) return;
  [self assertCallResult:results[0].integerValue disposeResult:results[1].integerValue];
  [self finishStoreRace:module objectId:objectId disposeResult:results[1].integerValue];
}

- (void)exerciseReplayControlDisposeRace:(TiRtcReactNative*)module lazy:(BOOL)lazy {
  NSNumber* storeId = [self createStore:module
                                  token:(lazy ? @"lazy-replay-parent-token" : @"replay-parent-token")];
  if (storeId == nil) return;
  if (!lazy) {
    XCTAssertEqualObjects([module tiCloudStorageUpdateToken:storeId.doubleValue
                                                      token:@"replay-parent-created"],
                          @0);
  }
  NSDictionary* created = [module tiCloudStorageCreateReplay:storeId.doubleValue];
  XCTAssertEqualObjects(created[@"code"], @0);
  NSNumber* replayId = created[@"objectId"];
  if (![replayId isKindOfClass:[NSNumber class]]) return;
  if (!lazy) {
    XCTAssertEqualObjects([module tiCloudStorageReplaySetSpeed:replayId.doubleValue speed:1], @0);
  }
  NSArray<NSNumber*>* results = [self runConcurrently:^{
    return [module tiCloudStorageReplaySetSpeed:replayId.doubleValue speed:2];
  } right:^{
    return [module tiCloudStorageReplayDispose:replayId.doubleValue];
  }];
  if (results.count != 2) return;
  [self assertCallResult:results[0].integerValue disposeResult:results[1].integerValue];
  if (results[1].integerValue == [TiCloudStorageErrorCode inUse]) {
    XCTAssertNotNil([[TiRtcReactNativeRegistry sharedRegistry] objectForId:replayId.integerValue]);
    XCTAssertEqualObjects([module tiCloudStorageReplaySetSpeed:replayId.doubleValue speed:0], @0);
    XCTAssertEqual([self retryDispose:^{
      return [module tiCloudStorageReplayDispose:replayId.doubleValue];
    }], 0);
  } else {
    XCTAssertEqual(results[1].integerValue, 0);
    XCTAssertNil([[TiRtcReactNativeRegistry sharedRegistry] objectForId:replayId.integerValue]);
    XCTAssertEqualObjects([module tiCloudStorageReplaySetSpeed:replayId.doubleValue speed:0],
                          @(TiRtcReactNativeErrorObjectReleased));
  }
  XCTAssertEqual([self retryDispose:^{
    return [module tiCloudStorageDispose:storeId.doubleValue];
  }], 0);
  XCTAssertNil([[TiRtcReactNativeRegistry sharedRegistry] objectForId:storeId.integerValue]);
}

- (NSNumber*)createStore:(TiRtcReactNative*)module token:(NSString*)token {
  NSDictionary* created = [module tiCloudStorageCreate:token];
  XCTAssertEqualObjects(created[@"code"], @0);
  NSNumber* objectId = created[@"objectId"];
  XCTAssertTrue([objectId isKindOfClass:[NSNumber class]]);
  return [objectId isKindOfClass:[NSNumber class]] ? objectId : nil;
}

- (void)finishStoreRace:(TiRtcReactNative*)module
                objectId:(NSNumber*)objectId
            disposeResult:(NSInteger)disposeResult {
  if (disposeResult == [TiCloudStorageErrorCode inUse]) {
    XCTAssertNotNil([[TiRtcReactNativeRegistry sharedRegistry] objectForId:objectId.integerValue]);
    XCTAssertEqualObjects([module tiCloudStorageUpdateToken:objectId.doubleValue token:@"retry-token"],
                          @0);
    XCTAssertEqual([self retryDispose:^{
      return [module tiCloudStorageDispose:objectId.doubleValue];
    }], 0);
  } else {
    XCTAssertEqual(disposeResult, 0);
    XCTAssertNil([[TiRtcReactNativeRegistry sharedRegistry] objectForId:objectId.integerValue]);
    XCTAssertEqualObjects([module tiCloudStorageUpdateToken:objectId.doubleValue token:@"released-token"],
                          @(TiRtcReactNativeErrorObjectReleased));
  }
  XCTAssertNil([[TiRtcReactNativeRegistry sharedRegistry] objectForId:objectId.integerValue]);
}

- (void)assertCallResult:(NSInteger)callResult disposeResult:(NSInteger)disposeResult {
  NSArray<NSNumber*>* allowedCalls = @[@0, @([TiCloudStorageErrorCode inUse]),
                                       @(TiRtcReactNativeErrorObjectReleased)];
  XCTAssertTrue([allowedCalls containsObject:@(callResult)]);
  XCTAssertTrue(disposeResult == 0 || disposeResult == [TiCloudStorageErrorCode inUse]);
  if (disposeResult == [TiCloudStorageErrorCode inUse]) XCTAssertEqual(callResult, 0);
  if (callResult == [TiCloudStorageErrorCode inUse] ||
      callResult == TiRtcReactNativeErrorObjectReleased) {
    XCTAssertEqual(disposeResult, 0);
  }
}

- (NSInteger)retryDispose:(NSNumber* (^)(void))dispose {
  NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:2];
  NSInteger code = dispose().integerValue;
  while (code == [TiCloudStorageErrorCode inUse] && [deadline timeIntervalSinceNow] > 0) {
    [NSThread sleepForTimeInterval:0.001];
    code = dispose().integerValue;
  }
  return code;
}

- (NSArray<NSNumber*>*)runConcurrently:(NSNumber* (^)(void))left
                                  right:(NSNumber* (^)(void))right {
  dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
  dispatch_group_t completed = dispatch_group_create();
  dispatch_semaphore_t ready = dispatch_semaphore_create(0);
  dispatch_semaphore_t start = dispatch_semaphore_create(0);
  __block NSNumber* leftResult = nil;
  __block NSNumber* rightResult = nil;
  dispatch_group_async(completed, queue, ^{
    dispatch_semaphore_signal(ready);
    if (dispatch_semaphore_wait(start, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0)
      leftResult = left();
  });
  dispatch_group_async(completed, queue, ^{
    dispatch_semaphore_signal(ready);
    if (dispatch_semaphore_wait(start, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0)
      rightResult = right();
  });
  BOOL bothReady =
      dispatch_semaphore_wait(ready, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0 &&
      dispatch_semaphore_wait(ready, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0;
  dispatch_semaphore_signal(start);
  dispatch_semaphore_signal(start);
  BOOL bothCompleted =
      dispatch_group_wait(completed, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0;
  XCTAssertTrue(bothReady);
  XCTAssertTrue(bothCompleted);
  XCTAssertNotNil(leftResult);
  XCTAssertNotNil(rightResult);
  return leftResult != nil && rightResult != nil ? @[leftResult, rightResult] : @[];
}

- (void)emitMarker:(NSString*)marker {
  fprintf(stdout, "TiRtcRnNative marker=%s\n", marker.UTF8String);
  fflush(stdout);
}

@end
