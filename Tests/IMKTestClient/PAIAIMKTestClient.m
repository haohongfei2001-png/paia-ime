#import "PAIAIMKTestClient.h"
@implementation PAIAIMKTestClient
- (instancetype)initWithText:(NSString *)text {
    if((self=[super init])){_view=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,600,200)];_view.richText=NO;_view.string=text;[_view setSelectedRange:NSMakeRange(text.length,0)];_reads=[NSMutableArray array];_writes=[NSMutableArray array];}return self;
}
- (NSRange)selectedRange {if(_onSelectedRange){void(^f)(void)=_onSelectedRange;_onSelectedRange=nil;f();}return _view.selectedRange;}
- (NSRange)markedRange {if(_onMarkedRange){void(^f)(void)=_onMarkedRange;_onMarkedRange=nil;f();}return _view.markedRange;}
- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range {
    [_reads addObject:[NSValue valueWithRange:range]];
    if(_onRead){void(^f)(void)=_onRead;_onRead=nil;f();}
    if(range.location==NSNotFound || range.location>_view.string.length || range.length>_view.string.length-range.location)return nil;
    if(_truncateReads && range.length>0)range.length--;
    return [[NSAttributedString alloc] initWithString:[_view.string substringWithRange:range]];
}
- (void)setMarkedText:(id)text selectionRange:(NSRange)selection replacementRange:(NSRange)replacement {
    _markCalls++;[_writes addObject:[NSValue valueWithRange:replacement]];
    [_view setMarkedText:text selectedRange:selection replacementRange:replacement];
    if(_onMark){void(^f)(void)=_onMark;_onMark=nil;f();}
}
- (void)insertText:(id)text replacementRange:(NSRange)replacement {
    _insertCalls++;[_writes addObject:[NSValue valueWithRange:replacement]];
    [_view insertText:text replacementRange:replacement];
    if(_onInsert){void(^f)(void)=_onInsert;_onInsert=nil;f();}
}
- (NSInteger)length {_documentLengthCalls++;return _view.string.length;}
- (NSDictionary *)attributesForCharacterIndex:(NSUInteger)index lineHeightRectangle:(NSRect *)rect {
    if(_onGeometry){void(^f)(void)=_onGeometry;_onGeometry=nil;f();}
    if(rect)*rect=_invalidGeometry?NSZeroRect:NSMakeRect(200,400,1,22);return @{};
}
- (NSInteger)characterIndexForPoint:(NSPoint)point tracking:(IMKLocationToOffsetMappingMode)mode inMarkedRange:(BOOL *)flag {if(flag)*flag=NO;return NSNotFound;}
- (NSArray *)validAttributesForMarkedText {return @[];}
- (void)overrideKeyboardWithKeyboardNamed:(NSString *)name {}
- (void)selectInputMode:(NSString *)mode {}
- (BOOL)supportsUnicode {return YES;}
- (NSString *)bundleIdentifier {return @"dev.paia.synthetic.imk-client";}
- (CGWindowLevel)windowLevel {return NSNormalWindowLevel;}
- (BOOL)supportsProperty:(TSMDocumentPropertyTag)property {return NO;}
- (NSString *)uniqueClientIdentifierString {return [NSString stringWithFormat:@"synthetic-%p", self];}
- (NSString *)stringFromRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    NSAttributedString *value=[self attributedSubstringFromRange:range];
    if(actualRange)*actualRange=value?NSMakeRange(range.location,value.length):NSMakeRange(NSNotFound,0);
    return value.string;
}
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    if(actualRange)*actualRange=NSMakeRange(NSNotFound,0);return NSZeroRect;
}
@end
