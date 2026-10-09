#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import LexiconCore

@MainActor private final class TermRowButton:NSButton {
    let term:PersonalTerm,revision:UInt64,render:UUID
    init(term:PersonalTerm,revision:UInt64,render:UUID,target:AnyObject,action:Selector){
        self.term=term;self.revision=revision;self.render=render;super.init(frame:.zero)
        title=(term.isDeleted ? "[deleted] ":term.explicitPin ? "[pinned] ":"")+term.surface+" · "+term.reading
        self.target=target;self.action=action;bezelStyle = .rounded;setAccessibilityLabel(title)
    }
    required init?(coder:NSCoder){fatalError("not used")}
}
@MainActor private final class TermActionButton:NSButton {
    let termID:UUID,revision:UInt64,render:UUID
    init(title:String,termID:UUID,revision:UInt64,render:UUID,target:AnyObject,action:Selector){
        self.termID=termID;self.revision=revision;self.render=render;super.init(frame:.zero)
        self.title=title;self.target=target;self.action=action;bezelStyle = .rounded;setAccessibilityLabel(title)
    }
    required init?(coder:NSCoder){fatalError("not used")}
}
@MainActor private final class ImportApplyButton:NSButton {
    let plan:LexiconImportPreview,render:UUID
    init(_ plan:LexiconImportPreview,render:UUID,target:AnyObject,action:Selector){
        self.plan=plan;self.render=render;super.init(frame:.zero)
        title="Apply reviewed import";self.target=target;self.action=action;bezelStyle = .rounded;isEnabled=plan.canApply;setAccessibilityLabel(title)
    }
    required init?(coder:NSCoder){fatalError("not used")}
}
@MainActor public final class PersonalLexiconController:NSObject,NSWindowDelegate,NSTextFieldDelegate {
    public let root=NSStackView(),rows=NSStackView(),actions=NSStackView(),importActions=NSStackView()
    public let surface=NSTextField(),reading=NSTextField(),aliases=NSTextField(),pin=NSButton(checkboxWithTitle:"Pin this reading",target:nil,action:nil)
    public let newButton=NSButton(),addButton=NSButton(),exportButton=NSButton(),importButton=NSButton(),cancelImportButton=NSButton(),previousButton=NSButton(),nextButton=NSButton()
    public let status=NSTextField(wrappingLabelWithString:""),importSummary=NSTextField(wrappingLabelWithString:"")
    public let previewDetails=NSTextView(frame:NSRect(x:0,y:0,width:740,height:140))
    private let store:LexiconStore,onChange:()->Void
    private weak var window:NSWindow?
    private var document=LexiconDocument(),selected:UUID?,render=UUID(),importRender:UUID?,page=0
    public private(set) var isOpen=false
    public init(store:LexiconStore,onChange:@escaping()->Void){
        self.store=store;self.onChange=onChange;super.init()
        root.orientation = .vertical;root.alignment = .leading;root.spacing=8;root.edgeInsets=NSEdgeInsets(top:16,left:16,bottom:16,right:16)
        root.addArrangedSubview(NSTextField(wrappingLabelWithString:"Only terms explicitly added/imported here are saved. Ordinary input never learns. Changes disable the personal overlay until the next launch. Deleted records remain as tombstones; public dictionary entries are unaffected."))
        rows.orientation = .vertical;rows.alignment = .leading;rows.spacing=4
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.documentView=rows
        root.addArrangedSubview(scroll);scroll.heightAnchor.constraint(equalToConstant:220).isActive=true;scroll.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-32).isActive=true
        configure(previousButton,"Previous 50",#selector(previousPage(_:)));configure(nextButton,"Next 50",#selector(nextPage(_:)))
        root.addArrangedSubview(NSStackView(views:[previousButton,nextButton]))
        for (field,label) in [(surface,"Exact term text"),(reading,"Reading codes: lowercase syllables separated by spaces"),(aliases,"Alternative readings, separated by semicolons")] {
            field.delegate=self;field.setAccessibilityLabel(label);field.widthAnchor.constraint(equalToConstant:700).isActive=true
            root.addArrangedSubview(NSTextField(labelWithString:label));root.addArrangedSubview(field)
        }
        pin.target=self;pin.action=#selector(parametersChanged(_:));pin.setAccessibilityLabel("Pin this reading");root.addArrangedSubview(pin)
        configure(newButton,"New term",#selector(newTerm(_:)));configure(addButton,"Add explicit term",#selector(addTerm(_:)))
        root.addArrangedSubview(NSStackView(views:[newButton,addButton]));root.addArrangedSubview(actions)
        configure(exportButton,"Export selected store…",#selector(exportFile(_:)));configure(importButton,"Choose import file…",#selector(importFile(_:)));configure(cancelImportButton,"Cancel import",#selector(cancelImport(_:)))
        root.addArrangedSubview(NSStackView(views:[exportButton,importButton,cancelImportButton]))
        root.addArrangedSubview(importSummary)
        previewDetails.isEditable=false;previewDetails.isRichText=false;previewDetails.autoresizingMask=[.width];previewDetails.setAccessibilityLabel("Complete import additions and conflict details")
        let detailScroll=NSScrollView();detailScroll.hasVerticalScroller=true;detailScroll.hasHorizontalScroller=true;detailScroll.documentView=previewDetails
        root.addArrangedSubview(detailScroll);detailScroll.heightAnchor.constraint(equalToConstant:120).isActive=true;detailScroll.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-32).isActive=true
        root.addArrangedSubview(importActions);root.addArrangedSubview(status)
        status.setAccessibilityLabel("Personal lexicon status");importSummary.setAccessibilityLabel("Import preview summary")
    }
    private func configure(_ button:NSButton,_ title:String,_ selector:Selector){button.title=title;button.target=self;button.action=selector;button.bezelStyle = .rounded;button.setAccessibilityLabel(title)}
    public func attach(to window:NSWindow)throws {
        self.window=window;window.contentView=root;window.delegate=self;isOpen=true
        try reload();clearForm();status.stringValue="Explicit store opened. Full/Simplified personal readings only; reading-code shape is validated, pronunciation is not inferred."
    }
    public func windowWillClose(_ notification:Notification){isOpen=false;render=UUID();cancelPreview()}
    private func reload()throws {
        document=try store.snapshot();render=UUID();page=min(page,max(0,(document.terms.count-1)/50))
        for view in rows.arrangedSubviews{rows.removeArrangedSubview(view);view.removeFromSuperview()}
        for term in document.terms.dropFirst(page*50).prefix(50){rows.addArrangedSubview(TermRowButton(term:term,revision:document.revision,render:render,target:self,action:#selector(selectTerm(_:))))}
        rows.layoutSubtreeIfNeeded();rows.setFrameSize(NSSize(width:max(700,rows.fittingSize.width),height:max(1,rows.fittingSize.height)))
        previousButton.isEnabled=page>0;nextButton.isEnabled=(page+1)*50<document.terms.count
    }
    private func clearForm(){selected=nil;surface.stringValue="";reading.stringValue="";aliases.stringValue="";pin.state = .off;addButton.isEnabled=true;clearActions();cancelPreview()}
    private func clearActions(){for view in actions.arrangedSubviews{actions.removeArrangedSubview(view);view.removeFromSuperview()}}
    private func cancelPreview(){importRender=nil;importSummary.stringValue="";previewDetails.string="";for view in importActions.arrangedSubviews{importActions.removeArrangedSubview(view);view.removeFromSuperview()}}
    private func parsedAliases()->[String]{aliases.stringValue.split(separator:";").map{String($0).trimmingCharacters(in:.whitespaces)}}
    public func controlTextDidChange(_ notification:Notification){cancelPreview()}
    @objc private func parametersChanged(_ sender:NSButton){cancelPreview()}
    @objc private func newTerm(_ sender:NSButton){guard isOpen else{return};render=UUID();clearForm();do{try reload()}catch{failed(error)}}
    @objc private func previousPage(_ sender:NSButton){guard isOpen,page>0 else{return};page-=1;clearForm();do{try reload()}catch{failed(error)}}
    @objc private func nextPage(_ sender:NSButton){guard isOpen,(page+1)*50<document.terms.count else{return};page+=1;clearForm();do{try reload()}catch{failed(error)}}
    @objc private func selectTerm(_ sender:TermRowButton){
        guard isOpen,sender.render==render,sender.revision==document.revision else{return}
        do {
            guard try store.snapshot().revision==sender.revision else{throw LexiconError.stale}
            try reload() // A new selection receives fresh immutable row/action identities.
            selected=sender.term.id;surface.stringValue=sender.term.surface;reading.stringValue=sender.term.reading;aliases.stringValue=sender.term.aliases.joined(separator:"; ");pin.state=sender.term.explicitPin ? .on:.off
            addButton.isEnabled=false;clearActions();cancelPreview()
            if !sender.term.isDeleted{actions.addArrangedSubview(TermActionButton(title:"Save explicit changes",termID:sender.term.id,revision:document.revision,render:render,target:self,action:#selector(editTerm(_:))))}
            actions.addArrangedSubview(TermActionButton(title:sender.term.isDeleted ? "Restore this term":"Delete personal contribution",termID:sender.term.id,revision:document.revision,render:render,target:self,action:#selector(toggleDeleted(_:))))
        }catch{failed(error)}
    }
    private func changed()throws {onChange();cancelPreview();try reload();clearForm();status.stringValue="Saved. Personal overlay disabled until next launch; public baseline remains available."}
    private func failed(_ error:Error){
        cancelPreview()
        switch error {
        case LexiconError.invalidEntry:status.stringValue="Invalid entry. Check text limits, lowercase reading codes and separators; nothing saved."
        case LexiconError.conflict:status.stringValue="Conflicting identity, alias or pin. Resolve it explicitly; nothing saved."
        case LexiconError.deleted:status.stringValue="A protected deletion exists. Select that record and explicitly Restore."
        case LexiconError.limit,LexiconError.overflow:status.stringValue="Store/import limit reached; nothing saved."
        default:onChange();status.stringValue="Authority changed or storage outcome is unavailable. Personal overlay disabled; reopen to verify. No automatic retry."
        }
    }
    @objc private func addTerm(_ sender:NSButton){guard isOpen,selected==nil else{return};do{_ = try store.add(surface:surface.stringValue,reading:reading.stringValue,aliases:parsedAliases(),pin:pin.state == .on,expectedRevision:document.revision);try changed()}catch{failed(error)}}
    private func current(_ sender:TermActionButton)->Bool {isOpen && sender.render==render && sender.termID==selected && sender.revision==document.revision}
    @objc private func editTerm(_ sender:TermActionButton){guard current(sender) else{return};do{try store.edit(id:sender.termID,surface:surface.stringValue,reading:reading.stringValue,aliases:parsedAliases(),pin:pin.state == .on,expectedRevision:sender.revision);try changed()}catch{failed(error)}}
    @objc private func toggleDeleted(_ sender:TermActionButton){guard current(sender),let term=document.terms.first(where:{$0.id==sender.termID}) else{return};do{try store.setDeleted(id:sender.termID,deleted:!term.isDeleted,expectedRevision:sender.revision);try changed()}catch{failed(error)}}
    public func previewSelectedFile(_ url:URL)throws {
        guard isOpen else{throw LexiconError.stale};cancelPreview()
        let plan=try store.previewImport(SelectedLexiconFile.read(url)),token=UUID();importRender=token
        importSummary.stringValue="Add \(plan.additions.count); unchanged \(plan.unchanged); protected deletions \(plan.protectedDeletions); conflicts \(plan.conflicts). Source bytes frozen for this preview."
        previewDetails.string=(plan.additions.map{($0.isDeleted ? "Add tombstone: ":$0.explicitPin ? "Add pinned: ":"Add: ")+$0.surface+" ["+$0.readings.joined(separator:"; ")+"]"}+plan.notices).joined(separator:"\n")
        previewDetails.sizeToFit()
        importActions.addArrangedSubview(ImportApplyButton(plan,render:token,target:self,action:#selector(applyImport(_:))))
    }
    public func writeSelectedExport(_ url:URL)throws {guard isOpen else{throw LexiconError.stale};try SelectedLexiconFile.write(store.exportData(),to:url);status.stringValue="Explicit export saved. It includes tombstones; keep this personal file private."}
    @objc private func cancelImport(_ sender:NSButton){cancelPreview()}
    @objc private func applyImport(_ sender:ImportApplyButton){guard isOpen,sender.render==importRender else{return};do{try store.applyImport(sender.plan);try changed()}catch{failed(error)}}
    @objc private func importFile(_ sender:NSButton){
        guard isOpen,let window=window else{return};let panel=NSOpenPanel();panel.allowedContentTypes=[.json];panel.allowsMultipleSelection=false;panel.canChooseDirectories=false;panel.resolvesAliases=false
        panel.beginSheetModal(for:window){[weak self] response in
            MainActor.assumeIsolated{guard let self=self,self.isOpen,response == .OK,let url=panel.url else{return};do{try self.previewSelectedFile(url)}catch{self.failed(error)}}
        }
    }
    @objc private func exportFile(_ sender:NSButton){
        guard isOpen,let window=window else{return};let panel=NSSavePanel();panel.allowedContentTypes=[.json];panel.nameFieldStringValue="PAIA-personal-lexicon.json"
        panel.beginSheetModal(for:window){[weak self] response in
            MainActor.assumeIsolated{guard let self=self,self.isOpen,response == .OK,let url=panel.url else{return};do{try self.writeSelectedExport(url)}catch{self.failed(error)}}
        }
    }
}
#endif
