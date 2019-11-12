//
//  MateSnippetConverter.swift
//  HTMLRendererDemo
//
//  Created by Stephen O'Connor (MHP) on 12.11.19.
//  Copyright © 2019 Walnut Productions. All rights reserved.
//

import Foundation
import HSHTMLImageRenderer

let testSnippet = "<p style=\"text-align:center\"><span style=\"font-size:24pt\">{{guest_attribute_default_meta_attribute__title}} {{guest_name}}</span></p><p style=\"text-align:center\"><span style=\"font-size:16.0px\">{{guest_attribute_22ec88e1-45c0-486f-8863-9438fa489aae}}</span></p>"

typealias ConversionData = (snippet: String, template: String)

struct FontSize {
    let value: Float
    let unit: Unit
    
    enum Unit: String, CaseIterable {
        case points = "pt"
        case pixels = "px"
        case relative = "em"
        case percentOfParent = "%"
        case viewportHeight = "vh"
        case viewportWidth = "vw"
        
        static var allRawCases: [String] {
            return self.allCases.map { $0.rawValue }
        }
    }
}

class MateSnippetConverter: NSObject {
    
    static let shared = MateSnippetConverter()
    
    public var guest: Guest?  // user info, etc.
    public var event: Event?  // QR Code info, data, etc.
    
    internal var xmlParser: XMLParser?

    var transformedSnippet: String = ""
    var cssToInject: String = ""
    
    // parsing variables
    private var elementName: String?
    private var fontSize: String?
    private var alignment: String?
    private var attributeName: String?
    private var styleAttributeStrings: [String] = []
    
    
    override init() {
        super.init()
    }
    
    func convert(_ data: ConversionData, replacements: [String: String]) -> ConversionData {
        
        let parser = self.parser(with: data.snippet)
        self.xmlParser = parser
        let success = parser.parse()
        
        
        // the first thing you want to do is make absolute sizes relative
        // if you inject CSS, make sure you also leave it for injecting more
        
        // it would seem that for each element, it has a font-size, an alignment, and an attribute.  We can re-write that into a div with these properties
        var altered = extractFontSizesAndMakeRelative(data: data)
        altered = extractTemplateAttributesAndInjectValues(data: altered)
        
        #warning("Implement Me")
        guard self.xmlParser == nil else {
            fatalError("I thought the XMLParser would do it synchronously.")
        }
        return altered
    }
    
    private func extractFontSizesAndMakeRelative(data: ConversionData) -> ConversionData {
        print(#function)
        // read out all font sizes
        // weird logic here, but look at various sizes, and choose something in the middle, or the company name, or something, as the base font size, then make the others relative to that.
        
        #warning("Implement Me")
        return data
    }
    
    private func extractTemplateAttributesAndInjectValues(data: ConversionData) -> ConversionData {
        
        print(#function)
        
        // here you'll want to get the guest attribute inside the {{ }}
        
        // you'll want to get the value for that attribute in the dictionary (self.guest?), then replace
        
        // you'll want to re-create the snippet using either divs, or p's, giving an id to that div, and injecting css.
        
        
        
        #warning("Implement Me")
        return data
    }
    
    private func parser(with testSnippet: String) -> XMLParser {
        let string = "<?xml version=\"1.0\"?><html>"+testSnippet+"</html>"
        guard let data = string.data(using: .utf8) else {
            fatalError("Really have no idea why here...")
        }
        
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser
    }
}

extension MateSnippetConverter: XMLParserDelegate {
    
    func parserDidStartDocument(_ parser: XMLParser) {
        print(#function)
        self.transformedSnippet = ""
        self.cssToInject = ""
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        print("\(#function)  \(elementName)\t\(qName ?? "")")
        print(attributeDict)
        
        if elementName == "p" {
            // this is like a new element
            self.styleAttributeStrings = []
            self.styleAttributeStrings.append(contentsOf: attributeDict.map({ $0.value }))
        } else if elementName == "span" {
            self.styleAttributeStrings.append(contentsOf: attributeDict.map({ $0.value }))
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        print("\(#function)  \(string)")
        
        // once we've found characters, it means we've likely got all the attributes we need.
        
        // here we have to parse the template fields and apply their values
        // the key to this working is that the replacements.keys are going to be in the snippet.
        
        // we could also be creating a new snippet with new css.
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        print("\(#function)  \(elementName)\t\(qName ?? "")")
    }
    
    func parserDidEndDocument(_ parser: XMLParser) {
        print(#function)
        self.xmlParser = nil
    }
    
    // MARK: - Helpers
    func extractTextAlignment(from styleString: String) -> String? {
        let searchString = "text-align:"
        guard styleString.contains(searchString) else {
            return nil
        }
        
        return styleString.replacingOccurrences(of: searchString, with: "").trimmingCharacters(in: .whitespaces)
    }
    
    func extractFontSize(from styleString: String) -> FontSize? {
        let searchString = "font-size:"
        guard styleString.contains(searchString) else {
            return nil
        }
        let knownUnits = FontSize.Unit.allRawCases
        let truncated = styleString.replacingOccurrences(of: searchString, with: "").trimmingCharacters(in: .whitespaces)
        
        // now we should have a value and a unit.
        var unitInUse = ""
        for unit in knownUnits {
            if truncated.contains(unit) {
                unitInUse = unit
                break
            }
        }
        if unitInUse.count > 0 {
            let valueString = truncated.replacingOccurrences(of: unitInUse, with: "")
            guard let value = Float(valueString) else {
                print("Could not parse a value from the string")
                return nil
            }
            return FontSize(value: value, unit: FontSize.Unit(rawValue: unitInUse)!)
        }
        return nil
    }
}
