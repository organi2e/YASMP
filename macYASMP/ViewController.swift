//
//  ViewController.swift
//  macYASMP
//
//  Created by Kota Nakano on 9/14/16.
//
//

import Cocoa

class ViewController: NSViewController {
	
	let player: YASMP = YASMP(dump: .standardError)
	
	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view, typically from a nib.
		guard let view: NSView = NSApplication.shared().windows.first?.contentViewController?.view else {
				assertionFailure()
				return
		}
		let url: URL = URL(fileURLWithPath: "/tmp/test.mov")
		let layer = player.layer
		layer.frame = view.frame
		view.layer = layer
		view.wantsLayer = true
		player.load(urls: [url], mode: .Server(port: 65500), loop: 24300) { print($0) }
//		player.load(urls: [url], mode: .Client(port: 9000, address: "192.168.2.1", threshold: 0.1, interval: 6.0), loop: 1024) { print($0) }
	}

	override var representedObject: Any? {
		didSet {
		// Update the view, if already loaded.
		}
	}


}

