import Foundation
import EngineBridge
import SessionCore
import ConstraintCore

struct CaseResult:Codable {let id:String,evidence:String,passed:Bool,detail:String,milliseconds:Double}
struct Report:Codable {
    let sourceSHA:String,dictionaryRevision:String,engine:String,scope:String
    let failures:Int,results:[CaseResult]
}
enum TestFailure:Error {case assertion(String)}
func check(_ value:Bool,_ message:String) throws {if !value{throw TestFailure.assertion(message)}}
let env=ProcessInfo.processInfo.environment
let temp=FileManager.default.temporaryDirectory.appendingPathComponent("paia-a2-"+UUID().uuidString)
try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
defer{try? FileManager.default.removeItem(at:temp)}
let schemas=["full","flypy","natural"].flatMap {kind in ["paia_a2_"+kind,"paia_a2_"+kind+"_traditional"]}
let runtime=try RimeRuntime(library:env["PAIA_RIME_LIBRARY"]!,shared:env["PAIA_A2_SHARED"]!,isolatedUser:temp.path,
    dictionaryRevision:env["PAIA_A2_REVISION"]!,schemas:schemas,g01Library:env["PAIA_G01_LIBRARY"]!)
var results=[CaseResult]()
func run(_ id:String,_ body:()throws->String) {
    let start=DispatchTime.now().uptimeNanoseconds
    do {let detail=try body();results.append(CaseResult(id:id,evidence:"ENGINE_NATIVE",passed:true,detail:detail,milliseconds:Double(DispatchTime.now().uptimeNanoseconds-start)/1e6))}
    catch {results.append(CaseResult(id:id,evidence:"ENGINE_NATIVE",passed:false,detail:String(describing:error),milliseconds:Double(DispatchTime.now().uptimeNanoseconds-start)/1e6))}
}
func type(_ raw:String,_ session:InputSession) throws {
    for b in raw.utf8 {let u=try session.process(.code(Int32(b)));try check(u.commit==nil,"typing unexpectedly committed")}
}
func confirm(_ session:InputSession,_ words:[String]) throws {
    for word in words {
        let choices=try session.repairChoices(limit:512)
        guard let c=choices.first(where:{$0.anchor.text==word}) else{throw TestFailure.assertion("missing real candidate: "+word+"; observed "+choices.prefix(8).map{$0.anchor.text}.joined(separator:"|"))}
        let u=try session.selectForRepair(c);try check(u.commit==nil,"deferred selection committed")
    }
}
func commit(_ s:InputSession,_ expected:String) throws {
    let u=try s.commitEngineComposition();try check(u.commit?.text==expected,"engine commit differs: "+(u.commit?.text ?? "nil"))
    guard let effect=u.commit else{throw TestFailure.assertion("no commit effect")}
    try check(s.reserve(effect),"first reservation failed");try check(!s.reserve(effect),"duplicate effect accepted")
    try check(try s.refresh().commit==nil,"second engine commit")
}
func repairCase(id:String,raw:String,words:[String],target:Int,replacement:String,surface:String,expected:String,schema:String="paia_a1") {
    run(id){
        let s=try runtime.makeSession(schema:schema,deferredCommit:true);defer{s.end()};try type(raw,s);try confirm(s,words)
        let original=s.snapshot!.rawASCII;let anchors=try s.repairAnchors();try check(anchors.count==words.count,"unexpected anchor decomposition")
        let proposal=try s.prepareRepair(target:target,replacementRaw:replacement,surface:surface)
        try check(s.snapshot!.rawASCII==original,"trial mutated original")
        try check(proposal.preview==expected,"trial engine preview differs")
        let update=try s.applyRepair(proposal);try check(update.commit==nil,"preview emitted commit")
        try commit(s,expected)
        return "anchors=\(anchors.count); candidates examined=\(proposal.examined); real engine commit once"
    }
}
repairCase(id:"G01.front.homophone",raw:"nihaoshijieni",words:["你好","世界","你"],target:0,replacement:"nihao",surface:"拟好",expected:"拟好世界你")
repairCase(id:"G01.middle.homophone",raw:"nihaonihaoshijie",words:["你好","你好","世界"],target:1,replacement:"nihao",surface:"你号",expected:"你好你号世界")
repairCase(id:"G01.end.homophone",raw:"nihaoshijieni",words:["你好","世界","你"],target:2,replacement:"ni",surface:"泥",expected:"你好世界泥")
repairCase(id:"G01.raw.insert",raw:"nishijieni",words:["你","世界","你"],target:0,replacement:"nihao",surface:"你好",expected:"你好世界你")
repairCase(id:"G01.raw.delete",raw:"nihaoshijieni",words:["你好","世界","你"],target:0,replacement:"ni",surface:"你",expected:"你世界你")
repairCase(id:"G01.target.delete",raw:"nihaoshijieni",words:["你好","世界","你"],target:1,replacement:"",surface:"",expected:"你好你")
repairCase(id:"G01.target.resegment",raw:"nihaoshijieni",words:["你好","世界","你"],target:1,replacement:"shijieni",surface:"世界泥",expected:"你好世界泥你")
repairCase(id:"G01.unicode.grapheme",raw:"nihaoemojikuo",words:["你好","👩🏽‍💻","𠀀"],target:1,replacement:"accent",surface:"e\u{301}",expected:"你好e\u{301}𠀀")
repairCase(id:"G01.long.suffix",raw:"nihao"+String(repeating:"shijie",count:16)+"ni",words:["你好"]+Array(repeating:"世界",count:16)+["你"],target:0,replacement:"nihao",surface:"拟好",expected:"拟好"+String(repeating:"世界",count:16)+"你")
run("G01.conflict.and.budget.preserve"){
    let s=try runtime.makeSession(deferredCommit:true);defer{s.end()};try type("nihaoshijieni",s);try confirm(s,["你好","世界","你"])
    let original=s.snapshot!.rawASCII
    for (raw,surface,limit,expectedCode) in [("zz","世界",2048,20),("nihao","拟好",1,21)] {
        do{let p=try s.prepareRepair(target:1,replacementRaw:raw,surface:surface,limit:limit);p.cancel();throw TestFailure.assertion("unexpected success")}
        catch ConstraintError.native(let code,_){try check(code==Int32(expectedCode),"wrong constraint status \(code)")}
        try check(s.snapshot!.rawASCII==original,"failure mutated original")
    }
    try commit(s,"你好世界你");return "exhausted conflict distinct from incomplete; original commit retained"
}
run("G01.stale.request.target.cancel"){
    let s=try runtime.makeSession(deferredCommit:true);defer{s.end()};try type("nihaoshijieni",s);try confirm(s,["你好","世界","你"])
    let p=try s.prepareRepair(target:0,replacementRaw:"nihao",surface:"拟好")
    let newer=try s.prepareRepair(target:0,replacementRaw:"nihao",surface:"你号")
    do{_ = try s.applyRepair(p);throw TestFailure.assertion("old request accepted")}catch ConstraintError.stale{}
    p.cancel();newer.cancel()
    do{_ = try s.applyRepair(newer);throw TestFailure.assertion("cancelled trial accepted")}catch ConstraintError.consumed{}
    let pending=try s.prepareRepair(target:0,replacementRaw:"nihao",surface:"拟好")
    _ = try s.refresh()
    do{_ = try s.applyRepair(pending);throw TestFailure.assertion("late reply accepted")}catch ConstraintError.stale{}
    pending.cancel();try commit(s,"你好世界你");return "request supersession, generation change and cancellation rejected"
}
run("G01.sentence.native.decomposition"){
    let s=try runtime.makeSession(deferredCommit:true);defer{s.end()};try type("nihaoshijieni",s)
    let first=try s.repairChoices(limit:4).first!;try check(first.anchor.text=="你好世界你","fixture sentence mismatch")
    _ = try s.selectForRepair(first)
    let anchors=try s.repairAnchors();try check(anchors.count>=3,"Sentence RTTI decomposition unavailable")
    let target=try anchors.enumerated().first(where:{$0.element.text=="世界"}).map{$0.offset}.unwrap("world anchor")
    let p=try s.prepareRepair(target:target,replacementRaw:"nihao",surface:"拟好");_ = try s.applyRepair(p);try commit(s,"你好拟好你")
    return "actual Sentence components and word_lengths validated by full-raw replay"
}
// Same full corpus, native translator and task inputs for both lanes. No answer rows are added.
let vocabulary:[(String,String)]=[("daimashencha","代码审查"),("chixujicheng","持续集成"),("danyuanceshi","单元测试"),("fenbushixitong","分布式系统"),("shengchengshirengongzhineng","生成式人工智能"),("dayuyanmoxing","大语言模型")]
for (raw,expected) in vocabulary {
    run("COMPARATOR.full."+raw){
        let baseline=try runtime.makeSession(schema:"paia_a2_full");defer{baseline.end()}
        let adapted=try runtime.makeSession(schema:"paia_a2_full",deferredCommit:true);defer{adapted.end()}
        try type(raw,baseline);try type(raw,adapted)
        let a=baseline.snapshot!.rows.map{$0.text},b=adapted.snapshot!.rows.map{$0.text}
        try check(a==b,"candidate order changed between otherwise equal lanes")
        guard let rank=a.firstIndex(of:expected) else{throw TestFailure.assertion("expected term absent from first page: "+a.joined(separator:"|"))}
        return "baseline and A2 top-page identical; expected rank=\(rank+1)"
    }
}
repairCase(id:"G01.modern.full",raw:"nihaoshurufashijie",words:["你好","输入法","世界"],target:1,replacement:"daimashencha",surface:"代码审查",expected:"你好代码审查世界",schema:"paia_a2_full")
repairCase(id:"G01.modern.initials",raw:"nhsrfshijie",words:["你好","输入法","世界"],target:1,replacement:"dmsc",surface:"代码审查",expected:"你好代码审查世界",schema:"paia_a2_full")
repairCase(id:"G01.modern.flypy",raw:"nihcuurufauijp",words:["你好","输入法","世界"],target:1,replacement:"ddmaufia",surface:"代码审查",expected:"你好代码审查世界",schema:"paia_a2_flypy")
repairCase(id:"G01.modern.natural",raw:"nihkuurufauijx",words:["你好","输入法","世界"],target:1,replacement:"dlmaufia",surface:"代码审查",expected:"你好代码审查世界",schema:"paia_a2_natural")
repairCase(id:"G01.modern.traditional",raw:"nihaoshurufashijie",words:["你好","輸入法","世界"],target:1,replacement:"daimashencha",surface:"代碼審查",expected:"你好代碼審查世界",schema:"paia_a2_full_traditional")
let report=Report(sourceSHA:env["PAIA_SOURCE_SHA"] ?? "unknown",dictionaryRevision:runtime.dictionaryRevision,engine:runtime.version,
 scope:"bounded emitted-candidate replay; core-only Rime Ice; synthetic workload, no installed IME or user-quality claim",
 failures:results.filter{!$0.passed}.count,results:results)
let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];print(String(data:try encoder.encode(report),encoding:.utf8)!)
if report.failures>0 {exit(1)}
extension Optional {func unwrap(_ message:String)throws->Wrapped{guard let x=self else{throw TestFailure.assertion(message)};return x}}
