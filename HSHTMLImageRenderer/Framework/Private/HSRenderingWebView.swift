//
//  HSRenderingWebView.swift
//  MatePrint
//
//  Created by Stephen O'Connor (MHP) on 08.11.19.
//  Copyright © 2019 MATE. All rights reserved.
//

import UIKit
import WebKit

class HSRenderingWebView: WKWebView {
    
    weak var operation: HSHTMLImageRenderingOperation?
    
    enum JSError: Error {
        case unexpected
    }
    
    private var widthConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint!
    
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        addWidthConstraint()
        addHeightConstraint()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addWidthConstraint()
        addHeightConstraint()
    }
    
    func addWidthConstraint() {
        let constraint = NSLayoutConstraint(item: self,
                                            attribute: .width,
                                            relatedBy: .equal,
                                            toItem: nil,
                                            attribute: .width,
                                            multiplier: 1,
                                            constant: UIScreen.main.bounds.width)
        self.addConstraint(constraint)
        self.widthConstraint = constraint
    }
    
    func addHeightConstraint() {
        let constraint = NSLayoutConstraint(item: self,
                                            attribute: .height,
                                            relatedBy: .equal,
                                            toItem: nil,
                                            attribute: .height,
                                            multiplier: 1,
                                            constant: UIScreen.main.bounds.height)
        self.addConstraint(constraint)
        self.heightConstraint = constraint
    }
    
    var width: CGFloat {
        get {
            return self.frame.size.width
        }
        set {
            self.widthConstraint.constant = max(0, newValue)
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
    }
    
    var height: CGFloat {
        get {
            return self.frame.size.height
        }
        set {
            self.heightConstraint.constant = max(0, newValue)
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
    }
  
    let jsRenderingContainerRect = """
var container = document.getElementById('render_container');
var rect = container.getBoundingClientRect();
var values = [];
values = values.concat(rect.left, rect.top, rect.width, rect.height);
values;
"""
    //let jsHeight = "document.documentElement.clientHeight;"
//    let jsHeight = """
//var container = document.getElementById('render_container');
//container.offsetHeight;
//"""
    let jsHeight = "document.body.scrollHeight;"
    
    func getContainerRect(completion: @escaping ((_ jsRect: CGRect, _ wkRect: CGRect, _ error: Error?) -> Void)) {
        
        let height = jsHeight
        let containerRect = jsRenderingContainerRect
        
        self.evaluateJavaScript(height) { (value, heightError) in
            if let error = heightError {
                completion(.zero, .zero, error)
                return
            }
            if let height = value as? CGFloat {
                
                self.evaluateJavaScript(containerRect) { [weak self] (rectValues, rectError) in
                    guard let `self` = self else { return }
                    
                    if let error = rectError {
                        completion(.zero, .zero, error)
                        return
                    }
                    
                    if let rectInfo = rectValues as? [CGFloat] {
                        let wkRect = self.jsToSwift(rectValues: rectInfo)
                        let jsRect = self.rectFrom(rectValues: rectInfo)
                        completion(jsRect, wkRect, nil)
                        return
                    } else {
                        completion(.zero, .zero, JSError.unexpected)
                    }
                }
                
            } else {
                completion(.zero, .zero, JSError.unexpected)
            }
        }
    }
    
    func rectFrom(rectValues: [CGFloat]) -> CGRect {
        return CGRect(x: rectValues[0], y: rectValues[1], width: rectValues[2], height: rectValues[3])
    }
    
    func jsToSwift(rectValues: [CGFloat]) -> CGRect {
        
        let zoom = self.scrollView.zoomScale
        return CGRect(x: rectValues[0] * zoom,
                      y: rectValues[1] * zoom,
                      width: rectValues[2] * zoom,
                      height: rectValues[3] * zoom)
    }
}
