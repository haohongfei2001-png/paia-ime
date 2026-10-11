import Foundation
import EngineBridge
import SessionCore

// Artificial, versioned fixture only. Warmup separate; no failed samples silently removed.
let tasks=["nihao","nihaoma","shi jie","ni","hao","kuo","emoji","accent"]
let rounds=100
var samples:[Double]=[],engineSamples:[Double]=[],copySamples:[Double]=[]
var failures:[String]=[]
let env:LabEnvironment
do {env=try LabEnvironment()} catch {
    print("{\"evidence\":\"ENGINE_NATIVE\",\"complete\":false,\"fatal\":\"startup failed before measurement\",\"samples\":0}")
    exit(1)
}
let session:InputSession
do {session=try env.runtime.makeSession()} catch {
    print("{\"evidence\":\"ENGINE_NATIVE\",\"complete\":false,\"fatal\":\"session creation failed before measurement\",\"samples\":0}")
    exit(1)
}
benchmark: for round in -1..<rounds {
    for (taskIndex,raw) in tasks.enumerated() {
        do {_=try session.process(.escape)} catch {failures.append("terminal reset failure at round=\(round),task=\(taskIndex)");break benchmark}
        for (keyIndex,key) in raw.utf8.enumerated() {
            var failed=false
            let begin=RimeRuntime.monotonicNanoseconds
            do {
                let u=try session.process(key==32 ? .code(39) : .code(Int32(key)))
                if let effect=u.commit { _=session.reserve(effect) }
            } catch {failures.append("round=\(round),task=\(taskIndex),key=\(keyIndex)");failed=true}
            let elapsed=Double(RimeRuntime.monotonicNanoseconds-begin)/1_000_000
            if round>=0 {
                samples.append(elapsed)
                if !failed {
                    engineSamples.append(Double(session.lastTiming.engineNanoseconds)/1_000_000)
                    copySamples.append(Double(session.lastTiming.copyNanoseconds)/1_000_000)
                }
            }
            if failed {break benchmark}
        }
    }
}
struct Statistics:Codable {
    let samples:Int
    let p50:Double,p95:Double,p99:Double,max:Double
    init(_ values:[Double]) {
        let sorted=values.sorted()
        func percentile(_ q:Double)->Double {sorted.isEmpty ? 0 : sorted[Swift.max(0,Int(ceil(Double(sorted.count)*q))-1)]}
        samples=values.count;p50=percentile(0.5);p95=percentile(0.95);p99=percentile(0.99)
        max=sorted.last ?? 0
    }
}
struct Report:Codable {
    let evidence:String,engine:String,dictionaryRevision:String,os:String,sourceSHA:String
    let fixtureInputs:[String],rounds:Int,warmupRounds:Int,samples:Int
    let boundary:String,learning:String
    let componentsMilliseconds:[String:Statistics]
    let unmeasured:[String],unavailableComponentSamples:Int
    let milliseconds:Statistics,complete:Bool,unmeasuredKeys:Int
    let failures:[String],failureCount:Int
    let latenciesMilliseconds:[Double],engineLatenciesMilliseconds:[Double],copyLatenciesMilliseconds:[Double]
}
let result=Report(evidence:"ENGINE_NATIVE",engine:"librime \(env.runtime.version)",
    dictionaryRevision:env.runtime.dictionaryRevision,os:ProcessInfo.processInfo.operatingSystemVersionString,
    sourceSHA:ProcessInfo.processInfo.environment["PAIA_SOURCE_SHA"] ?? "local-uncommitted",
    fixtureInputs:tasks,rounds:rounds,warmupRounds:1,samples:samples.count,
    boundary:"Swift session policy + serialized C API process_key + commit/context copy/free + pure state; no UI or visible rendering",
    learning:"disabled; fresh isolated user directory",
    componentsMilliseconds:["engineProcessKey":Statistics(engineSamples),"commitContextCopyAndFree":Statistics(copySamples),"sessionTotal":Statistics(samples)],
    unmeasured:["AppKit layout","host protocol","visible presentation"],
    unavailableComponentSamples:samples.count-engineSamples.count,milliseconds:Statistics(samples),
    complete:failures.isEmpty,unmeasuredKeys:rounds*tasks.reduce(0,{$0+$1.utf8.count})-samples.count,
    failures:failures,failureCount:failures.count,latenciesMilliseconds:samples,
    engineLatenciesMilliseconds:engineSamples,copyLatenciesMilliseconds:copySamples)
let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(result))
session.end()
if !failures.isEmpty {exit(1)}
