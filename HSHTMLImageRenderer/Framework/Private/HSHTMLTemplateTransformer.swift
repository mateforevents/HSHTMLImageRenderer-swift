//
//  StringExtensions.swift
//  HSHTMLImageRenderer
//
//  Created by Stephen O'Connor on 10.11.19.
//  Copyright © 2019 Stephen O'Connor. All rights reserved.
//

import UIKit

public struct TemplateAttributes {
    
    public struct Key {
        public static let lineHeight = "__LINE_HEIGHT__" // value should be a Float
        public static let fontSize = "__FONT_SIZE__"  // value should be a Float
        public static let textColor = "__TEXT_COLOR__"  // value should be a UIColor
        public static let backgroundColor = "__BACKGROUND_COLOR__"  // value should be a UIColor
        public static let targetWidth = "__OUTPUT_WIDTH__"  // value should be a Float
        public static let targetHeight = "__OUTPUT_HEIGHT__"  // value should be a Float
        public static let bodyText = "__HTML_BODY__"  // value should be a String
        public static let fontFamily = "__FONT_FAMILY__"  // value should be a String
        public static let font = "TemplateFont"
        public static let additionalCSS = "__ADDITIONAL_CSS__"  // this will be in the default_template.html
    }
    
    public static var defaultTemplateAttributes: [String: Any] = {
       return [
        TemplateAttributes.Key.lineHeight: Float(1.0),
        TemplateAttributes.Key.font: UIFont(name: "Helvetica", size: 16)!,
        TemplateAttributes.Key.textColor: UIColor.black,
        TemplateAttributes.Key.backgroundColor: UIColor.white,
        TemplateAttributes.Key.targetWidth: Float(300)
        ]
    }()
}

public class HSHTMLTemplateTransformer: NSObject {
    
    public static let defaultTemplateIdentifier = "++HSHTMLImageRendererDefaultTemplate++"
    
    public enum TemplateError: Error {
        /// happens if you haven't included all the required attributes to render the HTML properly
        case invalidTemplate
        /// if you try to render using a templateIdentifier you haven't registered.
        case unknownTemplateIdentifier
    }
    
    fileprivate var templateRegistry: [String: String] = [:]
    
    // incoming snippet, outgoing snippet
    public var snippetTransformer: ((_ snippet: String, _ template: String?) -> (transformedSnippet: String, transformedTemplate: String?))? = nil
    
    internal static func defaultTemplate() -> String {
        let template = try! String(contentsOf: self.defaultTemplateURL(), encoding: .utf8)
        return template
    }
    
    internal static func defaultTemplateURL() -> URL {
        guard let url = Bundle(for: HSHTMLImageRenderer.self).url(forResource: "default_template.html", withExtension: nil) else {
            fatalError("Handle this better.  Resource couldn't be located.")
        }
        return url
    }
    
    override init() {
        super.init()
        let template = HSHTMLTemplateTransformer.defaultTemplate()
        self.registerTemplate(template, identifier: HSHTMLTemplateTransformer.defaultTemplateIdentifier)
    }
    
    
    internal func registerTemplate(_ template: String, identifier: String) {
        templateRegistry[identifier] = template
    }
    
    /// this method aims to substitute the serverSnippet into the template, while also setting other properties of the template.
    internal func presentationHTML(with serverSnippet: String,
                                   usingTemplateWithIdentifier templateIdentifier: String,
                                   attributes: [String: Any]) throws -> String {
        
        guard let template = templateRegistry[templateIdentifier] else {
            throw TemplateError.unknownTemplateIdentifier
        }
        
        var transformedSnippet = serverSnippet
        var transformedTemplate = template
        
        // the idea is that you can make substitutions from incoming snippets, and if necessary, add CSS.
        if let transformer = self.snippetTransformer {
            let transformed = transformer(transformedSnippet, transformedTemplate)
            transformedSnippet = transformed.transformedSnippet
            transformedTemplate = transformed.transformedTemplate ?? transformedTemplate
        }
        
        // if you haven't removed this template variable, it needs to be!
        transformedTemplate = transformedTemplate.replacingOccurrences(of: TemplateAttributes.Key.additionalCSS, with: "")
        
        return try self.substitute(content: transformedSnippet, into: transformedTemplate, htmlAttributes: attributes)
    }
    
    // MARK: - Helpers
    
    public func validateTemplate(_ template: String, attributes: [String]) -> Bool {
        
        let requiredAttributeKeys = [
            TemplateAttributes.Key.lineHeight,
            TemplateAttributes.Key.fontSize,
            TemplateAttributes.Key.textColor,
            TemplateAttributes.Key.backgroundColor,
            TemplateAttributes.Key.targetWidth,
            TemplateAttributes.Key.targetHeight,
            TemplateAttributes.Key.bodyText,
            TemplateAttributes.Key.fontFamily
        ]
        
        //let allAttributes = Set(attributes + requiredAttributeKeys)
        
        for attribute in requiredAttributeKeys {
            guard let _ = template.range(of: attribute) else {
                print("The Template is supposed to have a settable \(attribute), but wasn't found.")
                return false
            }
        }
        
        // check for render_container
        let searchString = "<div id=\"render_container\""
        guard let _ = template.range(of: searchString) else {
            print("The Template is supposed to have a div with id = \"render_container\", but it wasn't found.")
            return false
        }
        
        return true
    }
    
    func validateDefaultTemplate() -> Bool {
        let template = HSHTMLTemplateTransformer.defaultTemplate()
        return validateTemplate(template, attributes: [])
    }
    
    public func finishUsingTemplates() {
        self.templateRegistry.removeAll()
    }
    
    // MARK: - The Meat of it
    private func substitute(content: String, into template: String, htmlAttributes: [String: Any]) throws -> String {
        
        let attributes = htmlAttributes.map { (key, _) in
            return key
        }
        guard validateTemplate(template, attributes: attributes) else {
            throw TemplateError.invalidTemplate
        }
        
        let workingAttributes = TemplateAttributes.defaultTemplateAttributes.merging(htmlAttributes) { (_, overriddenAttrib) -> Any in
            return overriddenAttrib
        }
        
        guard let lineHeight = workingAttributes[TemplateAttributes.Key.lineHeight] as? Float,
            let textColor = workingAttributes[TemplateAttributes.Key.textColor] as? UIColor,
            let backgroundColor = workingAttributes[TemplateAttributes.Key.backgroundColor] as? UIColor,
            let font = workingAttributes[TemplateAttributes.Key.font] as? UIFont,
            let targetWidth = workingAttributes[TemplateAttributes.Key.targetWidth] as? Float
        else {
            fatalError("You are missing some fundamental drawing attributes.  If you provided your own attributes, did you make sure to merge them with HSHTMLTemplateHelper.defaultTemplateAttributes ?")
        }
        
        // derived attributes
        var family = font.familyName
        
        // have to hack a fix here because Apple somehow maps Helvetica into something else.
        if family == ".AppleSystemUIFont" || family == ".SF UI Text" {
            family = "Helvetica"
        }
        
        let textColorHex = textColor.hexString(includeHashCharacter: true)
        let bgColorHex = backgroundColor.hexString(includeHashCharacter: true)
        
        
        var substitutedTemplate = template
        
        // textSize
        substitutedTemplate = substitutedTemplate.replacingOccurrences(of: TemplateAttributes.Key.lineHeight,
                                                                       with: String(format: "%.1f", lineHeight))
        
        // font
        substitutedTemplate = substitutedTemplate.replacingOccurrences(of: TemplateAttributes.Key.fontSize,
                                                                       with: "\(Int(font.pointSize))")
        
        // family
        substitutedTemplate = substitutedTemplate.replacingOccurrences(of: TemplateAttributes.Key.fontFamily,
                                                                       with: family)
        
        // output
        substitutedTemplate = substitutedTemplate.replacingOccurrences(of: TemplateAttributes.Key.targetWidth,
                                                                       with: "\(Int(targetWidth))")
        
        var targetHeightString = ""
        if let targetHeight = workingAttributes[TemplateAttributes.Key.targetHeight] as? Float {
            targetHeightString = "min-height: \(Int(targetHeight))px"
        } else {
            targetHeightString = "height: 100%"
        }
        substitutedTemplate = substitutedTemplate.replacingOccurrences(of: TemplateAttributes.Key.targetHeight,
                                                                       with: targetHeightString)
        
        // colors
        substitutedTemplate = substitutedTemplate.replacingOccurrences(of: TemplateAttributes.Key.textColor,
                                                                       with: textColorHex)
        
        substitutedTemplate = substitutedTemplate.replacingOccurrences(of: TemplateAttributes.Key.backgroundColor,
                                                                       with: bgColorHex)
        
        substitutedTemplate = substitutedTemplate.replacingOccurrences(of: TemplateAttributes.Key.bodyText,
                                                                       with: content)
        
        return substitutedTemplate
    }
}
