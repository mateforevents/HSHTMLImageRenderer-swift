//
//  HSHTMLImageRenderer.swift
//  HSHTMLImageRenderer
//
//  Created by Stephen O'Connor on 08.11.19.
//  Copyright © 2019 Stephen O'Connor. All rights reserved.
//

import UIKit
import WebKit

public typealias HSHTMLImageRendererCompletionBlock = (_ jobIdentifier: String, _ result: UIImage?, _ wasCached: Bool, _ error: Error?) -> Void

public class HSHTMLImageRenderer: NSObject {
    
    /// will write the template-converted files to disk, so that you can inspect and debug them in a browser, just to be sure.  Intended for the iOS Simulator.
    static let writeHTMLToDisk = false
    
    /// Make sure you call `.sharedRenderer(in: window)` first!
    private static var _shared: HSHTMLImageRenderer?
    
    @objc
    public static var shared: HSHTMLImageRenderer {
        return _shared!
    }
    
    let renderingWindow: UIWindow
    private(set) var operationsRequested: Int = 0
    
    /// basically when you set up a renderer, you'll want to initialize it with this method, and likely right after that register templates, set snippet converters, etc.
    @objc
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
        
        if #available(iOS 11.0, *) {
            webview.scrollView.contentInsetAdjustmentBehavior = .never
        } else {
            // Fallback on earlier versions
        }
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
    
    /// You are given access to this property so you can optionally set its `snippetTransformer` property.
    public let templateTransformer = HSHTMLTemplateTransformer()
    
    public var isSuspended: Bool {
        set {
            self.jobQueue.isSuspended = newValue
        }
        get {
            return self.jobQueue.isSuspended
        }
    }
    
    /**
            The principal method you use when rendering HTML snippets.
     - Parameter htmlString: the snippet of HTML you want to inject into your template and have rendered to an image
     - Parameter jobIdentifier: Consider this otherwise a cache identifier.  If you make a subsequent call to this `renderHTML(...)` method, `jobIdentifier` is used to retrieve any previously rendered version of `htmlString`
     - Parameter targetWidth: because your content is dynamic, it also needs to be constrained by width.  You need to provide this here.  If you provide a targetWidth or targetHeight in the `attributes` argument, they will be overwritten by this value.
     - Parameter targetHeight: (Optional) if you provide a `targetHeight`, the resulting rendered image will be padded top and bottom to fit that height, or scaled to fit into the height, so that the final image that is given in the `completion` block will have the dimensions `targetWidth` x `targetHeight`.  Should ideally be an optional, but for the sake of interoperability with objectiveC, provide a value of 0 to ignore targetHeight.
     - Parameter templateIdentifier: The name of the template you want to use to render your `htmlString`.  If you do not provide a `templateIdentifier`, the `HSHTMLImageRenderer` will just pass in the htmlString to the rendering WKWebView.  Note, working without templates has not been thoroughly tested yet. (21.11.2019).  You should first call `registerTemplate:identifier:` before you commit any rendering job, so that the `HSHTMLImageRenderer`has your template available.  Note, by default, a template is provided under the identifier `HSHTMLTemplateTransformer.defaultTemplateIdentifier`.  NOTE: If your template was not registered, then the `completion` block will return with an error.
     - Parameter attributes: This will most likely be a dictionary of `TemplateAttributes.Key` raw values.  If you customize your template, you will have to look through this source code to see how these attributes are substituted into your template.
     - Parameter ignoreCache: If you set this argument to `true`, it will guarantee that the `htmlString` is rendered and not retrieved from the cache.
     - Parameter cacheResult: If you set this argument to `true`, if your `htmlString` was rendered and not retrieved from the cache, this will place the result in the cache using the `jobIdentifier` as the cache key.
     - Parameter completion: The result of the call.  It provides the `jobIdentifier` to provide context.  If it succeeded, it will provide the image result, whether that came from the cache, or otherwise it will provide an error.  `error` will be defined if you try to render with a `templateIdentifier` that has not been registered via `registerTemplate:identifier:`.  `completion` is called immediately if the image is found in the cache.
     */
  
    @objc
    public func renderHTML(_ htmlString: String,
                           jobIdentifier: String,
                           targetWidth: Float,
                           targetHeight: Float = 0.0, /* 0.0 means ignore the height*/
                           templateIdentifier: String? = HSHTMLTemplateTransformer.defaultTemplateIdentifier,
                           attributes: [String: Any] = TemplateAttributes.defaultTemplateAttributes,
                           ignoreCache: Bool = false,
                           cacheResult: Bool = true,
                           completionQueue: DispatchQueue? = nil, /* if nil, uses the queue you invoked this method on. */
                           completion: @escaping HSHTMLImageRendererCompletionBlock) {
        
        // first check if we've rendered this already
        if !ignoreCache {
            if let existingImage = self.imageCache.object(forKey: jobIdentifier as NSString) {
                completion(jobIdentifier, existingImage, true, nil)
                return
            }
        }
        
        // have to insert/override targetWidth/Height
        var updatedAttributes = attributes
        updatedAttributes[TemplateAttributes.Key.targetWidth] = targetWidth
        
        if targetHeight > 0 {
            updatedAttributes[TemplateAttributes.Key.targetHeight] = targetHeight
        } else {
            updatedAttributes[TemplateAttributes.Key.targetHeight] = nil
        }
        
        var queueForCompletion: DispatchQueue
        if let providedQueue = completionQueue {
            queueForCompletion = providedQueue
        } else if let currentQueue = OperationQueue.current?.underlyingQueue {
            queueForCompletion = currentQueue
        } else {
            queueForCompletion = DispatchQueue.main
        }
            
        
        let renderOp = HSHTMLImageRenderingOperation(html: htmlString,
                                                     jobIdentifier: jobIdentifier,
                                                     templateIdentifier: templateIdentifier,
                                                     attributes: updatedAttributes,
                                                     renderer: self,
                                                     ignoreCache: ignoreCache,
                                                     shouldCache: cacheResult,
                                                     completionQueue: queueForCompletion,
                                                     completion:
            { (success, userInfo, error) in
                
                if let error = error {
                    completion(jobIdentifier, nil, false, error)
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
    
    @objc public func renderHTML(_ htmlString: String) {
        // testing
    }
    
    /// will clean up and release some resources.
    @objc
    @discardableResult public func finishRendering() -> Bool {
        guard self.jobQueue.operationCount == 0 else {
            log("Fail!  You should only call this after all your rendering jobs are finished!")
            return false
        }
        _webView?.removeFromSuperview()
        _webView = nil
        
        templateTransformer.finishUsingTemplates()
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

//        // this is where you can evaluate the content height, and re-size as necessary.
//        let javascriptHeightString = "" +
//            "var body = document.body;" +
//            "var html = document.documentElement;" +
//            "Math.max(" +
//            "   body.scrollHeight," +
//            "   body.offsetHeight," +
//            "   html.clientHeight," +
//            "   html.offsetHeight" +
//        ");"  // formerly "document.height"
//
//        webView.evaluateJavaScript(javascriptHeightString) { (result, error) in
//            guard let _ = result as? CGFloat else {
//                fatalError("DID NOT EXPECT THIS.  Failing")
//            }
//            self.notifyOperationThatWebviewCompletedLoading(self.webView)
//        }
        
        self.notifyOperationThatWebviewCompletedLoading(webView)
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
