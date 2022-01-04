// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

//@f:0
let package = Package(
    name: "ReadWriteLock",
    platforms: [ .macOS(.v11), .tvOS(.v14), .iOS(.v14), .watchOS(.v7) ],
    products: [ .library(name: "ReadWriteLock", targets: [ "ReadWriteLock", ]), ],
    dependencies: [],
    targets: [
        .target(name: "ReadWriteLock", dependencies: [], exclude: [ "Info.plist", ]),
        .testTarget(name: "ReadWriteLockTests", dependencies: [ "ReadWriteLock", ], exclude: [ "Info.plist", ]),
    ]
)
//@f:1
