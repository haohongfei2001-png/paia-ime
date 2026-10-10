import Foundation
import Darwin

public enum StoreTestFault {case beforePublication,afterPublication}
// One explicitly chosen directory, one writer, one authoritative atomic document.
// No typing/commit API references this store. Tombstones are never recovered from an older generation.
public final class LexiconStore {
    private let authorityGuard:()throws->Void
    private let lock=NSLock(),identity=UUID()
    private var rootFD:Int32 = -1,writerFD:Int32 = -1
    private var state=LexiconDocument(),uncertain=false,closed=false
    private let fault:StoreTestFault?
    // Internal deterministic read-race injection, not a production setting.
    var afterReadBeforeVerification:((String)throws->Void)?
    public let directory:URL
    public init(directory:URL,fault:StoreTestFault?=nil,preopenedDirectory:Int32?=nil,allowCreateLock:Bool=true,authorityGuard:@escaping()throws->Void={})throws {
        self.directory=directory.standardizedFileURL;self.fault=fault;self.authorityGuard=authorityGuard
        do {
            try authorityGuard()
            if let descriptor=preopenedDirectory {rootFD=fcntl(descriptor,F_DUPFD_CLOEXEC,0)}
            else {
                if allowCreateLock{try FileManager.default.createDirectory(at:self.directory,withIntermediateDirectories:true)}
                rootFD=Darwin.open(self.directory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
            }
            var rootInfo=stat(),linkedRoot=stat();guard rootFD>=0,fstat(rootFD,&rootInfo)==0,lstat(self.directory.path,&linkedRoot)==0,
                  (rootInfo.st_mode&S_IFMT)==S_IFDIR,(linkedRoot.st_mode&S_IFMT)==S_IFDIR,rootInfo.st_dev==linkedRoot.st_dev,rootInfo.st_ino==linkedRoot.st_ino else{throw LexiconError.unsafePath}
            try authorityGuard()
            var prior=stat();let hadLock=fstatat(rootFD,".writer.lock",&prior,AT_SYMLINK_NOFOLLOW)==0
            writerFD=openat(rootFD,".writer.lock",O_RDWR|(allowCreateLock ? O_CREAT:0)|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC,0o600)
            guard writerFD>=0 else{throw LexiconError.unsafePath}
            var info=stat();guard fstat(writerFD,&info)==0,(info.st_mode & S_IFMT)==S_IFREG,info.st_nlink==1 else{throw LexiconError.unsafePath}
            guard flock(writerFD,LOCK_EX|LOCK_NB)==0 else{throw LexiconError.busy}
            let marker=try readOwned(".initialized"),data=try readOwned("lexicon.json")
            if let data=data {
                guard marker==Data("paia.personal-lexicon.v1\n".utf8) else{throw LexiconError.invalidFormat}
                state=try LexiconCodec.decode(data)
            } else {
                guard !hadLock,marker==nil else{throw LexiconError.invalidFormat}
                try createMarker();try publish(try LexiconCodec.encode(state))
            }
            try authorityGuard()
        } catch {if writerFD>=0{Darwin.close(writerFD)};if rootFD>=0{Darwin.close(rootFD)};writerFD = -1;rootFD = -1;throw error}
    }
    deinit {if writerFD>=0{Darwin.close(writerFD)};if rootFD>=0{Darwin.close(rootFD)}}
    public func close(){lock.lock();defer{lock.unlock()};if !closed{closed=true;Darwin.close(writerFD);Darwin.close(rootFD);writerFD = -1;rootFD = -1}}
    private func ready()throws {
        try authorityGuard()
        guard !closed else{throw LexiconError.io};guard !uncertain else{throw LexiconError.durabilityUnknown}
        var ownedRoot=stat(),linkedRoot=stat()
        guard fstat(rootFD,&ownedRoot)==0,lstat(directory.path,&linkedRoot)==0,(linkedRoot.st_mode & S_IFMT)==S_IFDIR,ownedRoot.st_dev==linkedRoot.st_dev,ownedRoot.st_ino==linkedRoot.st_ino else{throw LexiconError.unsafePath}
        var owned=stat(),linked=stat()
        guard fstat(writerFD,&owned)==0,fstatat(rootFD,".writer.lock",&linked,AT_SYMLINK_NOFOLLOW)==0,
              owned.st_dev==linked.st_dev,owned.st_ino==linked.st_ino else{throw LexiconError.unsafePath}
    }
    public func snapshot()throws->LexiconDocument {lock.lock();defer{lock.unlock()};try verifyAuthority();return state}
    public func exportData()throws->Data {lock.lock();defer{lock.unlock()};try verifyAuthority();return try LexiconCodec.encode(state)}
    private func readOwned(_ name:String)throws->Data? {
        let fd=openat(rootFD,name,O_RDWR|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC)
        if fd<0 {if errno==ENOENT{return nil};throw LexiconError.unsafePath};defer{Darwin.close(fd)}
        var info=stat();guard fstat(fd,&info)==0,(info.st_mode & S_IFMT)==S_IFREG,info.st_nlink==1 else{throw LexiconError.unsafePath}
        guard info.st_size>=0,info.st_size<=LexiconRules.maximumBytes else{throw LexiconError.limit}
        var data=Data(),buffer=[UInt8](repeating:0,count:8192)
        while true {
            let n=Darwin.read(fd,&buffer,buffer.count)
            if n<0{if errno==EINTR{continue};throw LexiconError.io};if n==0{break}
            data.append(contentsOf:buffer.prefix(n));if data.count>LexiconRules.maximumBytes{throw LexiconError.limit}
        }
        // Reopening after an unknown publication is an explicit verification, not a mutation retry.
        // Require the OS's file flush and current directory barrier before acknowledging that generation.
        guard fcntl(fd,F_FULLFSYNC)==0,fsync(rootFD)==0 else{throw LexiconError.durabilityUnknown}
        try afterReadBeforeVerification?(name)
        var after=stat(),linked=stat()
        guard fstat(fd,&after)==0,fstatat(rootFD,name,&linked,AT_SYMLINK_NOFOLLOW)==0,
              (linked.st_mode&S_IFMT)==S_IFREG,after.st_nlink==1,linked.st_nlink==1,
              after.st_ino==info.st_ino,after.st_dev==info.st_dev,linked.st_ino==info.st_ino,linked.st_dev==info.st_dev,
              after.st_size==info.st_size,data.count==info.st_size,
              after.st_mtimespec.tv_sec==info.st_mtimespec.tv_sec,after.st_mtimespec.tv_nsec==info.st_mtimespec.tv_nsec,
              after.st_ctimespec.tv_sec==info.st_ctimespec.tv_sec,after.st_ctimespec.tv_nsec==info.st_ctimespec.tv_nsec else{throw LexiconError.stale}
        return data
    }
    private func publish(_ data:Data)throws {
        let name=".staging-"+UUID().uuidString,fd=openat(rootFD,name,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard fd>=0 else{throw LexiconError.io};defer{Darwin.close(fd);unlinkat(rootFD,name,0)}
        try data.withUnsafeBytes{bytes in
            var offset=0
            while offset<bytes.count {
                let n=Darwin.write(fd,bytes.baseAddress!.advanced(by:offset),bytes.count-offset)
                if n<0{if errno==EINTR{continue};throw LexiconError.io};if n==0{throw LexiconError.io};offset+=n
            }
        }
        guard fcntl(fd,F_FULLFSYNC)==0 else{throw LexiconError.io}
        if fault == .beforePublication{throw LexiconError.io}
        guard renameat(rootFD,name,rootFD,"lexicon.json")==0 else{throw LexiconError.io}
        if fault == .afterPublication || fsync(rootFD) != 0 {uncertain=true;throw LexiconError.durabilityUnknown}
        do{try authorityGuard()}catch{uncertain=true;throw error}
    }
    private func createMarker()throws {
        let fd=openat(rootFD,".initialized",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard fd>=0 else{throw LexiconError.unsafePath};defer{Darwin.close(fd)}
        let bytes=Data("paia.personal-lexicon.v1\n".utf8)
        let written=bytes.withUnsafeBytes{Darwin.write(fd,$0.baseAddress,$0.count)}
        guard written==bytes.count,fcntl(fd,F_FULLFSYNC)==0,fsync(rootFD)==0 else{throw LexiconError.io}
    }
    private func save(_ next:LexiconDocument)throws {try LexiconRules.validate(next);try publish(try LexiconCodec.encode(next));state=next}
    // Explicit management operations revalidate authority. No engine/typing path calls this store.
    private func verifyAuthority()throws {
        try ready()
        guard try readOwned(".initialized")==Data("paia.personal-lexicon.v1\n".utf8),
              try readOwned("lexicon.json")==LexiconCodec.encode(state) else{throw LexiconError.stale}
        try ready()
    }
    private func requireRevision(_ revision:UInt64)throws {
        try verifyAuthority();guard state.revision==revision else{throw LexiconError.stale}
    }
    @discardableResult public func add(surface:String,reading:String,aliases:[String]=[],pin:Bool=false,expectedRevision:UInt64)throws->UUID {
        lock.lock();defer{lock.unlock()};try requireRevision(expectedRevision)
        var next=state;next.revision=try LexiconRules.nextRevision(state)
        let term=PersonalTerm(id:UUID(),surface:surface,reading:try LexiconRules.canonicalReading(reading),aliases:try aliases.map{try LexiconRules.canonicalReading($0)},scope:.fullSimplified,explicitPin:pin,createdAtMilliseconds:LexiconRules.timestamp(),revision:next.revision,deletedAtMilliseconds:nil,noRelearn:false)
        if state.terms.contains(where:{$0.comparisonKey==term.comparisonKey && $0.isDeleted}){throw LexiconError.deleted}
        next.terms.append(term);try save(next);return term.id
    }
    public func edit(id:UUID,surface:String,reading:String,aliases:[String],pin:Bool,expectedRevision:UInt64)throws {
        lock.lock();defer{lock.unlock()};try requireRevision(expectedRevision)
        guard let index=state.terms.firstIndex(where:{$0.id==id}),!state.terms[index].isDeleted else{throw LexiconError.deleted}
        var next=state;next.revision=try LexiconRules.nextRevision(state)
        next.terms[index].surface=surface;next.terms[index].reading=try LexiconRules.canonicalReading(reading)
        next.terms[index].aliases=try aliases.map{try LexiconRules.canonicalReading($0)};next.terms[index].explicitPin=pin;next.terms[index].revision=next.revision
        try save(next)
    }
    public func setDeleted(id:UUID,deleted:Bool,expectedRevision:UInt64)throws {
        lock.lock();defer{lock.unlock()};try requireRevision(expectedRevision)
        guard let index=state.terms.firstIndex(where:{$0.id==id}) else{throw LexiconError.invalidEntry}
        guard state.terms[index].isDeleted != deleted else{return}
        var next=state;next.revision=try LexiconRules.nextRevision(state)
        next.terms[index].deletedAtMilliseconds=deleted ? max(LexiconRules.timestamp(),next.terms[index].createdAtMilliseconds):nil
        next.terms[index].noRelearn=deleted;next.terms[index].revision=next.revision;try save(next)
    }
    public func previewImport(_ bytes:Data)throws->LexiconImportPreview {
        lock.lock();defer{lock.unlock()};try verifyAuthority();return try preview(bytes)
    }
    private func preview(_ bytes:Data)throws->LexiconImportPreview {
        let imported=try LexiconCodec.decode(bytes);var additions=[PersonalTerm](),protected=0,unchanged=0,conflicts=0,notices=[String]()
        for term in imported.terms {
            if let local=state.terms.first(where:{$0.id==term.id || $0.comparisonKey==term.comparisonKey}) {
                if local.isDeleted && !term.isDeleted{protected+=1;notices.append("Protected deletion: "+term.surface+" ["+term.reading+"]")}
                else if local.sameContent(as:term){unchanged+=1}
                else{conflicts+=1;notices.append("Conflict, local retained: "+term.surface+" ["+term.reading+"]")} // Imported revisions never authorize replacement.
            } else {additions.append(term)}
        }
        if !additions.isEmpty {
            do {
                var candidate=state;candidate.revision=try LexiconRules.nextRevision(state)
                for var term in additions{term.revision=candidate.revision;candidate.terms.append(term)}
                _ = try LexiconCodec.encode(candidate) // Exact prospective byte limit and revision, not just row count.
            } catch {conflicts+=1;notices.append("Merged state exceeds a limit or has conflicting effective aliases/pins.")}
        }
        return LexiconImportPreview(baseRevision:state.revision,sha256:LexiconCodec.digest(bytes),additions:additions,protectedDeletions:protected,unchanged:unchanged,conflicts:conflicts,notices:notices,store:identity,bytes:bytes)
    }
    public func applyImport(_ plan:LexiconImportPreview)throws {
        lock.lock();defer{lock.unlock()};try requireRevision(plan.baseRevision)
        guard plan.store==identity,plan.sha256==LexiconCodec.digest(plan.bytes) else{throw LexiconError.stale}
        let verified=try preview(plan.bytes);guard verified.conflicts==0 else{throw LexiconError.conflict}
        guard !verified.additions.isEmpty else{return}
        var next=state;next.revision=try LexiconRules.nextRevision(state)
        for var term in verified.additions{term.revision=next.revision;next.terms.append(term)}
        try save(next)
    }
}
