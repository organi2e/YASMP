//
//  main.swift
//  YASMP
//
//  Created by Kota Nakano on 9/20/16.
//
//

import Cocoa

if let screen: NSScreen = NSScreen.main() {
	
	let app: NSApplication = NSApplication.shared()
	
	let view: NSView = NSView()
	
	let player: YASMP = YASMP()
	let layer = player.layer
	
	view.frame = screen.frame
	view.enterFullScreenMode(screen, withOptions: nil)
	
	layer.frame = view.frame
	
	view.layer = layer
	view.wantsLayer = true
	
	player.load(url: URL(fileURLWithPath: "/tmp/02.mp4"), mode: YASMP.Mode.Client(port: 9000, address: "192.168.10.137", threshold: 1/60.0, interval: 3), error: nil)
	
	NSEvent.addLocalMonitorForEvents(matching: NSEventMask.keyDown) {
		if $0.modifierFlags.contains(NSEventModifierFlags.command) && $0.charactersIgnoringModifiers == "q" {
			app.terminate(app)
		}
		return $0
	}
	
	app.run()
}

