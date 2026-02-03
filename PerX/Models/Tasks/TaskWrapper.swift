import CoreData

@objc(TaskWrapper)
public class TaskWrapper: NSManagedObject {
    @NSManaged public var taskData: Data?
    @NSManaged public var sinistro: Sinistro?
    
    var task: Any? {
        get {
            guard let data = taskData else { return nil }
            return try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data)
        }
        set {
            if let value = newValue {
                taskData = try? NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
            } else {
                taskData = nil
            }
        }
    }
} 