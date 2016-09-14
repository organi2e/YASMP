//
//  ViewController.swift
//  tvYASMP
//
//  Created by Kota Nakano on 9/13/16.
//
//

import UIKit
import QuartzCore
class ViewController: UIViewController {
	
	let player: YASMP = YASMP()
	
	override func viewDidLoad() {
		super.viewDidLoad()
		let bundle: NSBundle = NSBundle.mainBundle()
		if let url: NSURL = bundle.URLForResource("02", withExtension: "mp4") {
			let layer = player.layer
			layer.frame = view.frame
			//view.layer.sublayers?.removeAll()
			view.layer.addSublayer(layer)
			player.load(url) {
				print($0)
			}
		} else {
			assertionFailure()
		}
		// Do any additional setup after loading the view, typically from a nib.
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}


}

