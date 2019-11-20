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
    
    var cssValue: String {
        return "\(value)\(unit.rawValue);"
    }
    
    /// should return fontSize in .em
    func normalize(baseFontSizeInPt: Float, viewportWidth: Float) -> FontSize {
        switch self.unit {
        case .pixels:
            #warning("Do you need to do a scale conversion?")
            let relative = self.value / baseFontSizeInPt
            return FontSize(value: relative, unit: .relative)
        case .points:
            let relative = self.value / baseFontSizeInPt
            return FontSize(value: relative, unit: .relative)
        default:
            fatalError("Did not know we could get values like this: \(self.unit.rawValue)")
        }
    }
}

class MateSnippetConverter: NSObject {
    
    enum SupportedAttributes: String {
        case fontSize = "font-size:" // matches the CSS property
        case textAlignment = "text-align:" // matches the CSS property
    }
    
    enum ParsingError: Error {
        case unexpected
    }
    
    // these three shall always be either all defined or all undefined
    internal var xmlParser: XMLParser?
    internal var regex: NSRegularExpression?
    internal var templateValueReplacements: [String: String]?
    
    let targetOutputWidth: Float
    
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
    
    /// what we parse from a snippet
    var originalContentElements: [ContentElement] = []
    
    /// the adjusted originalContentElements whose fontSizes are in a parametric format, relative to a base font-size which is determined in relation to the targetOutputSize
    var normalizedContentElements: [ContentElement] = []
    
    init(targetOutputWidth: Float) {
        self.targetOutputWidth = targetOutputWidth
        super.init()
    }
    
    static func baseFontSize(for targetWidth: Float) -> Float {
        
        // key is target width, value is base size.  Should be in increasing order.
        let nominalSizes: [(Float, Float)] = [
            (100, 9),
            (200, 10),
            (300, 14),
            (500, 18)
        ]
        var chosenPairing = nominalSizes.first!
        for pairing in nominalSizes {
            if targetWidth < pairing.0 {
                return chosenPairing.1
            } else {
                chosenPairing = pairing
            }
        }
        return chosenPairing.1
    }
    
    func convert(_ data: ConversionData, replacements: [String: String]) -> ConversionData {
        
        let parser = self.parser(with: data.snippet)
        self.xmlParser = parser
        
        // original pattern that works on regextester.com is "\{\{([^\{\}]*)\}\}+"
        // but we have to escape it for iOS
        let pattern = "\\{\\{([^\\{\\}]*)\\}\\}+"
        self.regex = try! NSRegularExpression(pattern: pattern, options: [])
        
        self.templateValueReplacements = replacements
        
        self.originalContentElements = []
        
        let _ = parser.parse()
    
        // self.originalContentElements should now be parsed.
        
        // what we should have now is an array of ContentElement objects, that are analogously like the incoming snippet.
        // that snippet has a series of `p` tags, embedded in them span tags, and the css is scattered throughout their tag attributes.

        // now we have organized these into single elements that can be re-written into div tags.
        let baseSize = MateSnippetConverter.baseFontSize(for: self.targetOutputWidth)
        
        // using the targetOutputWidth property of this object, we can re-calculate the fontSize values.
        self.normalizedContentElements = self.originalContentElements.map({ (original) -> ContentElement in
            
            guard let originalFont = original.attributes[SupportedAttributes.fontSize.rawValue] as? FontSize else {
                fatalError("I don't think this can happen.")
            }
            
            let normalizedFont = originalFont.normalize(baseFontSizeInPt: baseSize, viewportWidth: self.targetOutputWidth)
            
            var newAttribs = original.attributes
            newAttribs[SupportedAttributes.fontSize.rawValue] = normalizedFont
            
            return ContentElement(identifier: original.identifier, content: original.content, attributes: newAttribs)
        })
        

        // now we have re-purposed content.  Now to generate some html and css from it, not forgetting to set the base-size.
        
        // this is where you return a new snippet
        let alteredSnippet = self.generateSnippet(from: self.normalizedContentElements)
        let alteredTemplate = self.templateWithInjectedCSS(data.template, with: self.normalizedContentElements)
        
        // also this is where you inject new CSS.
        
        // if you inject CSS into the template, make sure you also leave it for injecting more (i.e. __ADDITIONAL_CSS__ ).  It will get replaced with "" later.
        
        guard self.xmlParser == nil else {
            fatalError("I thought the XMLParser would do it synchronously.")
        }
        return (snippet: alteredSnippet, template: alteredTemplate)
    }
    
    private func parser(with testSnippet: String) -> XMLParser {
        // we have to embed the snippets in a master tag for the XMLParser to parse it all.
        let string = "<?xml version=\"1.0\"?><html>"+testSnippet+"</html>"
        guard let data = string.data(using: .utf8) else {
            fatalError("Really have no idea why here...")
        }
        
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser
    }
}

extension MateSnippetConverter {
    
    fileprivate func generateSnippet(from contentElements: [ContentElement]) -> String {
        var output = ""
        for element in contentElements {
            output += "<div id=\"\(element.identifier)\" class=\"label_element\">"
            output += "\(element.content)"
            output += "</div>\n"
        }
        return output
    }
    
    fileprivate func templateWithInjectedCSS(_ baseTemplate: String, with contentElements: [ContentElement]) -> String {
        var additionalCSS = "\n"
        for element in contentElements {
            let fontSize = element.attributes[SupportedAttributes.fontSize.rawValue] as! FontSize
            let alignment = element.attributes[SupportedAttributes.textAlignment.rawValue] as! String
            
            let additionalElement = """
            #\(element.identifier) { \n
            font-size: \(fontSize.cssValue)\n
            \(alignment)\n
            }\n
            """
            additionalCSS += additionalElement
        }
        
        additionalCSS += "\n\(TemplateAttributes.Key.additionalCSS)"
        
        return baseTemplate.replacingOccurrences(of: TemplateAttributes.Key.additionalCSS, with: additionalCSS)
    }
}

extension MateSnippetConverter: XMLParserDelegate {
    
    func parserDidStartDocument(_ parser: XMLParser) {
        print(#function)
        self.originalContentElements = []
        self.styleAttributeStrings = []
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
        
        // string will be for one element in the label.
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
        
        // now to get text alignment.  We deal in labels.  Align center is a reasonable default.
        let alignment: String = self.extractCSSTextAlignment(from: self.styleAttributeStrings) ?? "text-align: center;"
        
        // now to get font size.  If unavailable, use base size.
        let fontSize: FontSize = self.extractFontSize(from: self.styleAttributeStrings) ?? FontSize(value: 1.0, unit: .relative)
        
        let element = ContentElement(
            identifier: "element_\(self.originalContentElements.count)",
            content: content,
            attributes: [SupportedAttributes.fontSize.rawValue: fontSize,
                         SupportedAttributes.textAlignment.rawValue: alignment]
        )
        
        self.originalContentElements.append(element)
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
    
    // MARK: - Parsing Helpers
    private func extractCSSTextAlignment(from availableStyleStrings: [String]) -> String? {
        for css in availableStyleStrings {
            if css.contains(SupportedAttributes.textAlignment.rawValue) {
                return "\(css);"
            }
        }
        return nil
    }
    
    private func extractFontSize(from availableStyleStrings: [String]) -> FontSize? {
        print(#function)
        
        for css in availableStyleStrings {
            if css.contains(SupportedAttributes.fontSize.rawValue) {
                return extractFontSize(from: css)
            }
        }
        return nil
    }
    
    func extractFontSize(from styleString: String) -> FontSize? {
        let searchString = SupportedAttributes.fontSize.rawValue
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
