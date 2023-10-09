import Foundation
import Logging
import SwiftProxy

public struct TrafficRecord {
	public var request: HTTPRequestData
	public var response: HTTPResponseData?
	public var isStubbed: Bool
	public var time: TimeInterval
}

public class TrafficMonitor {
	static let INITIAL_CAPACITY = 32
	static let LOW_WATER_MARK = 4
	
	private var storage: [String:TrafficRecord] = [:]
	private var logger: Logger = StubLogger.stream_logger
	
	init(logger: Logger? = nil) {
		storage.reserveCapacity(Self.INITIAL_CAPACITY)
		if let logger {
			self.logger = logger
		}
	}
	
	public func get(_ uuid: String) -> TrafficRecord? {
		return storage[uuid]
	}
	
	public func addRequest(_ uuid: String, request: HTTPRequestData, time: TimeInterval) {
		// Avoid concurrency issues by sync execution of storage modification.
		GlobalVars.storageModificationQueue.sync {
			if get(uuid) != nil {
				return
			}
			
			let newRecord = TrafficRecord(request: request, isStubbed: false, time: time)
			
			storage.updateValue(newRecord, forKey: uuid)
			
			// Make sure we have sufficient remaining capacity.  The OS allocates
			// storage in increments and when re-allocated pointers can get moved
			// around - that is why this is being run in a 'sync' block
			if storage.capacity - storage.count < Self.LOW_WATER_MARK {
				let newCapacity = storage.count + Self.INITIAL_CAPACITY
				if GlobalVars.NETWORK_STUB_DEBUG {
					logger.info("Expanding monitor capacity to: \(newCapacity)")
				}
				storage.reserveCapacity(newCapacity)
			}
		}
	}
	
	public func updateResponse(_ uuid: String, request: HTTPRequestData, response: HTTPResponseData, isStubbed: Bool, time: TimeInterval) {
		guard var existing = get(uuid) else {
			return
		}
		existing.request = request
		existing.response = response
		existing.isStubbed = isStubbed
		existing.time = time
	}
	
	public func allValues() -> [(request: HTTPRequestData, response: HTTPResponseData?)] {
		return storage.values
			.sorted{$0.time < $1.time}
			.map { ($0.request, $0.response) }
	}
	
	public func stubbedValues() -> [(request: HTTPRequestData, response: HTTPResponseData?)] {
		return storage.values
			.sorted{$0.time < $1.time}
			.filter { $0.isStubbed }
			.map { ($0.request, $0.response) }
	}
	
	public func nonStubbedValues() -> [(request: HTTPRequestData, response: HTTPResponseData?)] {
		return storage.values
			.sorted{$0.time < $1.time}
			.filter { !$0.isStubbed }
			.map { ($0.request, $0.response) }
	}
}
