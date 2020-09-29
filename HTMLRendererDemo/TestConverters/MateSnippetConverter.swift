//
//  MateSnippetConverter.swift
//  HTMLRendererDemo
//
//  Created by Stephen O'Connor on 12.11.19.
//  Copyright © 2019 Stephen O'Connor. All rights reserved.
//


import Foundation
import HSHTMLImageRenderer

fileprivate let testSnippet = "<p style=\"text-align:center\"><span style=\"font-size:24pt\">{{guest_attribute_default_meta_attribute__title}} {{guest_name}}</span></p><p style=\"text-align:center\"><span style=\"font-size:16.0px\">{{guest_attribute_22ec88e1-45c0-486f-8863-9438fa489aae}}</span></p>"

typealias ConversionData = (snippet: String, template: String?)

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
    
    /// should return fontSize in vw
    func normalized(to viewportWidth: Float) -> FontSize {
        
        let conversionConstant: Float = conversionFactor(for: viewportWidth) // Experimentally determined using viewportWidth of 900, fontSizes of 24pt, 16px
        
        switch self.unit {
        case .pixels:
            // TODO: ("Do you need to do a scale conversion?")
            let relative = 100.0 * conversionConstant * self.value / viewportWidth
            return FontSize(value: relative, unit: .viewportWidth)
        case .points:
            // looking to this chart,
            // https://websemantics.uk/tools/convert-pixel-point-em-rem-percent/
            // and also assuming our template uses a base font size of 16px
            // we can see that to get px from pt, you take
            let relative = 100.0 * conversionConstant * (self.value * 4/3) / viewportWidth
            return FontSize(value: relative, unit: .viewportWidth)
        case .relative:
            // TODO: Inject base font-size.  For now assuming 16px.
            let baseFontSizePx = 16
            let relative = 100.0 * conversionConstant * (self.value * Float(baseFontSizePx)) / viewportWidth
            return FontSize(value: relative, unit: .viewportWidth)
        default:
            fatalError("Did not know we could get values like this: \(self.unit.rawValue)")
        }
    }
    
    /// This was experimentally determined
    private func conversionFactor(for viewportWidth: Float) -> Float {
        let dataPoint1 = (Float(400.0), Float(1.0))
        let dataPoint2 = (Float(700.0), Float(0.995))
        let slope = (dataPoint2.1 - dataPoint1.1) / (dataPoint2.0 - dataPoint1.0)
        
        let y = dataPoint1.1 + (viewportWidth - dataPoint1.0) * (slope)
        return y
    }
}

class MateSnippetConverter: NSObject {
    
    enum SupportedAttributes: String {
        case fontSize = "font-size:" // matches the CSS property
    }

    enum ParsingError: Error {
        case unexpected
    }
      
    // it will do the swaps by replacing occurrences of key with value.
    internal var textTemplateReplacements: [String: String] = [:]

    // i.e. the width of the label that the snippets were designed for.
    let viewportWidth: Float
    
    init(viewportWidth: Float) {
        self.viewportWidth = viewportWidth
        super.init()
    }
    

    func convert(snippet: String, template: String?, replacements: [String: String]) -> ConversionData {
        
        self.textTemplateReplacements = [:]
        
        // this will search the template for each key in the replacements, then add to a dictionary to make replacing easier.
        self.findTemplateTokens(in: snippet, using: replacements)  // will add values to the textTemplateReplacements
        
        // self.textTemplateReplacements should now be filled with templateValueReplacements
        if template != nil {
            self.addTextReplacementsAssociatedWithFontSize(in: snippet)
        }
            
        // this is where you return a new snippet
        let alteredSnippet = self.alteredSnippet(using: self.textTemplateReplacements, originalSnippet: snippet)
        let alteredTemplate = template // the HSHTMLImageRenderer will clean it up.
        
        return (snippet: alteredSnippet, template: alteredTemplate)
    }
    
    private func alteredSnippet(using textReplacements: [String: String], originalSnippet: String) -> String {
        
        var altered = originalSnippet
        for (key, value) in textReplacements {
            altered = altered.replacingOccurrences(of: key, with: value)
        }
        return altered
    }
    
    private func findTemplateTokens(in snippet: String, using replacements: [String: String]) {
        
        // original pattern that works on regextester.com is "\{\{([^\{\}]*)\}\}+"
        // but we have to escape it for iOS
        // this pattern is used to find tokens, such as {{guest_first_name}}
        // this pattern also matches the same token twice, once as guest_first_name and once as {{guest_first_name}}
        let pattern = "\\{\\{([^\\{\\}]*)\\}\\}+"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            
            regex.enumerateMatches(in: snippet,
                                   options: [],
                                   range: NSRange(location: 0, length: snippet.count),
                                   using:
                { [weak self] (result, flags, stop) in
                    
                    guard let `self` = self else { return }
                    
                    if let result = result {
                        // the shorter string will be the match without the brackets.
                        
                        let matches = result.sortedMatches(in: snippet)
                        if let key = matches.first?.0, let template = matches.last?.0 {
                            if let value = replacements[key] {
                                // we have the value for that key
                                self.textTemplateReplacements[template] = value
                            } else {
                                // we don't have a value for that token, so we just replace with ""
                                self.textTemplateReplacements[template] = ""
                            }
                        }
                    }
            })
            
        } catch let e {
            print("Error!  \(e.localizedDescription)")
        }
    }
    
    private func addTextReplacementsAssociatedWithFontSize(in snippet: String) {
        
        let findFontPattern = "font-size:[0-9a-z.]+"

        let targetString = snippet
        let targetPattern = findFontPattern

        do {
            let regex = try NSRegularExpression(pattern: targetPattern, options: [])

            regex.enumerateMatches(in: targetString,
                                   options: [],
                                   range: NSRange(location: 0, length: targetString.count)) { (result, flags, stop) in
                                   
                                    if let result: NSTextCheckingResult = result {
                                        let strings = result.matchedStrings(using: targetString)
                                        strings.forEach { (cssFontSizeString) in
                                            // get the normalized font in css syntax
                                            if let font = self.extractFontSize(from: cssFontSizeString) {
                                                let normalized = font.normalized(to: self.viewportWidth)
                                                let normalizedCSSStyle = "font-size:\(normalized.cssValue)"
                                                self.textTemplateReplacements[cssFontSizeString] = normalizedCSSStyle
                                            }
                                        }
                                    }
                                    // if you need to end the enumeration...
                                    //stop.pointee = true
            }

        } catch let e {
            print("Error!  \(e.localizedDescription)")
        }
    }
}

extension MateSnippetConverter {

    // MARK: - Parsing Helpers
    
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
    
    func matchedStrings(using original: String) -> [String] {
        var strings: [String] = []
        for i in 0..<self.numberOfRanges {
            let range = self.range(at: i)
            let extractedString = (original as NSString).substring(with: range)
            strings.append(extractedString)
        }
        return strings.sorted { return $0.count < $1.count }
    }
}
