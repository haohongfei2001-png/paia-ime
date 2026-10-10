import Foundation
import Darwin

public enum ProductDataTestFault {case afterPublication,readySyncFailure}
// One product-owned root, never a discovered profile or a migrated research store.
// Preflight supplies an isolated parent; only a normal installed-service launch
// may choose the fixed application-support parent. No input text enters this type.
public final class ProductDataRoot {
    public static let leaf="paia-ime"
    private static let prefix="paia.product-data.v1\n"
    public enum Slot:String,CaseIterable {case settings,personal,expressions}
    public let directory:URL
    public private(set) var createdThisLaunch=false
    private let lock=NSRecursiveLock()
    private struct Ancestor {let url:URL,fd:Int32,device:dev_t,inode:ino_t}
    private var ancestors=[Ancestor](),owner:ResourceDirectory?,writer:Int32 = -1,closed=false,layout=Data()
    public init(parent:URL,create:Bool,fault:ProductDataTestFault?=nil)throws {
        directory=parent.appendingPathComponent(Self.leaf,isDirectory:true)
        do {
            try openParents(parent)
            guard let verifiedParent=ancestors.last else{throw ResourceError.unsafePath}
            let parent=try ResourceDirectory(duplicating:verifiedParent.fd,url:verifiedParent.url)
            var linked=stat()
            if fstatat(parent.fd,Self.leaf,&linked,AT_SYMLINK_NOFOLLOW) != 0 {
                guard errno==ENOENT,create else{throw ResourceError.unavailable}
                let stagingName=".paia-data-"+UUID().uuidString.lowercased()
                let staging=try parent.createDirectory(stagingName)
                // A crash leaves an unselected staging root. Never recover it by
                // guessing, enumerate siblings, or overwrite an existing product root.
                let layout=Data((Self.prefix+UUID().uuidString.lowercased()+"\n").utf8)
                for slot in Slot.allCases {
                    let child=try staging.createDirectory(slot.rawValue)
                    try child.writeExclusive(".slot",Self.slotMarker(layout,slot));try child.sync()
                }
                try staging.writeExclusive(".product.lock",Data())
                try staging.writeExclusive(".layout",layout);try staging.sync()
                try checkParents();try staging.check();try parent.check()
                guard renameatx_np(parent.fd,stagingName,parent.fd,Self.leaf,UInt32(RENAME_EXCL))==0 else{throw ResourceError.io}
                createdThisLaunch=true
                if fault == .afterPublication{throw ResourceError.durabilityUnknown}
                try parent.sync()
            }
            let selected=try parent.child(Self.leaf);try Self.privateDirectory(selected)
            let names=try selected.names()
            guard names.contains(".layout"),names.contains(".product.lock"),Set(names).isSubset(of:Set([".layout",".product.lock"]+Slot.allCases.map(\.rawValue))) else{throw ResourceError.incompatible}
            let bytes=try selected.read(".layout",maximum:128)
            guard let text=String(data:bytes,encoding:.utf8),text.hasPrefix(Self.prefix),text.hasSuffix("\n"),
                  ResourceContract.generation(String(text.dropFirst(Self.prefix.count).dropLast())) else{throw ResourceError.incompatible}
            owner=selected;layout=bytes
            writer=openat(selected.fd,".product.lock",O_RDWR|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC)
            var lockInfo=stat()
            guard writer>=0,fstat(writer,&lockInfo)==0,(lockInfo.st_mode&S_IFMT)==S_IFREG,lockInfo.st_nlink==1,
                  lockInfo.st_uid==getuid(),(lockInfo.st_mode&0o077)==0 else{throw ResourceError.unsafePath}
            guard flock(writer,LOCK_EX|LOCK_NB)==0 else{throw ResourceError.busy}
            try verify()
            // Reopening is an explicit confirmation, not proof that an earlier
            // publication's directory barrier completed. Both paths acknowledge
            // the selected name under the original descriptors before readiness.
            if fault == .readySyncFailure{throw ResourceError.durabilityUnknown}
            try selected.sync();try parent.sync();try verify()
        } catch {close();throw error}
    }
    deinit{close()}
    private func openParents(_ parent:URL)throws {
        // Foundation standardization may shorten /private/var to the /var
        // symlink on macOS. Preserve the caller's physical spelling; validate
        // every component below with O_NOFOLLOW instead of normalizing it.
        guard parent.isFileURL,!parent.path.utf8.contains(0) else{throw ResourceError.unsafePath}
        let components=parent.pathComponents;guard components.first=="/",components.count<=64 else{throw ResourceError.unsafePath}
        var path=URL(fileURLWithPath:"/",isDirectory:true),handle=Darwin.open("/",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard handle>=0 else{throw ResourceError.unsafePath}
        var info=stat();guard fstat(handle,&info)==0 else{Darwin.close(handle);throw ResourceError.io}
        ancestors.append(Ancestor(url:path,fd:handle,device:info.st_dev,inode:info.st_ino))
        for component in components.dropFirst() {
            guard component != ".",component != "..",!component.contains("/"),component.utf8.count<=Int(MAXNAMLEN) else{throw ResourceError.unsafePath}
            let next=openat(handle,component,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
            guard next>=0 else{throw ResourceError.unsafePath}
            guard fstat(next,&info)==0 else{Darwin.close(next);throw ResourceError.io}
            path.appendPathComponent(component,isDirectory:true)
            ancestors.append(Ancestor(url:path,fd:next,device:info.st_dev,inode:info.st_ino));handle=next
        }
        // Do not repair permission modes of an existing path. A selected parent
        // must belong to this user and disallow writes by other accounts.
        guard info.st_uid==getuid(),(info.st_mode&0o022)==0 else{throw ResourceError.unsafePath}
        try checkParents()
    }
    private func checkParents()throws {
        guard !closed,!ancestors.isEmpty else{throw ResourceError.stale}
        for ancestor in ancestors {
            var linked=stat(),owned=stat()
            guard lstat(ancestor.url.path,&linked)==0,fstat(ancestor.fd,&owned)==0,(linked.st_mode&S_IFMT)==S_IFDIR,
                  linked.st_dev==ancestor.device,linked.st_ino==ancestor.inode,owned.st_dev==ancestor.device,owned.st_ino==ancestor.inode else{throw ResourceError.stale}
        }
        var parent=stat();guard let last=ancestors.last,fstat(last.fd,&parent)==0,parent.st_uid==getuid(),(parent.st_mode&0o022)==0 else{throw ResourceError.unsafePath}
    }
    private static func privateDirectory(_ directory:ResourceDirectory)throws {
        try directory.check();var info=stat()
        guard fstat(directory.fd,&info)==0,info.st_uid==getuid(),(info.st_mode&S_IFMT)==S_IFDIR,(info.st_mode&0o077)==0 else{throw ResourceError.unsafePath}
    }
    private static func slotMarker(_ layout:Data,_ slot:Slot)->Data {layout+Data((slot.rawValue+"\n").utf8)}
    public func verify()throws {
        lock.lock();defer{lock.unlock()}
        try checkParents();guard let owner=owner,writer>=0 else{throw ResourceError.stale}
        try Self.privateDirectory(owner)
        guard try owner.read(".layout",maximum:128)==layout else{throw ResourceError.incompatible}
        var owned=stat(),linked=stat()
        guard fstat(writer,&owned)==0,fstatat(owner.fd,".product.lock",&linked,AT_SYMLINK_NOFOLLOW)==0,
              owned.st_dev==linked.st_dev,owned.st_ino==linked.st_ino,linked.st_nlink==1,
              linked.st_uid==getuid(),(linked.st_mode&S_IFMT)==S_IFREG,(linked.st_mode&0o077)==0 else{throw ResourceError.stale}
    }
    // A missing/bad existing slot fails only that store. Never recreate a missing
    // child in a marked product root and turn lost authority into an empty store.
    public func slot(_ slot:Slot)throws->ProductDataSlot {
        lock.lock();defer{lock.unlock()}
        try verify();guard let owner=owner else{throw ResourceError.stale}
        let child=try owner.child(slot.rawValue);try verify(child,slot:slot)
        return ProductDataSlot(root:self,owner:child,slot:slot)
    }
    fileprivate func verify(_ child:ResourceDirectory,slot:Slot)throws {
        lock.lock();defer{lock.unlock()};try verify();try Self.privateDirectory(child)
        guard try child.read(".slot",maximum:128)==Self.slotMarker(layout,slot) else{throw ResourceError.incompatible}
        try checkParents()
    }
    fileprivate func withDescriptor<T>(_ child:ResourceDirectory,slot:Slot,_ operation:(Int32)throws->T)throws->T {
        lock.lock();defer{lock.unlock()};try verify(child,slot:slot)
        let value=try operation(child.fd);try verify(child,slot:slot);return value
    }
    public func close(){
        lock.lock();defer{lock.unlock()}
        guard !closed else{return};closed=true
        if writer>=0{Darwin.close(writer);writer = -1}
        for ancestor in ancestors{Darwin.close(ancestor.fd)};ancestors=[];owner=nil
    }
}

public final class ProductDataSlot {
    public let directory:URL
    private let root:ProductDataRoot,owner:ResourceDirectory,slot:ProductDataRoot.Slot
    fileprivate init(root:ProductDataRoot,owner:ResourceDirectory,slot:ProductDataRoot.Slot){self.root=root;self.owner=owner;self.slot=slot;directory=owner.url}
    public func verify()throws{try root.verify(owner,slot:slot)}
    // Synchronous only; the store duplicates this descriptor and owns its copy.
    // This prevents a URL re-open from creating authority in a replaced root.
    public func withDescriptor<T>(_ operation:(Int32)throws->T)throws->T {try root.withDescriptor(owner,slot:slot,operation)}
}
