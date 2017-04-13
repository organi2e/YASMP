//
//  main.swift
//  YASMP
//
//  Created by Kota Nakano on 9/20/16.
//
//

import Cocoa

let parse: Dictionary<String, Array<Any>> = [
	"--sync": [""],
	"--port": [UInt16(8080)],
	"--loop": [1],
	"--lock": [],
	"--threshold": [Double(0.3)],
	"--intervals": [Double(3.0)],
	"--playlist": [""],
]
print(parse)
let(rest, arguments): (Array<String>, Dictionary<String, Array<Any>>) = getopt(arguments: CommandLine.arguments, parse: parse)
print(arguments)
guard let sync: String = arguments["--sync"]?.first as? String else { fatalError("Invalid --sync") }
guard let port: UInt16 = arguments["--port"]?.first as? UInt16 else { fatalError("Invalid --port") }
guard let loop: Int = arguments["--loop"]?.first as? Int else { fatalError("Invalid --loop") }
let lock: Bool = arguments["--lock"]?.isEmpty == false
guard let threshold: Double = arguments["--threshold"]?.first as? Double else { fatalError("Invalid --threshold") }
guard let intervals: Double = arguments["--intervals"]?.first as? Double else { fatalError("Invalid --intervals") }
let playlist: Array<Int> = (arguments["--playlist"]?.first as? String)?.components(separatedBy: ",").map { Int($0) ?? 0 } ?? []

let urls: Array<URL> = rest.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }

if let screen: NSScreen = NSScreen.main(), urls.count > 0 {
	
	let app: NSApplication = NSApplication.shared()
	let view: NSView = NSView()
	
	let player: YASMP = YASMP()
	let layer = player.layer
	
	view.frame = screen.frame
	view.enterFullScreenMode(screen, withOptions: nil)
	
	layer.frame = view.frame
	
	view.layer = layer
	view.wantsLayer = true
	
	let mode: YASMP.Mode = sync.isEmpty ? .Server(port: port) : .Client(port: port, address: sync, threshold: threshold, interval: intervals)
	player.load(urls: urls, mode: mode, loop: loop) {
		print($0)
		app.terminate(app)
	}
	
	if !lock {
		NSEvent.addLocalMonitorForEvents(matching: NSEventMask.keyDown) {
			if $0.modifierFlags.contains(NSEventModifierFlags.command) && $0.charactersIgnoringModifiers == "q" {
				app.terminate(app)
			}
			return $0
		}
	}
	NSCursor.hide()
	app.run()
}

