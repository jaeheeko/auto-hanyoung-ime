// 입력기 번들을 TIS에 등록하고 입력 소스를 활성화한다. --select를 주면 현재 입력 소스로 바꾼다.
// --disable을 주면 반대로 입력 소스에서 뺀다(삭제 전).
// 사용: register <path/to/Hanyoung.app> [--select|--disable]
import Carbon
import Foundation

let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--") }
let doSelect = CommandLine.arguments.contains("--select")
let doDisable = CommandLine.arguments.contains("--disable")
let path = args.first ?? NSString(string: "~/Library/Input Methods/Hanyoung.app").expandingTildeInPath
let url = URL(fileURLWithPath: path)
let status = TISRegisterInputSource(url as CFURL)
print("TISRegisterInputSource:", status == noErr ? "ok" : "status \(status)")

let bundleID = "com.jerryko.inputmethod.Hanyoung"
let filter = [kTISPropertyBundleID as String: bundleID] as CFDictionary
guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource], !list.isEmpty else {
    print("입력 소스를 찾지 못했다. 로그아웃/로그인 후 다시 실행하거나 시스템 설정 > 키보드 > 입력 소스에서 추가한다.")
    exit(1)
}
for source in list {
    func prop(_ key: CFString) -> String {
        guard let p = TISGetInputSourceProperty(source, key) else { return "?" }
        return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }
    let id = prop(kTISPropertyInputSourceID)
    if doDisable {
        let st = TISDisableInputSource(source)
        print("disable \(id): \(st == noErr ? "ok" : "status \(st)")")
        continue
    }
    let enable = TISEnableInputSource(source)
    let enabled = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled)
        .map { CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque($0).takeUnretainedValue()) } ?? false
    print("enable \(id): \(enable == noErr ? "ok" : "status \(enable)") enabled=\(enabled)")
}
// 활성화 상태는 비동기로 저장된다. 바로 종료하면 반영되지 않을 수 있어 잠시 기다린다.
Thread.sleep(forTimeInterval: 1.0)
if doSelect, let auto = list.first(where: { s in
    guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return false }
    return (Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String).hasSuffix(".auto")
}) ?? list.first {
    let sel = TISSelectInputSource(auto)
    print("select:", sel == noErr ? "ok" : "status \(sel)")
}
