import Foundation
import XCTest

enum Fixtures {
    static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"),
            "missing fixture \(name)")
        return try Data(contentsOf: url)
    }
}
