import AppKit
import InputMethodKit
import Foundation

// Research-only host. No installed input source, event tap, or user document.
@objc(ResearchIMEController) final class ResearchIMEController: IMKInputController {}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var results: [[String: Any]] = []
func check(_ id: String, _ ok: Bool, _ details: String = "") {
    results.append(["id": id, "passed": ok, "details": details])
}
func makeView(_ text: String) -> NSTextView {
    let v = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
    v.isRichText = false
    v.allowsUndo = true
    v.string = text
    v.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    return v
}
let samples = ["", "A", "中文", "A👩🏽‍💻B", "e\u{301}", "𠮷", "✈️", "A\r\nB"]
for (i, prefix) in samples.enumerated() {
    let v = makeView(prefix)
    let offset = (prefix as NSString).length
    v.setMarkedText("shiyan", selectedRange: NSRange(location: 6, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    check("marked-\(i)", v.hasMarkedText() && v.markedRange() == NSRange(location: offset, length: 6) && v.string == prefix + "shiyan")
    v.setMarkedText("实验", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    check("update-\(i)", v.string == prefix + "实验" && v.markedRange() == NSRange(location: offset, length: 2))
    v.insertText("实验", replacementRange: NSRange(location: NSNotFound, length: 0))
    check("commit-\(i)", !v.hasMarkedText() && v.string == prefix + "实验" && v.selectedRange() == NSRange(location: offset + 2, length: 0))
}
let v = makeView("研究👩🏽‍💻结果")
let emoji = (v.string as NSString).range(of: "👩🏽‍💻")
v.setSelectedRange(emoji)
v.setMarkedText("yuan", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
v.insertText("员", replacementRange: NSRange(location: NSNotFound, length: 0))
check("replace-selected-grapheme", v.string == "研究员结果")
let r = makeView("今天提交草稿。")
let target = (r.string as NSString).range(of: "草稿")
r.insertText("终稿", replacementRange: target)
check("explicit-replacement-range", r.string == "今天提交终稿。")
let cancel = makeView("前缀")
cancel.setMarkedText("ceshi", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
cancel.insertText("", replacementRange: NSRange(location: NSNotFound, length: 0))
check("cancel-own-marked-range", cancel.string == "前缀" && !cancel.hasMarkedText())
let q = makeView("原文")
let snapshot = (q.string, q.selectedRange())
q.setSelectedRange(NSRange(location: 0, length: 0))
let unchanged = q.string == snapshot.0 && q.selectedRange() == snapshot.1
check("stale-selection-guard", !unchanged)
q.string = "原文变了"
check("stale-body-guard", q.string != snapshot.0)
let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 88), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
check("panel-not-visible", !panel.isVisible)
check("panel-nonactivating-style", panel.styleMask.contains(.nonactivatingPanel))
let pass = results.filter { $0["passed"] as? Bool == true }.count
let report: [String: Any] = ["test": "Isolated AppKit host + InputMethodKit compile probe", "os": ProcessInfo.processInfo.operatingSystemVersionString, "architecture": "arm64", "cases": results, "passed": pass, "total": results.count, "installedIME": false, "crossApplicationTest": false, "userDocumentsRead": false, "networkInProbe": false]
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
print(String(data: data, encoding: .utf8)!)
if pass != results.count { exit(1) }
