import Foundation

/// Monitor per aggiornamenti in tempo reale delle directory
class DirectoryMonitor: ObservableObject {
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var fileDescriptors: [String: Int32] = [:]
    private let queue = DispatchQueue(label: "com.perx.directorymonitor", qos: .utility)
    var onChange: (() -> Void)?
    
    func startMonitoring(paths: [String]) {
        stopMonitoring()
        
        for path in paths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            
            fileDescriptors[path] = fd
            
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .extend, .attrib],
                queue: queue
            )
            
            source.setEventHandler { [weak self] in
                DispatchQueue.main.async {
                    self?.onChange?()
                }
            }
            
            source.setCancelHandler {
                close(fd)
            }
            
            source.resume()
            sources[path] = source
        }
    }
    
    func stopMonitoring() {
        for (_, source) in sources {
            source.cancel()
        }
        sources.removeAll()
        fileDescriptors.removeAll()
    }
    
    deinit {
        stopMonitoring()
    }
}
