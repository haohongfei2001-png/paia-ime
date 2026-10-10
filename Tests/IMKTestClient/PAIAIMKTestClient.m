#import "PAIAIMKTestClient.h"
@implementation PAIAIMKTestClient { id _contextObserver; }
- (instancetype)initWithText:(NSString *)text {
    if((self=[super init])){_view=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,600,200)];_view.richText=NO;_view.string=text;[_view setSelectedRange:NSMakeRange(text.length,0)];_reads=[NSMutableArray array];_writes=[NSMutableArray array];_contextRevision=1;_applicationIdentifier=@"dev.paia.synthetic.imk-client";
        __weak PAIAIMKTestClient *weakSelf=self;
        _contextObserver=[[NSNotificationCenter defaultCenter] addObserverForName:NSTextStorageDidProcessEditingNotification object:_view.textStorage queue:nil usingBlock:^(NSNotification *note){PAIAIMKTestClient *strong=weakSelf;if(strong)strong->_contextRevision++;}];}return self;
}
- (void)dealloc {if(_contextObserver)[[NSNotificationCenter defaultCenter] removeObserver:_contextObserver];}
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
    [_view insertText:text replacementRange:_ignoreReplacementRange?NSMakeRange(_view.string.length,0):replacement];
    if(_onInsert){void(^f)(void)=_onInsert;_onInsert=nil;f();}
}
- (NSInteger)length {_documentLengthCalls++;if(_onLength){void(^f)(void)=_onLength;_onLength=nil;f();}return _view.string.length;}
- (NSDictionary *)attributesForCharacterIndex:(NSUInteger)index lineHeightRectangle:(NSRect *)rect {
    _lastGeometryIndex=index;
    if(_onGeometry){void(^f)(void)=_onGeometry;_onGeometry=nil;f();}
    if(rect)*rect=_invalidGeometry?NSZeroRect:NSMakeRect(200,400,1,22);return @{};
}
- (NSInteger)characterIndexForPoint:(NSPoint)point tracking:(IMKLocationToOffsetMappingMode)mode inMarkedRange:(BOOL *)flag {if(flag)*flag=NO;return NSNotFound;}
- (NSArray *)validAttributesForMarkedText {return @[];}
- (void)overrideKeyboardWithKeyboardNamed:(NSString *)name {}
- (void)selectInputMode:(NSString *)mode {}
- (BOOL)supportsUnicode {return YES;}
- (NSString *)bundleIdentifier {_applicationIdentifierCalls++;if(_onApplicationIdentifier){void(^f)(void)=_onApplicationIdentifier;_onApplicationIdentifier=nil;f();}return _applicationIdentifier;}
- (CGWindowLevel)windowLevel {return NSNormalWindowLevel;}
- (BOOL)supportsProperty:(TSMDocumentPropertyTag)property {return NO;}
- (NSString *)uniqueClientIdentifierString {return [NSString stringWithFormat:@"synthetic-%p", self];}
- (NSString *)stringFromRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    if(_contextReadFault==1){[_reads addObject:[NSValue valueWithRange:range]];unichar bad=0xD800;if(actualRange)*actualRange=NSMakeRange(range.location,1);return [NSString stringWithCharacters:&bad length:1];}
    if(range.location>0 && range.location<_view.string.length){unichar u=[_view.string characterAtIndex:range.location];if(u>=0xDC00 && u<=0xDFFF){range.location--;range.length++;}}
    NSUInteger end=range.location+range.length;
    if(end>0 && end<_view.string.length){unichar u=[_view.string characterAtIndex:end-1];if(u>=0xD800 && u<=0xDBFF)range.length++;}
    NSAttributedString *value=[self attributedSubstringFromRange:range];
    NSRange actual=value?NSMakeRange(range.location,value.length):NSMakeRange(NSNotFound,0);
    if(_contextReadFault==2)actual.location+=2;
    if(_contextReadFault==3)actual.length++;
    if(_contextReadFault==4)actual.location=NSNotFound;
    if(actualRange)*actualRange=actual;
    return value.string;
}
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    if(actualRange)*actualRange=NSMakeRange(NSNotFound,0);return NSZeroRect;
}
@end
