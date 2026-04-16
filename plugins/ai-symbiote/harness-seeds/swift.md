[Seed #S1] Never add @MainActor to a protocol conformance without checking if the protocol itself requires it
[Seed #S2] When editing SwiftUI views, always verify the preview still compiles after changes
[Seed #S3] Do not use force unwrap (!) in production code; use guard let or if let with proper error handling
[Seed #S4] When adding a new Swift file, ensure the target membership is correct in the Xcode project
[Seed #S5] Check for Sendable compliance before passing closures across actor boundaries
[Seed #S6] Do not add import Foundation to files that already import UIKit or SwiftUI (it is implicit)
[Seed #S7] When modifying CoreData/SwiftData models, always create a migration plan before changing the schema
[Seed #S8] Use async/await instead of completion handlers for new code; do not mix paradigms in the same function
