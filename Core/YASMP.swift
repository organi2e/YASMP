//
//  YASMP.swift
//  YASMP
//
//  Created by Kota Nakano on 9/13/16.
//
//
import AVFoundation
import MultipeerConnectivity
import os.log
class YASMP: NSObject {
	public enum Mode {
		case shuffle(_: Int)
		case playlist(_: Array<Int>)
	}
	let master: CMClock
	let player: AVQueuePlayer
	let looper: AVPlayerLooper
	let session: MCSession
	let advertiser: MCNearbyServiceAdvertiser
	let browser: MCNearbyServiceBrowser
	let source: DispatchSourceTimer
	let threshold: Double
	let upper: Double
	let lower: Double
	let full: CMTime
	let half: CMTime
	let myself: MCPeerID
	var trying: Int
	var follow: MCPeerID
	var little: CMTime
	var peerAnchor: CMTime
	var selfAnchor: CMTime
	var layer: AVPlayerLayer {
		return AVPlayerLayer(player: player)
	}
	init(urls: Array<URL>, mode: Mode, interval: Double, range: Double, service: String = "YASMP") throws {
		let assets: Array<AVAsset> = urls.map {
			AVURLAsset(url: $0, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true, AVURLAssetReferenceRestrictionsKey: true])
		}
		let maxfps: Double = Double(assets.reduce([]){ $0 + $1.tracks }.reduce(1){ max($0, $1.nominalFrameRate )})
		let index: Array<Int> = {
			switch $0 {
			case let .playlist(index):
				return index
			case let .shuffle(count):
				return rndseq(count: count, range: UInt32(assets.count))
			}
		} ( mode )
		let composition: AVComposition = try index.reduce(AVMutableComposition()) {
			try $0.insertTimeRange(CMTimeRange(start: kCMTimeZero, duration: assets[$1].duration), of: assets[$1], at: $0.duration)
			return $0
		}
		full = composition.duration
		half = CMTimeMultiplyByRatio(full, 1, 2)
		player = AVQueuePlayer(items: [AVPlayerItem(asset: composition), AVPlayerItem(asset: composition)])
		looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: composition))
		master = CMClockGetHostTimeClock()
		myself = MCPeerID(displayName: UUID().uuidString)
		follow = myself
		little = kCMTimeZero
		trying = 0
		session = MCSession(peer: myself, securityIdentity: nil, encryptionPreference: .none)
		advertiser = MCNearbyServiceAdvertiser(peer: myself, discoveryInfo: nil, serviceType: service)
		browser = MCNearbyServiceBrowser(peer: myself, serviceType: service)
		source = DispatchSource.makeTimerSource(flags: .strict, queue: .global(qos: .userInteractive))
		threshold = 3.0 / maxfps
		(lower, upper) = (pow(0.5, range), pow(2.0, range))
		selfAnchor = kCMTimeZero
		peerAnchor = kCMTimeZero
		super.init()
		os_log("myself %{public}@", log: facility, type: .debug, myself.displayName)
		player.masterClock = master
//		player.actionAtItemEnd = .none
		player.automaticallyWaitsToMinimizeStalling = false
		advertiser.delegate = self
		browser.delegate = self
		session.delegate = self
		source.setEventHandler(handler: check)
		source.schedule(wallDeadline: .now(), repeating: interval)
		source.resume()
	}
	deinit {
		player.pause()
		source.cancel()
	}
}
extension YASMP {
	func pause() {
		session.connectedPeers.forEach(session.cancelConnectPeer)
		session.disconnect()
		browser.stopBrowsingForPeers()
		advertiser.stopAdvertisingPeer()
		follow = myself
		little = kCMTimeZero
		peerAnchor = kCMTimeZero
		selfAnchor = kCMTimeZero
		player.pause()
	}
	func resume() {
		player.play()
		follow = myself
		little = kCMTimeZero
		peerAnchor = kCMTimeZero
		selfAnchor = kCMTimeZero
		session.connectedPeers.forEach(session.cancelConnectPeer)
		session.disconnect()
		advertiser.startAdvertisingPeer()
		browser.startBrowsingForPeers()
		print(player.rate)
		player.play()
	}
}
extension YASMP {
	func check() {
		guard trying < 11 else {
			print(trying, 2)
			advertiser.delegate = self
			advertiser.startAdvertisingPeer()
			browser.delegate = self
			browser.startBrowsingForPeers()
			trying = 0
			return
		}
		guard trying < 10 else {
			print(trying, 1)
			browser.stopBrowsingForPeers()
			browser.delegate = nil
			advertiser.stopAdvertisingPeer()
			advertiser.delegate = nil
			trying = trying + 1
			return
		}
		guard !session.connectedPeers.isEmpty else {
			print(trying, 0)
			trying = trying + 1
			return
		}
		guard let dwarf: MCPeerID = session.connectedPeers.sorted(by: {$0.displayName < $1.displayName}).first, dwarf.displayName < myself.displayName else {
			player.rate = 1.0
			return
		}
		let playedTime: CMTime = player.currentTime()
		let masterTime: CMTime = CMClockGetTime(master)
		let data: Data = Data(count: 6 * MemoryLayout<CMTime>.stride)
		data.withUnsafeBytes { (ref: UnsafePointer<CMTime>) in
			let mutating: UnsafeMutablePointer<CMTime> = UnsafeMutablePointer<CMTime>(mutating: ref)
			mutating[0] = playedTime
			mutating[1] = masterTime
			mutating[4] = kCMTimeZero
			mutating[5] = UnsafeBufferPointer<CMTime>(start: ref, count: 4).reduce(kCMTimeZero, CMTimeAdd)
		}
		do {
			try session.send(data, toPeers: Array<MCPeerID>(repeating: dwarf, count: 1), with: .unreliable)
		} catch {
			os_log("%{public}@", log: facility, type: .error, error.localizedDescription)
		}
	}
}
extension YASMP: MCNearbyServiceAdvertiserDelegate {
	func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
		os_log("join to %{public}@", log: facility, type: .debug, peerID.displayName)
		invitationHandler(true, session)
	}
	func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
		os_log("critical error %{public}@", log: facility, type: .fault, error.localizedDescription)
		assertionFailure("critical error \(error)")
	}
}
extension YASMP: MCNearbyServiceBrowserDelegate {
	func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
		os_log("found peer %{public}@", log: facility, type: .debug, String(peerID.displayName))
		browser.invitePeer(peerID, to: session, withContext: nil, timeout: 3.0)
	}
	func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
		os_log("lost peer %{public}@", log: facility, type: .debug, String(peerID.displayName))
	}
	func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
		os_log("critical error %{public}@", log: facility, type: .fault, error.localizedDescription)
		assertionFailure("critical error \(error)")
	}
}
extension YASMP: MCSessionDelegate {
	func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
		certificateHandler(true)
	}
	func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
		switch state {
		case .connecting:
			os_log("connecting to %{public}@", log: facility, type: .debug, peerID.displayName)
//			browser.stopBrowsingForPeers()
		case .connected:
			os_log("connected to %{public}@", log: facility, type: .debug, peerID.displayName)
//			browser.stopBrowsingForPeers()
//			browser.startBrowsingForPeers()
//			guard peerID.displayName < myself.displayName else { return }
//			os_log("stop browsing", log: facility, type: .debug)
//			browser.stopBrowsingForPeers()
		case .notConnected:
			os_log("not connected to %{public}@", log: facility, type: .debug, peerID.displayName)
//			browser.stopBrowsingForPeers()
//			browser.startBrowsingForPeers()
//			guard peerID.displayName < myself.displayName else { return }
//			os_log("restart browsing", log: facility, type: .debug)
//			browser.startBrowsingForPeers()
		}
	}
	func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
		guard data.count == 6 * MemoryLayout<CMTime>.stride else {
			os_log("incorrect byte %d", log: facility, type: .error, data.count)
			return
		}
		let playedTime: CMTime = player.currentTime()
		let masterTime: CMTime = CMClockGetTime(master)
		data.withUnsafeBytes { (ref: UnsafePointer<CMTime>) in
			guard ref[5] == UnsafeBufferPointer<CMTime>(start: ref, count: 4).reduce(kCMTimeZero, CMTimeAdd) else {
				os_log("incorrect data", log: facility, type: .error)
				return
			}
			switch ref[4] {
			case kCMTimeZero:
				let mutating: UnsafeMutablePointer<CMTime> = UnsafeMutablePointer<CMTime>(mutating: ref)
				mutating[2] = playedTime
				mutating[3] = masterTime
				mutating[4] = kCMTimeInvalid
				mutating[5] = UnsafeBufferPointer<CMTime>(start: ref, count: 4).reduce(kCMTimeZero, CMTimeAdd)
				do {
					try session.send(data, toPeers: Array<MCPeerID>(repeating: peerID, count: 1), with: .unreliable)
					os_log("receive: %lf, %lf response: %lf, %lf, from: %{public}@", log: facility, type: .debug, ref[0].seconds, ref[1].seconds, ref[2].seconds, ref[3].seconds, peerID.displayName)
				} catch {
					os_log("%{public}@", log: facility, type: .error, error.localizedDescription)
				}
			case kCMTimeInvalid:
				let selfPlayedTime: CMTime = CMTimeMultiplyByRatio(CMTimeAdd(playedTime, ref[0]), 1, 2)
				let selfMasterTime: CMTime = CMTimeMultiplyByRatio(CMTimeAdd(masterTime, ref[1]), 1, 2)
				let peerPlayedTime: CMTime = ref[2]
				let peerMasterTime: CMTime = ref[3]
				let delay: CMTime = CMTimeSubtract(CMTimeModApprox(CMTimeAdd(CMTimeSubtract(peerPlayedTime, selfPlayedTime), half), full), half)
				let reply: CMTime = CMTimeSubtract(masterTime, ref[1])
				os_log("delay: %lf, reply: %lf, little: %lf", log: facility, type: .debug, delay.seconds, reply.seconds, little.seconds)
				//
				guard follow == peerID else {
					follow = peerID
					little = kCMTimeInvalid
					return
				}
				//re-anchor on getting more reliable reply
				guard CMTimeCompare(little, reply) < 0 else {
					selfAnchor = selfMasterTime
					peerAnchor = peerMasterTime
					little = reply
					return
				}
				//
				guard CMTimeCompare(reply, CMTimeMultiplyByRatio(little, 13, 8)) < 0 else { return }
				//
				guard threshold < CMTimeAbsoluteValue(delay).seconds else { return }
				let rate: Double = CMTimeSubtract(peerMasterTime, peerAnchor).seconds / CMTimeSubtract(selfMasterTime, selfAnchor).seconds
				guard lower < rate, rate < upper else { return }
				player.setRate(Float(rate), time: peerPlayedTime, atHostTime: selfMasterTime)
				os_log("adjust rate %lf", log: facility, type: .info, rate, rate)
			default:
				break
			}
		}
	}
	func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
		//nop
		assertionFailure("\(#function) is not implemented")
	}
	func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
		//nop
		assertionFailure("\(#function) is not implemented")
	}
	func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
		//nop
		assertionFailure("\(#function) is not implemented, \(String(describing: error))")
	}
}
private func gcd<T: BinaryInteger>(_ m: T, _ n: T) -> T {
	return n == 0 ? m : gcd(n, m % n)
}
private func mod<T: BinaryInteger>(_ m: T, _ n: T) -> T {
	return ( ( m % n ) + n ) % n
}
private func CMTimeMod(_ x: CMTime, _ y: CMTime) -> CMTime {
	let cs: Int64 = Int64(gcd(x.timescale, y.timescale))
	let xs: Int64 = Int64(x.timescale) / cs
	let ys: Int64 = Int64(y.timescale) / cs
	return CMTime(value: mod(x.value*ys, y.value*xs), timescale: Int32(xs*ys*cs))
}
private func CMTimeModApprox(_ x: CMTime, _ y: CMTime) -> CMTime {
	let cs: Int64 = Int64(gcd(x.timescale, y.timescale))
	let xs: Int64 = Int64(x.timescale) / cs
	let ys: Int64 = Int64(y.timescale) / cs
	let (xv, yv, ts): (Int64, Int64, Int32) = x.timescale < y.timescale ?
		(x.value * ys / xs, y.value, y.timescale) :
		(x.value, y.value * xs / ys, x.timescale)
	return CMTime(value: mod(xv, yv), timescale: ts)
}
private func rndseq(count: Int, range: UInt32, last: UInt32? = nil) -> Array<Int> {
	guard 0 < count else { return Array<Int>() }
	let next: UInt32 = ( ( last ?? arc4random_uniform(range)) + arc4random_uniform(range-1) + 1 ) % range
	return [Int(next)] + rndseq(count: count - 1, range: range, last: next)
}
private let facility: OSLog = OSLog(subsystem: "YASMP", category: "Core")
