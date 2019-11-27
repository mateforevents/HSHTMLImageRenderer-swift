//
//  HSHTMLImageRenderingOperation.swift
//  MatePrint
//
//  Created by Stephen O'Connor (MHP) on 08.11.19.
//  Copyright © 2019 MATE. All rights reserved.
//

import UIKit
import WebKit

class HSHTMLImageRenderingOperation: HSAsyncOperation {
    
    struct UserInfoKey {
        static let image = "image"
        static let wasCached = "wasCached"
        static let identifier = "identifier"
    }
    
    enum RenderError: Error {
        // if the issue is unexpected.
        case unexpected
    }
    
    let htmlToLoad: String
    let jobIdentifier: String
    let templateIdentifier: String?
    let attributes: [String: Any]
    let ignoreCache: Bool
    let shouldCache: Bool
    
    var userInfo: [String: Any]
    
    var startTime: Date = Date()
    var operationIndex: Int = 0
    
    weak var renderer: HSHTMLImageRenderer?
    var contentSize: CGSize = .zero
    
    init(html: String,
         jobIdentifier: String,
         templateIdentifier: String?,
         attributes: [String: Any],
         renderer: HSHTMLImageRenderer,
         ignoreCache: Bool,
         shouldCache: Bool,
         completion: HSOperationCompletionBlock?) {
        
        self.htmlToLoad = html
        self.jobIdentifier = jobIdentifier
        self.templateIdentifier = templateIdentifier
        self.attributes = attributes
        self.renderer = renderer
        self.ignoreCache = ignoreCache
        self.shouldCache = shouldCache
        
        self.userInfo = [UserInfoKey.identifier: jobIdentifier]
        
        super.init(completion: completion)
        self.name = jobIdentifier
    }
    
    override func work() {
        self.startTime = Date()
        
        // figure out if we can used a cached copy
        if !ignoreCache,
            let cache = self.renderer?.imageCache,
            let image = cache.object(forKey: self.jobIdentifier as NSString) {
            
            self.userInfo[UserInfoKey.image] = image
            self.userInfo[UserInfoKey.wasCached] = true
            self.finish()
            return
        }
        
        // nope, we have to render it.
        let baseURL: URL? = nil
        
        
        guard let transformer = self.renderer?.templateTransformer else {
            self._error = RenderError.unexpected
            finish()
            return
        }
        
        
        do {
            
            var modifiedString: String = self.htmlToLoad
            
            if let templateIdentifier = self.templateIdentifier {
                modifiedString = try transformer.presentationHTML(with: self.htmlToLoad,
                                                                  usingTemplateWithIdentifier: templateIdentifier,
                                                                  attributes: self.attributes)
                
            }
            
            
            let targetWidth = self.attributes[TemplateAttributes.Key.targetWidth] as? Float ?? TemplateAttributes.defaultTemplateAttributes[TemplateAttributes.Key.targetWidth] as! Float
            
            let targetHeight = self.attributes[TemplateAttributes.Key.targetHeight] as? Float ?? Float(UIScreen.main.bounds.height)
            
             // now we do substitutions....
             
             // we take the template from the server
             
             // we inject CSS as required, but perhaps most line wrapping will be asssociated with the p tag, or possibly the span tag that we assign a css class to.
             
             // then we substitute template keys with actual values
             
             if HSHTMLImageRenderer.writeHTMLToDisk {
                 
                 do {
                     let filename = "\(String(format: "%03d.html", self.operationIndex))"
                     try self.saveHTML(modifiedString, to: filename)
                 } catch let error {
                     log("HTML Saving error: \(error.localizedDescription)")
                 }
             }
             
             DispatchQueue.main.async { [weak self] in
                guard let `self` = self else { return }
             
                self.renderer?.webView.width = CGFloat(targetWidth)
                self.renderer?.webView.height = CGFloat(targetHeight)
                self.renderer?.webView.operation = self
                self.renderer?.webView.loadHTMLString(modifiedString, baseURL: baseURL)
            }
            
        } catch let e {
            self._error = e
            self.finish()
        }
    }
    
    func completedLoading(webView: WKWebView) {
        
        self.image(from: webView, attributes: self.attributes) { (image, error) in
        
            self.userInfo[UserInfoKey.image] = image
            
            if self.shouldCache, let image = image {
                self.renderer?.imageCache.setObject(image, forKey: self.jobIdentifier as NSString)
            }
            
            // because we rendered it, it wasn't cached
            self.userInfo[UserInfoKey.wasCached] = false
                   
            self.finish()
        }
    }
    
    func failedLoading(webView: WKWebView, error: Error) {
        self._error = error
        self.finish()
    }
    
    private func image(from webView: WKWebView,
                       attributes: [String: Any],
                       completion: @escaping ((_ image: UIImage?, _ error: Error?) -> Void)) {
        
        // this has to be performed on the main thread because it involves calls to UIKit.
        // Will cause crashes otherwise...
        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else { return }
            self._renderWebView(webView) { image in
                self.renderer?.webLoadCompletionQueue.async {
                    completion(image, nil)
                }
            }
        }
    }
    
    private func _renderWebView(_ webView: WKWebView, completion: @escaping ((_ image: UIImage?) -> Void)) {
        
        guard let webView = webView as? HSRenderingWebView else {
            fatalError("Something went wrong here.")
        }
        
        guard Thread.isMainThread else {
            fatalError("This has to be done on the main thread.")
        }

        webView.getContainerRect { [weak self] (jsRect, wkRect, error) in
            
            print("WebKitRect: \(wkRect), jsRect: \(jsRect)")
            
            if #available(iOS 11.0, *) {
                
                let config = WKSnapshotConfiguration()
                config.rect = wkRect
                if #available(iOS 13.0, *) {
                    config.afterScreenUpdates = true
                } else {
                    // Fallback on earlier versions
                    webView.layoutIfNeeded()
                }
                
                webView.takeSnapshot(with: config) { (image, error) in
                 
                    completion(image)
                }
                
            } else {
                // Fallback on earlier versions
                
                if let image = self?.renderUsingLegacyMethod(wkRect.size, webView: webView) {
                    completion(image)
                } else {
                    print("Could not render an image using the legacy method.  No idea why...")
                    completion(nil)
                }
            }
        }
    }
    
    private func renderUsingLegacyMethod(_ targetSize: CGSize, webView: HSRenderingWebView) -> UIImage? {

        // adapted from this: http://atmarkplant.com/wkwebview-screenshots/
        // TODO: ("Determine if context should be opaque or not.  Affects clear labels?")
        UIGraphicsBeginImageContextWithOptions(targetSize, true, UIScreen.main.scale)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            print("Could not get context to render WebView...")
            return nil
        }
        let scale = targetSize.width / webView.layer.bounds.size.width
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        ctx.concatenate(transform)
        webView.layer.render(in: ctx)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
    
    override func finish() {
        self._userInfo = self.userInfo
        super.finish()
    }
    
    override func endOperation(_ sender: Any? = nil) {
        let wasCached = (self.userInfo[UserInfoKey.wasCached] as? Bool) ?? false
        
        if let error = self._error {
            log("Completed a HTML render in \(String(format:"%.4fs", -self.startTime.timeIntervalSinceNow)).  Was cached: \(wasCached) with Error: \(error.localizedDescription)")
        } else {
            log("Completed a HTML render in \(String(format:"%.4fs", -self.startTime.timeIntervalSinceNow)).  Was cached: \(wasCached)")
        }
        super.endOperation(sender)
    }
    
    // MARK: - File Helpers
    
    private func saveHTML(_ htmlString: String, to filename: String) throws {
    
        let fileURL = self.fileURL(for: filename)
        let dirURL = fileURL.deletingLastPathComponent()
        let dirExists = FileManager.default.fileExists(atPath: dirURL.absoluteString)
        
        if !dirExists {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        try htmlString.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    private func fileURL(for filename: String) -> URL {
        var url = HSHTMLImageRenderingOperation.fileBasePath()
        url = url.appendingPathComponent("html").appendingPathComponent(filename)
        return url
    }
    
    static func fileBasePath() -> URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths.first!
    }
}
