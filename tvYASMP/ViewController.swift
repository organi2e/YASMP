//
//  ViewController.swift
//  tvYASMP
//
//  Created by Kota Nakano on 9/20/16.
//
//

import UIKit

class ViewController: UIViewController {
	
	override func viewDidLoad() {
		super.viewDidLoad()
		let bundle: Bundle = Bundle.main
		if let url: URL = bundle.url(forResource: "02", withExtension: "mp4"), let player: YASMP = (UIApplication.shared.delegate as? AppDelegate)?.player {
			let layer = player.layer
			layer.frame = view.frame
			//view.layer.sublayers?.removeAll()
			view.layer.addSublayer(layer)
			player.load(url: url) {
				print($0)
			}
			print("ok")
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

