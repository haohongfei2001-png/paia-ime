#if os(macOS)
import Foundation
import ExpressionCore
import SessionCore

// A new presentation token per query/highlight/review prevents retained controls
// from resolving themselves against a later array or mutable editor contents.
public struct ExpressionRecallState {
    public let token:UUID,query:String,rows:[ExpressionMatch],selected:Int,review:ExpressionMatch?
    let binding:ExpressionBinding,catalogEpoch:UUID
    init(query:String,rows:[ExpressionMatch],selected:Int=0,review:ExpressionMatch?=nil,binding:ExpressionBinding,catalogEpoch:UUID){
        token=UUID();self.query=query;self.rows=rows;self.selected=selected;self.review=review;self.binding=binding;self.catalogEpoch=catalogEpoch
    }
}
#endif
