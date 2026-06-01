import Foundation

let delegate = PerXLocalAgentServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
