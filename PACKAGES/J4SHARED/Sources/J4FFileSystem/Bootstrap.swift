import Foundation
import J4FCore

public enum J4FFileSystemBootstrap {
    public static func isReady() -> Bool {
        !J4FCoreBootstrap.version.isEmpty
    }
}
