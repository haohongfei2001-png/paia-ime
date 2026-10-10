#if os(macOS)
import Foundation
import EngineBridge
import ConstraintCore
import SessionCore

// Menu callbacks retain this exact issuing target, never whatever is active later.
public struct RetainedMenuAction {
    let driverGeneration:UInt64,activation:UInt64,session:SessionKey,inputGeneration:UInt64
    let arm:Bool
}
@MainActor public final class SegmentRepairState {
    public let token=UUID(),target:RepairTarget,original:String,replacementRaw:String,caret:Int
    public let rows:[RepairAlternative],complete:Bool,selected:Int,searched:Bool,notice:String?
    public let proposal:RepairProposal?
    public var page:Int {selected/5}
    public var visibleRows:ArraySlice<RepairAlternative> {rows.dropFirst(page*5).prefix(5)}
    public init(target:RepairTarget,original:String,replacementRaw:String,caret:Int?=nil,rows:[RepairAlternative]=[],complete:Bool=false,selected:Int=0,searched:Bool=false,notice:String?=nil,proposal:RepairProposal?=nil){
        self.target=target;self.original=original;self.replacementRaw=replacementRaw;self.caret=caret ?? replacementRaw.utf8.count
        self.rows=rows;self.complete=complete;self.selected=selected;self.searched=searched;self.notice=notice;self.proposal=proposal
    }
}
#endif
