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

class YASMP {
	enum Mode {
		case Server(port: UInt16)
		case Client(port: UInt16, address: String, threshold: Double, interval: Double)
	}
	enum Item {
		case Single(url: URL)
		case Shuffle(urls: Array<URL>)
		case Sequence(urls: Array<URL>, playlist: Array<Int>)
	}
	let player: AVQueuePlayer
	let clock: CMClock
	let timer: DispatchSourceTimer
	let source: DispatchSourceRead
	var launch: CMTime
	var layer: AVPlayerLayer {
		return AVPlayerLayer(player: player)
	}
	init() {
		clock = CMClockGetHostTimeClock()
		player = AVQueuePlayer()
		player.actionAtItemEnd = .none
		player.masterClock = clock
		player.automaticallyWaitsToMinimizeStalling = false
		source = DispatchSource.makeReadSource(fileDescriptor: socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP), queue: .global(qos: .userInteractive))
		timer = DispatchSource.makeTimerSource(flags: .strict, queue: .global(qos: .default))
		launch = kCMTimeZero
	}
	deinit {
		player.pause()
		timer.cancel()
		source.cancel()
		close(Int32(source.handle))
	}
	private func server(loop: AVPlayerLooper, port: UInt16) {
		func recv() {
			if let error: Error = loop.error {
				os_log("loop error %@", log: .default, type: .fault, String(describing: error))
				abort()
			}
			guard MemoryLayout<CMTime>.stride * 3 <= Int(source.data) else {
				os_log("Invalid available byte length", log: .default, type: .error)
				return
			}
			Data(count: MemoryLayout<sockaddr_in>.size).withUnsafeBytes { (ref: UnsafePointer<sockaddr>) in
				let sockref: UnsafeMutablePointer<sockaddr> = UnsafeMutablePointer<sockaddr>(mutating: ref)
				let buffer: Array<CMTime> = [
					kCMTimeZero, kCMTimeZero, kCMTimeZero,//peer
					launch, player.currentTime(), CMClockGetTime(clock)//self
				]
				var socklen: socklen_t = socklen_t(MemoryLayout<sockaddr_in>.size)
				guard MemoryLayout<CMTime>.stride * 3 == recvfrom(Int32(source.handle), UnsafeMutableRawPointer(mutating: buffer), MemoryLayout<CMTime>.stride * 3, 0, sockref, &socklen) else {
					os_log("Invalid recv byte length", log: .default, type: .error)
					return
				}
				guard MemoryLayout<CMTime>.stride * 6 == sendto(Int32(source.handle), buffer, MemoryLayout<CMTime>.stride * 6, 0, sockref, socklen) else {
					os_log("Invalid sent byte length", log: .default, type: .error)
					return
				}
			}
		}
		let bound: Bool = Data(count: MemoryLayout<sockaddr_in>.size).withUnsafeBytes { (ref: UnsafePointer<sockaddr_in>) -> Bool in
			let sockref: UnsafeMutablePointer<sockaddr_in> = UnsafeMutablePointer<sockaddr_in>(mutating: ref)
			sockref.pointee.sin_family = sa_family_t(PF_INET)
			sockref.pointee.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
			sockref.pointee.sin_port = port
			sockref.pointee.sin_addr.s_addr = in_addr_t(0x00000000)
			return 0 == sockref.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				bind(Int32(source.handle), $0, socklen_t(MemoryLayout<sockaddr_in>.size))
			}
		}
		guard bound else {
			os_log("port %@ has been not bind", log: .default, type: .fault, port)
			abort()
		}
		
		source.setEventHandler(handler: recv)
		source.resume()
		
		launch = CMClockGetTime(clock)
		player.play()
		
	}
	private func client(duration: CMTime, loop: AVPlayerLooper, port: UInt16, address: String, threshold: Double, interval: Double) {
		
		let full: CMTime = duration
		let half: CMTime = CMTimeMultiplyByRatio(full, 1, 2)
		
		var prev: CMTime = kCMTimeZero
		var hostAnchor: CMTime = kCMTimeZero
		var peerAnchor: CMTime = kCMTimeZero
		
		func recv() {
			guard MemoryLayout<CMTime>.stride * 6 <= Int(source.data) else {
				os_log("Invalid available byte length", log: .default, type: .error)
				return
			}
			let buffer: Array<CMTime> = [
				kCMTimeZero, kCMTimeZero, kCMTimeZero,//self
				kCMTimeZero, kCMTimeZero, kCMTimeZero,//peer
				player.currentTime(), CMClockGetTime(clock)//elapsed
			]
			guard MemoryLayout<CMTime>.stride * 6 == recvfrom(Int32(source.handle), UnsafeMutableRawPointer(mutating: buffer), MemoryLayout<CMTime>.stride * 6, 0, nil, nil) else {
				assertionFailure("e1")
				return
			}
			
			//let host: CMTime = buffer[0]
			let hostSeek: CMTime = CMTimeMultiplyByRatio(CMTimeAdd(buffer[1], buffer[6]), 1, 2)
			let hostTime: CMTime = CMTimeMultiplyByRatio(CMTimeAdd(buffer[2], buffer[7]), 1, 2)
			let peer: CMTime = buffer[3]
			let peerSeek: CMTime = buffer[4]
			let peerTime: CMTime = buffer[5]
			
			if player.status == .readyToPlay && threshold < CMTimeGetSeconds(CMTimeAbsoluteValue(CMTimeSubtract(CMTimeModApprox(CMTimeAdd(CMTimeSubtract(peerSeek, hostSeek), half), full), half))) {
				player.setRate(Float(UserDefaults().double(forKey: address)), time: peerSeek, atHostTime: hostTime)
			}
			if 0 != CMTimeCompare(peer, prev) {
				hostAnchor = hostTime
				peerAnchor = peerTime
				prev = peer
			} else {
				let hostInterval: CMTime = CMTimeSubtract(hostTime, hostAnchor)
				let peerInterval: CMTime = CMTimeSubtract(peerTime, peerAnchor)
				UserDefaults().set((Double(peerInterval.value)/Double(hostInterval.value))*(Double(hostInterval.timescale)/Double(peerInterval.timescale)), forKey: address)
				os_log("adjust rate to %@", log: .default, type: .default, UserDefaults().double(forKey: address))
			}
			os_log("recv done", log: .default, type: .info)
		}
		func send() {
			let sent: Int = Data(count: MemoryLayout<sockaddr_in>.size).withUnsafeBytes { (ref: UnsafePointer<sockaddr_in>) -> Int in
				let sockref: UnsafeMutablePointer<sockaddr_in> = UnsafeMutablePointer<sockaddr_in>(mutating: ref)
				sockref.pointee.sin_family = sa_family_t(PF_INET)
				sockref.pointee.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
				sockref.pointee.sin_port = port
				sockref.pointee.sin_addr.s_addr = address.components(separatedBy: ".").enumerated().reduce(UInt32(0)) {
					$0.0 | ( UInt32($0.1.element) ?? 0 ) << ( UInt32($0.1.offset) << 3 )
				}
				return sockref.withMemoryRebound(to: sockaddr.self, capacity: 1) {
					sendto(Int32(source.handle), Array<CMTime>(arrayLiteral: launch, player.currentTime(), CMClockGetTime(clock)), MemoryLayout<CMTime>.stride * 3, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
				}
			}
			guard sent == MemoryLayout<CMTime>.size * 3 else {
				os_log("receive invalid message", log: .default, type: .error)
				return
			}
			os_log("send done", log: .default, type: .info)
		}
		
		source.setEventHandler(handler: recv)
		timer.scheduleRepeating(deadline: .now(), interval: interval)
		timer.setEventHandler(handler: send)
		
		launch = CMClockGetTime(clock)
		source.resume()
		timer.resume()
		
		player.play()
		
	}
	public func load(urls: Array<URL>, mode: Mode, loop: Int, playlist: Array<Int> = Array<Int>(), error: ((AVKeyValueStatus)->())?) {
		let composition: AVMutableComposition = AVMutableComposition()
		let assets: Array<AVURLAsset> = urls.map { AVURLAsset(url: $0) }
		let group: DispatchGroup = DispatchGroup()
		assets.forEach {
			let assets: AVURLAsset = $0
			let key: String = "tracks"
			group.enter()
			assets.loadValuesAsynchronously(forKeys: [key]) {
				switch assets.statusOfValue(forKey: key, error: nil) {
				case .cancelled:
					error?(.cancelled)
				case .failed:
					error?(.failed)
				case .loaded:
					group.leave()
				case .loading:
					break
				case .unknown:
					error?(.unknown)
				}
			}
		}
		group.wait()
		func seq(loop: Int, max: Int) -> Array<Int> {
			var last: Int = Int(arc4random_uniform(UInt32(max)))
			return Array<Void>(repeating: (), count: loop).map {
				let next: Int = last + Int ( arc4random_uniform ( UInt32( max ) - 1 ) + 1 )
				defer { last = next }
				return next
			}
		}
		( playlist.isEmpty ? seq(loop: loop, max: assets.count ) : playlist ).forEach {
			let asset: AVURLAsset = assets [ $0 % assets.count ]
			do {
				let range: CMTimeRange = CMTimeRange(start: kCMTimeZero, duration: asset.duration)
				try composition.insertTimeRange(range, of: asset, at: composition.duration)
			} catch {
				os_log("failed inserting %@", log: .default, type: .error, asset)
			}
		}
		let loop: AVPlayerLooper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: composition))
		switch mode {
		case let .Server(port):
			os_log("player starts as server mode", log: .default, type: .info)
			server(loop: loop, port: port)
		case let .Client(port, address, threshold, interval):
			os_log("player starts as client mode", log: .default, type: .info)
			client(duration: composition.duration, loop: loop, port: port, address: address, threshold: threshold, interval: interval)
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
