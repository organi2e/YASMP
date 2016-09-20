//
//  ViewController.swift
//  macYASMP
//
//  Created by Kota Nakano on 9/14/16.
//
//

import Cocoa

class ViewController: NSViewController {
	
	let player: YASMP = YASMP()
	
	override func viewDidLoad() {
		super.viewDidLoad()
		let bundle: Bundle = Bundle.main
		if let url: URL = bundle.url(forResource: "02", withExtension: "mp4") {
			
			view.window?.toggleFullScreen(nil)
			
			let layer = player.layer
			layer.frame = view.frame
			//view.layer.sublayers?.removeAll()
			view.layer = layer
			view.wantsLayer = true
			
			player.load(url: url) {
				print($0)
			}
		} else {
			assertionFailure()
		}
		// Do any additional setup after loading the view, typically from a nib.
	}


	override var representedObject: Any? {
		didSet {
		// Update the view, if already loaded.
		}
	}


}

