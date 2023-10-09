import Foundation
import Logging

#if os(macOS) || os(tvOS) || os(iOS) || os(watchOS)
let systemStderr = Darwin.stderr
let systemStdout = Darwin.stdout
#elseif os(Windows)
let systemStderr = CRT.stderr
let systemStdout = CRT.stdout
#elseif canImport(Glibc)
let systemStderr = Glibc.stderr!
let systemStdout = Glibc.stdout!
#elseif canImport(WASILibc)
let systemStderr = WASILibc.stderr!
let systemStdout = WASILibc.stdout!
#else
#error("Unsupported runtime")
#endif

#if canImport(WASILibc) || os(Android)
internal typealias CFilePointer = OpaquePointer
#else
internal typealias CFilePointer = UnsafeMutablePointer<FILE>
#endif

public struct PreciseStdioOutputStream: TextOutputStream {
	internal let file: CFilePointer
	internal let flushMode: FlushMode
	
	public func write(_ string: String) {
		self.contiguousUTF8(string).withContiguousStorageIfAvailable { utf8Bytes in
#if os(Windows)
			_lock_file(self.file)
#elseif canImport(WASILibc)
			// no file locking on WASI
#else
			flockfile(self.file)
#endif
			defer {
#if os(Windows)
				_unlock_file(self.file)
#elseif canImport(WASILibc)
				// no file locking on WASI
#else
				funlockfile(self.file)
#endif
			}
			_ = fwrite(utf8Bytes.baseAddress!, 1, utf8Bytes.count, self.file)
			if case .always = self.flushMode {
				self.flush()
			}
		}!
	}
	
	/// Flush the underlying stream.
	/// This has no effect when using the `.always` flush mode, which is the default
	internal func flush() {
		_ = fflush(self.file)
	}
	
	internal func contiguousUTF8(_ string: String) -> String.UTF8View {
		var contiguousString = string
#if compiler(>=5.1)
		contiguousString.makeContiguousUTF8()
#else
		contiguousString = string + ""
#endif
		return contiguousString.utf8
	}
	
	static let stderr = PreciseStdioOutputStream(file: systemStderr, flushMode: .always)
	static let stdout = PreciseStdioOutputStream(file: systemStdout, flushMode: .always)
	
	/// Defines the flushing strategy for the underlying stream.
	enum FlushMode {
		case undefined
		case always
	}
}

public struct PreciseTimeStreamLogHandler: LogHandler {
#if compiler(>=5.6)
	internal typealias _SendableTextOutputStream = TextOutputStream & Sendable
#else
	internal typealias _SendableTextOutputStream = TextOutputStream
#endif
	
	static let dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-mm-dd'T'HH:mm:ss.SSSZ"
		return formatter
	}()
	
	/// Factory that makes a `StreamLogHandler` that directs its output to `stdout`
	public static func standardOutput(label: String, metadataProvider: Logger.MetadataProvider?) -> PreciseTimeStreamLogHandler {
		return PreciseTimeStreamLogHandler(label: label, stream: PreciseStdioOutputStream.stdout, metadataProvider: metadataProvider)
	}
	
	/// Factory that makes a `StreamLogHandler` that directs its output to `stderr`
	public static func standardError(label: String) -> PreciseTimeStreamLogHandler {
		return PreciseTimeStreamLogHandler(label: label, stream: PreciseStdioOutputStream.stderr, metadataProvider: LoggingSystem.metadataProvider)
	}
	
	public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
		get {
			return self.metadata[metadataKey]
		}
		set {
			self.metadata[metadataKey] = newValue
		}
	}
	
	internal static let stdout = PreciseStdioOutputStream(file: systemStdout, flushMode: .always)
	
	public var logLevel: Logging.Logger.Level = .info
	public var metadataProvider: Logger.MetadataProvider?
	private var prettyMetadata: String?
	
	private let label: String
	private let stream: _SendableTextOutputStream
	
	public var metadata = Logging.Logger.Metadata() {
		didSet {
			self.prettyMetadata = self.prettify(self.metadata)
		}
	}
	
	// internal for testing only
	internal init(label: String, stream: _SendableTextOutputStream) {
		self.init(label: label, stream: stream, metadataProvider: LoggingSystem.metadataProvider)
	}
	
	// internal for testing only
	internal init(label: String, stream: _SendableTextOutputStream, metadataProvider: Logger.MetadataProvider?) {
		self.label = label
		self.stream = stream
		self.metadataProvider = metadataProvider
	}
	
	public func log(level: Logger.Level,
					message: Logger.Message,
					metadata explicitMetadata: Logger.Metadata?,
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
		
		PreciseStdioOutputStream.stdout.write("\(self.timestamp()) \(level) \(self.label) :\(prettyMetadata.map { " \($0)" } ?? "") [\(source)] \(message)\n")
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
	
	private func timestamp() -> String {
		var buffer = [Int8](repeating: 0, count: 255)
#if os(Windows)
		var timestamp = __time64_t()
		_ = _time64(&timestamp)
		
		var localTime = tm()
		_ = _localtime64_s(&localTime, &timestamp)
		
		_ = strftime(&buffer, buffer.count, "%Y-%m-%dT%H:%M:%S%z", &localTime)
		return buffer.withUnsafeBufferPointer {
			$0.withMemoryRebound(to: CChar.self) {
				String(cString: $0.baseAddress!)
			}
		}
#else
		return Self.dateFormatter.string(from: Date())
#endif
	}
}
