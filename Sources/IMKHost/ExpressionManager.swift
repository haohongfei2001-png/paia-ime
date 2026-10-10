#if os(macOS)
import AppKit
import ExpressionCore

// Only manually entered/pasted editor text is saved. Never reads a client, clipboard
// service, previous commit, screen or message provider to populate this editor.
@MainActor public final class ExpressionManager:NSObject,NSWindowDelegate {
    public let root=NSView(),editor=NSTextView(),aliases=NSTextField(),records=NSPopUpButton(frame:.zero,pullsDown:false),status=NSTextField(wrappingLabelWithString:"")
    public let save=NSButton(),delete=NSButton(),verify=NSButton()
    public private(set) var selected:ExpressionRecord?,document:ExpressionDocument?,isOpen=false
    private let workspace:IMKWorkspace
    private var window:NSWindow?,recordList=[ExpressionRecord](),selectionStale=false
    private enum PendingAction {case save,delete}
    private var pendingAction:PendingAction?
    private var hasPending:Bool {workspace.expressionStore?.hasUnverifiedSave==true}
    public init(workspace:IMKWorkspace){
        self.workspace=workspace;super.init()
        root.frame=NSRect(x:0,y:0,width:760,height:600)
        let help=NSTextField(wrappingLabelWithString:"Exact local expressions. Enter or paste the complete text yourself, then Save explicitly. Ordinary typing never saves it. Manual saves are not sent messages.")
        help.frame=NSRect(x:20,y:530,width:720,height:50);root.addSubview(help)
        records.frame=NSRect(x:20,y:482,width:570,height:32);records.target=self;records.action=#selector(selectRecord(_:));root.addSubview(records)
        let fresh=NSButton(title:"New expression",target:self,action:#selector(newRecord(_:)));fresh.frame=NSRect(x:600,y:482,width:140,height:32);root.addSubview(fresh)
        let scroll=NSScrollView(frame:NSRect(x:20,y:180,width:720,height:290));scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder
        editor.frame=NSRect(origin:.zero,size:scroll.contentSize);editor.isRichText=false;editor.font = .systemFont(ofSize:16);editor.isVerticallyResizable=true;editor.isHorizontallyResizable=false
        editor.autoresizingMask=[.width];editor.textContainer?.widthTracksTextView=true;editor.textContainer?.containerSize=NSSize(width:scroll.contentSize.width,height:CGFloat.greatestFiniteMagnitude)
        editor.isAutomaticQuoteSubstitutionEnabled=false;editor.isAutomaticDashSubstitutionEnabled=false;editor.isAutomaticTextReplacementEnabled=false;editor.isAutomaticSpellingCorrectionEnabled=false
        editor.setAccessibilityLabel("Complete exact expression, explicit save only");scroll.documentView=editor;root.addSubview(scroll)
        aliases.frame=NSRect(x:20,y:140,width:720,height:28);aliases.placeholderString="Optional lookup aliases / pinyin, separated by commas (up to 8)";aliases.setAccessibilityLabel("Lookup aliases");root.addSubview(aliases)
        let buttons=[(save,"Save exact text",#selector(saveAction(_:))),(delete,"Delete selected",#selector(deleteAction(_:))),(verify,"Verify last save",#selector(verifyAction(_:)))]
        for (i,tuple) in buttons.enumerated(){let(button,title,action)=tuple;button.title=title;button.bezelStyle = .rounded;button.target=self;button.action=action;button.frame=NSRect(x:20+CGFloat(i)*185,y:92,width:175,height:32);root.addSubview(button)}
        status.frame=NSRect(x:20,y:18,width:720,height:64);root.addSubview(status)
    }
    public func show(){
        guard workspace.isIdle,workspace.expressionStore != nil else{return}
        if window==nil {let w=NSWindow(contentRect:root.bounds,styleMask:[.titled,.closable],backing:.buffered,defer:false);w.isReleasedWhenClosed=false;w.title="Exact local expressions · Explicit save";w.contentView=root;w.delegate=self;window=w}
        isOpen=true
        do{try workspace.reloadExpressions();reload();status.stringValue="Save is explicit. Recall with Option+Space when idle and delivered to this input method."}
        catch{document=nil;status.stringValue="Saved-expression authority unavailable. Draft retained; no automatic overwrite or retry."}
        if selectionStale{status.stringValue="Selected record changed. Draft kept without rebasing. Choose a current record or explicitly start New."}
        refreshControls();window?.makeKeyAndOrderFront(nil)
    }
    private func reload(){document=workspace.expressionCatalog?.document;recordList=(document?.records ?? []).filter{$0.deletedAt==nil};records.removeAllItems();records.addItem(withTitle:"Choose an existing expression or New")
        for r in recordList{records.addItem(withTitle:String((r.exactText ?? "").prefix(72)).replacingOccurrences(of:"\n",with:" ↵ "))}
        selectionStale=false
        if let old=selected {
            if let index=recordList.firstIndex(where:{$0.id==old.id}){selectionStale=recordList[index].revision != old.revision;records.selectItem(at:index+1)}
            else{selectionStale=true;records.selectItem(at:0)}
        }else{records.selectItem(at:0)}
    }
    public func refreshControls(){let idle=isOpen && workspace.isIdle,pending=hasPending
        save.isEnabled=idle && !pending && !selectionStale && workspace.expressionCatalog != nil
        delete.isEnabled=idle && !pending && !selectionStale && selected != nil && workspace.expressionCatalog != nil
        verify.isEnabled=idle && pending;editor.isEditable=idle && !pending;aliases.isEnabled=idle && !pending;records.isEnabled=idle && !pending
    }
    @objc public func newRecord(_ sender:Any?){guard isOpen,workspace.isIdle,!hasPending else{return};selected=nil;selectionStale=false;editor.string="";aliases.stringValue="";records.selectItem(at:0);refreshControls()}
    @objc public func selectRecord(_ sender:Any?){guard isOpen,workspace.isIdle,!hasPending else{return};let index=records.indexOfSelectedItem-1;guard recordList.indices.contains(index) else{return};selected=recordList[index];selectionStale=false;editor.string=selected?.exactText ?? "";aliases.stringValue=selected?.aliases.joined(separator:", ") ?? "";refreshControls()}
    @objc public func saveAction(_ sender:Any?){
        guard isOpen,workspace.isIdle,!hasPending,!selectionStale else{return}
        let list=aliases.stringValue.isEmpty ? []:aliases.stringValue.components(separatedBy:",").map{$0.trimmingCharacters(in:.whitespaces)}
        pendingAction = .save
        do{let next=try workspace.saveExpression(editor.string,aliases:list,editing:selected?.id,recordRevision:selected?.revision,catalogRevision:document?.revision ?? 0)
            selected=next.records.first(where:{$0.revision==next.revision});pendingAction=nil;reload();status.stringValue="Exact text saved locally. Sent time remains unknown. No host text was changed."}
        catch{if !hasPending{pendingAction=nil};status.stringValue="Save not confirmed or rejected. Draft retained. Use Verify last save if available; do not assume it was not saved."}
        refreshControls()
    }
    @objc public func deleteAction(_ sender:Any?){
        guard isOpen,workspace.isIdle,!hasPending,!selectionStale,let record=selected else{return}
        pendingAction = .delete
        do{_ = try workspace.deleteExpression(record,catalogRevision:document?.revision ?? 0);pendingAction=nil;selected=nil;editor.string="";aliases.stringValue="";reload();status.stringValue="Deleted text removed from the current store. Revision tombstone retained; filesystem backups are not erased."}
        catch{if !hasPending{pendingAction=nil};status.stringValue="Deletion unconfirmed or rejected. No automatic retry."};refreshControls()
    }
    @objc public func verifyAction(_ sender:Any?){
        guard isOpen,workspace.isIdle,hasPending else{return}
        do{let result=try workspace.verifyExpressionSave()
            var unresolvedEditor=false
            if result.resolution == .published {
                if pendingAction == .delete{selected=nil;editor.string="";aliases.stringValue=""}
                else if pendingAction == .save,let id=result.attemptedRecordID,let saved=result.document?.records.first(where:{$0.id==id && $0.deletedAt==nil}) {
                    selected=saved;editor.string=saved.exactText ?? "";aliases.stringValue=saved.aliases.joined(separator:", ")
                }else{unresolvedEditor=true}
            }
            pendingAction=nil;reload();selectionStale = selectionStale || unresolvedEditor;status.stringValue=result.resolution == .published ? "Last operation is published. Editor reconciled to that record; nothing was reapplied.":"Previous state verified. The unsaved draft is still here; nothing was reapplied."
        }
        catch{status.stringValue="Authority still unresolved. No write or retry was performed."};refreshControls()
    }
    public func windowDidBecomeKey(_ notification:Notification){refreshControls()}
    public func windowWillClose(_ notification:Notification){isOpen=false;refreshControls()}
    public func close(){window?.close();editor.string="";aliases.stringValue="";selected=nil}
}
#endif
