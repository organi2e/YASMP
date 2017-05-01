//
//  main.swift
//  YASMP
//
//  Created by Kota Nakano on 9/20/16.
//
//

import Cocoa
import CoreFoundation
import CoreGraphics
import Quartz
import QuartzCore

let parse: Dictionary<String, Array<Any>> = [
	"--sync": [""],
	"--port": [UInt16(9000)],
	"--loop": [1],
	"--lock": [],
	"--threshold": [Double(0.3)],
	"--intervals": [Double(3.0)],
	"--playlist": [""],
	"--profile": [""],
	"--dump": [""]
]
let(rest, arguments): (Array<String>, Dictionary<String, Array<Any>>) = getopt(arguments: CommandLine.arguments, parse: parse)
guard let sync: String = arguments["--sync"]?.first as? String else { fatalError("Invalid --sync") }
guard let port: UInt16 = arguments["--port"]?.first as? UInt16 else { fatalError("Invalid --port") }
guard let loop: Int = arguments["--loop"]?.first as? Int else { fatalError("Invalid --loop") }
let lock: Bool = arguments["--lock"]?.isEmpty == false
guard let threshold: Double = arguments["--threshold"]?.first as? Double else { fatalError("Invalid --threshold") }
guard let intervals: Double = arguments["--intervals"]?.first as? Double else { fatalError("Invalid --intervals") }
let playlist: Array<Int> = (arguments["--playlist"]?.first as? String)?.components(separatedBy: ",").map { Int($0) ?? 0 } ?? []
let profile: URL? = arguments["--profile"]?.flatMap { $0 as? String }.filter { FileManager.default.fileExists(atPath: $0) } .map { URL(fileURLWithPath: $0) }.first
let dump: FileHandle = arguments["--dump"]?.flatMap { $0 as? String }.filter { !$0.isEmpty && ( FileManager.default.fileExists(atPath: $0) || FileManager.default.createFile(atPath: $0, contents: nil, attributes: nil) ) }.map { FileHandle(forUpdatingAtPath: $0) ?? FileHandle.standardError }.first ?? FileHandle.standardError
let urls: Array<URL> = rest.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
if let screen: NSScreen = NSScreen.main(), urls.count > 0 {
	if let profile: URL = profile {//Change Color Profile if .icc file distributed
		let key: String = "NSScreenNumber"
		guard let num: UInt32 = screen.deviceDescription[key] as? UInt32 else {
			fatalError("\(screen.deviceDescription) contains no \(key)")
		}
		guard ColorSyncDeviceSetCustomProfiles(kColorSyncDisplayDeviceClass.takeUnretainedValue(),
		                                               CGDisplayCreateUUIDFromDisplayID(num).takeUnretainedValue(),
		                                               [(kColorSyncDeviceDefaultProfileID.takeUnretainedValue() as String): (profile as CFURL),
		                                                (kColorSyncProfileUserScope.takeUnretainedValue() as String): (kCFPreferencesCurrentUser as String)]
														as CFDictionary) else {
			fatalError("Profile \(profile) is not compatible for \(screen.deviceDescription)")
		}
	}
	
	let app: NSApplication = NSApplication.shared()
	let view: NSView = NSView()
	
	let player: YASMP = YASMP(dump: dump)
	let layer = player.layer
	
	view.frame = screen.frame
	view.enterFullScreenMode(screen, withOptions: nil)
	
	layer.frame = view.frame
	
	view.layer = layer
	view.wantsLayer = true
	
	let mode: YASMP.Mode = sync.isEmpty ? .Server(port: port) : .Client(port: port, address: sync, threshold: threshold, interval: intervals)
	player.load(urls: urls, mode: mode, loop: loop) {
		fatalError(String(describing: $0))
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

