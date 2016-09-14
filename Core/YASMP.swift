//
//  YASMP.swift
//  YASMP
//
//  Created by Kota Nakano on 9/13/16.
//
//
import AVFoundation

class YASMP {
	let intervals: Double = 3
	let port: Int = 10
	let player: AVQueuePlayer
	let sock: Int32
	let clock: CMClock
	var layer: AVPlayerLayer {
		return AVPlayerLayer(player: player)
	}
	init() {
		clock = CMClockGetHostTimeClock()
		player = AVQueuePlayer()
		player.actionAtItemEnd = .None
		player.masterClock = clock
		sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
	}
	func server() {
		
		let source: dispatch_source_t = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(sock), 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0))

		let launch: CMTime = CMClockGetTime(clock)

		func recv() {
			
			var socklen: socklen_t = socklen_t(sizeof(sockaddr_in))
			let sockbuf: [UInt8] = [UInt8](count: Int(socklen), repeatedValue: 0)
			let sockref: UnsafeMutablePointer<sockaddr> = UnsafeMutablePointer<sockaddr>(sockbuf)
			
			let length: Int = Int(dispatch_source_get_data(source))
			let buffer: [CMTime] = [kCMTimeZero, kCMTimeZero, kCMTimeZero, launch, player.currentTime(), CMClockGetTime(clock)]
			
			assert(length==sizeof(CMTime)*3)
			
			assert(recvfrom(sock, UnsafeMutablePointer<Void>(buffer), sizeof(CMTime)*3, 0, sockref, &socklen)==sizeof(CMTime)*3)
			assert(sendto(sock, UnsafePointer<Void>(buffer), sizeof(CMTime)*6, 0, sockref, socklen)==sizeof(CMTime)*6)
			
		}
		
		let sockbuf: [UInt8] = [UInt8](count: sizeof(sockaddr_in), repeatedValue: 0)
		let sockref: UnsafeMutablePointer<sockaddr_in> = UnsafeMutablePointer<sockaddr_in>(sockbuf)
		
		sockref.memory.sin_family = sa_family_t(AF_INET)
		sockref.memory.sin_len = __uint8_t(sockbuf.count)
		sockref.memory.sin_port = in_port_t(9000)
		sockref.memory.sin_addr.s_addr = in_addr_t(0x00000000)
		
		assert(0==bind(sock, UnsafePointer<sockaddr>(sockbuf), socklen_t(sockbuf.count)))
		
		dispatch_source_set_event_handler(source, recv)
		dispatch_resume(source)
		
		player.play()
		
	}
	func client(reference: String, threshold: Double) {
		
		let source: dispatch_source_t = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(sock), 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0))
		let timer: dispatch_source_t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0))
		
		let launch: CMTime = CMClockGetTime(clock)

		var prev: CMTime = kCMTimeZero
		var hostAnchor: CMTime = kCMTimeZero
		var peerAnchor: CMTime = kCMTimeZero
		
		func recv() {
			
			let length: Int = Int(dispatch_source_get_data(source))
			assert(length==sizeof(CMTime)*6)
			
			let buffer: [CMTime] = [kCMTimeZero, kCMTimeZero, kCMTimeZero, kCMTimeZero, kCMTimeZero, kCMTimeZero, player.currentTime(), CMClockGetTime(clock)]
			assert(recvfrom(sock, UnsafeMutablePointer<Void>(buffer), sizeof(CMTime)*6, 0, nil, nil)==sizeof(CMTime)*6)
			
			//let host: CMTime = buffer[0]
			let hostSeek: CMTime = CMTimeMultiplyByRatio(CMTimeAdd(buffer[1], buffer[6]), 1, 2)
			let hostTime: CMTime = CMTimeMultiplyByRatio(CMTimeAdd(buffer[2], buffer[7]), 1, 2)
			let peer: CMTime = buffer[3]
			let peerSeek: CMTime = buffer[4]
			let peerTime: CMTime = buffer[5]
			
			if threshold < CMTimeGetSeconds(CMTimeAbsoluteValue(CMTimeSubtract(peerSeek, hostSeek))) {
				player.setRate(Float(NSUserDefaults().doubleForKey(reference)), time: peerSeek, atHostTime: hostTime)
			}
			if 0 != CMTimeCompare(peer, prev) {
				hostAnchor = hostTime
				peerAnchor = peerTime
				prev = peer
			}
			else {
				let hostInterval = CMTimeSubtract(hostTime, hostAnchor)
				let peerInterval = CMTimeSubtract(peerTime, peerAnchor)
				NSUserDefaults().setDouble((Double(peerInterval.value)/Double(hostInterval.value))*(Double(hostInterval.timescale)/Double(peerInterval.timescale)), forKey: reference)
				NSUserDefaults().synchronize()
			}
		
		}
		func send() {
			
			dispatch_suspend(timer)
			
			let sockbuf: [UInt8] = [UInt8](count: sizeof(sockaddr_in), repeatedValue: 0)
			let sockref: UnsafeMutablePointer<sockaddr_in> = UnsafeMutablePointer<sockaddr_in>(sockbuf)
				
			sockref.memory.sin_family = sa_family_t(AF_INET)
			sockref.memory.sin_len = __uint8_t(sockbuf.count)
			sockref.memory.sin_port = in_port_t(9000)
			sockref.memory.sin_addr.s_addr = reference.componentsSeparatedByString(".").enumerate().reduce(UInt32(0)) { $0.0 | ( UInt32($0.1.element) ?? 0 ) << ( UInt32($0.1.index) << 3 ) }
			
			let pair: [CMTime] = [launch, player.currentTime(), CMClockGetTime(clock)]
			assert(sendto(sock, pair, sizeof(CMTime)*3, 0, UnsafePointer<sockaddr>(sockbuf), socklen_t(sockbuf.count))==sizeof(CMTime)*pair.count)
				
			dispatch_resume(timer)
			
		}
		
		dispatch_source_set_event_handler(source, recv)
		dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, Int64(intervals*Double(NSEC_PER_SEC))), UInt64(intervals * Double(NSEC_PER_SEC)), NSEC_PER_SEC)
		dispatch_source_set_event_handler(timer, send)
		
		dispatch_resume(source)
		dispatch_resume(timer)
	}
	func loop(notification: NSNotification) {
		guard let played: AVPlayerItem = notification.object as? AVPlayerItem else { fatalError() }
		played.seekToTime(kCMTimeZero)
		player.advanceToNextItem()
		player.seekToTime(kCMTimeZero)
		player.insertItem(played, afterItem: nil)
	}
	func play(composition: AVComposition) {
		let centre: NSNotificationCenter = NSNotificationCenter.defaultCenter()
		(0..<2).forEach { (_) in
			let item: AVPlayerItem = AVPlayerItem(asset: composition)
			centre.addObserverForName(AVPlayerItemDidPlayToEndTimeNotification, object: item, queue: nil, usingBlock: loop)
			player.insertItem(item, afterItem: nil)
		}
		client("192.168.10.137", threshold: 1/60.0)
//		server()
	}
	func load(url: NSURL, error: ((AVKeyValueStatus)->())?) {
		
		func prepare(assets: AVURLAsset) {
			let composition: AVMutableComposition = AVMutableComposition()
			(0..<1024).forEach { (_) in
				do {
					let range: CMTimeRange = CMTimeRange(start: kCMTimeZero, duration: assets.duration)
					try composition.insertTimeRange(range, ofAsset: assets, atTime: composition.duration)
				} catch {
					print("failed inserting")
				}
			}
			play(composition)
		}

		let key: String = "tracks"
		let assets: AVURLAsset = AVURLAsset(URL: url)
		
		assets.loadValuesAsynchronouslyForKeys([key]) {
			switch assets.statusOfValueForKey(key, error: nil) {
			case .Cancelled:
				error?(.Cancelled)
			case .Failed:
				error?(.Cancelled)
			case .Loaded:
				prepare(assets)
			case .Loading:
				break
			case .Unknown:
				error?(.Cancelled)
			}
		}
		
	}
}
