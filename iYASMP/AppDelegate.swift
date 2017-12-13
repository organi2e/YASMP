//
//  AppDelegate.swift
//  iYASMP
//
//  Created by Kota Nakano on 12/7/17.
//

import UIKit
import AVFoundation
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
	var window: UIWindow?
	var yasmp: YASMP?
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
		// Override point for customization after application launch.
		guard
			let url: URL = Bundle.main.url(forResource: "02", withExtension: "mp4"),
			FileManager.default.fileExists(atPath: url.path),
			let view: UIView = window?.rootViewController?.view else {
				assertionFailure()
				return false
		}
		let yasmp: YASMP = try!YASMP(urls: [url], mode: .shuffle(1024), interval: 6.0, range: 1.0, service: "YASMP")
		let layer: AVPlayerLayer = AVPlayerLayer(player: yasmp.player)
		layer.frame = view.frame
		layer.videoGravity = .resizeAspectFill
		view.layer.sublayers?.forEach{$0.removeFromSuperlayer()}
		view.layer.addSublayer(layer)
		yasmp.resume()
		self.yasmp = yasmp
		return true
	}
	func applicationWillResignActive(_ application: UIApplication) {
		// Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
		// Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
	}
	func applicationDidEnterBackground(_ application: UIApplication) {
		// Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
		// If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
	}
	func applicationWillEnterForeground(_ application: UIApplication) {
		// Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
	}
	func applicationDidBecomeActive(_ application: UIApplication) {
		// Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
	}
	func applicationWillTerminate(_ application: UIApplication) {
		// Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
	}
}

