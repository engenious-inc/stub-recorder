import Foundation

public protocol StubMappingsMutable {
	func modify(stubMap: StubMappingsModel.Map) -> StubMappingsModel.Map
	func modify(responseHeaders: [String: String], responseData: Data) -> (headers: [String: String], data: Data)
}
