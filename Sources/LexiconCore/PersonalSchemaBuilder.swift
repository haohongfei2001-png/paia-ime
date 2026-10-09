import Foundation

public struct PersonalResources {
    public let shared:URL,schemas:[String],requiredArtifacts:[String],revision:String,activeTerms:Int,overlaySchemas:Set<String>
    public static func baselineSchema(punctuation:Bool)->String {"paia_b2_baseline_full_"+(punctuation ? "punct":"ascii")}
}
public enum PersonalSchemaBuilder {
    // Startup only. Trusted fixed schema templates; personal text appears exclusively in validated TSV data rows.
    public static func prepare(baseline:URL,destination:URL,document:LexiconDocument,baseRevision:String)throws->PersonalResources {
        try LexiconRules.validate(document)
        guard !FileManager.default.fileExists(atPath:destination.path) else{throw LexiconError.unsafePath}
        try FileManager.default.copyItem(at:baseline,to:destination)
        let digest=LexiconCodec.digest(try LexiconCodec.encode(document)),suffix=String(digest.prefix(32))
        var builders=[String](),artifacts=[String](),namespaces=[String](),blocks=""
        for (tier,pinned,quality) in [("terms",false,"1.0"),("pin",true,"10.0")] {
            let terms=document.activeTerms.filter{$0.explicitPin==pinned}.sorted{($0.reading,$0.id.uuidString)<($1.reading,$1.id.uuidString)}
            if terms.isEmpty{continue} // librime rejects empty syllabaries; never emit an empty dictionary.
            let dictionary="paia_b2_\(tier)_\(suffix)",prism="paia_b2_\(tier)_full_\(suffix)",builder="paia_b2_build_\(tier)_\(suffix)",namespace="paia_b2_\(tier)"
            let rows=terms.flatMap{term in term.readings.map{term.surface+"\t"+$0+"\t10000\n"}}.joined()
            let dict="---\nname: \(dictionary)\nversion: \"\(suffix)\"\nsort: original\nuse_preset_vocabulary: false\ncolumns: [text, code, weight]\n...\n"+rows
            try dict.write(to:destination.appendingPathComponent(dictionary+".dict.yaml"),atomically:false,encoding:.utf8)
            let options="""
              dictionary: \(dictionary)
              prism: \(prism)
              enable_user_dict: false
              enable_completion: false
              enable_word_completion: false
              enable_correction: false
              contextual_suggestions: false
              strict_spelling: true
              initial_quality: \(quality)
            """+"\n"
            let schema="""
            schema:
              schema_id: \(builder)
              name: PAIA B2 explicit terms compiler
              version: "\(suffix)"
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
            """+"\n"+options
            try schema.write(to:destination.appendingPathComponent(builder+".schema.yaml"),atomically:false,encoding:.utf8)
            builders.append(builder);artifacts += [dictionary+".table.bin",dictionary+".reverse.bin",prism+".prism.bin",builder+".schema.yaml"]
            namespaces.insert("script_translator@"+namespace,at:0);blocks += "\n"+namespace+":\n"+options
        }
        var overlays=Set<String>(),schemas=builders
        for punctuation in [false,true] {
            let original="paia_b1_full_"+(punctuation ? "punct":"ascii"),baselineName=PersonalResources.baselineSchema(punctuation:punctuation)
            let text=try String(contentsOf:baseline.appendingPathComponent(original+".schema.yaml"),encoding:.utf8)
            guard text.contains("schema_id: "+original),text.contains("enable_user_dict: false") else{throw LexiconError.invalidFormat}
            let plain=text.replacingOccurrences(of:"schema_id: "+original,with:"schema_id: "+baselineName)
            try plain.write(to:destination.appendingPathComponent(baselineName+".schema.yaml"),atomically:false,encoding:.utf8)
            schemas.append(baselineName);artifacts.append(baselineName+".schema.yaml")
            if !namespaces.isEmpty {
                let old=punctuation ? "translators: [punct_translator, script_translator]":"translators: [script_translator]"
                guard text.components(separatedBy:old).count==2 else{throw LexiconError.invalidFormat}
                let list=(punctuation ? ["punct_translator"]:[])+namespaces+["script_translator"]
                let enhanced=text.replacingOccurrences(of:old,with:"translators: ["+list.joined(separator:", ")+"]")+blocks
                try enhanced.write(to:destination.appendingPathComponent(original+".schema.yaml"),atomically:false,encoding:.utf8)
                overlays.insert(original)
            }
        }
        for spelling in ["full","flypy","natural"] {for traditional in [false,true] {for punctuation in [false,true] {
            let schema="paia_b1_"+spelling+(traditional ? "_traditional":"")+(punctuation ? "_punct":"_ascii")
            schemas.append(schema);artifacts.append(schema+".schema.yaml")
        }}}
        let identity=Data((baseRevision+"|librime-1.16.0|b2-template-1|"+digest).utf8)
        return PersonalResources(shared:destination,schemas:schemas,requiredArtifacts:artifacts,revision:LexiconCodec.digest(identity),activeTerms:document.activeTerms.count,overlaySchemas:overlays)
    }
    public static func verifyCompiled(_ resources:PersonalResources,userDirectory:URL)throws {
        for artifact in resources.requiredArtifacts {
            let url=userDirectory.appendingPathComponent("build").appendingPathComponent(artifact)
            let values=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            guard values.isRegularFile==true,values.isSymbolicLink != true,(values.fileSize ?? 0)>0 else{throw LexiconError.invalidFormat}
        }
    }
}
