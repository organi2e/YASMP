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
	let divisor: Int32
	let full: CMTime
	let half: CMTime
	let myself: MCPeerID
	var follow: MCPeerID
	var peerAnchor: CMTime
	var selfAnchor: CMTime
	var delay: CMTime
	var layer: AVPlayerLayer {
		return AVPlayerLayer(player: player)
	}
	init(urls: Array<URL>, mode: Mode,
	     interval: Double,
	     average: Int,
	     service: String = "YASMP") throws {
		let assets: Array<AVURLAsset> = urls.map(AVURLAsset.init)
		let maxfps: Double = Double(assets.reduce([], { $0 + $1.tracks }).reduce(1, { max($0, $1.nominalFrameRate )}))
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
		player = AVQueuePlayer()
		looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: composition))
		master = CMClockGetHostTimeClock()
		myself = MCPeerID(displayName: UUID().uuidString)
		follow = myself
		session = MCSession(peer: myself, securityIdentity: nil, encryptionPreference: .none)
		advertiser = MCNearbyServiceAdvertiser(peer: myself, discoveryInfo: nil, serviceType: service)
		browser = MCNearbyServiceBrowser(peer: myself, serviceType: service)
		source = DispatchSource.makeTimerSource(flags: .strict, queue: .global(qos: .userInteractive))
		threshold = 1 / maxfps
		divisor = Int32(average)
		delay = kCMTimeZero
		selfAnchor = kCMTimeZero
		peerAnchor = kCMTimeZero
		super.init()
		//player.actionAtItemEnd = .none
		player.masterClock = master
		player.automaticallyWaitsToMinimizeStalling = false
		source.setEventHandler(handler: check)
		source.scheduleRepeating(deadline: .now(), interval: interval)
		advertiser.delegate = self
		browser.delegate = self
		session.delegate = self
		advertiser.startAdvertisingPeer()
		browser.startBrowsingForPeers()
	}
	deinit {
		browser.stopBrowsingForPeers()
		advertiser.stopAdvertisingPeer()
		player.pause()
		source.cancel()
	}
}
extension YASMP {
	func pause() {
		source.suspend()
		player.pause()
	}
	func resume() {
		player.play()
		source.resume()
	}
}
extension YASMP {
	func check() {
		guard let dwarf: MCPeerID = session.connectedPeers.sorted(by: {$0.displayName < $1.displayName}).first, dwarf.displayName < myself.displayName else {
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
			os_log("%s", log: facility, type: .error, error.localizedDescription)
		}
	}
}
extension YASMP: MCNearbyServiceAdvertiserDelegate {
	func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
		os_log("join to %s", log: facility, type: .debug, peerID.displayName)
		invitationHandler(myself.displayName < peerID.displayName, session)
	}
	func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
		os_log("critical error %s", log: facility, type: .error, error.localizedDescription)
	}
}
extension YASMP: MCNearbyServiceBrowserDelegate {
	func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
		os_log("found peer %s", log: facility, type: .debug, peerID.displayName)
		guard peerID.displayName < session.connectedPeers.reduce(myself.displayName, { min($0, $1.displayName) }) else { return }
		session.connectedPeers.forEach(session.cancelConnectPeer)
		browser.invitePeer(peerID, to: session, withContext: nil, timeout: 0)
	}
	func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
		os_log("lost peer %s", log: facility, type: .debug, peerID.displayName)
	}
	func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
		os_log("critical error %s", log: facility, type: .fault, error.localizedDescription)
	}
}
extension YASMP: MCSessionDelegate {
	func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
		certificateHandler(true)
	}
	func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
		switch state {
		case .connecting:
			os_log("connecting to %s", log: facility, type: .debug, peerID.displayName)
		case .connected:
			os_log("connected to %s", log: facility, type: .debug, peerID.displayName)
			guard peerID.displayName < myself.displayName else { return }
			os_log("stop browsing", log: facility, type: .debug)
			browser.stopBrowsingForPeers()
		case .notConnected:
			os_log("not connected to %s", log: facility, type: .debug, peerID.displayName)
			guard peerID.displayName < myself.displayName else { return }
			os_log("restart browsing", log: facility, type: .debug)
			browser.startBrowsingForPeers()
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
					} catch {
						os_log("%s", log: facility, type: .error, error.localizedDescription)
					}
				case kCMTimeInvalid:
					let selfPlayedTime: CMTime = CMTimeMultiplyByRatio(CMTimeAdd(playedTime, ref[0]), 1, 2)
					let selfMasterTime: CMTime = CMTimeMultiplyByRatio(CMTimeAdd(masterTime, ref[1]), 1, 2)
					let peerPlayedTime: CMTime = ref[2]
					let peerMasterTime: CMTime = ref[3]
					let delta: CMTime = CMTimeSubtract(CMTimeModApprox(CMTimeAdd(CMTimeSubtract(peerPlayedTime, selfPlayedTime), half), full), half)
					guard follow == peerID else {
						selfAnchor = selfMasterTime
						peerAnchor = peerMasterTime
						follow = peerID
						delay = delta
						return
					}
					delay = CMTimeAdd(CMTimeMultiplyByRatio(delta, 1, divisor), CMTimeMultiplyByRatio(delay, divisor - 1, divisor))
					guard threshold < CMTimeGetSeconds(CMTimeAbsoluteValue(delay)) else { return }
					let selfElapsed: CMTime = CMTimeSubtract(selfMasterTime, selfAnchor)
					let peerElapsed: CMTime = CMTimeSubtract(peerMasterTime, peerAnchor)
					let rate: Double = Double(peerElapsed.value) / Double(selfElapsed.value) * Double(selfElapsed.timescale) / Double(peerElapsed.timescale)
					player.setRate(Float(rate), time: peerPlayedTime, atHostTime: selfMasterTime)
					os_log("Adjust rate %lf for delay %lf sec", log: facility, type: .info, rate, CMTimeGetSeconds(delta))
					delay = kCMTimeZero
				default:
					break
			}
		}
	}
	func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
		//nop
	}
	func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
		//nop
	}
	func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL, withError error: Error?) {
		//nop
	}
}
private func gcd<T: Integer>(_ m: T, _ n: T) -> T {
	return n == 0 ? m : gcd(n, m % n)
}
private func mod<T: Integer>(_ m: T, _ n: T) -> T {
	return ( ( m % n ) + n ) % n
}
private func CMTimeMod(_ x: CMTime, _ y: CMTime) -> CMTime {
	let cs: Int64 = Int64(gcd(x.timescale, y.timescale))
	let xs: Int64 = Int64(x.timescale) / cs
	let ys: Int64 = Int64(y.timescale) / cs
	return CMTime(value: mod(x.value*ys, y.value*xs), timescale: Int32(xs*ys*cs))
}
private func CMTimeModApprox(_ x: CMTime, _ y: CMTime) -> CMTime {
	let (xv, yv, ts): (Int64, Int64, Int32) = x.timescale < y.timescale ?
		(x.value * Int64(y.timescale) / Int64(x.timescale), y.value, y.timescale) :
		(x.value, y.value * Int64(x.timescale) / Int64(y.timescale), x.timescale)
	return CMTime(value: ((xv%yv)+yv)%yv, timescale: ts)
}
private func rndseq(count: Int, range: UInt32, last: UInt32? = nil) -> Array<Int> {
	guard 0 < count else { return Array<Int>() }
	let next: UInt32 = ( ( last ?? arc4random_uniform(range)) + arc4random_uniform(range-1) + 1 ) % range
	return Array<Int>(repeating: Int(next), count: 1) + rndseq(count: count - 1, range: range, last: next)
}
private let facility: OSLog = OSLog(subsystem: "YASMP", category: "Core")
