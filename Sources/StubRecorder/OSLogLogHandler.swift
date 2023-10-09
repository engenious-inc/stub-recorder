import Foundation
import Logging
import os.log

public struct OSLogLogHandler: LogHandler {
	public static let defaultLog = OSLog.default
	
	private let label: String
	private let osLog: OSLog
	
	public var metadata = Logging.Logger.Metadata() {
		didSet {
			self.prettyMetadata = self.prettify(self.metadata)
		}
	}
	
	public var metadataProvider: Logging.Logger.MetadataProvider?
	public var logLevel: Logging.Logger.Level = .info
	private var prettyMetadata: String?
	
	public static func factory(withSubsystem subsystem: String, andCategory catagory: String) -> ((String) -> OSLogLogHandler) {
		
		// Return a builder function that creates an OSLog with the specified subsystem/category
		return {
			(label: String) -> (OSLogLogHandler) in
			return defaultLog(label: label, osLog: OSLog(subsystem: subsystem, category: catagory))
		}
	}
	
	public static func defaultLog(label: String) -> OSLogLogHandler {
		return OSLogLogHandler(label: label, osLog: Self.defaultLog, metadataProvider: Logging.LoggingSystem.metadataProvider)
	}

	public static func defaultLog(label: String, osLog: OSLog, metadataProvider: Logging.Logger.MetadataProvider? = nil) -> OSLogLogHandler {
		return OSLogLogHandler(label: label, osLog: osLog, metadataProvider: metadataProvider)
	}
	
	internal init(label: String, osLog: OSLog, metadataProvider: Logging.Logger.MetadataProvider?) {
		self.label = label
		self.osLog = osLog
		self.metadataProvider = metadataProvider
	}
	
	public subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
		get {
			return self.metadata[metadataKey]
		}
		set(newValue) {
			self.metadata[metadataKey] = newValue
		}
	}
	
	public func log(
		level: Logging.Logger.Level,
		message: Logging.Logger.Message,
		metadata explicitMetadata: Logging.Logger.Metadata?,
		source: String,
		file: String,
		function: String,
		line: UInt) {
			
			let effectiveMetadata = Self.prepareMetadata(base: self.metadata, provider: self.metadataProvider, explicit: explicitMetadata)
			
			let prettyMetadata: String?
			if let effectiveMetadata = effectiveMetadata {
				prettyMetadata = self.prettify(effectiveMetadata)
			} else {
				prettyMetadata = self.prettyMetadata
			}
			
			let messageContent = "\(self.label) :\(prettyMetadata.map { " \($0)" } ?? "") [\(source)] \(message)"
			os_log("%@", log: osLog, type: loggingLevelToOSLogType(logLevel: level), messageContent as CVarArg)
	}
	
	internal func loggingLevelToOSLogType(logLevel: Logging.Logger.Level) -> OSLogType {
		switch logLevel {
			case .trace:
				return .debug
			case .debug:
				return .debug
			case .info:
				return .default
			case .notice:
				return .info
			case .warning:
				return .info
			case .error:
				return .error
			case .critical:
				return .fault
		}
	}
	
	
	internal static func prepareMetadata(base: Logging.Logger.Metadata, provider: Logging.Logger.MetadataProvider?, explicit: Logging.Logger.Metadata?) -> Logging.Logger.Metadata? {
		var metadata = base
		
		let provided = provider?.get() ?? [:]
		
		guard !provided.isEmpty || !((explicit ?? [:]).isEmpty) else {
			// all per-log-statement values are empty
			return nil
		}
		
		if !provided.isEmpty {
			metadata.merge(provided, uniquingKeysWith: { _, provided in provided })
		}
		
		if let explicit = explicit, !explicit.isEmpty {
			metadata.merge(explicit, uniquingKeysWith: { _, explicit in explicit })
		}
		
		return metadata
	}
	
	private func prettify(_ metadata: Logging.Logger.Metadata) -> String? {
		if metadata.isEmpty {
			return nil
		} else {
			return metadata.lazy.sorted(by: { $0.key < $1.key }).map { "\($0)=\($1)" }.joined(separator: " ")
		}
	}
}
