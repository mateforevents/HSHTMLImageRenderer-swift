//
//  StringExtensions.swift
//  MatePrint
//
//  Created by Stephen O'Connor (MHP) on 10.11.19.
//  Copyright © 2019 MATE. All rights reserved.
//

import UIKit

public struct TemplateAttributes {
    
    public struct Key {
        public static let lineHeight = "__LINE_HEIGHT__"
        public static let fontSize = "__FONT_SIZE__"
        public static let textColor = "__TEXT_COLOR__"
        public static let backgroundColor = "__BACKGROUND_COLOR__"
        public static let targetWidth = "__OUTPUT_WIDTH__"
        public static let targetHeight = "__OUTPUT_HEIGHT__"
        public static let bodyText = "__HTML_BODY__"
        public static let fontFamily = "__FONT_FAMILY__"
        public static let font = "TemplateFont"
    }
    
    public static var defaultTemplateAttributes: [String: Any] = {
       return [
        TemplateAttributes.Key.lineHeight: CGFloat(1.0),
        TemplateAttributes.Key.font: UIFont.systemFont(ofSize: 16),
        TemplateAttributes.Key.textColor: UIColor.black,
        TemplateAttributes.Key.backgroundColor: UIColor.white,
        TemplateAttributes.Key.targetWidth: CGFloat(300)
        ]
    }()
}

public class HSHTMLTemplateHelper {
    
    public enum TemplateError: Error {
        /// happens if you haven't included all the required attributes to render the HTML properly
        case invalidTemplate
    }
    
    fileprivate var templateRegistry: [String: String] = [:]
    
    // incoming snippet, outgoing snippet
    public var snippetTransformer: ((_ snippet: String, _ template: String) -> (transformedSnippet: String, transformedTemplate: String))? = nil
    
    public func defaultTemplate() -> String {
        let template = try! String(contentsOf: self.defaultTemplateURL(), encoding: .utf8)
        return template
    }
    
    public func defaultTemplateURL() -> URL {
        guard let url = Bundle(for: HSHTMLImageRenderer.self).url(forResource: "default_template.html", withExtension: nil) else {
            fatalError("Handle this better.  Resource couldn't be located.")
        }
        return url
    }
    
    public func registerTemplate(_ template: String, identifier: String) {
        templateRegistry[identifier] = template
    }
    
    /// this method aims to substitute the serverSnippet into the template, while also setting other properties of the template.
    func presentationHTML(with serverSnippet: String,
                          usingTemplateWithIdentifier identifier: String,
                          attributes: [String: Any]) throws -> String {
        
        guard let template = templateRegistry[identifier] else {
            fatalError("You need to register your template before you can render with it.  Before calling this method, make sure you load and set a template using registerTemplate:identifier:")
        }
        
        var transformedSnippet = serverSnippet
        var transformedTemplate = template
        
        // the idea is that you can make substitutions from incoming snippets, and if necessary, add CSS.
        if let transformer = self.snippetTransformer {
            let transformed = transformer(transformedSnippet, transformedTemplate)
            transformedSnippet = transformed.transformedSnippet
            transformedTemplate = transformed.transformedTemplate
        }
        
        // if this hasn't been removed, it needs to be!
        transformedTemplate = transformedTemplate.replacingOccurrences(of: "__ADDITIONAL_CSS__", with: "")
        
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
        return true
    }
    
    func validateDefaultTemplate() -> Bool {
        let template = self.defaultTemplate()
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
        
        guard let lineHeight = workingAttributes[TemplateAttributes.Key.lineHeight] as? CGFloat,
            let textColor = workingAttributes[TemplateAttributes.Key.textColor] as? UIColor,
            let backgroundColor = workingAttributes[TemplateAttributes.Key.backgroundColor] as? UIColor,
            let font = workingAttributes[TemplateAttributes.Key.font] as? UIFont,
            let targetWidth = workingAttributes[TemplateAttributes.Key.targetWidth] as? CGFloat
        else {
            fatalError("You are missing some fundamental drawing attributes.  If you provided your own attributes, did you make sure to merge them with HSHTMLTemplateHelper.defaultTemplateAttributes ?")
        }
        
        // derived attributes
        let family = font.familyName
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
        if let targetHeight = workingAttributes[TemplateAttributes.Key.targetHeight] as? CGFloat {
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
