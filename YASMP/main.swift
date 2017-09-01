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
		guard let num: UInt32 = deviceDescription["NSScreenNumber"] as? UInt32 else { return false }
		return ColorSyncDeviceSetCustomProfiles(kColorSyncDisplayDeviceClass.takeUnretainedValue(),
		                                        CGDisplayCreateUUIDFromDisplayID(num).takeUnretainedValue(),
		                                        [(kColorSyncDeviceDefaultProfileID.takeUnretainedValue() as String): (profile as URL),
		                                         (kColorSyncProfileUserScope.takeUnretainedValue() as String): (kCFPreferencesCurrentUser as String)]as CFDictionary)
	}
}
let parse: Dictionary<String, Array<Any>> = [
	"--identifier": ["YASMP"],
	"--interval": [Double(6.0)],
	"--playlist": [""],
	"--loop": [1],
	"--profile": [""],
	"--lock": []
]
let(rest, arguments): (Array<String>, Dictionary<String, Array<Any>>) = getopt(arguments: CommandLine.arguments, parse: parse)
guard let service: String = arguments["--identifier"]?.first as? String else { abort() }
guard let interval: Double = arguments["--interval"]?.first as? Double else { abort() }
//guard let playlist: Array<Int> = (arguments["--playlist"]?.first? as? String)?.components(separatedBy: ",").flatMap { Int($0) } ?? [Int]()
guard let loop: Int = arguments["--loop"]?.first as? Int else { abort() }
let lock: Bool = arguments["--lock"]?.isEmpty == false
let profile: URL? = arguments["--profile"]?.flatMap{$0 as?String}.filter{FileManager.default.fileExists(atPath: $0)}.map{URL(fileURLWithPath: $0)}.first
let urls: Array<URL> = rest.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
do {
	let app: NSApplication = .shared()
	guard let screen: NSScreen = .main() else {
		throw NSError(domain: #function, code: #line, userInfo: nil)
	}
	if let profile: URL = profile {
		guard screen.apply(profile: profile) else { throw NSError(domain: #function, code: #line, userInfo: nil) }
	}
	let yasmp: YASMP = try YASMP(urls: urls, mode: .shuffle(loop), interval: interval, service: service)
	let view: NSView = NSView(frame: screen.frame)
	
	view.layer = yasmp.layer
	view.layer?.frame = view.frame
	view.wantsLayer = true
	view.enterFullScreenMode(screen, withOptions: nil)
	yasmp.resume()
	
	if !lock {
		NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
			if $0.modifierFlags.contains(.command), $0.charactersIgnoringModifiers == "q" {
				app.terminate(app)
			}
			return $0
		}
	}
	NSCursor.hide()
	withExtendedLifetime(yasmp, app.run)
} catch {
	os_log("%s", log: .default, type: .fault, error.localizedDescription)
}
