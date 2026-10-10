#if os(macOS)
import XCTest
import AppKit
@testable import NativeHost
import EngineBridge
import SessionCore
import LexiconCore

final class CandidateOverflowTests:XCTestCase {
    @MainActor func descendants(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap{descendants($0)}}
    @MainActor func buttons(_ panel:CandidatePanel)throws->[NSButton] {descendants(try XCTUnwrap(panel.contentView)).compactMap{$0 as? NSButton}.sorted{$0.tag<$1.tag}}
    @MainActor func key(_ text:String,_ view:NSTextView,code:UInt16=0)throws {
        view.keyDown(with:try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:view.window?.windowNumber ?? 0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code)))
    }
    @MainActor func capture(_ panel:CandidatePanel,name:String)throws {
        let view=try XCTUnwrap(panel.contentView);view.layoutSubtreeIfNeeded();view.displayIfNeeded()
        let bitmap=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds));view.cacheDisplay(in:view.bounds,to:bitmap)
        let data=try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
        let directory=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("evidence/b6-run")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);try data.write(to:directory.appendingPathComponent(name+".png"))
        let encoded=data.base64EncodedString();var offset=encoded.startIndex,index=0
        while offset<encoded.endIndex{let end=encoded.index(offset,offsetBy:3000,limitedBy:encoded.endIndex) ?? encoded.endIndex;FileHandle.standardError.write(Data(("PAIA_B6_\(name)_IMAGE_\(index):"+encoded[offset..<end]+"\n").utf8));offset=end;index+=1}
    }
    @MainActor func assertReadable(_ panel:CandidatePanel,screen:NSRect)throws {
        XCTAssertTrue(panel.isVisible,"Valid screen must display candidates")
        XCTAssertTrue(screen.contains(panel.frame),"Candidate panel exceeds supplied safe screen")
        let view=try XCTUnwrap(panel.contentView)
        let scroll=try XCTUnwrap(descendants(view).compactMap{$0 as? NSScrollView}.first)
        XCTAssertGreaterThanOrEqual(scroll.contentSize.height,24);XCTAssertFalse(scroll.hasHorizontalScroller)
        for button in try buttons(panel) {
            // Measure every glyph at the actual available row width, not its unbounded intrinsic width.
            let width=min(button.bounds.width,view.bounds.width-24)
            let needed=button.attributedTitle.boundingRect(with:NSSize(width:width,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading]).height
            XCTAssertLessThanOrEqual(button.bounds.width,view.bounds.width-24,"Candidate row horizontally clipped")
            XCTAssertGreaterThanOrEqual(button.bounds.height,ceil(needed),"Candidate title cannot show all wrapped lines")
            XCTAssertLessThanOrEqual(button.bounds.width,scroll.contentSize.width)
            let row=try XCTUnwrap(button as? CandidateButton),layout=row.textLayout
            XCTAssertEqual(layout.storage.string,button.title)
            XCTAssertEqual(layout.manager.characterRange(forGlyphRange:layout.glyphs,actualGlyphRange:nil),NSRange(location:0,length:button.title.utf16.count))
            XCTAssertGreaterThanOrEqual(button.bounds.height,layout.height+8)
            layout.manager.enumerateLineFragments(forGlyphRange:layout.glyphs){_,used,_,_,_ in
                XCTAssertLessThanOrEqual(used.maxX,layout.container.size.width+0.5,"Rendered glyphs horizontally clipped")
            }
        }
        let label=try XCTUnwrap(descendants(view).compactMap{$0 as? NSTextField}.first)
        XCTAssertTrue(view.bounds.contains(label.frame));XCTAssertFalse(label.frame.intersects(scroll.frame))
        let footerHeight=try XCTUnwrap(label.cell).cellSize(forBounds:NSRect(x:0,y:0,width:label.bounds.width,height:10000)).height
        XCTAssertGreaterThanOrEqual(label.bounds.height,ceil(footerHeight),"Page/scroll status clipped")
    }
    @MainActor func revealTail(_ panel:CandidatePanel,index:Int)throws {
        let view=try XCTUnwrap(panel.contentView),scroll=try XCTUnwrap(descendants(view).compactMap{$0 as? NSScrollView}.first)
        let row=try XCTUnwrap(try buttons(panel).first{$0.tag==index} as? CandidateButton)
        let glyph=NSRange(location:row.textLayout.glyphs.upperBound-1,length:1)
        let last=row.textLayout.manager.boundingRect(forGlyphRange:glyph,in:row.textLayout.container).offsetBy(dx:4,dy:4)
        let target=row.frame.minY+last.maxY-scroll.contentSize.height
        scroll.contentView.scroll(to:NSPoint(x:0,y:min(max(0,target),max(0,try XCTUnwrap(scroll.documentView).frame.height-scroll.contentSize.height))))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertLessThanOrEqual(row.visibleRect.minY,last.minY+0.5);XCTAssertGreaterThanOrEqual(row.visibleRect.maxY,last.maxY-0.5)
        XCTAssertGreaterThan(row.visibleRect.width,0)
    }
    @MainActor func testRealLongPersonalCandidateIsReadableAndCommitsThroughEngineOnce()throws {
        _=NSApplication.shared
        // Authored synthetic term, deliberately reachable via the existing explicit B2 authority.
        // This proves presentation/selection, not accuracy or discovery of an unknown rare word.
        let term="首"+String(repeating:"長詞測試",count:18)+"𠀀e\u{301}👩🏽‍💻尾"
        XCTAssertLessThanOrEqual(term.count,80)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("paia-b6-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let store=try LexiconStore(directory:root)
        _ = try store.add(surface:term,reading:"qiong hai ce li jia",pin:true,expectedRevision:0);store.close()
        var variables=ProcessInfo.processInfo.environment;variables["PAIA_B2_RESEARCH"]="1";variables["PAIA_B2_STORE"]=root.path
        let environment=try PersonalLabEnvironment(environment:variables)
        defer{environment.store?.close();_ = environment.runtime.close()}
        let c=NativeLabController(runtime:environment.runtime,configuredSession:{try environment.makeSession(configuration:$0)})
        let w=LabWindow(contentRect:NSRect(x:0,y:0,width:1040,height:720),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        w.isReleasedWhenClosed=false;try c.attach(to:w)
        XCTAssertTrue(NSApp.setActivationPolicy(.regular));NSApp.finishLaunching();NSApp.activate(ignoringOtherApps:true)
        w.makeKeyAndOrderFront(nil);XCTAssertTrue(w.makeFirstResponder(c.editor));defer{w.close()}
        for _ in 0..<20 {if w.isKeyWindow{break};RunLoop.current.run(until:Date(timeIntervalSinceNow:0.05))}
        XCTAssertTrue(w.isKeyWindow,"Establish an active synthetic host before testing retained key ownership")
        for character in "qionghaicelijia" {try key(String(character),c.editor)}
        let host=try XCTUnwrap(c.editor.dispatcher)
        var found=false
        for _ in 0..<200 {
            let snapshot=try XCTUnwrap(host.session.snapshot)
            if let index=snapshot.rows.firstIndex(where:{$0.text==term}) {
                for _ in 0..<snapshot.rows.count {
                    if host.session.snapshot?.highlighted==index{break};try key("\u{F701}",c.editor,code:125)
                }
                found=true;break
            }
            if !snapshot.hasMore{break};try key("\u{F72D}",c.editor,code:121)
        }
        XCTAssertTrue(found,"Real engine must return authored long candidate")
        let snapshot=try XCTUnwrap(host.session.snapshot);XCTAssertEqual(snapshot.rows[snapshot.highlighted].text,term)
        let panel=c.editor.candidates,screen=NSRect(x:-500,y:20,width:360,height:200)
        panel.show(snapshot,below:NSRect(x:-450,y:40,width:80,height:20),screen:screen)
        let selected=try XCTUnwrap(try buttons(panel).first{$0.tag==snapshot.highlighted})
        XCTAssertGreaterThan(selected.attributedTitle.size().width,616)
        try capture(panel,name:"long-engine");try assertReadable(panel,screen:screen)
        let small=NSRect(x:-500,y:20,width:180,height:140),anchor=NSRect(x:-490,y:30,width:80,height:20)
        panel.show(snapshot,below:anchor,screen:small);try assertReadable(panel,screen:small)
        let scroll=try XCTUnwrap(descendants(try XCTUnwrap(panel.contentView)).compactMap{$0 as? NSScrollView}.first)
        let start=try XCTUnwrap(try buttons(panel).first{$0.tag==snapshot.highlighted})
        XCTAssertGreaterThan(start.frame.height,scroll.contentSize.height)
        XCTAssertEqual(start.visibleRect.minY,0,accuracy:0.5)
        try capture(panel,name:"long-engine-start");try revealTail(panel,index:snapshot.highlighted)
        try capture(panel,name:"long-engine-tail")
        let offset=scroll.contentView.bounds.origin.y
        panel.show(snapshot,below:anchor,screen:small)
        let rerendered=try XCTUnwrap(descendants(try XCTUnwrap(panel.contentView)).compactMap{$0 as? NSScrollView}.first)
        XCTAssertEqual(rerendered.contentView.bounds.origin.y,offset,accuracy:0.5)
        XCTAssertEqual(host.session.snapshot?.inputGeneration,snapshot.inputGeneration)
        XCTAssertTrue(w.isKeyWindow);XCTAssertFalse(panel.isKeyWindow)
        XCTAssertTrue(w.firstResponder===c.editor);XCTAssertEqual(host.insertCount,0)
        try key(" ",c.editor,code:49);XCTAssertEqual(c.editor.string,term);XCTAssertEqual(host.insertCount,1)
        selected.performClick(nil);XCTAssertEqual(c.editor.string,term);XCTAssertEqual(host.insertCount,1)
        XCTAssertTrue(w.firstResponder===c.editor);XCTAssertFalse(panel.isVisible)
        // A fresh real composition also commits through the visible button, never through title text.
        for character in "qionghaicelijia"{try key(String(character),c.editor)}
        let current=try XCTUnwrap(host.session.snapshot),index=try XCTUnwrap(current.rows.firstIndex{$0.text==term})
        let click=try XCTUnwrap(try buttons(panel).first{$0.tag==index})
        click.performClick(nil);XCTAssertEqual(c.editor.string,term+term);XCTAssertEqual(host.insertCount,2)
        click.performClick(nil);XCTAssertEqual(host.insertCount,2);XCTAssertTrue(w.firstResponder===c.editor);XCTAssertTrue(w.isKeyWindow)
        print("B6_ENGINE_NATIVE real authored long candidate; APPKIT_HOST layout, scroll and once-only selection assertions executed")
    }
    @MainActor func testSimulatedNarrowShortAndNegativeOriginScreens()throws {
        _=NSApplication.shared
        var core=SessionCore(dictionaryRevision:"b6-simulated-geometry")
        let text=[String(repeating:"長𠀀e\u{301}👩🏽‍💻",count:20),"第二候選",String(repeating:"尾部完整",count:20)]
        let snapshot=try XCTUnwrap(core.receive(EngineValue(raw:"shi",preedit:"shi",caretUTF8:3,candidates:text,page:2,highlighted:2,hasMore:false)).snapshot)
        let panel=CandidatePanel();defer{panel.orderOut(nil)}
        for screen in [NSRect(x:0,y:0,width:120,height:180),NSRect(x:0,y:0,width:180,height:140),NSRect(x:-900,y:-400,width:320,height:160),NSRect(x:500,y:800,width:640,height:300)] {
            panel.show(snapshot,below:NSRect(x:screen.maxX-10,y:screen.minY+10,width:5,height:20),screen:screen)
            try assertReadable(panel,screen:screen)
            let rows=try buttons(panel);XCTAssertEqual(rows.count,text.count)
            for i in text.indices{XCTAssertTrue(rows[i].title.hasSuffix(text[i]))}
            XCTAssertTrue(rows[2].title.hasPrefix("▶ "))
            try revealTail(panel,index:2)
            if screen.width==120{try capture(panel,name:"narrow-footer")}
        }
        print("B6_SIMULATED supplied screen rectangles, not physical multi-display evidence")
    }
    @MainActor func testFullTextLayoutAndStableHighlightGeometry()throws {
        _=NSApplication.shared
        let text=[String(repeating:"unbrokensyntheticASCII",count:10),String(repeating:"spaced English words ",count:12),"首行\n"+String(repeating:"𠀀e\u{301}👩🏽‍💻",count:25)+"\n尾行"]
        var core=SessionCore(dictionaryRevision:"b6-simulated-text-layout")
        let panel=CandidatePanel();defer{panel.orderOut(nil)}
        let screen=NSRect(x:-700,y:-500,width:320,height:220),anchor=NSRect(x:-400,y:-300,width:5,height:18)
        var frames:[NSRect]?,size:NSSize?
        for turn in 0..<18 {
            let index=turn%text.count
            let snapshot=try XCTUnwrap(core.receive(EngineValue(raw:"shi",preedit:"shi",caretUTF8:3,candidates:text,highlighted:index)).snapshot)
            panel.show(snapshot,below:anchor,screen:screen);try assertReadable(panel,screen:screen)
            let rows=try buttons(panel),current=rows.map{$0.frame}
            if let frames=frames,let size=size{XCTAssertEqual(current,frames);XCTAssertEqual(panel.frame.size,size)}else{frames=current;size=panel.frame.size}
            for i in text.indices{XCTAssertEqual(rows[i].accessibilityLabel(),"Candidate \(i+1), \(text[i])");XCTAssertTrue(rows[i].title.hasSuffix(text[i]))}
            let scroll=try XCTUnwrap(descendants(try XCTUnwrap(panel.contentView)).compactMap{$0 as? NSScrollView}.first)
            if rows[index].frame.height>scroll.contentSize.height {
                XCTAssertEqual(scroll.contentView.bounds.origin.y,rows[index].frame.minY,accuracy:0.5)
            } else {XCTAssertEqual(rows[index].visibleRect.intersection(rows[index].bounds),rows[index].bounds)}
            try revealTail(panel,index:index)
            if turn==2{try capture(panel,name:"unicode-tail")}
        }
    }
    @MainActor func testUnusableGeometryHidesInsteadOfShowingStaleCandidates()throws {
        _=NSApplication.shared
        var core=SessionCore(dictionaryRevision:"b6-simulated-invalid-geometry")
        let snapshot=try XCTUnwrap(core.receive(EngineValue(raw:"a",preedit:"a",caretUTF8:1,candidates:["候選"])).snapshot)
        let panel=CandidatePanel();defer{panel.orderOut(nil)}
        let valid=NSRect(x:0,y:0,width:800,height:600),anchor=NSRect(x:10,y:30,width:10,height:18)
        for invalid in [NSRect.zero,NSRect(x:0,y:0,width:80,height:80),NSRect(x:0,y:0,width:180,height:10),NSRect(x:0,y:0,width:CGFloat.infinity,height:500)] {
            panel.show(snapshot,below:anchor,screen:valid);XCTAssertTrue(panel.isVisible)
            panel.show(snapshot,below:anchor,screen:invalid);XCTAssertFalse(panel.isVisible)
        }
        panel.show(snapshot,below:NSRect(x:CGFloat.nan,y:0,width:1,height:18),screen:valid);XCTAssertFalse(panel.isVisible)
        let empty=try XCTUnwrap(core.receive(EngineValue(raw:"",preedit:"",caretUTF8:0)).snapshot)
        panel.show(empty,below:anchor,screen:valid);XCTAssertFalse(panel.isVisible)
    }

}
#endif
