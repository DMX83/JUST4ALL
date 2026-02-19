import Foundation
import J4FCore
import J4FFileSystem

public enum J4FOpsBootstrap {
    public static func isReady() -> Bool {
        J4FFileSystemBootstrap.isReady() && !J4FCoreBootstrap.version.isEmpty
    }
}
