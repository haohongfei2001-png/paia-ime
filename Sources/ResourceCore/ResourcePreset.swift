import Foundation

// Closed authored fixture preset. No arbitrary schema/plugin import.
public enum ResourcePreset:String,Codable,CaseIterable {
    case baseline, extended
    public var schemas:[String] {["paia_a1","paia_resource_secondary"]}
    public var probeRaw:String {self == .baseline ? "nihao":"ceshigengxin"}
    public var probeText:String {self == .baseline ? "你好":"测试更新"}
    public var sources:[String:Data] {
        var files=[String:Data]()
        files["default.yaml"] = Data(#"""
config_version: "1.0"
schema_list:
  - schema: paia_a1
menu:
  page_size: 5
"""#.utf8) + Data([10])
        files["paia_a1.dict.yaml"] = Data(#"""
# Artificial test data authored for this repository; no user history or public corpus.
---
name: paia_a1
version: "1.0"
sort: by_weight
use_preset_vocabulary: false
...
你	ni	1000
呢	ni	900
泥	ni	800
拟	ni	700
逆	ni	600
倪	ni	500
腻	ni	400
好	hao	1000
号	hao	500
吗	ma	1000
你好	ni hao	10000
拟好	ni hao	9000
你号	ni hao	8000
你好呀	ni hao ya	7000
你好吗	ni hao ma	10000
世界	shi jie	10000
𠀀	kuo	10000
👩🏽‍💻	emoji	10000
é	accent	10000
"""#.utf8) + Data([10])
        files["paia_a1.schema.yaml"] = Data(#"""
# Artificial integration fixture, not a competitive language model.
schema:
  schema_id: paia_a1
  name: PAIA A1 artificial fixture
  version: "1.0"
switches:
  - name: ascii_mode
    reset: 0
engine:
  processors: [speller, selector, navigator, express_editor]
  segmentors: [abc_segmentor, fallback_segmentor]
  translators: [script_translator]
menu:
  page_size: 5
speller:
  alphabet: abcdefghijklmnopqrstuvwxyz
  delimiter: " '"
translator:
  dictionary: paia_a1
  enable_user_dict: false
  enable_sentence: true
  enable_completion: true
  initial_quality: 1
"""#.utf8) + Data([10])
        let schema=String(decoding:files["paia_a1.schema.yaml"]!,as:UTF8.self)
        files["paia_resource_secondary.schema.yaml"]=Data(schema.replacingOccurrences(of:"schema_id: paia_a1",with:"schema_id: paia_resource_secondary").utf8)
        if self == .extended {files["paia_a1.dict.yaml"]!.append(Data("测试更新\tce shi geng xin\t10000\n".utf8))}
        return files
    }
    public var requiredArtifacts:[String] {
        (["default.yaml","build/paia_a1.table.bin","build/paia_a1.reverse.bin","build/paia_a1.prism.bin"]+schemas.map{"build/"+$0+".schema.yaml"}).sorted()
    }
}
