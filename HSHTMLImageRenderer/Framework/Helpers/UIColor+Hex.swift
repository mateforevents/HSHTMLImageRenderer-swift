//
//  UIColor+Hex.swift
//  HSHTMLImageRenderer
//
//  Created by Stephen O'Connor on 10.11.19.
//  Copyright © 2019 Stephen O'Connor. All rights reserved.
//

import UIKit

extension UIColor {
    public convenience init?(hex: String) {
        let r, g, b, a: CGFloat

        if hex.hasPrefix("#") {
            let start = hex.index(hex.startIndex, offsetBy: 1)
            let hexColor = String(hex[start...])

            if hexColor.count == 8 {
                // RGBA
                let scanner = Scanner(string: hexColor)
                var hexNumber: UInt64 = 0

                if scanner.scanHexInt64(&hexNumber) {
                    r = CGFloat((hexNumber & 0xff000000) >> 24) / 255
                    g = CGFloat((hexNumber & 0x00ff0000) >> 16) / 255
                    b = CGFloat((hexNumber & 0x0000ff00) >> 8) / 255
                    a = CGFloat(hexNumber & 0x000000ff) / 255

                    self.init(red: r, green: g, blue: b, alpha: a)
                    return
                }
            } else if hexColor.count == 6 {
                // RGB, A = 1
                let scanner = Scanner(string: hexColor)
                var hexNumber: UInt64 = 0
                
                if scanner.scanHexInt64(&hexNumber) {
                    r = CGFloat((hexNumber & 0x00ff0000) >> 16) / 255
                    g = CGFloat((hexNumber & 0x0000ff00) >> 8) / 255
                    b = CGFloat(hexNumber & 0x000000ff) / 255
                    a = CGFloat(1.0)
                    self.init(red: r, green: g, blue: b, alpha: a)
                    return
                }
            }
        }

        return nil
    }
    
    public static func hexString(from color: UIColor, includeHashCharacter: Bool = false) -> String {
        
        // white isn't usually in a RGB color space
        if color == .white {
            return "#FFFFFF"
        }
        
        var r = CGFloat(0)
        var g = CGFloat(0)
        var b = CGFloat(0)
        var a = CGFloat(0)
        
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        let redByte = UInt8(r * 255)
        let greenByte = UInt8(g * 255)
        let blueByte = UInt8(b * 255)
        let alphaByte = UInt8(a * 255)
        
        let hashCharacter = includeHashCharacter ? "#" : ""
        
        if alphaByte == 255 {
            return String(format: "%@%02x%02x%02x", hashCharacter, redByte, greenByte, blueByte)
        } else {
            return String(format: "%@%02x%02x%02x%02x", hashCharacter, redByte, greenByte, blueByte, alphaByte)
        }
    }
    
    func hexString(includeHashCharacter: Bool = false) -> String {
        return UIColor.hexString(from: self, includeHashCharacter: includeHashCharacter)
    }
}
