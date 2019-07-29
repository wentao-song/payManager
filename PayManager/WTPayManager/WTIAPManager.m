//
//  WTIAPManager.m
//  PayManager
//
//  Created by MOYO on 2019/7/29.
//  Copyright © 2019年 MOYO. All rights reserved.
//

#import "WTIAPManager.h"
#import <StoreKit/StoreKit.h>

@interface WTIAPManager()<SKPaymentTransactionObserver,SKProductsRequestDelegate> {
    
    NSString *_productID;
    IAPCompletionHandle _handle;
}
@end

@implementation WTIAPManager

/**
 单例模式
 购买行为不需要常驻内存
 @return WTIAPManager
 */

//+ (instancetype)shareIAPManager {
//    static WTIAPManager *IAPManager = nil;
//    static dispatch_once_t onceToken;
//    dispatch_once(&onceToken, ^{
//        IAPManager = [[WTIAPManager alloc] init];
//    });
//    return IAPManager;
//}

- (instancetype)init {
    if (self = [super init]) {
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    }
    return self;
}

- (void)dealloc{
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

#pragma mark -- Method


- (void)startIAPWithProductID:(NSString *)productID  completeHandle: (IAPCompletionHandle)handle {
    _handle = handle;
    if(productID && productID.length > 0) {
        if ([SKPaymentQueue canMakePayments]) {// 允许内购
            //产品id
            _productID = productID;
            NSSet *set = [NSSet setWithObjects:productID, nil];
            SKProductsRequest *request = [[SKProductsRequest alloc] initWithProductIdentifiers:set];
            request.delegate = self;
            // 获取内购项目信息
            [request start];
        } else {
            // 不允许内购
            [self handleActionWithType:IAPResultNotArrow data:nil];
        }
        
    } else {
        NSLog(@"内购项目ID错误");
        
        [self handleActionWithType:IAPResultIDError data:nil];
    }
    
}
- (void)handleActionWithType:(IAPResultType)type data:(NSData *)data{
    
    switch (type) {
            case IAPResultSuccess:
            NSLog(@"购买成功");
            break;
            case IAPResultFailed:
            NSLog(@"购买失败");
            break;
            case IAPResultCancle:
            NSLog(@"用户取消购买");
            break;
            case IAPResultVerFailed:
            NSLog(@"订单校验失败");
            break;
            case IAPResultVerSuccess:
            NSLog(@"订单校验成功");
            break;
            case IAPResultNotArrow:
            NSLog(@"不允许程序内付费");
            break;
        default:
            break;
    }
    if(_handle){
        _handle(type,data);
    }
}

#pragma mark --  SKProductsRequestDelegate

/**
 收到产品信息的回调
 接收到产品的返回信息，然后用返回的商品信息进行发起购买请求
 @param request  请求的信息
 @param response 返回的产品信息
 */
- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
    // 商品所在数组
    NSArray *productArr = response.products;
    if (productArr.count > 0) {
        SKProduct *product = nil;
        //在商品列表里查找购买的商品
        for (SKProduct *p in productArr) {
            if ([p.productIdentifier isEqualToString:_productID]) {
                product = p;
                break;
            }
        }
        // 请求体
        SKPayment *payMent = [SKPayment paymentWithProduct:product];
        // 发起内购
        [[SKPaymentQueue defaultQueue] addPayment:payMent];
        
    } else {//没有商品
        [self handleActionWithType:IAPResultIDError data:nil];
    }
}

#pragma mark - SKRequestDelegate
//请求失败
- (void)request:(SKRequest *)request didFailWithError:(NSError *)error{
    //请求失败的处理
}

-(void)requestDidFinish:(SKRequest *)request{
    //请求结果
}

#pragma mark --  SKPaymentTransactionObserver
//购买结果
- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
    // 获取结果
    // 验证成功与否都注销交易,否则会出现虚假凭证信息一直验证不通过,每次进程序都得输入苹果账号
    for (SKPaymentTransaction *trans in transactions) {
        
        switch (trans.transactionState) {
                case SKPaymentTransactionStatePurchasing:
                NSLog(@"商品添加进列表");
                break;
                case SKPaymentTransactionStatePurchased:
                NSLog(@"交易完成");
                [self completeTransaction:trans];
                [[SKPaymentQueue defaultQueue] finishTransaction:trans];
                break;
                case SKPaymentTransactionStateFailed:
                NSLog(@"交易失败");
                [self failedTransaction:trans];
                [[SKPaymentQueue defaultQueue] finishTransaction:trans];
                break;
                case SKPaymentTransactionStateRestored:
                NSLog(@"已经购买过商品");
                [[SKPaymentQueue defaultQueue] finishTransaction:trans]; //消耗型商品不用写
                break;
                case SKPaymentTransactionStateDeferred:
                
                break;
            default:
                break;
        }
        
        
    }
    
}

/**
 内购完成
 交易结束,当交易结束后还要去appstore上验证支付信息是否都正确,只有所有都正确后,我们就可以给用户方法我们的虚拟物品了。
 @param transaction 内购项目体
 */
- (void) completeTransaction:(SKPaymentTransaction *)transaction {
    
    NSString * productIdentifier = transaction.payment.productIdentifier;
    //从沙盒中获取交易凭证并且拼接成请求体数据
    //appStoreReceiptURL iOS7.0增加的，购买交易完成后，会将凭据存放在该地址
    NSURL *recepitURL = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receipt = [NSData dataWithContentsOfURL:recepitURL];
    if ([productIdentifier length] > 0 && !receipt) {
        // 向自己的服务器验证购买凭证
    }
    // 自己向苹果发送验证
    [self verifyPurchaseWithPaymentTransaction:transaction isTestServer:NO];
}



- (void)verifyPurchaseWithPaymentTransaction:(SKPaymentTransaction *)transaction isTestServer:(BOOL)flag{
    //交易验证
    NSURL *recepitURL = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receipt = [NSData dataWithContentsOfURL:recepitURL];
    
    NSError *error;
    NSDictionary *requestContents = @{@"receipt-data": [receipt base64EncodedStringWithOptions:0]};
    NSData *requestData = [NSJSONSerialization dataWithJSONObject:requestContents options:0 error:&error];
    if (!requestData) { // 交易凭证为空验证失败
        [self handleActionWithType:IAPResultVerFailed data:nil];
        return;
    }
    
    //In the test environment, use https://sandbox.itunes.apple.com/verifyReceipt
    //In the real environment, use https://buy.itunes.apple.com/verifyReceipt
    
    NSString *serverString = @"https://buy.itunes.apple.com/verifyReceipt";
    if (flag) {
        serverString = @"https://sandbox.itunes.apple.com/verifyReceipt";
    }
    NSURL *storeURL = [NSURL URLWithString:serverString];
    NSMutableURLRequest *storeRequest = [NSMutableURLRequest requestWithURL:storeURL];
    [storeRequest setHTTPMethod:@"POST"];
    [storeRequest setHTTPBody:requestData];
    storeRequest.timeoutInterval = 20;
    [storeRequest addValue:@"application/json;charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:storeRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            // 无法连接服务器,购买校验失败
            [self handleActionWithType:IAPResultVerFailed data:nil];
        } else {
            NSError *error;
            NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            if (!jsonResponse) {
                // 苹果服务器校验数据返回为空校验失败
                [self handleActionWithType:IAPResultVerFailed data:nil];
            }
            
            // 先验证正式服务器,如果正式服务器返回21007再去苹果测试服务器验证,沙盒测试环境苹果用的是测试服务器
            NSString *status = [NSString stringWithFormat:@"%@",jsonResponse[@"status"]];
            if (status && [status isEqualToString:@"21007"]) {
                [self verifyPurchaseWithPaymentTransaction:transaction isTestServer:YES];
            }else if(status && [status isEqualToString:@"0"]){
                [self handleActionWithType:IAPResultVerSuccess data:nil];
            }
        }
        
    }];
    [task resume];
}

/**
 交易失败
 @param transaction  内购项目体
 */
- (void)failedTransaction:(SKPaymentTransaction *)transaction{
    if (transaction.error.code != SKErrorPaymentCancelled) {
        
        [self handleActionWithType:IAPResultFailed data:nil];
    }else{
        
        [self handleActionWithType:IAPResultCancle data:nil];
    }
}



@end
