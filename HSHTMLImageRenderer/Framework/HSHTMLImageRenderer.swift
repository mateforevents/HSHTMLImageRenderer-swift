//
//  HSHTMLImageRenderer.swift
//  MatePrint
//
//  Created by Stephen O'Connor (MHP) on 08.11.19.
//  Copyright © 2019 MATE. All rights reserved.
//

import UIKit
import WebKit

public typealias HSHTMLImageRendererCompletionBlock = (_ identifier: String, _ result: UIImage?, _ wasCached: Bool, _ error: Error?) -> Void

public class HSHTMLImageRenderer: NSObject {
    
    public enum RenderingIntent: Int {
        case standard = 0
    }
    
    /// will write the template-converted files to disk, so that you can inspect and debug them in a browser, just to be sure.  Intended for the iOS Simulator.
    static let writeHTMLToDisk = false
    
    /// Make sure you call renderer(in window) first!
    private static var _shared: HSHTMLImageRenderer?
    
    public static var shared: HSHTMLImageRenderer! {
        return _shared!
    }
    
    let renderingWindow: UIWindow
    private(set) var operationsRequested: Int = 0
    
    public static func sharedRenderer(in window: UIWindow) -> HSHTMLImageRenderer {
        guard _shared == nil else {
            return _shared!
        }
    
        _shared = HSHTMLImageRenderer(window: window)
        return _shared!
    }
    
    init(window: UIWindow) {
        self.renderingWindow = window
        super.init()
        
        if HSHTMLImageRenderer.writeHTMLToDisk {
            log("Test HTML Save Path: \(HSHTMLImageRenderingOperation.fileBasePath())")
        }
        
        log("Creating Rendering webview on main thread: \(self.webView.description)")
    }
    
    deinit {
        finishRendering()
    }
    
    internal lazy var jobQueue: OperationQueue = {
       var queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "HSHTMLImageRendererQueue"
        queue.qualityOfService = .background
        return queue
    }()
    
    private var _webView: HSRenderingWebView? = nil
    internal var webView: HSRenderingWebView {
        
        guard _webView == nil else {
            return _webView!
        }
        let screenSize = self.renderingWindow.bounds.size
        let webview = HSRenderingWebView(frame: CGRect(x: 0, y: 0, width: screenSize.width, height: screenSize.height))
        webview.translatesAutoresizingMaskIntoConstraints = false
        webview.scrollView.contentInsetAdjustmentBehavior = .never
        webview.navigationDelegate = self
        webview.isOpaque = false
        webview.backgroundColor = .clear
        self.renderingWindow.insertSubview(webview, at: 0)
        self.renderingWindow.leadingAnchor.constraint(equalTo: webview.leadingAnchor).isActive = true
        self.renderingWindow.topAnchor.constraint(equalTo: webview.topAnchor).isActive = true
        
        _webView = webview
        return webview
    }
    
    internal lazy var webLoadCompletionQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "com.horseshoe7.html.renderer")
        return queue
    }()
    
    internal lazy var imageCache: NSCache<NSString, UIImage> = {
        return NSCache<NSString, UIImage>()
    }()
    
    internal let templateHelper = HSHTMLTemplateHelper()
    
    public var isSuspended: Bool {
        set {
            self.jobQueue.isSuspended = newValue
        }
        get {
            return self.jobQueue.isSuspended
        }
    }
    
    /// completion is called immediately if the image is found in the cache.
    /// `identifier` is ultimately a cache key.
    public func renderHTML(_ htmlString: String,
                           identifier: String,
                           intent: RenderingIntent = .standard,
                           attributes: [String: Any] = TemplateAttributes.defaultTemplateAttributes,
                           ignoreCache: Bool = false,
                           cacheResult: Bool = true,
                           completion: @escaping HSHTMLImageRendererCompletionBlock) {
        
        // first check if we've rendered this already
        if !ignoreCache {
            if let existingImage = self.imageCache.object(forKey: identifier as NSString) {
                completion(identifier, existingImage, true, nil)
                return
            }
        }
        
        let renderOp = HSHTMLImageRenderingOperation(html: htmlString,
                                                     identifier: identifier,
                                                     intent: intent,
                                                     attributes: attributes,
                                                     renderer: self,
                                                     ignoreCache: ignoreCache,
                                                     shouldCache: cacheResult,
                                                     completion:
            { (success, userInfo, error) in
                
                if let error = error {
                    completion(identifier, nil, false, error)
                    return
                }
                
                guard let results = userInfo else {
                    fatalError("The Render operation should have returned userInfo")
                }
                
                guard let image = results[HSHTMLImageRenderingOperation.UserInfoKey.image] as? UIImage,
                    let identifier = results[HSHTMLImageRenderingOperation.UserInfoKey.identifier] as? String,
                    let wasCached = results[HSHTMLImageRenderingOperation.UserInfoKey.wasCached] as? Bool else {
                    fatalError("The Render operation should have returned values in userInfo")
                }
                
                completion(identifier, image, wasCached, nil)
        })
        
        self.operationsRequested += 1
        renderOp.operationIndex = self.operationsRequested
        
        self.jobQueue.addOperation(renderOp)
    }
    
    /// will clean up and release some resources.
    @discardableResult public func finishRendering() -> Bool {
        guard self.jobQueue.operationCount == 0 else {
            log("Fail!  You should only call this after all your rendering jobs are finished!")
            return false
        }
        _webView?.removeFromSuperview()
        _webView = nil
        
        templateHelper.finishUsingTemplates()
        return true
    }
}

extension HSHTMLImageRenderer: WKNavigationDelegate {
    
    public func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: ((WKNavigationActionPolicy) -> Void)) {

        decisionHandler(.allow)
    }
    
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // do nothing.  aka  webViewDidStartLoad:
    }
        
    public func webView(_ webView: WKWebView,
                        didFail navigation: WKNavigation!,
                        withError error: Error) {
        
        log("webView:\(webView) didFailNavigation:\(navigation.description) withError:\(error.localizedDescription)")
        
        if webView == self.webView {
            if let operation = self.webView.operation {
                log("Failure Context: \(operation.name ?? "Unspecified Operation Name")")
                self.webLoadCompletionQueue.async {
                    operation.failedLoading(webView: webView, error: error)
                    self.webView.operation = nil
                }
            }
        }
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    
        self.perform(#selector(continueAfterWebViewFinished), with: nil, afterDelay: 0.3)
    }
    
    @objc
    private func continueAfterWebViewFinished() {
        
        guard webView == self.webView else {
            log("Something went wrong here!  Old code just says 'Tried Resetting the Webview', whatever that means")
            return
        }

        // this is where you can evaluate the content height, and re-size as necessary.
        let javascriptHeightString = "" +
            "var body = document.body;" +
            "var html = document.documentElement;" +
            "Math.max(" +
            "   body.scrollHeight," +
            "   body.offsetHeight," +
            "   html.clientHeight," +
            "   html.offsetHeight" +
        ");"  // formerly "document.height"
        
        webView.evaluateJavaScript(javascriptHeightString) { (result, error) in
            guard let height = result as? CGFloat else {
                fatalError("DID NOT EXPECT THIS.  Failing")
            }
            self.notifyOperationThatWebviewCompletedLoading(self.webView)
        }
    }
    
    private func notifyOperationThatWebviewCompletedLoading(_ webView: HSRenderingWebView) {
        
        if let operation = webView.operation {
            self.webLoadCompletionQueue.async {
                operation.completedLoading(webView: webView)
                webView.operation = nil
            }
        }
    }
}
