import Foundation
import EngineBridge
import SessionCore
struct TaskCase:Codable {let id:String,raw:String,expected:String}
struct Observation:Codable {let task:String,round:Int,raw:String,expected:String,candidates:[String],expectedRank:Int?,commit:String?,error:String?,milliseconds:Double}
struct Report:Codable {let evidence:String,sourceSHA:String,revision:String,lane:String,engine:String,scope:String,observations:[Observation]}
let env=ProcessInfo.processInfo.environment
func required(_ key:String)throws->String {guard let s=env[key],!s.isEmpty else{throw NSError(domain:key,code:1)};return s}
do {
 let lane=try required("PAIA_DICTIONARY_LANE")
 let tasks=try JSONDecoder().decode([TaskCase].self,from:Data(contentsOf:URL(fileURLWithPath:try required("PAIA_DICTIONARY_TASKS"))))
 guard tasks.count==48,Set(tasks.map{$0.id}).count==48 else{throw NSError(domain:"task identity",code:1)}
 let temp=FileManager.default.temporaryDirectory.appendingPathComponent("paia-dictionary-"+UUID().uuidString)
 try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
 defer{try? FileManager.default.removeItem(at:temp)}
 let runtime=try RimeRuntime(library:required("PAIA_RIME_LIBRARY"),shared:required("PAIA_DICTIONARY_SHARED"),isolatedUser:temp.path,dictionaryRevision:required("PAIA_DICTIONARY_REVISION"),schemas:["paia_dictionary_experiment"],g01Library:nil)
 defer{runtime.close()}
 var observations=[Observation]();var errors=0
 for round in 0..<5 {for task in tasks {
  let start=DispatchTime.now().uptimeNanoseconds
  var candidates=[String](),commit:String?,error:String?
  do {
   let session=try runtime.makeSession(schema:"paia_dictionary_experiment");defer{session.end()}
   for key in task.raw.utf8 {
    let update=try session.process(.code(Int32(key)))
    if update.commit != nil{throw NSError(domain:"unexpected typing commit",code:1)}
   }
   guard let snapshot=session.snapshot,snapshot.rawASCII==task.raw else{throw NSError(domain:"lost raw",code:1)}
   candidates=snapshot.rows.map{$0.text}
   if let first=snapshot.rows.first {
    let update=try session.select(first.ref);commit=update.commit?.text
    // Partial candidates can continue composition; only emitted commits need reservation.
    if let effect=update.commit {
     guard session.reserve(effect),!session.reserve(effect),try session.refresh().commit==nil else{throw NSError(domain:"duplicate commit",code:1)}
    }
   }
  }catch let failure{error=String(describing:failure);errors+=1}
  observations.append(Observation(task:task.id,round:round,raw:task.raw,expected:task.expected,candidates:candidates,expectedRank:candidates.firstIndex(of:task.expected).map{$0+1},commit:commit,error:error,milliseconds:Double(DispatchTime.now().uptimeNanoseconds-start)/1e6))
 }}
 let report=Report(evidence:"ENGINE_NATIVE",sourceSHA:env["PAIA_SOURCE_SHA"] ?? "unknown",revision:runtime.dictionaryRevision,lane:lane,engine:runtime.version,scope:"new fixed authored diagnostic v1; top page only; missing expected output is reported, not hidden; not human quality or installed IME",observations:observations)
 let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.prettyPrinted]
 let data=try encoder.encode(report)
 try data.write(to:URL(fileURLWithPath:required("PAIA_DICTIONARY_RESULT")),options:.withoutOverwriting)
 print("dictionary observations=\(observations.count) errors=\(errors)")
 if errors>0{exit(1)}
}catch{fputs("dictionary experiment failed: \(error)\n",stderr);exit(1)}
