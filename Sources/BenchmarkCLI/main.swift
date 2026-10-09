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
            let begin=DispatchTime.now().uptimeNanoseconds
            do {
                let u=try session.process(key==32 ? .code(39) : .code(Int32(key)))
                if let effect=u.commit { _=session.reserve(effect) }
            } catch {failures.append("round=\(round),task=\(taskIndex),key=\(keyIndex)");failed=true}
            let elapsed=Double(DispatchTime.now().uptimeNanoseconds-begin)/1_000_000
            if round>=0 {
                samples.append(elapsed)
                engineSamples.append(Double(session.lastTiming.engineNanoseconds)/1_000_000)
                copySamples.append(Double(session.lastTiming.copyNanoseconds)/1_000_000)
            }
            if failed {break benchmark}
        }
    }
}
let sorted=samples.sorted()
func percentile(_ p:Double)->Double {sorted.isEmpty ? 0 : sorted[max(0,Int(ceil(Double(sorted.count)*p))-1)]}
func summary(_ samples:[Double])->[String:Any] {
    let sorted=samples.sorted()
    func p(_ q:Double)->Double {sorted.isEmpty ? 0 : sorted[max(0,Int(ceil(Double(sorted.count)*q))-1)]}
    return ["samples":samples.count,"p50":p(0.5),"p95":p(0.95),"p99":p(0.99),"max":(sorted.last ?? 0)]
}
let result:[String:Any] = ["evidence":"ENGINE_NATIVE","engine":"librime \(env.runtime.version)",
    "dictionaryRevision":env.runtime.dictionaryRevision,"os":ProcessInfo.processInfo.operatingSystemVersionString,
    "sourceSHA":ProcessInfo.processInfo.environment["PAIA_SOURCE_SHA"] ?? "local-uncommitted",
    "fixtureInputs":tasks,"rounds":rounds,"warmupRounds":1,"samples":samples.count,
    "boundary":"Swift session policy + serialized C API process_key + commit/context copy/free + pure state; no UI or visible rendering",
    "learning":"disabled; fresh isolated user directory",
    "componentsMilliseconds":["engineProcessKey":summary(engineSamples),"commitContextCopyAndFree":summary(copySamples),"sessionTotal":summary(samples)],
    "unmeasured":["AppKit layout","host protocol","visible presentation"],"milliseconds":["p50":percentile(0.5),"p95":percentile(0.95),"p99":percentile(0.99),"max":(sorted.last ?? 0)],
    "complete":failures.isEmpty,"unmeasuredKeys":rounds*tasks.reduce(0,{$0+$1.utf8.count})-samples.count,"failures":failures,"failureCount":failures.count,"latenciesMilliseconds":samples,"engineLatenciesMilliseconds":engineSamples,"copyLatenciesMilliseconds":copySamples]
let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
FileHandle.standardOutput.write(data)
session.end()
if !failures.isEmpty {exit(1)}
