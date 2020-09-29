//
//  HSAsyncOperation.swift
//  HSHTMLImageRenderer
//
//  Created by Stephen O'Connor on 08.11.19.
//  Copyright © 2019 Stephen O'Connor. All rights reserved.
//

import Foundation

func log(_ message: String) {
    print(message)
}

typealias HSOperationCompletionBlock = ((_ success: Bool, _ userInfo: [String: Any]?, _ error: Error?) -> Void)

class HSAsyncOperation: Operation {
    
    fileprivate struct KVOKey {
        static let isExecuting = "isExecuting"
        static let isFinished = "isFinished"
    }
    
    var _isExecuting: Bool = false
    var _isFinished: Bool = false
    
    var _userInfo: [String: Any]?
    var _error: Error?
    var _operationCompletionBlock: HSOperationCompletionBlock?
    
    let completionQueue: DispatchQueue
    
    init(completion: HSOperationCompletionBlock?, completionQueue: DispatchQueue = .main) {
        _operationCompletionBlock = completion
        self.completionQueue = completionQueue
        super.init()
    }
    
    func work() {
        // for subclasses to override!
        finish()
    }
    
    func finish() {
        guard !self.isCancelled else {
            endOperation()
            return
        }
        
        let success = (_error == nil)
        let info = _userInfo
        let error = _error
        
        if let completion = _operationCompletionBlock {
            
            self._setCompletionBlock {
                self.completionQueue.async {
                    completion(success, info, error)
                }
            }
        }
        endOperation()
    }
    
    override var isConcurrent: Bool { return true }
    override var isAsynchronous: Bool { return true }
    override var isExecuting: Bool { return _isExecuting }
    override var isFinished: Bool { return _isFinished }
    
    /// you can only set this property if you're writing a subclass and know what you're doing!
    func _setCompletionBlock(_ completion: (() -> Void)?) {
        super.completionBlock = completion
    }
    
    override var completionBlock: (() -> Void)? {
        get {
            return super.completionBlock
        }
        set {
            // do nothing!!
            fatalError("You should never explicitly call setCompletionBlock: unless you are overriding in the subclass.  use operationCompletionBlock: instead")
        }
    }
    
    // MARK: - The Meat
    override func start() {
        log("Started \(self.description)")
        
        // this property has to be KVO observable, so we send those here and now.
        self.willChangeValue(forKey: KVOKey.isExecuting)
        _isExecuting = true
        self.didChangeValue(forKey: KVOKey.isExecuting)
        
        // our work should always periodically check to see if the user's code has cancelled the operation
        guard !self.isCancelled else {
            finish()
            return
        }
        
        // but wait!  Nothing will happen here.  Although this is an abstract baseclass, it should not fail.
        
        // so we add a 'doSomething' method that the subclasses can override
        work()
    }
 
    func endOperation(_ sender: Any? = nil) {
        self.willChangeValue(forKey: KVOKey.isExecuting)
        self.willChangeValue(forKey: KVOKey.isFinished)
        _isExecuting = false
        _isFinished = true
        self.didChangeValue(forKey: KVOKey.isExecuting)
        self.didChangeValue(forKey: KVOKey.isFinished)
    }
}
