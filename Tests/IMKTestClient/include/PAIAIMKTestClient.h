#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>
NS_ASSUME_NONNULL_BEGIN
// Authored synthetic IMKTextInput client backed by actual NSTextView. No service
// connection or system input source is created by this test fixture.
@interface PAIAIMKTestClient : NSObject <IMKTextInput>
@property(nonatomic,readonly) NSTextView *view;
@property(nonatomic,copy) NSString *applicationIdentifier;
@property(nonatomic,copy,nullable) void (^onApplicationIdentifier)(void);
@property(nonatomic,readonly) NSInteger applicationIdentifierCalls;
@property(nonatomic,copy,nullable) void (^onSelectedRange)(void);
@property(nonatomic,copy,nullable) void (^onMarkedRange)(void);
@property(nonatomic,copy,nullable) void (^onRead)(void);
@property(nonatomic,copy,nullable) void (^onMark)(void);
@property(nonatomic,copy,nullable) void (^onInsert)(void);
@property(nonatomic,copy,nullable) void (^onGeometry)(void);
@property(nonatomic,copy,nullable) void (^onLength)(void);
@property(nonatomic) BOOL ignoreReplacementRange;
@property(nonatomic) NSInteger contextReadFault;
@property(nonatomic,readonly) NSUInteger contextRevision;
@property(nonatomic) BOOL truncateReads;
@property(nonatomic) BOOL invalidGeometry;
@property(nonatomic,readonly) NSInteger insertCalls;
@property(nonatomic,readonly) NSInteger markCalls;
@property(nonatomic,readonly) NSUInteger lastGeometryIndex;
@property(nonatomic,readonly) NSInteger documentLengthCalls;
@property(nonatomic,readonly) NSMutableArray<NSValue *> *reads;
@property(nonatomic,readonly) NSMutableArray<NSValue *> *writes;
- (instancetype)initWithText:(NSString *)text NS_SWIFT_NAME(init(text:));
@end
NS_ASSUME_NONNULL_END
