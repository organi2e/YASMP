//
//  YASMP.swift
//  YASMP
//
//  Created by Kota Nakano on 9/13/16.
//
//
import AVFoundation

class YASMP {
	enum Mode {
		case Server(port: UInt16)
		case Client(refer: String, port: UInt16, interval: Double)
	}
	let intervals: Double = 3
	let port: Int = 10
	let player: AVQueuePlayer
	let clock: CMClock
	let source: DispatchSourceRead
	var launch: CMTime
	var layer: AVPlayerLayer {
		return AVPlayerLayer(player: player)
	}
	var sock: Int32 {
		return Int32(source.handle)
	}
	init() {
		clock = CMClockGetHostTimeClock()
		player = AVQueuePlayer()
		player.actionAtItemEnd = .none
		player.masterClock = clock
		source = DispatchSource.makeReadSource(fileDescriptor: socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP), queue: DispatchQueue.global(qos: .userInteractive))
		launch = kCMTimeZero
	}
	private func server() {
		
		func recv() {
			
			var socklen: socklen_t = socklen_t(MemoryLayout<sockaddr_in>.size)
			let sockref: UnsafeMutablePointer<sockaddr> = UnsafeMutablePointer<sockaddr>.allocate(capacity: MemoryLayout<sockaddr_in>.size)
			defer { sockref.deinitialize() }
			
			let length: Int = Int(source.data)
			let buffer: [CMTime] = [kCMTimeZero, kCMTimeZero, kCMTimeZero, launch, player.currentTime(), CMClockGetTime(clock)]
			
			assert(length==MemoryLayout<CMTime>.size*3)
			
			assert(recvfrom(sock, UnsafeMutableRawPointer(mutating: buffer), MemoryLayout<CMTime>.size*3, 0, sockref, &socklen)==MemoryLayout<CMTime>.size*3)
			assert(sendto(sock, UnsafeRawPointer(buffer), MemoryLayout<CMTime>.size*6, 0, sockref, socklen)==MemoryLayout<CMTime>.size*6)
			
		}
		
		let sockref: UnsafeMutablePointer<sockaddr_in> = UnsafeMutablePointer<sockaddr_in>.allocate(capacity: MemoryLayout<sockaddr_in>.size)
		defer { sockref.deallocate(capacity: MemoryLayout<sockaddr_in>.size) }
		
		sockref.pointee.sin_family = sa_family_t(AF_INET)
		sockref.pointee.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
		sockref.pointee.sin_port = in_port_t(9000)
		sockref.pointee.sin_addr.s_addr = in_addr_t(0x00000000)
		
		assert(0==bind(sock, UnsafeMutablePointer<sockaddr>(OpaquePointer(sockref)), socklen_t(MemoryLayout<sockaddr_in>.size)))
		
		source.setEventHandler(handler: recv)
		source.resume()

		launch = CMClockGetTime(clock)
		player.play()
		
	}
	private func client(reference: String, threshold: Double) {
		
		let timer: DispatchSourceTimer = DispatchSource.makeTimerSource(flags: .strict, queue: DispatchQueue.global(qos: .background))
		
		var prev: CMTime = kCMTimeZero
		var hostAnchor: CMTime = kCMTimeZero
		var peerAnchor: CMTime = kCMTimeZero
		
		func recv() {
			
			let length: Int = Int(source.data)
			assert(length==MemoryLayout<CMTime>.size*6)
			
			let buffer: [CMTime] = [kCMTimeZero, kCMTimeZero, kCMTimeZero, kCMTimeZero, kCMTimeZero, kCMTimeZero, player.currentTime(), CMClockGetTime(clock)]
			assert(recvfrom(sock, UnsafeMutableRawPointer(mutating: buffer), MemoryLayout<CMTime>.size*6, 0, nil, nil)==MemoryLayout<CMTime>.size*6)
			
			//let host: CMTime = buffer[0]
			let hostSeek: CMTime = CMTimeMultiplyByRatio(CMTimeAdd(buffer[1], buffer[6]), 1, 2)
			let hostTime: CMTime = CMTimeMultiplyByRatio(CMTimeAdd(buffer[2], buffer[7]), 1, 2)
			let peer: CMTime = buffer[3]
			let peerSeek: CMTime = buffer[4]
			let peerTime: CMTime = buffer[5]
			
			if threshold < CMTimeGetSeconds(CMTimeAbsoluteValue(CMTimeSubtract(peerSeek, hostSeek))) {
				player.setRate(Float(UserDefaults().double(forKey: reference)), time: peerSeek, atHostTime: hostTime)
			}
			if 0 != CMTimeCompare(peer, prev) {
				hostAnchor = hostTime
				peerAnchor = peerTime
				prev = peer
			}
			else {
				let hostInterval = CMTimeSubtract(hostTime, hostAnchor)
				let peerInterval = CMTimeSubtract(peerTime, peerAnchor)
				UserDefaults().set((Double(peerInterval.value)/Double(hostInterval.value))*(Double(hostInterval.timescale)/Double(peerInterval.timescale)), forKey: reference)
				UserDefaults().synchronize()
			}
		
		}
		
		func send() {
			
			print("send")
			
			timer.suspend()
			
			let sockref: UnsafeMutablePointer<sockaddr_in> = UnsafeMutablePointer<sockaddr_in>.allocate(capacity: MemoryLayout<sockaddr_in>.size)
			defer { sockref.deallocate(capacity: MemoryLayout<sockaddr_in>.size) }
			
			sockref.pointee.sin_family = sa_family_t(AF_INET)
			sockref.pointee.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
			sockref.pointee.sin_port = in_port_t(9000)
			sockref.pointee.sin_addr.s_addr = reference.components(separatedBy: ".").enumerated().reduce(UInt32(0)) { $0.0 | ( UInt32($0.1.element) ?? 0 ) << ( UInt32($0.1.offset) << 3 ) }
			
			let pair: [CMTime] = [launch, player.currentTime(), CMClockGetTime(clock)]
			assert(sendto(sock, pair, MemoryLayout<CMTime>.size*3, 0, UnsafePointer<sockaddr>(OpaquePointer(sockref)), socklen_t(MemoryLayout<sockaddr_in>.size))==MemoryLayout<CMTime>.size*3)
				
			timer.resume()
			
		}
		
		source.setEventHandler(handler: recv)
		timer.scheduleRepeating(deadline: DispatchTime.now(), interval: intervals)
		timer.setEventHandler(handler: send)
		
		launch = CMClockGetTime(clock)
		source.resume()
		timer.resume()
	}
	private func loop(notification: Notification) {
		guard let played: AVPlayerItem = notification.object as? AVPlayerItem else { fatalError() }
		played.seek(to: kCMTimeZero)
		player.advanceToNextItem()
		player.seek(to: kCMTimeZero)
		player.insert(played, after: nil)
	}
	private func play(composition: AVComposition) {
		let centre: NotificationCenter = NotificationCenter.default
		(0..<2).forEach { (_) in
			let item: AVPlayerItem = AVPlayerItem(asset: composition)
			centre.addObserver(forName: Notification.Name.AVPlayerItemDidPlayToEndTime, object: item, queue: nil, using: loop)
			player.insert(item, after: nil)
		}
		//client(reference: "192.168.10.137", threshold: 1/60.0)
		server()
	}
	func load(url: URL, error: ((AVKeyValueStatus)->())?) {
		
		func prepare(assets: AVURLAsset) {
			let composition: AVMutableComposition = AVMutableComposition()
			(0..<1024).forEach { (_) in
				do {
					let range: CMTimeRange = CMTimeRange(start: kCMTimeZero, duration: assets.duration)
					try composition.insertTimeRange(range, of: assets, at: composition.duration)
				} catch {
					print("failed inserting")
				}
			}
			play(composition: composition)
		}

		let key: String = "tracks"
		let assets: AVURLAsset = AVURLAsset(url: url)
		
		assets.loadValuesAsynchronously(forKeys: [key]) {
			switch assets.statusOfValue(forKey: key, error: nil) {
			case .cancelled:
				error?(.cancelled)
			case .failed:
				error?(.cancelled)
			case .loaded:
				prepare(assets: assets)
			case .loading:
				break
			case .unknown:
				error?(.cancelled)
			}
		}
		
	}
	func pause() {
		launch = kCMTimeZero
		player.pause()
	}
	func resume() {
		launch = CMClockGetTime(clock)
		player.play()
	}
}
