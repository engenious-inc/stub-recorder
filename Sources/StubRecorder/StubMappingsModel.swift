import Foundation
import Logging
import SwiftProxy

// MARK: - Requests
public class StubMappingsModel: Codable {
	static let INITIAL_CAPACITY = 32
	static let LOW_WATER_MARK = 4
	
	public var mappings: [Map]
	public var logger: Logger = StubLogger.stream_logger
	public var label: String = "Unspecified mapping model"

	enum CodingKeys: String, CodingKey {
		case mappings
	}
	
	// MARK: - Request
	public struct Map: Codable {
		public var requestID: String
		public var requestHeaders: [String: String]?
		public var requestEndpoint: String
		public var requestMethod: String
		public var requestBody: String?
		public var responseStatus: Int
		public var responseHeaders: [String: String]
		public var responseDelay: TimeInterval
		public var responseID: String?
		public var activeIterations: Int
		
		public init(requestID: String,
			 requestHeaders: [String : String]?,
			 requestEndpoint: String,
			 requestMethod: String,
			 requestBody: String?,
			 responseStatus: Int,
			 responseHeaders: [String : String],
			 responseDelay: TimeInterval = 0,
			 responseID: String?,
			 activeIterations: Int = 1,
			 label: String = "Unspecified map") {
			self.requestID = requestID
			self.requestHeaders = requestHeaders
			self.requestEndpoint = requestEndpoint
			self.requestMethod = requestMethod
			self.requestBody = requestBody
			self.responseStatus = responseStatus
			self.responseHeaders = responseHeaders
			self.responseDelay = responseDelay
			self.responseID = responseID
			self.activeIterations = activeIterations
		}
		
		fileprivate mutating func decrementIterations() {
			self.activeIterations -= 1
		}
	}

	public init(logger: Logger? = nil) {
		mappings = []
		mappings.reserveCapacity(Self.INITIAL_CAPACITY)
		if let logger {
			self.logger = logger
		}
	}
	
	convenience init(map: [Map]?, label: String? = nil, logger: Logger? = nil) {
		self.init(logger: logger)
		if let map {
			self.mappings = map
		}
		if let label {
			self.label = label
		}
		if let logger {
			self.logger = logger
		}
	}
	
	public func addMapping(_ map: Map) {
		// Arrays are not thread safe, force a sync operation when modifying the map.
		GlobalVars.storageModificationQueue.sync {
			if GlobalVars.NETWORK_STUB_DEBUG {
				logger.info("Adding map to '\(label)' for requestID '\(map.requestID)' at index \(mappings.endIndex)")
			}
			mappings.append(map)
			if mappings.capacity - mappings.count < Self.LOW_WATER_MARK {
				let newCapacity = mappings.count + Self.INITIAL_CAPACITY
				if GlobalVars.NETWORK_STUB_DEBUG {
					logger.info("Expanding mappings '\(label)' capacity to: \(newCapacity)")
				}
				mappings.reserveCapacity(newCapacity)
			}
		}
	}
	
	public func addMappings(fromMappingModel otherModel: StubMappingsModel?) {
		otherModel?.mappings.forEach { recordedMap in
			if !mappings.contains(where: { newMap in newMap.requestID == recordedMap.requestID }) {
				addMapping(recordedMap)
			}
		}
	}
	
	public func addResponse(_ index: Int, responseID: String, responseHeaders: [String: String], responseStatus: Int) {
		GlobalVars.storageModificationQueue.sync {
			mappings[index].responseID = responseID
			mappings[index].responseHeaders = responseHeaders
			mappings[index].responseStatus = responseStatus
		}
	}
	
	public func decrementMappingIterations(_ index: Int) {
		GlobalVars.storageModificationQueue.sync {
			mappings[index].decrementIterations()
		}
	}
	
	public func mapIndex(withRequestID uuid: String) -> Int? {
		
		let foundIndex = mappings.firstIndex(where: { $0.requestID == uuid })
		if GlobalVars.NETWORK_STUB_DEBUG {
			logger.info("Looking in  '\(label)' for index for request id: \(uuid), found: \(foundIndex ?? -1)")
		}
		
		return foundIndex
	}
	
	public func mapForIndex(_ index: Int) -> Map {
		return mappings[index]
	}
	
	public func responseIdForMap(index: Int) -> String {
		return mappings[index].responseID!
	}
	
	public func pendingRequests() -> [StubMappingsModel.Map] {
		let response = mappings.filter { $0.responseStatus == 0 }
		return response
	}
	
	public func responseFilenameSet(withExtension: String = "") -> Set<String> {
		let responseIdSet = Set(mappings.compactMap { $0.responseID })
		return Set(responseIdSet.map {"\($0)\(withExtension)"})
	}
	
	public func mappingsEnumerated() -> EnumeratedSequence<[Map]> {
		return mappings.enumerated()
	}
	
	public static func create(data: Data) throws -> StubMappingsModel {
		return try JSONDecoder().decode(StubMappingsModel.self, from: data)
	}

	public static func create(_ json: String, using encoding: String.Encoding = .utf8) throws -> StubMappingsModel {
		guard let data = json.data(using: encoding) else {
			throw NSError(domain: "JSONDecoding", code: 1, userInfo: nil)
		}
		return try create(data: data)
	}

	public static func create(path: String) throws -> StubMappingsModel {
		let fileURL = URL(fileURLWithPath: path)
		if !FileManager.default.fileExists(atPath: fileURL.relativePath) {
			throw NSError(domain: "FileNotFound: \(fileURL.relativePath)", code: 1)
		}
		
		return try create(data: try Data(contentsOf: URL(fileURLWithPath: path)))
	}
}
