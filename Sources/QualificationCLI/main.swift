import Foundation
import EngineBridge
import SessionCore
import QualificationCore
import QualificationMetrics

// Explicit engineering executable. Every document/string below is authored.
// It is never invoked by the input service and never discovers a user profile.
enum Failure:Error {case check(String)}
func require(_ condition:Bool,_ message:String)throws {if !condition{throw Failure.check(message)}}
func now()->UInt64 {DispatchTime.now().uptimeNanoseconds}
func writeJSON(_ value:Any,_ path:URL)throws {
    try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]).write(to:path,options:.atomic)
}
func object<T:Encodable>(_ value:T)throws->Any {try JSONSerialization.jsonObject(with:JSONEncoder().encode(value))}
func signature(_ value:CandidateSnapshot?)->[String] {
    guard let s=value else{return []}
    return [s.rawASCII,s.preedit,String(s.caretUTF8),String(s.pageIndex),String(s.highlighted),String(s.hasMore)]+s.rows.map{$0.text}
}
let variables=ProcessInfo.processInfo.environment
let args=Array(CommandLine.arguments.dropFirst())
guard args.count==4,["prepare","startup","calibrate","endurance"].contains(args[0]),variables["PAIA_B1_RESEARCH"]=="1",
      let library=variables["PAIA_RIME_LIBRARY"],let revision=variables["PAIA_B1_REVISION"] else {
    FileHandle.standardError.write(Data("Explicit verified B1 research environment and mode/shared/new-user/output required.\n".utf8));exit(2)
}
let mode=args[0],shared=args[1],user=args[2],output=URL(fileURLWithPath:args[3],isDirectory:true)
let reportPath=output.appendingPathComponent("report.json")
var report:[String:Any]=["complete":false,"evidence":"ENGINE_NATIVE","mode":mode,
    "sourceSHA":variables["PAIA_SOURCE_SHA"] ?? "local-uncommitted","dictionaryRevision":revision,
    "compiledInventorySHA":variables["PAIA_QUALIFICATION_PACK_SHA"] ?? "build-process",
    "seed":String(QualificationSchedule.seed),"learning":"schema user_dict disabled; runtime _no_learning checked",
    "scope":"authored repeated workload on unbundled strong research corpus; not language-quality or installed-IME evidence",
    "unmeasured":["visible latency","M1 release budget","true OS-cold cache","installed clients","8 hours continuous input","500 hours real use","human quality","production corpus rights"],
    "operationSamples":0,"failures":[],"OS":ProcessInfo.processInfo.operatingSystemVersionString,
    "engine":"librime 1.16.0","generator":"xorshift64 with Fisher-Yates eight-case permutation per schema; 32-schema cycle"]
var runtime:RimeRuntime?
var records:FileHandle?
var buffer=Data(),samples=0,assertions=0,commits=0,diagnosticReads=0,episodes=0
var byOperation=["key":0,"selection":0,"clear":0]
var schemaEpisodes=[String:Int](),scenarioEpisodes=[String:Int](),rss=[[String:Any]]()
func check(_ condition:Bool,_ message:String)throws {assertions+=1;try require(condition,message)}
func checkpoint(_ phase:String)throws {
    if !buffer.isEmpty {try records?.write(contentsOf:buffer);buffer.removeAll(keepingCapacity:true)}
    let resident=paia_qualification_current_rss();try require(resident>0,"resident measurement unavailable")
    rss.append(["phase":phase,"samples":samples,"episodes":episodes,"residentBytes":resident,"wholeProcessPeakBytes":paia_qualification_peak_rss()])
    report["operationSamples"]=samples;report["episodes"]=episodes;report["assertions"]=assertions;report["commits"]=commits
    report["operationCounts"]=byOperation;report["schemaEpisodes"]=schemaEpisodes;report["scenarioEpisodes"]=scenarioEpisodes
    report["diagnosticReads"]=diagnosticReads;report["rssCheckpoints"]=rss
    if let runtime=runtime {report["nativeCounters"]=try object(runtime.diagnostics)}
    try writeJSON(report,reportPath)
    print("PAIA_NATIVE_CHECKPOINT phase=\(phase) samples=\(samples) episodes=\(episodes) residentBytes=\(resident)")
}
func timed(_ session:InputSession,operation:String,_ action:()throws->SessionUpdate)throws->SessionUpdate {
    let generation=session.snapshot?.inputGeneration ?? 0,begin=now()
    let update:SessionUpdate
    do{update=try action()}catch{
        // Preserve the attempted failure and its wall duration. Never reuse a
        // previous successful component timing when native/Swift decode fails.
        report["failedAttempt"]=["operation":operation,"ownerNanoseconds":now()-begin,"completedSamples":samples]
        throw error
    }
    let elapsed=now()-begin,timing=session.lastTiming
    try check(update.snapshot?.inputGeneration==generation+1,"operation did not produce exactly one native snapshot")
    let code:UInt64=operation=="key" ? 1:operation=="selection" ? 2:3
    buffer.append(QualificationTimingRecord(operation:code,owner:elapsed,nativeAction:timing.engineNanoseconds,contextCopy:timing.copyNanoseconds).data)
    samples+=1;byOperation[operation,default:0]+=1
    if buffer.count>=262144 {try records!.write(contentsOf:buffer);buffer.removeAll(keepingCapacity:true)}
    return update
}
func input(_ key:InputKey,_ session:InputSession,operation:String="key",mayCommit:Bool=false)throws->SessionUpdate {
    let update=try timed(session,operation:operation){try session.process(key)}
    try check(update.refusal==nil,"unexpected owner refusal")
    if !mayCommit {try check(update.commit==nil,"unsolicited engine commit")}
    return update
}
func type(_ raw:String,_ session:InputSession)throws {
    var expected=session.snapshot?.rawASCII ?? ""
    for byte in raw.utf8 {
        expected.append(Character(UnicodeScalar(byte)))
        let update=try input(.code(Int32(byte)),session)
        try check(update.snapshot?.rawASCII==expected,"raw bytes diverged during typing")
    }
}
func expectPending(_ session:InputSession)throws {
    do {_ = try session.process(.code(97));throw Failure.check("pending commit accepted another key")}
    catch SessionError.pendingCommit {assertions+=1}
    do {_ = try session.refresh();throw Failure.check("pending commit accepted refresh")}
    catch SessionError.pendingCommit {assertions+=1}
}
func reserve(_ update:SessionUpdate,expected:String,session:InputSession,other:InputSession,literal:Bool=false)throws {
    guard let effect=update.commit else{throw Failure.check("expected complete commit absent")}
    try check(effect.text.utf8.elementsEqual(expected.utf8),"commit bytes differ")
    try check(effect.replacementUTF16==nil,"ordinary commit offered replacement")
    switch effect.origin {case .engine:try check(!literal,"engine origin used for raw Return");case .literal:try check(literal,"literal bypass used for candidate selection");default:throw Failure.check("unexpected commit origin")}
    try expectPending(session)
    try check(!other.reserve(effect),"foreign session reserved effect")
    try check(session.reserve(effect),"first reservation failed")
    try check(!session.reserve(effect),"duplicate reservation succeeded")
    commits+=1
    let refreshed=try session.refresh();diagnosticReads+=1
    try check(refreshed.commit==nil && refreshed.snapshot?.rawASCII=="" && refreshed.snapshot?.preedit=="","commit was not drained exactly once")
}
func stale(_ ref:CandidateRef,_ session:InputSession)throws {
    let before=signature(session.snapshot),generation=session.snapshot?.inputGeneration
    do {_ = try session.select(ref);throw Failure.check("stale/foreign candidate accepted")}
    catch SessionError.staleCandidate {assertions+=1}
    try check(signature(session.snapshot)==before && session.snapshot?.inputGeneration==generation,"rejected candidate changed current composition")
}
func diagnostics(_ runtime:RimeRuntime,schemas:[String])throws->[[String:Any]] {
    var result=[[String:Any]]()
    for schema in schemas {
        let session=try runtime.makeSession(schema:schema,chinesePunctuation:schema.contains("_punct"));defer{session.end()}
        try check(session.learningDisabled,"diagnostic session learning enabled")
        for raw in [schema.contains("_full_") ? "shurufa":"uurufa",schema.contains("_full_") ? "shi":"ui"] {
            for byte in raw.utf8 {let u=try session.process(.code(Int32(byte)));try check(u.commit==nil,"diagnostic typing committed")}
            let expected=schema.contains("_traditional_") ? "輸入法":"输入法"
            if raw.hasSuffix("rufa"){try check(session.snapshot?.rows.first?.text==expected,"authored strong-corpus oracle failed")}
            result.append(["schema":schema,"raw":raw,"signature":signature(session.snapshot)])
            _ = try session.process(.escape)
        }
    }
    return result
}
do {
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:false)
    try require(FileManager.default.contentsOfDirectory(atPath:user).isEmpty,"user directory is not newly empty")
    try writeJSON(report,reportPath)
    let schemas=LabConfiguration.researchSchemas
    try require(schemas.count==32,"research schema contract changed")
    let opened=now()
    let owner=try RimeRuntime(library:library,shared:shared,isolatedUser:user,dictionaryRevision:revision,
                              schemas:mode=="prepare" ? schemas:[],precompiled:mode != "prepare")
    runtime=owner;report["runtimeOpenNanoseconds"]=now()-opened
    if mode=="prepare" {
        try require(owner.deploymentCalls==33,"not all 32 research schemas and fixture deployed")
        try require(owner.close(),"deployment close failed")
        report["schemas"]=schemas;report["deploymentCalls"]=owner.deploymentCalls;report["complete"]=true
        try checkpoint("deployment-closed")
    } else {
        try require(owner.deploymentCalls==0 && !owner.repairExtensionLoaded && !owner.mixedExtensionLoaded,"measured path deployed or loaded unverified extension")
        if mode=="startup" {
            let start=now(),s=try owner.makeSession(schema:"paia_b1_full_ascii")
            report["firstSessionNanoseconds"]=now()-start;try check(s.learningDisabled,"learning option not disabled")
            let first=now(),u=try s.process(.code(115));report["firstKeyNanoseconds"]=now()-first
            try check(u.snapshot?.rawASCII=="s" && u.commit==nil,"first snapshot mismatch")
            report["runtimeOpenToFirstSnapshotNanoseconds"]=now()-opened
            _ = try s.process(.escape)
            let warm=now();_ = try s.process(.code(115));report["warmFirstKeyNanoseconds"]=now()-warm
            _ = try s.process(.escape);s.end()
            try checkpoint("zero-session-idle")
            let cpu=paia_qualification_cpu_ns(),wall=now();Thread.sleep(forTimeInterval:2)
            report["idleCPUFractionOfOneCore"]=Double(paia_qualification_cpu_ns()-cpu)/Double(now()-wall)
            try require(owner.close(),"startup close failed");report["complete"]=true;try checkpoint("startup-closed")
        } else {
            let minimum=mode=="calibrate" ? QualificationSchedule.calibrationEvents:QualificationSchedule.minimumEvents
            report["requestedMinimumNativeInputOperations"]=minimum
            report["timingRecordBytes"]=QualificationTimingRecord.bytes
            report["timingColumns"]=["operation: 1 key, 2 selection, 3 clear","owner nanoseconds: InputSession call including Swift decoding and snapshot free","native action nanoseconds: select includes current-page validation","C context/commit acquisition, malloc-copy and upstream free nanoseconds; excludes Swift decoding and shim snapshot free"]
            let timingFile=output.appendingPathComponent("timings.bin")
            try Data().write(to:timingFile,options:.withoutOverwriting);records=try FileHandle(forWritingTo:timingFile);buffer.reserveCapacity(262144)
            let before=try autoreleasepool{try diagnostics(owner,schemas:schemas)}
            try writeJSON(before,output.appendingPathComponent("diagnostics-before.json"))
            // At most two simultaneous sessions. This sentinel crosses native
            // readback at checkpoints; cached Swift state alone is insufficient.
            let sentinel=try owner.makeSession(schema:"paia_b1_full_ascii")
            for byte in "ni".utf8 {_ = try sentinel.process(.code(Int32(byte)))}
            let sentinelSignature=signature(sentinel.snapshot)
            let baseline=owner.diagnostics;report["nativeCountersBeforeWorkload"]=try object(baseline)
            var schedule=QualificationSchedule(),session:InputSession?,schemaIndex:Int?,nextCheckpoint=10_000
            try checkpoint("all-schemas-warmed-before-workload")
            let begin=now(),cpu=paia_qualification_cpu_ns()
            while samples<minimum {
                try autoreleasepool {
                    let entry=schedule.next(),schema=schemas[entry.schema]
                    if schemaIndex != entry.schema {
                        if let old=session {old.end();old.end();do{_ = try old.process(.code(97));throw Failure.check("ended session processed a key")}catch EngineError.closed{assertions+=1}}
                        session=try owner.makeSession(schema:schema,chinesePunctuation:schema.contains("_punct"));schemaIndex=entry.schema
                        try check(session!.learningDisabled,"workload session learning enabled")
                    }
                    let s=session!,raw=schema.contains("_full_") ? "shurufa":"uurufa"
                    let expected=schema.contains("_traditional_") ? "輸入法":"输入法"
                    try check((s.snapshot?.rawASCII ?? "").isEmpty,"episode starts with abandoned input")
                    schemaEpisodes[schema,default:0]+=1;scenarioEpisodes[String(entry.scenario),default:0]+=1
                    switch entry.scenario {
                    case 0,1:
                        try type(raw,s)
                        if entry.scenario==1 {
                            _ = try input(.code(0xff08),s);try check(s.snapshot?.rawASCII==String(raw.dropLast()),"backspace raw mismatch")
                            try type(String(raw.suffix(1)),s)
                        }
                        try check(s.snapshot?.rows.first?.text==expected,"whole-word candidate changed")
                        let ref=s.snapshot!.rows[0].ref;try stale(ref,sentinel)
                        let selected=try input(.space,s,operation:"selection",mayCommit:true)
                        try reserve(selected,expected:expected,session:s,other:sentinel);try stale(ref,s)
                    case 2:
                        try type(raw,s);_ = try input(.code(0xff51),s)
                        try check(s.snapshot?.caretUTF8==raw.utf8.count-1,"left is not raw-character movement")
                        _ = try input(.code(120),s)
                        var bytes=Array(raw.utf8);bytes.insert(120,at:bytes.count-1)
                        try check(s.snapshot?.rawASCII==String(bytes:bytes,encoding:.utf8),"insertion lost suffix")
                        _ = try input(.code(0xff51),s);_ = try input(.code(0xffff),s)
                        try check(s.snapshot?.rawASCII==raw,"forward delete did not recover raw")
                        _ = try input(.code(0xff50),s);try check(s.snapshot?.caretUTF8==0,"Home raw caret mismatch")
                        _ = try input(.code(0xff53),s);try check(s.snapshot?.caretUTF8==1,"Right raw caret mismatch")
                        _ = try input(.code(0xff57),s);try check(s.snapshot?.caretUTF8==raw.utf8.count,"End raw caret mismatch")
                        try reserve(try input(.returnKey,s,operation:"clear",mayCommit:true),expected:raw,session:s,other:sentinel,literal:true)
                    case 3:
                        try type(raw,s);try reserve(try input(.returnKey,s,operation:"clear",mayCommit:true),expected:raw,session:s,other:sentinel,literal:true)
                        let generation=s.snapshot?.inputGeneration
                        for key:InputKey in [.returnKey,.escape,.command,.space,.code(0xff51),.code(0xff09)] {try check(!(try s.process(key)).handled,"idle host key swallowed")}
                        try check(s.snapshot?.inputGeneration==generation,"idle passthrough mutated engine")
                    case 4:
                        try type(schema.contains("_full_") ? "shi":"ui",s)
                        guard let first=s.snapshot,let ref=first.rows.first?.ref else{throw Failure.check("paging fixture has no candidates")}
                        try check(first.hasMore,"paging fixture lacks second page")
                        _ = try input(.code(0xff56),s);try check(s.snapshot?.pageIndex==first.pageIndex+1,"page down failed")
                        try stale(ref,s)
                        _ = try input(.code(0xff55),s);try check(signature(s.snapshot)==signature(first),"page roundtrip changed candidates")
                        guard let shown=s.snapshot,shown.rows.count>=2 else{throw Failure.check("single-syllable second row absent")}
                        _ = try input(.code(0xff54),s);try check(s.snapshot?.highlighted==1,"Down highlight mismatch")
                        _ = try input(.code(0xff52),s);try check(s.snapshot?.highlighted==0,"Up highlight mismatch")
                        let text=shown.rows[1].text
                        try reserve(try input(.number(2),s,operation:"selection",mayCommit:true),expected:text,session:s,other:sentinel)
                    case 5:
                        try type(raw,s);let ref=s.snapshot!.rows[0].ref
                        _ = try input(.escape,s,operation:"clear");try stale(ref,s)
                        try check(s.snapshot?.rawASCII=="" && s.snapshot?.preedit=="","cancel retained composition")
                        if schema.contains("_punct") {
                            for (key,text) in [(44,"，"),(63,"？"),(33,"！"),(59,"；")] {
                                try reserve(try input(.code(Int32(key)),s,mayCommit:true),expected:text,session:s,other:sentinel)
                            }
                        }
                    case 6:
                        let long=String(repeating:raw,count:4);try type(long,s)
                        try reserve(try input(.returnKey,s,operation:"clear",mayCommit:true),expected:long,session:s,other:sentinel,literal:true)
                    default:
                        try type(raw,s);let state=signature(s.snapshot),generation=s.snapshot?.inputGeneration
                        for text in ["𠀀","👩🏽‍💻","e\u{301}"] {
                            let refused=try s.process(.text(text));try check(refused.refusal == .unsupportedTextDuringComposition && refused.commit==nil,"unsupported Unicode corrupted composition")
                        }
                        try check(signature(s.snapshot)==state && s.snapshot?.inputGeneration==generation,"owner-only refusal changed generation")
                        _ = try input(.escape,s,operation:"clear")
                    }
                    episodes+=1
                }
                if samples>=nextCheckpoint {
                    let read=try sentinel.refresh();diagnosticReads+=1
                    try check(read.commit==nil && signature(read.snapshot)==sentinelSignature,"independent native sentinel changed")
                    let count=owner.diagnostics
                    try check(count.inputOperations-baseline.inputOperations==UInt64(samples),"native input denominator differs")
                    try check(count.snapshots-baseline.snapshots==UInt64(samples+diagnosticReads),"unexpected native snapshot path")
                    try check(count.failedSteps==baseline.failedSteps && count.liveSessions==2,"native failure or leaked live session")
                    try check(session!.learningDisabled && sentinel.learningDisabled,"checkpoint learning option changed")
                    try checkpoint("steady-two-sessions");nextCheckpoint+=10_000
                }
            }
            report["workloadWallNanoseconds"]=now()-begin;report["workloadCPUNanoseconds"]=paia_qualification_cpu_ns()-cpu
            let measured=owner.diagnostics
            try check(measured.inputOperations-baseline.inputOperations==UInt64(samples),"final native count mismatch")
            try check(measured.keys-baseline.keys==UInt64(byOperation["key"]!) && measured.selections-baseline.selections==UInt64(byOperation["selection"]!) && measured.clears-baseline.clears==UInt64(byOperation["clear"]!),"per-operation denominator mismatch")
            try check(measured.snapshots-baseline.snapshots==UInt64(samples+diagnosticReads) && measured.failedSteps==baseline.failedSteps,"snapshot/failure total mismatch")
            report["nativeCountersAfterWorkload"]=try object(measured)
            session?.end();session=nil;sentinel.end()
            try check(owner.diagnostics.liveSessions==0,"sessions survived explicit teardown")
            let after=try autoreleasepool{try diagnostics(owner,schemas:schemas)}
            try writeJSON(after,output.appendingPathComponent("diagnostics-after.json"))
            try check(try JSONSerialization.data(withJSONObject:before,options:.sortedKeys)==JSONSerialization.data(withJSONObject:after,options:.sortedKeys),"before/after candidate diagnostics drifted")
            try check(Set(schemaEpisodes.keys)==Set(schemas) && scenarioEpisodes.count==8,"workload did not cover every schema/scenario")
            try check(owner.deploymentCalls==0,"deployment occurred in input process")
            try require(owner.close(),"runtime close failed")
            let final=owner.diagnostics
            try check(final.liveSessions==0 && final.sessionsCreated==final.sessionsDestroyed,"unbalanced native session lifecycle")
            report["complete"]=true;try checkpoint("closed")
            try records?.close();records=nil
        }
    }
    print("PAIA_NATIVE_QUALIFICATION mode=\(mode) complete=true samples=\(samples) episodes=\(episodes)")
} catch {
    report["complete"]=false;report["failures"]=[String(describing:error)]
    if let runtime=runtime {_=runtime.close()}
    do{try checkpoint("failed")}catch{FileHandle.standardError.write(Data("Could not preserve final checkpoint.\n".utf8))}
    try? records?.close()
    FileHandle.standardError.write(Data("PAIA_NATIVE_QUALIFICATION failed; complete=false preserved when writable.\n".utf8));exit(1)
}
