import Foundation

typealias JSON = [String: Any]

public extension Data {
	
	func string(encoding: String.Encoding = .utf8) -> String? {
		String(data: self, encoding: encoding)
	}
	
	func makePrettyPrintedJsonData() -> Data {
		guard let json = try? JSONSerialization.jsonObject(with: self, options: .allowFragments) else {
			return self
		}
		return (try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])) ?? self
	}
}

public extension Date {
	var jsonFormat: String {
		let formatter: DateFormatter = .init()
		formatter.timeZone = TimeZone(identifier: "GMT")
		formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
		return formatter.string(from: self)
	}
	
	var tomorrow: Date {
		return addingTimeInterval(86400.0)
	}
}

public extension String {
	
	/// Add regex comparison to strings
	static func ~= (lhs: String, rhs: String) -> Bool {
		guard let regex = try? NSRegularExpression(pattern: rhs) else { return false }
		let range = NSRange(location: 0, length: lhs.utf16.count)
		return regex.firstMatch(in: lhs, options: [], range: range) != nil
	}
	
	/// Convenience to make a URL from a String
	var url: URL {
		URL(fileURLWithPath: self)
	}
	
	func withPathParts(_ parts: [String]) -> String {
		var response = [self]
		response.append(contentsOf: parts)		
		return response.joined(separator: "/")
	}
	
	mutating func remove(prefix: String) {
		guard self.hasPrefix(prefix) else {
			return
		}
		self = String(self.dropFirst(prefix.count))
	}
	
	func replacing(regex: String, with value: String) -> String {
		if let regex = try? NSRegularExpression(pattern: regex) {
			let range = NSRange(location: 0, length:  self.count)
			return regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: value)
		}
		return self
	}
}

extension Encodable {
	
	/// Convenience for returning a [String: Any] dictionary from an Encodable
	func json() -> JSON {
		do {
			let jsonData: Data = try (self as? Data) ?? (self.jsonData())
			let json = try JSONSerialization.jsonObject(with: jsonData, options: .allowFragments)
			return json as? JSON ?? JSON()
		}
		catch {
			return [:]
		}
	}
	
	/// If Encodable is a string return Data of it, otherwise return Data from a JSONEncoder apply pretty print and key sorting.
	func jsonData() throws -> Data {
		if let string = self as? String {
			return Data(string.utf8)
		}
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		return try encoder.encode(self)
	}
}

extension Dictionary where Key == String, Value == Any {
	
	public enum CustomDictionaryCompareType {
		case equals
		case contains
	}
	
	/// Adds customized comparison to [String:Any] Dictionary, providing support for customized logic to support special operators:
	///
	/// All values for every key must match between this Dictionary and the 'other' dictionary
	///
	/// If a the value for a common key in 'this' Dictionary is `"#AnyValue#"` then it is considered a match - accepts all values as equal
	///
	/// If a the value for a common key in 'this' Dictionary begins with `"%REGEX="` then use the value as a regex expression to determine equality with the 'other' value
	///
	/// If a the value for a common key in 'this' Dictionary begins with `"%CONTAINS="` then do a 'String.contains' comparison to determine equality with the 'other' value
	///
	/// If a the value for a common key in 'this' Dictionary begins with `"%IGNORE_ORDER="` then treat both values as comma-separated array, ignoring string order, and determine equality if the arrays have the same values
	public func compare(is compareType: CustomDictionaryCompareType, _ other: [String: Any]) -> Bool {
		// Make sure we are comparing all keys if this is an 'equals' comparison
		guard compareType == .contains || keys.count == other.keys.count else {
			return false
		}
		
		for key in keys {
			guard let otherValue = other[key] else { return false }
			if let myValue = self[key] as? String, myValue == "#AnyValue#" { continue }
			
			if let myValue = self[key] as? [String: Any],
			   let otherValue = otherValue as? [String: Any] {
				guard myValue.keys.count == otherValue.keys.count else { return false }
				guard myValue.compare(is: compareType, otherValue) else { return false }
				continue
			}
			
			if let myValue = self[key] as? [AnyHashable],
			   let otherValue = otherValue as? [AnyHashable] {
				guard myValue.count == otherValue.count else { return false }
				for index in 0..<myValue.count {
					let result = otherValue.first { ["": myValue[index]].compare(is: compareType, ["": $0]) }
					guard result != nil else { return false }
				}
				continue
			}
			
			guard let myValueAnyHashable = self[key] as? AnyHashable,
				  let otherValueAnyHashable = otherValue as? AnyHashable else {
				return false
			}
			
			if var myValueString = myValueAnyHashable as? String,
			   let otherValueString = otherValueAnyHashable as? String,
			   myValueString.hasPrefix("%REGEX=") {
				
				myValueString.remove(prefix: "%REGEX=")
				return otherValueString ~= myValueString
			}
			
			if var myValueString = myValueAnyHashable as? String,
			   let otherValueString = otherValueAnyHashable as? String,
			   myValueString.hasPrefix("%CONTAINS=") {
				
				myValueString.remove(prefix: "%CONTAINS=")
				let myValueStringComponents = myValueString.components(separatedBy: ",")
				let result = myValueStringComponents.filter {
					otherValueString.contains($0)
				}
				
				return result.count == myValueStringComponents.count
			}
			
			if var myValueString = myValueAnyHashable as? String,
			   let otherValueString = otherValueAnyHashable as? String,
			   myValueString.hasPrefix("%IGNORE_ORDER=") {
				
				myValueString.remove(prefix: "%IGNORE_ORDER=")
				let myValueStringComponents = myValueString.components(separatedBy: ",").sorted()
				let otherValueStringComponents = otherValueString.components(separatedBy: ",").sorted()
				
				return myValueStringComponents == otherValueStringComponents
			}
			
			guard myValueAnyHashable == otherValueAnyHashable else {
				return false
			}
		}
		
		return true
	}
}
