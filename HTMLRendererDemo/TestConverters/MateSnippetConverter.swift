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
    
    // these three shall always be either all defined or all undefined
    internal var xmlParser: XMLParser?
    internal var regex: NSRegularExpression?
    internal var templateValueReplacements: [String: String]?
    
    var transformedSnippet: String = ""
    var cssToInject: String = ""
    
    // parsing variables
    private var elementName: String?
    private var fontSize: String?
    private var alignment: String?
    private var attributeName: String?
    private var styleAttributeStrings: [String] = []
    
    struct ContentElement {
        let identifier: String
        let content: String
        let attributes: [String: Any]
    }
    var contentElements: [ContentElement] = []
    
    override init() {
        super.init()
    }
    
    func convert(_ data: ConversionData, replacements: [String: String]) -> ConversionData {
        
        let parser = self.parser(with: data.snippet)
        self.xmlParser = parser
        
        // original pattern that works on regextester.com is "\{\{([^\{\}]*)\}\}+"
        // but we have to escape it for iOS
        let pattern = "\\{\\{([^\\{\\}]*)\\}\\}+"
        self.regex = try! NSRegularExpression(pattern: pattern, options: [])
        
        self.templateValueReplacements = replacements
        
        self.contentElements = []
        
        let success = parser.parse()
    
        
        // what we should have now is an array of ContentElement objects, that are analogously like the incoming snippet.
        // that snippet has a series of `p` tags, embedded in them span tags, and the css is scattered throughout their tag attributes.
        
        // first, THIS CLASS needs to include target size of the label.  It will help determine how to scale the fonts.
        
        // now we have content that needs to be in a container, and we know its properties.
        // so we can generate a new snippet while adding those things to the CSS.
                
        // so we could go through and adjust the parsed font sizes and make them relative.
        
        // if you inject CSS into the template, make sure you also leave it for injecting more (i.e. __ADDITIONAL_CSS__ ).  It will get replaced with "" later.
        
        // it would seem that for each element, it has a font-size, an alignment, and an attribute.  We can re-write that into a div with these properties
        
        
        
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
        
        // it seems that the MATE backend only returns "style" attributes, so we can just take the values.
        
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
        
        var content = string
        
        // once we've found characters, it means we've likely got all the attributes we need.
        
        // here we have to parse the template fields and apply their values
        // the key to this working is that by specification, the replacements.keys are going to be in the snippet somewhere
        regex?.enumerateMatches(in: string,
                                options: [],
                                range: NSRange(location: 0, length: string.count),
                                using: { (result, flags, stop) in
                                    if let result = result {
                                        // the shorter string will be the match without the brackets.
                                        let matches = result.sortedMatches(in: string)
                                        if let key = matches.first?.0, let template = matches.last?.0 {
                                            if let value = self.templateValueReplacements?[key] {
                                                // we have the value for that key
                                                content = content.replacingOccurrences(of: template, with: value)
                                            }
                                        }
                                    }
        })
        
        // content has now had its template placeholders replaced and is now 'real content'
        
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
        self.regex = nil
        self.templateValueReplacements = nil
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

/// This extension is for our use case where typically the matches have the content and the content wrapped in curly braces.
fileprivate extension NSTextCheckingResult {

    /// shortest string first
    func sortedMatches(in original: String) -> [(String, NSRange)] {
        var strings: [(String, NSRange)] = []
        for i in 0..<self.numberOfRanges {
            let range = self.range(at: i)
            let extractedString = (original as NSString).substring(with: range)
            strings.append((extractedString, range))
        }
        return strings.sorted { return $0.0.count < $1.0.count }
    }
    
    /// shortest string first
    func sortedMatchedStrings(in original: String) -> [String] {
        return self.sortedMatches(in: original).map { $0.0 }
    }
}
