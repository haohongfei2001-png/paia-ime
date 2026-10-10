import Foundation

// Parse only our engineering flags. Preserve the pre-existing AppKit service
// path for other launch arguments; malformed preflight intent must never start
// the ordinary service. Parsing itself performs no filesystem operation.
public struct InputMethodLaunchArguments {
    public let preflight:Bool,isolatedParent:URL?
    public init(_ arguments:[String])throws {
        let owned=arguments.contains{$0.hasPrefix("--preflight") || $0.hasPrefix("--isolated-parent")}
        if !owned{preflight=false;isolatedParent=nil;return}
        if arguments==["--preflight"]{preflight=true;isolatedParent=nil;return}
        guard arguments.count==3,arguments[0]=="--preflight",arguments[1]=="--isolated-parent",
              arguments[2].hasPrefix("/"),!arguments[2].utf8.contains(0) else{throw ResourceError.format}
        preflight=true;isolatedParent=URL(fileURLWithPath:arguments[2])
    }
}
