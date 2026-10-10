#import "PAIAIMKContext.h"
@interface PAIABoundedContextRead ()
@property(nonatomic,readwrite) NSRange actualRange;
@property(nonatomic,readwrite) NSData *utf16LE;
@end
@implementation PAIABoundedContextRead
@end
PAIABoundedContextRead *PAIAReadIMKContext(id<IMKTextInput> client,NSRange requested,NSUInteger maxUnits) {
    if(maxUnits>1410 || requested.location==NSNotFound || requested.length>maxUnits || requested.length>NSUIntegerMax-requested.location)return nil;
    @try {
        if(![(id)client respondsToSelector:@selector(stringFromRange:actualRange:)])return nil;
        NSRange actual=NSMakeRange(NSNotFound,0);
        NSString *value=[client stringFromRange:requested actualRange:&actual];
        if(![value isKindOfClass:NSString.class] || value.length>maxUnits || actual.length!=value.length)return nil;
        NSUInteger count=value.length;
        NSMutableData *bytes=[NSMutableData dataWithCapacity:count*2];
        // Length is bounded before any copy or Swift bridging. No document scan.
        for(NSUInteger index=0;index<count;index++) {
            unichar unit=[value characterAtIndex:index];uint8_t pair[2]={(uint8_t)(unit&255),(uint8_t)(unit>>8)};[bytes appendBytes:pair length:2];
        }
        if(value.length!=count)return nil;
        PAIABoundedContextRead *result=[PAIABoundedContextRead new];result.actualRange=actual;result.utf16LE=bytes;return result;
    }@catch(NSException *exception){return nil;}
}
NSNumber *PAIAReadIMKLength(id<IMKTextInput> client) {
    @try {if(![(id)client respondsToSelector:@selector(length)])return nil;return @([client length]);}
    @catch(NSException *exception){return nil;}
}
