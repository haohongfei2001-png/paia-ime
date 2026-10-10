#if os(macOS)
import XCTest
import AppKit
import NativeHost
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
        XCTAssertTrue(screen.contains(panel.frame),"Candidate panel exceeds supplied safe screen")
        let view=try XCTUnwrap(panel.contentView)
        for button in try buttons(panel) {
            // Measure every glyph at the actual available row width, not its unbounded intrinsic width.
            let width=min(button.bounds.width,view.bounds.width-24)
            let needed=button.attributedTitle.boundingRect(with:NSSize(width:width,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading]).height
            XCTAssertLessThanOrEqual(button.bounds.width,view.bounds.width-24,"Candidate row horizontally clipped")
            XCTAssertGreaterThanOrEqual(button.bounds.height,ceil(needed),"Candidate title cannot show all wrapped lines")
        }
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
        w.isReleasedWhenClosed=false;try c.attach(to:w);w.orderFront(nil);w.makeKey();XCTAssertTrue(w.makeFirstResponder(c.editor));defer{w.close()}
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
        XCTAssertTrue(w.firstResponder===c.editor);XCTAssertEqual(host.insertCount,0)
        try key(" ",c.editor,code:49);XCTAssertEqual(c.editor.string,term);XCTAssertEqual(host.insertCount,1)
        selected.performClick(nil);XCTAssertEqual(c.editor.string,term);XCTAssertEqual(host.insertCount,1)
        XCTAssertTrue(w.firstResponder===c.editor);XCTAssertFalse(panel.isVisible)
        print("B6_ENGINE_NATIVE authored long term from real librime; APPKIT_HOST safe-screen layout and once-only engine commit")
    }
    @MainActor func testSimulatedNarrowShortAndNegativeOriginScreens()throws {
        _=NSApplication.shared
        var core=SessionCore(dictionaryRevision:"b6-simulated-geometry")
        let text=[String(repeating:"長𠀀e\u{301}👩🏽‍💻",count:20),"第二候選",String(repeating:"尾部完整",count:20)]
        let snapshot=try XCTUnwrap(core.receive(EngineValue(raw:"shi",preedit:"shi",caretUTF8:3,candidates:text,page:2,highlighted:2,hasMore:false)).snapshot)
        let panel=CandidatePanel();defer{panel.orderOut(nil)}
        for screen in [NSRect(x:0,y:0,width:180,height:140),NSRect(x:-900,y:-400,width:320,height:160),NSRect(x:500,y:800,width:640,height:300)] {
            panel.show(snapshot,below:NSRect(x:screen.maxX-10,y:screen.minY+10,width:5,height:20),screen:screen)
            try assertReadable(panel,screen:screen)
            let rows=try buttons(panel);XCTAssertEqual(rows.count,text.count)
            for i in text.indices{XCTAssertTrue(rows[i].title.hasSuffix(text[i]))}
            XCTAssertTrue(rows[2].title.hasPrefix("▶ "))
        }
        print("B6_SIMULATED supplied screen rectangles, not physical multi-display evidence")
    }
}
#endif
