import Foundation

public struct StubResources {
	public var mappingsFile: String { "mappings.json" }
	public var responsesFolder: String { "responses" }
	public var sharedFolder: String { "Shared" }
	public var sharedLocalFolder: String { "SharedLocal" }
	
	let recordRoot: String
	let playbackRoot: String
	let playbackRelativePath: String
	let scenarioName: String
	let hostName: String
	
	var recordMappingsPath: String {
		recordRoot.withPathParts([scenarioName, hostName, mappingsFile])
	}
	var recordMappingsSharedPath: String {
		recordRoot.withPathParts([sharedFolder, hostName, mappingsFile])
	}
	
	var recordMappingsSharedLocalPath: String {
		recordRoot.withPathParts([sharedLocalFolder, hostName, mappingsFile])
	}
	
	var recordResponsesPath: String {
		recordRoot.withPathParts([scenarioName, hostName, responsesFolder])
	}
	
	var recordResponsesSharedPath: String {
		recordRoot.withPathParts([sharedFolder, hostName, responsesFolder])
	}
	
	var recordResponsesSharedLocalPath: String {
		recordRoot.withPathParts([sharedLocalFolder, hostName, responsesFolder])
	}
	
	var playbackMappingsPath: String {
		playbackRoot.withPathParts([playbackRelativePath, scenarioName, hostName, mappingsFile])
	}
	
	var playbackMappingsSharedPath: String {
		playbackRoot.withPathParts([playbackRelativePath, sharedFolder, hostName, mappingsFile])
	}
	
	var playbackMappingsSharedLocalPath: String {
		playbackRoot.withPathParts([playbackRelativePath, sharedLocalFolder, hostName, mappingsFile])
	}
	
	var playbackResponsesPath: String {
		playbackRoot.withPathParts([playbackRelativePath, scenarioName, hostName, responsesFolder])
	}
	
	var playbackResponsesSharedPath: String {
		playbackRoot.withPathParts([playbackRelativePath, sharedFolder, hostName, mappingsFile])
	}
	
	var playbackResponsesSharedLocalPath: String {
		playbackRoot.withPathParts([playbackRelativePath, sharedLocalFolder, hostName, mappingsFile])
	}
}
