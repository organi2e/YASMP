//
//  main.swift
//  YASMP
//
//  Created by Kota Nakano on 9/20/16.
//
//
import Cocoa
import os.log
extension NSScreen {
	func apply(profile: URL) -> Bool {
		guard let num: UInt32 = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return false }
		return ColorSyncDeviceSetCustomProfiles(kColorSyncDisplayDeviceClass.takeUnretainedValue(),
		                                        CGDisplayCreateUUIDFromDisplayID(num).takeUnretainedValue(),
		                                        [kColorSyncDeviceDefaultProfileID.takeUnretainedValue(): profile,
		                                         kColorSyncProfileUserScope.takeUnretainedValue(): kCFPreferencesCurrentUser] as CFDictionary)
	}
}
let parse: Dictionary<String, Array<Any>> = [
	"--identifier": ["YASMP"],
	"--interval": [Double(6.0)],
	"--playlist": [""],
	"--loop": [1],
	"--profile": [""],
	"--range": [Double(0.05)],
	"--lock": []
]
let(rest, arguments): (Array<String>, Dictionary<String, Array<Any>>) = getopt(arguments: CommandLine.arguments, parse: parse)
guard let service: String = arguments["--identifier"]?.first as? String else { fatalError("Invalid identifier") }
guard let interval: Double = arguments["--interval"]?.first as? Double else { fatalError("Invalid interval") }
//guard let playlist: Array<Int> = (arguments["--playlist"]?.first? as? String)?.components(separatedBy: ",").flatMap { Int($0) } ?? [Int]()
guard let loop: Int = arguments["--loop"]?.first as? Int else { fatalError("Invalid loop") }
guard let range: Double = arguments["--range"]?.first as? Double else { fatalError("Invalid range") }
let lock: Bool = arguments["--lock"]?.isEmpty == false
let profile: URL? = arguments["--profile"]?.flatMap {
	guard
		let path: String = $0 as? String,
		FileManager.default.fileExists(atPath: path) else {
			return nil
		}
		return URL(fileURLWithPath: path)
	}.first
let urls: Array<URL> = rest.flatMap {
	guard FileManager.default.fileExists(atPath: $0) else {
		return nil
	}
	return URL(fileURLWithPath: $0)
	}
do {
	let app: NSApplication = .shared
	let yasmp: YASMP = try YASMP(urls: urls, mode: .shuffle(loop), interval: interval, range: range, service: service)
	let view: NSView = NSView()
	view.layer = yasmp.layer
	view.wantsLayer = true
	if !lock {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            if $0.modifierFlags.contains(.command), $0.charactersIgnoringModifiers == "q" {
				app.terminate(app)
			}
			return $0
		}
	}
	func reset() {
		guard let screen: NSScreen = .main else { return }
		yasmp.pause()
		view.exitFullScreenMode(options: nil)
		view.frame = screen.frame
		view.layer?.frame = screen.frame
		view.enterFullScreenMode(screen, withOptions: nil)
		yasmp.resume()
		NSCursor.hide()
		os_log("reset playing", log: OSLog(subsystem: "YASMP", category: "player"), type: .info)
	}
	func reset(notification: Notification) {
		reset()
	}
	let nc: NSObjectProtocol = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: reset)
	RunLoop.current.perform(reset)
	withExtendedLifetime((yasmp, view, app, nc), app.run)
} catch {
	os_log("%s", log: .default, type: .fault, String(describing: error))
}
