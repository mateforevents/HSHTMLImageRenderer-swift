//
//  ViewController.swift
//  HTMLRendererDemo
//
//  Created by Stephen O'Connor on 12.11.19.
//  Copyright © 2019 Walnut Productions. All rights reserved.
//

import UIKit
import HSHTMLImageRenderer

extension Bool {
    var stringValue: String {
        if self == true {
            return "true"
        } else {
            return "false"
        }
    }
}

class ViewController: UIViewController {

    @IBOutlet weak var imageView: UIImageView!
    
//    let testHTML = "<p>I just want to render some HTML.</p><p>It took quite a lot of trial and error to make the underlying WebView render things as I wanted it to!</p><p>It took quite a lot of trial and error to make the underlying WebView render things as I wanted it to!</p>"
    
    let testSnippet = "<p style=\"text-align:center\"><span style=\"font-size:24pt\">{{guest_attribute_default_meta_attribute__title}} {{guest_name}}</span></p><p style=\"text-align:center\"><span style=\"font-size:16.0px\">{{guest_attribute_22ec88e1-45c0-486f-8863-9438fa489aae}}</span></p>"
    
    let snippetReplacements: [String: String] = [
        "guest_attribute_default_meta_attribute__title": "Dr.",
        "guest_name" : "Apu Nahasapeemapetilon",
        "guest_attribute_22ec88e1-45c0-486f-8863-9438fa489aae": "Kwik-E-Mart Productions GmbH"
    ]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        let targetWidth: CGFloat = 200
        //let targetHeight: CGFloat = 70
        
        guard let window = self.view.window else {
            fatalError("No idea how this can happen!")
        }
        
        let renderer = HSHTMLImageRenderer.sharedRenderer(in: window)
        let snippetTransformer = MateSnippetConverter()
        
        let testReplacements = snippetReplacements
        
        renderer.templateTransformer.snippetTransformer = { (snippet, template) in
            let result = snippetTransformer.convert((snippet: snippet, template: template), replacements: testReplacements)
            return (result.snippet, result.template)
        }
        
        renderer.renderHTML(testSnippet,
                            identifier: "Test",
                            intent: .standard,
                            attributes: [
                                TemplateAttributes.Key.targetWidth : targetWidth
                                /*TemplateAttributes.Key.targetHeight : targetHeight,*/
                            ],
                            ignoreCache: false,
                            cacheResult: true) { [weak self] (identifier, image, wasCached, error) in
                                
                                if let e = error {
                                    print("Rendering error: \(e.localizedDescription)")
                                } else {
                                    print("Finished!  Was Cached \(wasCached.stringValue)")
                                }
                                
                                self?.imageView.image = image
        }
        
//        renderer.renderHTML(testHTML,
//                            identifier: "Test") { [weak self] (identifier, image, wasCached, error) in
//
//                                if let e = error {
//                                    print("Rendering error: \(e.localizedDescription)")
//                                } else {
//                                    print("Finished!  Was Cached \(wasCached.stringValue)")
//                                }
//
//                                self?.imageView.image = image
//        }
//
//        self.perform(#selector(loadANewImage), with: nil, afterDelay: 3.0)
    }

    @objc func loadANewImage() {
        
        let targetWidth = self.imageView.bounds.size.width
        let newAttributes: [String : Any] = [
            TemplateAttributes.Key.targetWidth: targetWidth,
            TemplateAttributes.Key.font: UIFont(name: "Helvetica", size: 7)!
        ]
        
        HSHTMLImageRenderer.shared.renderHTML(testSnippet,
                                              identifier: "Test",
                                              intent: .standard,
                                              attributes: newAttributes,
                                              ignoreCache: true, /* ignore the cache because attribs have changed. */
                                              cacheResult: true) { [weak self] (_, image, wasCached, error) in
                                                if let e = error {
                                                    print("Rendering error: \(e.localizedDescription)")
                                                } else {
                                                    print("Finished!  Was Cached \(wasCached.stringValue)")
                                                }
                                                
                                                self?.imageView.image = image
        }
    }
}

