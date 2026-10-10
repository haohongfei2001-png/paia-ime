#import <Foundation/Foundation.h>
#import <InputMethodKit/InputMethodKit.h>
NS_ASSUME_NONNULL_BEGIN
// Raw UTF-16 little-endian bytes prevent NSString-to-String's lossy surrogate
// repair from turning a malformed host response into apparently valid evidence.
@interface PAIABoundedContextRead : NSObject
@property(nonatomic,readonly) NSRange actualRange;
@property(nonatomic,readonly) NSData *utf16LE;
@end
FOUNDATION_EXPORT PAIABoundedContextRead * _Nullable PAIAReadIMKContext(id<IMKTextInput> client,NSRange requested,NSUInteger maxUnits);
FOUNDATION_EXPORT NSNumber * _Nullable PAIAReadIMKLength(id<IMKTextInput> client);
NS_ASSUME_NONNULL_END
