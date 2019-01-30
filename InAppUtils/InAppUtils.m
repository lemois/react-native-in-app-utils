#import "InAppUtils.h"
#import <StoreKit/StoreKit.h>
#import <React/RCTLog.h>
#import <React/RCTUtils.h>
#import "SKProduct+StringPrice.h"

@implementation InAppUtils
{
    NSArray *products;
    NSMutableDictionary *_callbacks;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _callbacks = [[NSMutableDictionary alloc] init];
    }
    return self;
}

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(getPendingTransactions:(RCTPromiseResolveBlock)resolve
                                  reject:(RCTPromiseRejectBlock)reject)
{
  NSArray *transactions = [[SKPaymentQueue defaultQueue] transactions];
  NSMutableArray *mapped = [NSMutableArray arrayWithCapacity:[transactions count]];
  for (int i = 0; i < transactions.count; i++) {
    SKPaymentTransaction* t = transactions[i];
    NSDictionary *purchase = [self getPurchaseData:t];
    [mapped addObject:purchase];
  }
  resolve(mapped);
}

RCT_EXPORT_METHOD(startPaymentQueueObservation)
{
    [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
}

RCT_EXPORT_METHOD(finishTransaction:(NSString *)transactionIdentifier
                            resolve:(RCTPromiseResolveBlock)resolve
                             reject:(RCTPromiseRejectBlock)reject)
{
  NSArray *transactions = [[SKPaymentQueue defaultQueue] transactions];
  for (int i = 0; i < transactions.count; i++) {
    SKPaymentTransaction* t = transactions[i];
    if ([transactionIdentifier isEqualToString:t.transactionIdentifier]) {
      [[SKPaymentQueue defaultQueue] finishTransaction:t];
      resolve(t.transactionIdentifier);
      return;
    }
  }
  reject(@"E_TRANSACTION_NOT_FOUND", @"Transaction not found", nil);
}

RCT_EXPORT_METHOD(canPurchaseProduct:(NSString *)productIdentifier
                            resolve:(RCTPromiseResolveBlock)resolve
                             reject:(RCTPromiseRejectBlock)reject)
{
  NSArray *transactions = [[SKPaymentQueue defaultQueue] transactions];
  for (int i = 0; i < transactions.count; i++) {
    SKPaymentTransaction* t = transactions[i];
    if (
      (
        t.transactionState == SKPaymentTransactionStatePurchasing ||
        t.transactionState == SKPaymentTransactionStatePurchased
      ) &&
      [productIdentifier isEqualToString:t.payment.productIdentifier]
    ) {
      resolve(@"false");
      return;
    }
  }
  resolve(@"true");
}

NSString *const TRANSACTION_UPDATED_EVENT_NAME = @"transactionUpdated";

- (NSArray<NSString *> *)supportedEvents
{
  return @[TRANSACTION_UPDATED_EVENT_NAME];
}

- (void)paymentQueue:(SKPaymentQueue *)queue
 updatedTransactions:(NSArray *)transactions
{
    for (SKPaymentTransaction *transaction in transactions) {
        NSDictionary *purchase = [self getPurchaseData:transaction];
        [self sendEventWithName:TRANSACTION_UPDATED_EVENT_NAME body:purchase];
    }
}

RCT_EXPORT_METHOD(purchaseProductForUser:(NSString *)productIdentifier
                  username:(NSString *)username
                  callback:(RCTResponseSenderBlock)callback)
{
    [self doPurchaseProduct:productIdentifier username:username callback:callback];
}

RCT_EXPORT_METHOD(purchaseProduct:(NSString *)productIdentifier
                  callback:(RCTResponseSenderBlock)callback)
{
    [self doPurchaseProduct:productIdentifier username:nil callback:callback];
}

- (void) doPurchaseProduct:(NSString *)productIdentifier
                  username:(NSString *)username
                  callback:(RCTResponseSenderBlock)callback
{
    SKProduct *product;
    for(SKProduct *p in products)
    {
        if([productIdentifier isEqualToString:p.productIdentifier]) {
            product = p;
            break;
        }
    }

    if(product) {
        SKMutablePayment *payment = [SKMutablePayment paymentWithProduct:product];
        if(username) {
            payment.applicationUsername = username;
        }
        [[SKPaymentQueue defaultQueue] addPayment:payment];
        callback(@[[NSNull null]]);
    } else {
        callback(@[@"invalid_product"]);
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue
restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    NSString *key = RCTKeyForInstance(@"restoreRequest");
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        switch (error.code)
        {
            case SKErrorPaymentCancelled:
                callback(@[@"user_cancelled"]);
                break;
            default:
                callback(@[@"restore_failed"]);
                break;
        }

        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for restore product request.");
    }
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
    NSString *key = RCTKeyForInstance(@"restoreRequest");
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        NSMutableArray *productsArrayForJS = [NSMutableArray array];
        for(SKPaymentTransaction *transaction in queue.transactions){
            if(transaction.transactionState == SKPaymentTransactionStateRestored) {

                NSDictionary *purchase = [self getPurchaseData:transaction];

                [productsArrayForJS addObject:purchase];
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
            }
        }
        callback(@[[NSNull null], productsArrayForJS]);
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for restore product request.");
    }
}

RCT_EXPORT_METHOD(restorePurchases:(RCTResponseSenderBlock)callback)
{
    NSString *restoreRequest = @"restoreRequest";
    _callbacks[RCTKeyForInstance(restoreRequest)] = callback;
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

RCT_EXPORT_METHOD(restorePurchasesForUser:(NSString *)username
                    callback:(RCTResponseSenderBlock)callback)
{
    NSString *restoreRequest = @"restoreRequest";
    _callbacks[RCTKeyForInstance(restoreRequest)] = callback;
    if(!username) {
        callback(@[@"username_required"]);
        return;
    }
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactionsWithApplicationUsername:username];
}

RCT_EXPORT_METHOD(loadProducts:(NSArray *)productIdentifiers
                  callback:(RCTResponseSenderBlock)callback)
{
    SKProductsRequest *productsRequest = [[SKProductsRequest alloc]
                                          initWithProductIdentifiers:[NSSet setWithArray:productIdentifiers]];
    productsRequest.delegate = self;
    _callbacks[RCTKeyForInstance(productsRequest)] = callback;
    [productsRequest start];
}

RCT_EXPORT_METHOD(canMakePayments: (RCTResponseSenderBlock)callback)
{
    BOOL canMakePayments = [SKPaymentQueue canMakePayments];
    callback(@[@(canMakePayments)]);
}

RCT_EXPORT_METHOD(receiptData:(RCTResponseSenderBlock)callback)
{
    NSURL *receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptUrl];
    if (!receiptData) {
      callback(@[@"not_available"]);
    } else {
      callback(@[[NSNull null], [receiptData base64EncodedStringWithOptions:0]]);
    }
}

// SKProductsRequestDelegate protocol method
- (void)productsRequest:(SKProductsRequest *)request
     didReceiveResponse:(SKProductsResponse *)response
{
    NSString *key = RCTKeyForInstance(request);
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        products = [NSMutableArray arrayWithArray:response.products];
        NSMutableArray *productsArrayForJS = [NSMutableArray array];
        for(SKProduct *item in response.products) {
            NSDictionary *product = @{
                                      @"identifier": item.productIdentifier,
                                      @"price": item.price,
                                      @"currencySymbol": [item.priceLocale objectForKey:NSLocaleCurrencySymbol],
                                      @"currencyCode": [item.priceLocale objectForKey:NSLocaleCurrencyCode],
                                      @"priceString": item.priceString,
                                      @"countryCode": [item.priceLocale objectForKey: NSLocaleCountryCode],
                                      @"downloadable": item.downloadable ? @"true" : @"false" ,
                                      @"description": item.localizedDescription ? item.localizedDescription : @"",
                                      @"title": item.localizedTitle ? item.localizedTitle : @"",
                                      };
            [productsArrayForJS addObject:product];
        }
        callback(@[[NSNull null], productsArrayForJS]);
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for load product request.");
    }
}

// SKProductsRequestDelegate network error
- (void)request:(SKRequest *)request didFailWithError:(NSError *)error{
    NSString *key = RCTKeyForInstance(request);
    RCTResponseSenderBlock callback = _callbacks[key];
    if(callback) {
        callback(@[RCTJSErrorFromNSError(error)]);
        [_callbacks removeObjectForKey:key];
    }
}

- (NSString *)stringifyTransactionState:(SKPaymentTransactionState)state {
    switch (state) {
        case SKPaymentTransactionStateDeferred:
          return @"deferred";
        case SKPaymentTransactionStatePurchasing:
          return @"purchasing";
        case SKPaymentTransactionStatePurchased:
          return @"purchased";
        case SKPaymentTransactionStateRestored:
          return @"restored";
        case SKPaymentTransactionStateFailed:
          return @"failed";
        default:
          return @"unknown";
    }
}

- (NSDictionary *)getPurchaseData:(SKPaymentTransaction *)transaction {
    NSString *transactionIdentifier = transaction.transactionIdentifier;
    NSString *transactionReceipt = [[transaction transactionReceipt] base64EncodedStringWithOptions:0];
    NSMutableDictionary *purchase = [NSMutableDictionary dictionaryWithDictionary: @{
                                                                                     @"transactionDate": @(transaction.transactionDate.timeIntervalSince1970 * 1000),
                                                                                     @"transactionIdentifier": transactionIdentifier == nil ? [NSNull null] : transactionIdentifier,
                                                                                     @"productIdentifier": transaction.payment.productIdentifier,
                                                                                     @"transactionReceipt": transactionReceipt == nil ? [NSNull null] : transactionReceipt,
                                                                                     @"state": [self stringifyTransactionState:transaction.transactionState],
                                                                                     @"error": transaction.transactionState == SKPaymentTransactionStateFailed ?
                                                                                     RCTJSErrorFromNSError(transaction.error) : [NSNull null]
                                                                                     }];
    // originalTransaction is available for restore purchase and purchase of cancelled/expired subscriptions
    SKPaymentTransaction *originalTransaction = transaction.originalTransaction;
    if (originalTransaction) {
        purchase[@"originalTransactionDate"] = @(originalTransaction.transactionDate.timeIntervalSince1970 * 1000);
        purchase[@"originalTransactionIdentifier"] = originalTransaction.transactionIdentifier;
    }

    return purchase;
}

- (void)dealloc
{
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

#pragma mark Private

static NSString *RCTKeyForInstance(id instance)
{
    return [NSString stringWithFormat:@"%p", instance];
}

@end
