import Foundation

public class GlobalVars {
	static public var BUNDLE_PATH: String {
		ProcessInfo.processInfo.environment["BUNDLE_PATH"] as String? ?? Bundle(for: Self.self).resourcePath!
	}
	
	static public var NETWORK_STUB_DEBUG =
		["1","true","TRUE","on","ON"].contains(ProcessInfo.processInfo.environment["NETWORK_STUB_DEBUG"] as String? ?? "")
	
	static public var OVERRIDE_STUB_DELAY_MILLIS =
		Int(ProcessInfo.processInfo.environment["OVERRIDE_STUB_DELAY_MILLIS"] ?? "0") ?? 0
	
	static let storageModificationQueue: DispatchQueue = .init(label: "StubRecorderDelegateQueue", qos: .default)
}
