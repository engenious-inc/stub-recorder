import Foundation
import Logging

public struct StubStorage {
	public var stubMappingsModel: StubMappingsModel
	public private(set) var recordMappingsPath: String
	public private(set) var playbackMappingsPath: String
	public private(set) var recordResponsesPath: String
	public private(set) var playbackResponsesPath: String
	
	public private(set) var recordMappings: Bool
	public private(set) var storageLabel: String
	
	static func create(recordMappingsPath: String, playbackMappingsPath: String, recordResponsesPath: String, playbackResponsesPath: String, recordMappings: Bool = false, storageLabel: String = "Stub", logger: Logger? = nil) throws -> StubStorage {
		
		let stubMappingModel = try StubMappingsModel.create(path: playbackMappingsPath)
		
		return StubStorage(
			stubMappingsModel: StubMappingsModel(map: stubMappingModel.mappings, label: storageLabel, logger: logger),
			recordMappingsPath: recordMappingsPath,
			playbackMappingsPath: playbackMappingsPath,
			recordResponsesPath: recordResponsesPath,
			playbackResponsesPath: playbackResponsesPath,
			recordMappings: recordMappings, storageLabel: storageLabel)
	}
}
