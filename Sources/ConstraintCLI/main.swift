import Foundation
import EngineBridge
import SessionCore
import ConstraintCore

struct CaseResult:Codable {let id:String,evidence:String,passed:Bool,detail:String,milliseconds:Double}
struct Report:Codable {
    let sourceSHA:String,dictionaryRevision:String,engine:String,scope:String
    let startupMilliseconds:Double,failures:Int,results:[CaseResult],benchmarks:[BenchmarkResult]
}
struct BenchmarkResult:Codable {let lane:String,samples:Int,failures:Int,p50:Double,p95:Double,p99:Double,max:Double,latenciesMilliseconds:[Double]}
enum TestFailure:Error {case assertion(String)}
func check(_ value:Bool,_ message:String) throws {if !value{throw TestFailure.assertion(message)}}
let env=ProcessInfo.processInfo.environment
let startupBegin=DispatchTime.now().uptimeNanoseconds
let temp=FileManager.default.temporaryDirectory.appendingPathComponent("paia-a2-"+UUID().uuidString)
let schemas=["full","flypy","natural"].flatMap {kind in ["paia_a2_"+kind,"paia_a2_"+kind+"_traditional"]}+["paia_a2_filter"]
let runtime:RimeRuntime
func required(_ key:String)throws->String{guard let value=env[key],!value.isEmpty else{throw TestFailure.assertion("missing environment "+key)};return value}
do {
    try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
    runtime=try RimeRuntime(library:required("PAIA_RIME_LIBRARY"),shared:required("PAIA_A2_SHARED"),isolatedUser:temp.path,
        dictionaryRevision:required("PAIA_A2_REVISION"),schemas:schemas,g01Library:required("PAIA_G01_LIBRARY"))
} catch {
    let fatal=["evidence":"ENGINE_NATIVE","startupFailure":String(describing:error),"sourceSHA":env["PAIA_SOURCE_SHA"] ?? "unknown"]
    print(String(data:try JSONEncoder().encode(fatal),encoding:.utf8)!);exit(1)
}
let startupMilliseconds=Double(DispatchTime.now().uptimeNanoseconds-startupBegin)/1e6
defer{try? FileManager.default.removeItem(at:temp)}
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
        let choices=try session.repairChoices(limit:512).rows
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
        let original=s.snapshot!.rawASCII;let anchors=try s.repairAnchors().rows;try check(anchors.count==words.count,"unexpected anchor decomposition")
        let proposal=try s.prepareRepair(target:try s.repairAnchors().targets[target],replacementRaw:replacement,surface:surface)
        try check(s.snapshot!.rawASCII==original,"trial mutated original")
        try check(proposal.preview==expected,"trial engine preview differs")
        let update=try s.applyRepair(proposal);try check(update.commit==nil,"preview emitted commit")
        try commit(s,expected)
        return "anchors=\(anchors.count); candidates examined=\(proposal.examined); real engine commit once"
    }
    run(id+".issued-alternatives") {
        let s=try runtime.makeSession(schema:schema,deferredCommit:true);defer{s.end()};try type(raw,s);try confirm(s,words)
        let before=s.snapshot!,targetRef=try s.repairAnchors().targets[target]
        let choices=try s.repairAlternatives(target:targetRef,replacementRaw:replacement)
        guard let choice=choices.rows.first(where:{$0.surface.utf8.elementsEqual(surface.utf8) && $0.preview.utf8.elementsEqual(expected.utf8)}) else {
            throw TestFailure.assertion("issued expected choice absent; status=\(choices.status), complete=\(choices.complete), examined=\(choices.examined), rows="+choices.rows.prefix(8).map{$0.surface}.joined(separator:"|"))
        }
        try check(s.snapshot!.inputGeneration==before.inputGeneration && s.snapshot!.rawASCII==before.rawASCII,"enumeration mutated source")
        let proposal=try s.prepareAlternative(choice)
        try check(proposal.preview.utf8.elementsEqual(expected.utf8),"issued preview changed")
        let update=try s.applyRepair(proposal);try check(update.commit==nil,"alternative apply committed")
        try commit(s,expected)
        return "native issued rows=\(choices.rows.count), complete=\(choices.complete), examined=\(choices.examined); prepared exact displayed preview and engine committed once"
    }
}
run("G01.explicit-idle-arm-capability") {
    let s=try runtime.makeSession();defer{s.end()};_ = try s.refresh()
    try check(s.canRetainForRepair && !s.supportsRepair,"loaded capability confused with retained state")
    let binding=s.idleExpressionBinding!;let armed=try s.beginRetained(binding:binding)
    try check(armed.commit==nil && s.supportsRepair && s.isRetainedComposition,"arm did not remain idle")
    do{_ = try s.beginRetained(binding:binding);throw TestFailure.assertion("duplicate arm accepted")}catch ConstraintError.stale{}
    try type("nihao",s);let before=s.snapshot!
    for key:Int32 in [44,46,58,65,33] {let u=try s.process(.code(key));try check(u.commit==nil && u.refusal != nil && s.snapshot!.inputGeneration==before.inputGeneration,"retained punctuation mutated engine")}
    try confirm(s,["你好"]);try check(s.snapshot!.rawASCII=="nihao","retained confirmation lost raw")
    try commit(s,"你好")
    return "idle-only same-session arm; no resources loaded; unsupported punctuation refused before mutation"
}
run("G01.alternatives-bounds-and-stale") {
    let s=try runtime.makeSession(deferredCommit:true);defer{s.end()};try type("nihaoshijieni",s);try confirm(s,["你好","世界","你"])
    let before=s.snapshot!
    let one=try s.repairAlternatives(target:try s.repairAnchors().targets[0],replacementRaw:"nihao",limit:1)
    try check(!one.complete && one.status==21 && one.rows.isEmpty,"work exhaustion disguised as conflict")
    let partial=try s.repairAlternatives(target:try s.repairAnchors().targets[0],replacementRaw:"nihao",maxRows:1)
    try check(!partial.complete && partial.status==21 && partial.rows.count==1,"row-limited result not honestly partial")
    let stale=partial.rows[0]
    let next=try s.repairAlternatives(target:partial.target,replacementRaw:"nihao")
    do{_ = try s.prepareAlternative(stale);throw TestFailure.assertion("old list accepted")}catch ConstraintError.stale{}
    try check(!next.rows.isEmpty,"replacement query empty")
    s.invalidateRepairActions()
    do{_ = try s.prepareAlternative(next.rows[0]);throw TestFailure.assertion("cancelled choice accepted")}catch ConstraintError.stale{}
    let conflict=try s.repairAlternatives(target:try s.repairAnchors().targets[1],replacementRaw:"zz")
    try check(conflict.complete && conflict.status==20 && conflict.rows.isEmpty,"fixture invalid spelling did not exhaust to conflict")
    try check(s.snapshot!.rawASCII==before.rawASCII && s.snapshot!.inputGeneration==before.inputGeneration,"failed/search/cancel changed source")
    try commit(s,"你好世界你")
    return "work=1 incomplete; one usable partial row; old/cancelled rows stale; candidate-free zz conflict; source unchanged"
}
repairCase(id:"G01.front.homophone",raw:"nihaoshijieni",words:["你好","世界","你"],target:0,replacement:"nihao",surface:"拟好",expected:"拟好世界你")
repairCase(id:"G01.middle.homophone",raw:"nihaonihaoshijie",words:["你好","你好","世界"],target:1,replacement:"nihao",surface:"你号",expected:"你好你号世界")
repairCase(id:"G01.end.homophone",raw:"nihaoshijieni",words:["你好","世界","你"],target:2,replacement:"ni",surface:"泥",expected:"你好世界泥")
repairCase(id:"G01.raw.insert",raw:"nishijieni",words:["你","世界","你"],target:0,replacement:"nihao",surface:"你好",expected:"你好世界你")
repairCase(id:"G01.raw.delete",raw:"nihaoshijieni",words:["你好","世界","你"],target:0,replacement:"ni",surface:"你",expected:"你世界你")
repairCase(id:"G01.target.delete",raw:"nihaoshijieni",words:["你好","世界","你"],target:1,replacement:"",surface:"",expected:"你好你")
repairCase(id:"G01.target.resegment",raw:"nihaoshijieni",words:["你好","世界","你"],target:1,replacement:"shijieni",surface:"世界泥",expected:"你好世界泥你")
repairCase(id:"G01.unicode.grapheme",raw:"nihaoemojikuo",words:["你好","👩🏽‍💻","𠀀"],target:1,replacement:"accent",surface:"e\u{301}",expected:"你好e\u{301}𠀀")
repairCase(id:"G01.long.suffix",raw:"nihao"+String(repeating:"shijie",count:128)+"ni",words:["你好"]+Array(repeating:"世界",count:128)+["你"],target:0,replacement:"nihao",surface:"拟好",expected:"拟好"+String(repeating:"世界",count:128)+"你")
repairCase(id:"G01.raw.missing-letter.insert",raw:"niha",words:["你好"],target:0,replacement:"nihao",surface:"你好",expected:"你好")
repairCase(id:"G01.raw.typo.transposition",raw:"nihaoyignxiangshijie",words:["你好","影响","世界"],target:1,replacement:"yingxiang",surface:"影响",expected:"你好影响世界",schema:"paia_a2_full")
run("G01.conflict.and.budget.preserve"){
    let s=try runtime.makeSession(deferredCommit:true);defer{s.end()};try type("nihaoshijieni",s);try confirm(s,["你好","世界","你"])
    let original=s.snapshot!.rawASCII
    for (raw,surface,limit,expectedCode) in [("zz","世界",2048,20),("nihao","拟好",1,21)] {
        do{let p=try s.prepareRepair(target:try s.repairAnchors().targets[1],replacementRaw:raw,surface:surface,limit:limit);p.cancel();throw TestFailure.assertion("unexpected success")}
        catch ConstraintError.native(let code,_){try check(code==Int32(expectedCode),"wrong constraint status \(code)")}
        try check(s.snapshot!.rawASCII==original,"failure mutated original")
    }
    try commit(s,"你好世界你");return "exhausted conflict distinct from incomplete; original commit retained"
}
run("G01.stale.request.target.cancel"){
    let s=try runtime.makeSession(deferredCommit:true);defer{s.end()};try type("nihaoshijieni",s);try confirm(s,["你好","世界","你"])
    let p=try s.prepareRepair(target:try s.repairAnchors().targets[0],replacementRaw:"nihao",surface:"拟好")
    let newer=try s.prepareRepair(target:try s.repairAnchors().targets[0],replacementRaw:"nihao",surface:"你号")
    do{_ = try s.applyRepair(p);throw TestFailure.assertion("old request accepted")}catch ConstraintError.stale{}
    p.cancel();newer.cancel()
    do{_ = try s.applyRepair(newer);throw TestFailure.assertion("cancelled trial accepted")}catch ConstraintError.consumed{}
    let pending=try s.prepareRepair(target:try s.repairAnchors().targets[0],replacementRaw:"nihao",surface:"拟好")
    _ = try s.refresh()
    do{_ = try s.applyRepair(pending);throw TestFailure.assertion("late reply accepted")}catch ConstraintError.stale{}
    pending.cancel();try commit(s,"你好世界你");return "request supersession, generation change and cancellation rejected"
}
run("G01.stale.target.and.choice.snapshot"){
    let s=try runtime.makeSession(deferredCommit:true);defer{s.end()};try type("nihaoshijieni",s)
    let oldChoices=try s.repairChoices(limit:1)
    try check(!oldChoices.complete,"one-row enumeration incorrectly claimed exhausted")
    let newerChoices=try s.repairChoices(limit:2)
    do{_ = try s.selectForRepair(oldChoices.rows[0]);throw TestFailure.assertion("superseded choice capability accepted")}catch ConstraintError.stale{}
    try check(!newerChoices.rows.isEmpty,"no new choices")
    try confirm(s,["你好","世界","你"])
    let oldTarget=try s.repairAnchors().targets[1]
    _ = try s.refresh()
    do{let p=try s.prepareRepair(target:oldTarget,replacementRaw:"nihao",surface:"拟好");p.cancel();throw TestFailure.assertion("old target rebound to current generation")}catch ConstraintError.stale{}
    try commit(s,"你好世界你");return "displayed target lease and issued choice identity enforced; partial list explicit"
}
run("G01.sentence.native.decomposition"){
    let s=try runtime.makeSession(deferredCommit:true);defer{s.end()};try type("nihaoshijieni",s)
    let first=try s.repairChoices(limit:4).rows.first.unwrap("empty native sentence menu");try check(first.anchor.text=="你好世界你","fixture sentence mismatch")
    _ = try s.selectForRepair(first)
    let anchors=try s.repairAnchors().rows;try check(anchors.count>=3,"Sentence RTTI decomposition unavailable")
    let target=try anchors.enumerated().first(where:{$0.element.text=="世界"}).map{$0.offset}.unwrap("world anchor")
    let p=try s.prepareRepair(target:try s.repairAnchors().targets[target],replacementRaw:"nihao",surface:"拟好");_ = try s.applyRepair(p);try commit(s,"你好拟好你")
    return "actual Sentence components and word_lengths validated by full-raw replay"
}
run("G01.cross-boundary-filter.unsupported.preserve"){
    let s=try runtime.makeSession(schema:"paia_a2_filter",deferredCommit:true);defer{s.end()};try type("toufa",s)
    let first=try s.repairChoices(limit:32).rows.first(where:{$0.anchor.text=="頭髮"}).unwrap("cross-boundary conversion missing")
    _ = try s.selectForRepair(first)
    do{_ = try s.repairAnchors();throw TestFailure.assertion("non-replayable filtered split falsely accepted")}
    catch ConstraintError.native(let code,_){try check(code==22,"wrong failure for unsupported filter boundary")}
    try check(s.snapshot?.rawASCII=="toufa","mapping failure modified original");try commit(s,"頭髮")
    return "observed unsupported split: whole 頭髮 cannot replay as separately filtered 頭+發; original retained"
}
run("G01.traditional.whole-sentence.mapping"){
    let s=try runtime.makeSession(schema:"paia_a2_full_traditional",deferredCommit:true);defer{s.end()}
    try type("nihaoshurufashijie",s)
    let sentence=try s.repairChoices(limit:128).rows.first(where:{$0.anchor.text=="你好輸入法世界"}).unwrap("traditional whole sentence not emitted")
    _ = try s.selectForRepair(sentence)
    let target=try s.repairAnchors().targets.first(where:{$0.anchor.text=="輸入法"}).unwrap("no verified traditional inner component")
    let p=try s.prepareRepair(target:target,replacementRaw:"daimashencha",surface:"代碼審查");_ = try s.applyRepair(p)
    try commit(s,"你好代碼審查世界");return "genuine spans independently replayed through actual filtered candidates; engine commits Traditional once"
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
var benchmarks=[BenchmarkResult]()
for lane in ["baseline-cancel-retype","constrained-replay"] {
    var samples=[Double]();var failed=0
    for iteration in 0..<55 {
        let start=DispatchTime.now().uptimeNanoseconds
        do {
            let session=try runtime.makeSession(schema:"paia_a2_full",deferredCommit:true);defer{session.end()}
            try type("nihaoshurufashijie",session);try confirm(session,["你好","输入法","世界"])
            // Identical starting composition, dictionary and learning policy; measure correction+commit only.
            let correctionStart=DispatchTime.now().uptimeNanoseconds
            if lane=="baseline-cancel-retype" {
                _ = try session.process(.escape);try type("nihaodaimashenchashijie",session);try confirm(session,["你好","代码审查","世界"])
            } else {
                let target=try session.repairAnchors().targets[1]
                let proposal=try session.prepareRepair(target:target,replacementRaw:"daimashencha",surface:"代码审查")
                _ = try session.applyRepair(proposal)
            }
            try commit(session,"你好代码审查世界")
            if iteration>=5 {samples.append(Double(DispatchTime.now().uptimeNanoseconds-correctionStart)/1e6)}
        } catch {
            failed += 1
            results.append(CaseResult(id:"BENCH."+lane+".\(iteration)",evidence:"ENGINE_NATIVE",passed:false,detail:String(describing:error),milliseconds:Double(DispatchTime.now().uptimeNanoseconds-start)/1e6))
        }
    }
    let sorted=samples.sorted()
    func percentile(_ p:Double)->Double{sorted.isEmpty ? 0 : sorted[min(sorted.count-1,Int(ceil(Double(sorted.count)*p))-1)]}
    benchmarks.append(BenchmarkResult(lane:lane,samples:samples.count,failures:failed,p50:percentile(0.5),p95:percentile(0.95),p99:percentile(0.99),max:sorted.last ?? 0,latenciesMilliseconds:samples))
}
let report=Report(sourceSHA:env["PAIA_SOURCE_SHA"] ?? "unknown",dictionaryRevision:runtime.dictionaryRevision,engine:runtime.version,
 scope:"bounded emitted-candidate replay; core-only Rime Ice; synthetic workload, no installed IME or user-quality claim",
 startupMilliseconds:startupMilliseconds,failures:results.filter{!$0.passed}.count,results:results,benchmarks:benchmarks)
let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];print(String(data:try encoder.encode(report),encoding:.utf8)!)
if report.failures>0 {exit(1)}
extension Optional {func unwrap(_ message:String)throws->Wrapped{guard let x=self else{throw TestFailure.assertion(message)};return x}}
