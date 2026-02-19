import Foundation
import J4FCore
import J4FFileSystem
import J4FOps

public enum J4FUIBootstrap {
    public static func isReady() -> Bool {
        J4FOpsBootstrap.isReady() && J4FFileSystemBootstrap.isReady() && !J4FCoreBootstrap.version.isEmpty
    }
}
