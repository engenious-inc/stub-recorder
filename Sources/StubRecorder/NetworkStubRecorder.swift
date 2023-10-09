import Foundation
import SwiftProxy
import Logging

public let DEFAULT_STUB_RESPONSE_DELAY_MILLIS = 0

public struct StubLogger {
	public static let os_logger: Logger = Logger(label: "OSLogger", factory: OSLogLogHandler.factory(withSubsystem: "StubRecorder", andCategory: "Default"))
	
	public static let stream_logger: Logger = Logger(label: "StreamLogger", factory: PreciseTimeStreamLogHandler.standardOutput)
}

open class StubRecorder: ProxyDelegate {
	public enum RecordOption {
		case on
		case off
	}
	
	public private(set) var logger: Logger
	private let sslCertPath: String
	private let sslPrivateKeyPath: String
	private var proxy: SwiftProxy?

	private(set) var stubResources: StubResources?
	private(set) var recordedMappings: StubStorage?
	private(set) var sharedMappings: StubStorage?
	private(set) var sharedLocalMappings: StubStorage?
	private var unstubbedMappings: StubMappingsModel
	
	private var trafficMonitorStorage: TrafficMonitor
	
	private var isNewMappingsCounter: Int = 0
	public private(set) var isRecording: RecordOption
	private lazy var bundlePath = GlobalVars.BUNDLE_PATH
	
	public let host: String
	public let port: Int
	public let endpoint: String
	public var endpointHost: String {
		endpoint.components(separatedBy: "://").last ?? endpoint
	}
	
	public private(set) var testName: String?
	public var stubMutators: [StubMappingsMutable]
	public private(set) var defaultDelay: TimeInterval = Double(DEFAULT_STUB_RESPONSE_DELAY_MILLIS) / 1000.0
	public private(set) var defaultFileExtension = ""
	
	public var debugMode = false
	public var showResponses = false
	
	public var recordMode: Bool {
		isRecording == .on
	}
	
	public var stubExists: Bool {
		guard let path = recordMode ? stubResources?.recordMappingsPath : stubResources?.playbackMappingsPath else {
			return false
		}
		return FileManager.default.fileExists(atPath: path)
	}
	
	/// Constructor for starting proxy only
	public init(
		sslCertPath: String,
		sslPrivateKeyPath: String,
		host: String,
		port: NetworkPort,
		endpoint: String,
		logger: Logger = StubLogger.stream_logger
	) {
		self.logger = logger
		self.sslCertPath = sslCertPath
		self.sslPrivateKeyPath = sslPrivateKeyPath
		self.host = host
		self.port = port.get()
		self.endpoint = endpoint
		
		self.isRecording = .off
		self.stubMutators = []
		self.trafficMonitorStorage = TrafficMonitor(logger: logger)
		self.unstubbedMappings = .init(map: nil, label: "New requests", logger: logger)
	}
	
	/// Constructor for creating staring proxy and reading / recording existing stubs
	public convenience init(
		recordModePath: String,
		playbackModeRelativePath: String,
		sslCertPath: String,
		sslPrivateKeyPath: String,
		scenarioName: String,
		host: String,
		port: NetworkPort,
		endpoint: String,
		record: RecordOption,
		stubMutators: [StubMappingsMutable],
		logger: Logger = StubLogger.stream_logger,
		responseDelayMillis: Int = DEFAULT_STUB_RESPONSE_DELAY_MILLIS,
		optionalFileExtension: String = ""
	) throws {
		
		self.init(sslCertPath: sslCertPath, sslPrivateKeyPath: sslPrivateKeyPath, host: host, port: port, endpoint: endpoint, logger: logger)
		
		self.testName = testName
		self.isRecording = record
		self.stubMutators = stubMutators
		
		self.defaultDelay = Double(responseDelayMillis) / 1000.0
		self.defaultFileExtension = optionalFileExtension
		
		initStubResources(recordModePath: recordModePath, playbackModeRelativePath: playbackModeRelativePath, scenarioName: scenarioName)
		initMappings(stubResources: self.stubResources!)
	}
	
	private func newUnstubbedMappings() -> StubMappingsModel {
		return .init(map: nil, label: "New requests", logger: logger)
	}
	
	private func initStubResources(recordModePath: String, playbackModeRelativePath: String, scenarioName: String) {
		if stubResources != nil {
			return
		}
		stubResources = .init(recordRoot: recordModePath, playbackRoot: bundlePath, playbackRelativePath: playbackModeRelativePath, scenarioName: scenarioName, hostName: endpointHost)
	}
	
	private func initMappings(stubResources: StubResources) {
		do {
			try recordedMappings = .create(
				recordMappingsPath: stubResources.recordMappingsPath,
				playbackMappingsPath: stubResources.playbackMappingsPath,
				recordResponsesPath: stubResources.recordResponsesPath,
				playbackResponsesPath: stubResources.playbackResponsesPath,
				recordMappings: true,
				storageLabel: "Recorded Stubs",
				logger: self.logger
			)
			self.logger.info("recordedMappings '\(recordedMappings!.storageLabel)' created")
		} catch {
			self.logger.info("FYI: Unable to create recordedMappings: \(error)")
		}
		
		do {
			try sharedMappings = .create(
				recordMappingsPath: stubResources.recordMappingsSharedPath,
				playbackMappingsPath: stubResources.playbackMappingsSharedPath,
				recordResponsesPath: stubResources.recordResponsesSharedPath,
				playbackResponsesPath: stubResources.playbackResponsesSharedPath,
				storageLabel: "Shared Stubs",
				logger: self.logger
			)
			self.logger.info("sharedMappings '\(sharedMappings!.storageLabel)' created")
		} catch {
			self.logger.info("FYI: Unable to create sharedMappings: \(error)")
		}
		
		do {
			try sharedLocalMappings = .create(
				recordMappingsPath: stubResources.recordMappingsSharedLocalPath,
				playbackMappingsPath: stubResources.playbackMappingsSharedLocalPath,
				recordResponsesPath: stubResources.recordResponsesSharedLocalPath,
				playbackResponsesPath: stubResources.playbackResponsesSharedLocalPath,
				storageLabel: "Shared Local Stubs",
				logger: self.logger
			)
			self.logger.info("sharedLocalMappings '\(sharedLocalMappings!.storageLabel)' created")
		} catch {	
			self.logger.info("FYI: Unable to create sharedLocalMappings: \(error)")
		}
	}
	
	open func canPlayback() -> Bool {
		recordedMappings?.recordMappingsPath != nil
	}
	
	open func start() throws {
		proxy = SwiftProxy(proxyEndpoint: URL(string: self.endpoint),
						 delegate: self,
						 sslCertFilePath: sslCertPath,
						 sslPrivateKeyPath: sslPrivateKeyPath)
		try proxy?.start(host: host, port: port)
	}
	
	open func stop(timeout: Int = 20) {
		let pendingRequests = pendingRequests()
		if !pendingRequests.isEmpty && timeout > 0 {
			let pendingRequestsStrings = pendingRequests.map {
				"- \($0.requestMethod) - \($0.requestEndpoint) Request ID:\($0.requestID)"
			}.joined(separator: "\n\t\t")
			logger.info("🕘 Waiting for pending requests:\n\t\t\(pendingRequestsStrings)")
			sleep(1)
			stop(timeout: timeout - 1)
			return
		}
		do {
			try proxy?.stop()
		} catch {
			logger.error("❌ \(error)")
		}
		writeAndFlush()
	}
	
	// MARK: - Delegate implementation
	
	open func logMatchedRequest(request: HTTPRequestData, uuid: String, mappings: StubStorage, map: StubMappingsModel.Map, response: HTTPResponseData) {
		let message = "🟢 Found '\(mappings.storageLabel)':\n\t\t" +
		"- \(request.headers.method) \(request.headers.uri)\n\t\t" +
		"- Request Body: \(String(decoding: request.body, as: UTF8.self))\n\t\t" +
		"- Matched with Mapping: \(map.requestMethod) \(map.requestEndpoint)\n\t\t" +
		"- Matched Body: \(map.requestBody ?? "")\n\t\t" +
		"- Request ID:\(map.requestID), Response ID:\(map.responseID ?? "")"
		logger.info("\(message)")
	}
	
	open func logUnmatchedRequest(request: HTTPRequestData, uuid: String) {
		let body = request.body.string(encoding: .utf8) ?? "binary: \(request.body.count)"
		logger.info("⚠️ Not stubed request:\n\t\t-\(request.headers.method) \(request.headers.uri) - ID:\(uuid)\n\t\t-REQUEST BODY:\n\t\t\(body)")
	}
	
	open func logNewRequest(request: HTTPRequestData, uuid: String) {
		let body = request.body.string(encoding: .utf8) ?? "binary: \(request.body.count)"
		logger.info("🆕 🔴 New request:\n\t\t-\(request.headers.method) \(request.headers.uri) - ID:\(uuid)\n\t\t-REQUEST BODY:\n\t\t\(body)\n\t\tBeing recorded...")
	}
	
	open func request(_ request: HTTPRequestData, uuid: String) -> (request: HTTPRequestData, response: HTTPResponseData?) {
		let timeInterval = Date().timeIntervalSince1970
		
		guard stubResources != nil else {
			return (request, nil)
		}
		
		// Add request to NetworkMonitor
		trafficMonitorStorage.addRequest(uuid, request: request, time: timeInterval)
		
		for var mappings in [recordedMappings, sharedLocalMappings, sharedMappings] {
			// Looking for stub for this request in test/Shared/SharedLocal folders
			if let result = getMatchedResponse(for: request, in: &mappings) {
				logMatchedRequest(
					request: request,
					uuid: uuid,
					mappings: mappings!,
					map: result.map,
					response: result.response
				)
				
				let stubTimeInterval = Date(timeIntervalSince1970: timeInterval).timeIntervalSinceNow
				logger.info("Stub Response time: \(String(format: "%.3fs", 0 - stubTimeInterval))")
				
				trafficMonitorStorage.updateResponse(uuid, request: request, response: result.response, isStubbed: true, time: timeInterval)
				
				return (request, result.response)
			}
		}
		
		guard self.isRecording == .on else {
			logUnmatchedRequest(request: request, uuid: uuid)
			return (request, nil)
		}
		
		isNewMappingsCounter += 1
		logNewRequest(request: request, uuid: uuid)
		
		var map = StubMappingsModel.Map(requestID: uuid,
										requestHeaders: request.headers.headers,
										requestEndpoint: request.headers.uri,
										requestMethod: request.headers.method,
										requestBody: request.body.string(),
										responseStatus: 0,
										responseHeaders: [:],
										responseDelay: defaultDelay,
										responseID: nil)
		stubMutators.forEach {
			map = $0.modify(stubMap: map)
		}
		unstubbedMappings.addMapping(map)
		
		return (request, nil)
	}
	
	open func response(_ response: HTTPResponseData, uuid: String) -> HTTPResponseData {
		if response.headers.status >= 400 {
			logger.warning("⚠️ - !!WARNING!! - Response Code \(response.headers.status) - \(uuid)")
		} else {
			logger.info("🆕 - Response Code \(response.headers.status) - \(uuid)")
		}
		
		guard let trafficMonitor = trafficMonitorStorage.get(uuid) else {
			logger.error("❌ Something went wrong, request - \(uuid) not found")
			return response
		}
		
		let timeInterval = Date(timeIntervalSince1970: trafficMonitor.time).timeIntervalSinceNow
		logger.info("Server Response time: \(String(format: "%.3fs", 0 - timeInterval))")
		
		if showResponses {
			let responseHeaders = response.headers.headers
			let headerText = responseHeaders.compactMap { (key: String, value: String) in
				"\(key): \(value)"
			}.sorted(by: {$0.localizedCaseInsensitiveCompare($1) == ComparisonResult.orderedAscending}).joined(separator: "\n\t")
			
			logger.info("Server Response headers:\n\t\(headerText)\n")
			
			if response.body.isEmpty {
				logger.info("Server Response body: <empty body>")
			} else {
				let responseBody = response.body.string(encoding: .utf8) ?? "binary: \(response.body.count) bytes"
				logger.info("Server Response body:\n\(responseBody)\n")
			}
		}
		
		// Add response to network monitor
		trafficMonitorStorage.updateResponse(uuid, request: trafficMonitor.request, response: response, isStubbed: false, time: trafficMonitor.time)
		
		guard self.isRecording == .on else {
			return response
		}
		
		// Can't record when stubResources nil - work as porxy network monitor
		guard let stubResources = stubResources else {
			return response
		}
		
		guard let index = unstubbedMappings.mapIndex(withRequestID: uuid) else {
			logger.error("❌ Something went wrong, request - \(uuid) not found")
			return response
		}
		
		var modifiedResponse: (headers: [String: String], data: Data) = (response.headers.headers,
																		 response.body.makePrettyPrintedJsonData())
		stubMutators.forEach {
			modifiedResponse = $0.modify(responseHeaders: modifiedResponse.headers,
										 responseData: modifiedResponse.data)
		}
		
		unstubbedMappings.addResponse(index, responseID: UUID().uuidString, responseHeaders: modifiedResponse.headers, responseStatus: Int(response.headers.status))
		
		let responseFile = "\(stubResources.recordResponsesPath)/\(unstubbedMappings.responseIdForMap(index: index))\(defaultFileExtension)"
		do {
			let folderExisted = FileManager.default.fileExists(atPath: stubResources.recordResponsesPath.url.path)
			try FileManager.default.createDirectory(at: stubResources.recordResponsesPath.url,
													withIntermediateDirectories: true)
			// Try to force the directory to persist
			let folderCreated = FileManager.default.fileExists(atPath: stubResources.recordResponsesPath.url.path)
			if (!folderExisted && folderCreated) {
				if debugMode {
					logger.info("Folder created: \(folderCreated): '\(stubResources.recordResponsesPath.url.path)'")
				}
			}
			
			try modifiedResponse.data.write(to: responseFile.url, options: [.atomic])
			
			// Try to force the file to persist
			let fileCreated = FileManager.default.fileExists(atPath: responseFile.url.path)
			let data = FileManager.default.contents(atPath: responseFile.url.path)
			if debugMode {
				logger.info("File created: \(fileCreated): \(data?.count ?? -1) bytes: '\(responseFile.url.path)'")
			}
		} catch {
			logger.error("❌ Can't write response data to \(responseFile). \(error)")
		}
		
		return response
	}
	
	public func ignoreShared() {
		sharedMappings = nil
	}
	
	public func ignoreSharedLocal() {
		sharedLocalMappings = nil
	}
}

public extension StubRecorder {
	func networkMonitor(_ requestType: NetworkMonitorRequestType) -> [(request: HTTPRequestData, response: HTTPResponseData?)] {
		switch requestType {
			case .all:
				return trafficMonitorStorage.allValues()
			case .stubbed:
				return trafficMonitorStorage.stubbedValues()
			case .nonStubbed:
				return trafficMonitorStorage.nonStubbedValues()
		}
	}
	
	enum NetworkMonitorRequestType {
		case all
		case stubbed
		case nonStubbed
	}
}

public extension StubRecorder {
	func pendingRequests() -> [StubMappingsModel.Map] {
		unstubbedMappings.pendingRequests()
	}
	
	private func writeAndFlush() {
		guard isNewMappingsCounter > 0 else {
			return
		}
		
		guard let stubResources = stubResources else {
			return
		}
		
		// Remove requests without response
		unstubbedMappings.mappings.removeAll { map in
			map.responseStatus == 0
		}
		// Add rest of the mappings
		unstubbedMappings.addMappings(fromMappingModel: recordedMappings?.stubMappingsModel)
		
		do {
			try unstubbedMappings.jsonData().write(to: stubResources.recordMappingsPath.url, options: [.atomic])
			
			// Try to force the file to persist
			let fileCreated = FileManager.default.fileExists(atPath: stubResources.recordMappingsPath.url.path)
			let data = FileManager.default.contents(atPath: stubResources.recordMappingsPath.url.path)
			if debugMode {
				logger.info("File created: \(fileCreated): \(data?.count ?? -1) bytes: '\(stubResources.recordMappingsPath.url.path)'")
			}
			
			let allResponseFiles = try Set(FileManager.default.contentsOfDirectory(atPath: stubResources.recordResponsesPath))
			let validResponseFiles = unstubbedMappings.responseFilenameSet(withExtension: defaultFileExtension)
			let garbageFiles = allResponseFiles.subtracting(validResponseFiles)
			try garbageFiles.forEach {
				try FileManager.default.removeItem(atPath: "\(stubResources.recordResponsesPath)/\($0)")
			}
		} catch {
			logger.error("❌ \(error)")
		}
		
		recordedMappings = nil
		sharedMappings = nil
		sharedLocalMappings = nil
		
		logger.info("Unstubbed mappings persisted, creating new mappings instance")
		unstubbedMappings = .init(map: nil, label: "New requests", logger: logger)
	}
	
	private func getMatchedResponse(for request: HTTPRequestData, in recordedMappings: inout StubStorage?) -> (map: StubMappingsModel.Map, response: HTTPResponseData)? {
		
		guard let mappingModel = recordedMappings?.stubMappingsModel else {
			return nil
		}
		
		for (index, map) in mappingModel.mappingsEnumerated()  {
			guard map.activeIterations > 0 else {
				continue
			}
			
			guard doesRequestMatchEndpoint(request: request, map: map) else {
				continue
			}
			
			guard doesRequestBodyMatch(request: request, map: map) else {
				continue
			}
			
			guard doesRequestHeadersMatch(request: request, map: map) else {
				continue
			}
			
			mappingModel.decrementMappingIterations(index)
			if recordedMappings!.recordMappings {
				unstubbedMappings.addMapping(map)
			}
			
			// Response Delay - If there is a global override, always use that.
			// If there is not a global override, use the recorded delay value unless
			// it's 0.  If recorded delay is 0, use the 'defaultDelay' provided
			// when the stub was constructed - see initializer
			let delayAmount =
				GlobalVars.OVERRIDE_STUB_DELAY_MILLIS > 0 ?
					Double(GlobalVars.OVERRIDE_STUB_DELAY_MILLIS) / 1000.0 :
					map.responseDelay == 0 ?
						defaultDelay : map.responseDelay
			
			let deadline = Date().advanced(by: delayAmount)
			Thread.sleep(until: deadline)
			
			let responsePath = recordMode ? recordedMappings!.recordResponsesPath :  recordedMappings!.playbackResponsesPath
			
			return (recordedMappings!.stubMappingsModel.mapForIndex(index),
					createHTTPResponseData(from: map, responsesPath: responsePath))
		}
		
		return nil
	}
	
	private func doesRequestMatchEndpoint(request: HTTPRequestData, map: StubMappingsModel.Map) -> Bool {
		var mapRequestEndpoint = map.requestEndpoint
		
		if mapRequestEndpoint.hasPrefix("%REGEX=") {
			mapRequestEndpoint.remove(prefix: "%REGEX=")
			return request.headers.uri ~= mapRequestEndpoint && request.headers.method == map.requestMethod
		} else if mapRequestEndpoint.hasPrefix("%CONTAINS=") {
			mapRequestEndpoint.remove(prefix: "%CONTAINS=")
			return request.headers.uri.contains(mapRequestEndpoint) && request.headers.method == map.requestMethod
		} else if mapRequestEndpoint.hasPrefix("%IGNORE_ORDER=") {
			mapRequestEndpoint.remove(prefix: "%IGNORE_ORDER=")
			return doesIgnoreOrderMatch(request: request, mapRequestEndpoint: mapRequestEndpoint)
		} else {
			return request.headers.uri == mapRequestEndpoint && request.headers.method == map.requestMethod
		}
	}
	
	private func doesRequestBodyMatch(request: HTTPRequestData, map: StubMappingsModel.Map) -> Bool {
		guard let requestBodyJson = map.requestBody?.json() else {
			return true
		}
		
		let result = requestBodyJson.compare(is: .equals, request.body.json())
		return result
	}
	
	private func doesRequestHeadersMatch(request: HTTPRequestData, map: StubMappingsModel.Map) -> Bool {
		guard let mapHeaders: [String: Any] = map.requestHeaders else {
			return true
		}
		return mapHeaders.compare(is: .contains, request.headers.headers)
	}
	
	private func doesIgnoreOrderMatch(request: HTTPRequestData, mapRequestEndpoint: String) -> Bool {
		let mapRequestEndpointComponents = mapRequestEndpoint.components(separatedBy: "/")
		let requestUriComponents = request.headers.uri.components(separatedBy: "/")
		guard mapRequestEndpointComponents.count == requestUriComponents.count else {
			return false
		}
		
		for index in 0..<mapRequestEndpointComponents.count {
			if mapRequestEndpointComponents[index] != requestUriComponents[index] {
				let separator = mapRequestEndpointComponents[index].contains(",") ? "," : "&"
				let mapRequestEndpointSubcomponents: Set<String> = Set(mapRequestEndpointComponents[index].components(separatedBy: separator))
				let requestUriSubcomponents: Set<String> = Set(requestUriComponents[index].components(separatedBy: separator))
				
				guard mapRequestEndpointSubcomponents == requestUriSubcomponents else {
					return false
				}
			}
		}
		return true
	}
	
	private func createHTTPResponseData(from stubMap: StubMappingsModel.Map, responsesPath: String) -> HTTPResponseData {
		var responseData = Data()
		if let responseFile = stubMap.responseID {
			let contentPath = "\(responsesPath)/\(responseFile)\(defaultFileExtension)".url
			if debugMode {
				if FileManager.default.fileExists(atPath: contentPath.absoluteString) {
					logger.info("Matched stub found but file does not exist at: '\(contentPath.absoluteString)'")
				} else {
					logger.info("Loading response from: '\(contentPath.absoluteString)'")
				}
			}
			responseData = (try? Data(contentsOf: contentPath)) ?? Data()
			if debugMode {
				logger.info("\(responseData.count) bytes loaded from stub response")
			}
		}
		
		var modifiedResponse: (headers: [String: String], data: Data) = (stubMap.responseHeaders, responseData)
		stubMutators.forEach {
			modifiedResponse = $0.modify(responseHeaders: modifiedResponse.headers, responseData: modifiedResponse.data)
		}
		
		let headers: [(String, String)] = modifiedResponse.headers.map { ($0.key, $0.value) }
		let httpResponseHeaders = HTTPResponseHeaders.init(version: .http1_1, status: stubMap.responseStatus, headers: headers)
		
		return HTTPResponseData(headers: httpResponseHeaders, body: modifiedResponse.data)
	}
}

public  extension StubRecorder {
	enum NetworkPort {
		case random
		case custom(Int)
		
		func get() -> Int {
			switch self {
				case .random:
					return getRandomPort() ?? Int.random(in: 1024...49151)
				case .custom(let port):
					return port
			}
		}
		
		private func getRandomPort() -> Int? {
			guard let port = SocketPort(tcpPort: 0) else {
				return nil
			}
			let addressData = port.address
			port.invalidate()
			
			let addressLen = Int (addressData[1])
			var portNumber = 0
			for i in 0 ..< addressLen {
				let offset = 2 + i
				let v = Int(addressData[offset])
				// Values are in reverse order, need to shift left every
				// time we get a new value, except the first time
				if portNumber != 0 {
					portNumber = portNumber << 8
				}
				portNumber += v
			}
			return portNumber
		}
	}
}
