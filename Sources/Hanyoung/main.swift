import Cocoa
import InputMethodKit

// 모델을 먼저 올린다. 첫 키 입력에서 지연이 생기지 않도록 서버 생성 전에 동기로 로드한다.
Runtime.shared.load()

guard let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String,
      let bundleID = Bundle.main.bundleIdentifier else {
    fatalError("Info.plist에 InputMethodConnectionName / CFBundleIdentifier가 없다")
}

let server = IMKServer(name: connectionName, bundleIdentifier: bundleID)
Runtime.shared.log(["event": "launch", "connection": connectionName])
NSApplication.shared.run()
