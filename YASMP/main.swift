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
let profile: URL? = arguments["--profile"]?.flatMap{$0 as?String}.filter{FileManager.default.fileExists(atPath: $0)}.map{URL(fileURLWithPath: $0)}.first
let urls: Array<URL> = rest.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }

do {
	let yasmp: YASMP = try YASMP(urls: urls, mode: .shuffle(loop), interval: interval, range: range, service: service)
	let view: NSView = NSView()
	view.layer = yasmp.layer
	view.wantsLayer = true
	func reset() {
		guard let screen: NSScreen = .main else { return }
		if let profile: URL = profile {
			guard screen.apply(profile: profile) else { return }
		}
		yasmp.pause()
		view.exitFullScreenMode(options: nil)
		view.frame = screen.frame
		view.layer?.frame = view.frame
		view.enterFullScreenMode(screen, withOptions: nil)
		yasmp.resume()
		os_log("reset playing", log: OSLog(subsystem: "YASMP", category: "player"), type: .info)
	}
	let app: NSApplication = .shared
	if !lock {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            if $0.modifierFlags.contains(.command), $0.charactersIgnoringModifiers == "q" {
				app.terminate(app)
			}
			return $0
		}
	}
	let monitor: NSObjectProtocol = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil) { _ in
		reset()
	}
	reset()
	NSCursor.hide()
	withExtendedLifetime((yasmp, view, monitor), app.run)
} catch {
	os_log("%s", log: .default, type: .fault, String(describing: error))
}
