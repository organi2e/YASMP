//
//  AppDelegate.swift
//  macYASMP
//
//  Created by Kota Nakano on 9/14/16.
//
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

	let player: YASMP = YASMP()

	func applicationDidFinishLaunching(aNotification: NSNotification) {
		// Insert code here to initialize your application
		print("1")
		print(NSApp.windows)
		if let url: URL = Bundle.main.url(forResource: "02", withExtension: "mp4"), let view: NSView = NSApplication.shared().windows.first?.contentViewController?.view {
			print("ok")
			let layer = player.layer
			layer.frame = view.frame
			view.layer = layer
			view.wantsLayer = true
			player.load(url: url, mode: .Client(port: 9000, address: "192.168.10.137", threshold: 1/60.0, interval: 3)) {
				//player.load(url: url, mode: .Server(port: 9000)) {
				print($0)
			}
		} else {
			assertionFailure()
		}
	}

	func applicationWillTerminate(aNotification: NSNotification) {
		// Insert code here to tear down your application
	}


}

