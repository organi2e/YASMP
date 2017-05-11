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
		case Client(port: UInt16, address: String, threshold: Double, interval: Double)
	}
	enum Item {
		case Single(url: URL)
		case Shuffle(urls: Array<URL>)
		case Sequence(urls: Array<URL>, playlist: Array<Int>)
	}
	
	let player: AVQueuePlayer
	let clock: CMClock
	let source: DispatchSourceRead
	let logger: FileHandle
	var looper: AVPlayerLooper?
	var launch: CMTime
	var layer: AVPlayerLayer {
		return AVPlayerLayer(player: player)
	}
	var sock: Int32 {
		return Int32(source.handle)
	}
	init(dump: FileHandle) {
		logger = dump
		clock = CMClockGetHostTimeClock()
		player = AVQueuePlayer()
		player.actionAtItemEnd = .none
		player.masterClock = clock
		player.automaticallyWaitsToMinimizeStalling = false
		source = DispatchSource.makeReadSource(fileDescriptor: socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP), queue: DispatchQueue.global(qos: .userInteractive))
		launch = kCMTimeZero
	}
	private func server(loop: AVPlayerLooper, port: UInt16) {
		
		func recv() {
			
			var socklen: socklen_t = socklen_t(MemoryLayout<sockaddr_in>.size)
			let sockref: UnsafeMutablePointer<sockaddr> = UnsafeMutablePointer<sockaddr>.allocate(capacity: MemoryLayout<sockaddr_in>.size)
			defer { sockref.deallocate(capacity: MemoryLayout<sockaddr_in>.size) }
			
			if let error: Error = loop.error {
				fatalError(String(describing: error))
			}
			guard MemoryLayout<CMTime>.stride * 3 <= Int(source.data) else {
				assertionFailure("Invalid bytes length @ \(loop.loopCount)")
				return
			}
			let buffer: Array<CMTime> = [
				kCMTimeZero, kCMTimeZero, kCMTimeZero,//peer
				launch, player.currentTime(),
				CMClockGetTime(clock)//self
			]
			guard MemoryLayout<CMTime>.stride * 3 == recvfrom(sock, UnsafeMutableRawPointer(mutating: buffer), MemoryLayout<CMTime>.stride * 3, 0, sockref, &socklen) else {
				assertionFailure("e1")
				return
			}
			guard MemoryLayout<CMTime>.stride * 6 == sendto(sock, UnsafeRawPointer(buffer), MemoryLayout<CMTime>.stride * 6, 0, sockref, socklen) else {
				assertionFailure("e2")
				return
			}
		}
		
		let sockref: UnsafeMutablePointer<sockaddr_in> = UnsafeMutablePointer<sockaddr_in>.allocate(capacity: MemoryLayout<sockaddr_in>.size)
		defer { sockref.deallocate(capacity: MemoryLayout<sockaddr_in>.size) }
		
		sockref.pointee.sin_family = sa_family_t(PF_INET)
		sockref.pointee.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
		sockref.pointee.sin_port = port
		sockref.pointee.sin_addr.s_addr = in_addr_t(0x00000000)
		
		guard 0 == bind(sock, UnsafeMutablePointer<sockaddr>(OpaquePointer(sockref)), socklen_t(MemoryLayout<sockaddr_in>.size)) else {
			fatalError("Port \(port) has been not bind")
		}
		
		source.setEventHandler(handler: recv)
		source.resume()
		
		launch = CMClockGetTime(clock)
		player.play()
		
	}
	private func client(duration: CMTime, loop: AVPlayerLooper, port: UInt16, address: String, threshold: Double, interval: Double) {
		
		let timer: DispatchSourceTimer = DispatchSource.makeTimerSource(flags: .strict, queue: DispatchQueue.global(qos: .default))
		
		let full: CMTime = duration
		let half: CMTime = CMTimeMultiplyByRatio(full, 1, 2)
		
		var prev: CMTime = kCMTimeZero
		var hostAnchor: CMTime = kCMTimeZero
		var peerAnchor: CMTime = kCMTimeZero
		
		func recv() {
			
			guard MemoryLayout<CMTime>.stride * 6 <= Int(source.data) else {
				assertionFailure("Invalid bytes length")
				return
			}
			
			let buffer: Array<CMTime> = [
				kCMTimeZero, kCMTimeZero, kCMTimeZero,//self
				kCMTimeZero, kCMTimeZero, kCMTimeZero,//peer
				player.currentTime(), CMClockGetTime(clock)//elapsed
			]
			
			guard MemoryLayout<CMTime>.stride * 6 == recvfrom(sock, UnsafeMutableRawPointer(mutating: buffer), MemoryLayout<CMTime>.stride * 6, 0, nil, nil) else {
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
				UserDefaults().synchronize()
			}
			
			"recv done@\(Date())\r\n".data(using: .utf8)?.write(to: logger)
			
		}
		
		func send() {
			
			timer.suspend()
			
			let sockref: UnsafeMutablePointer<sockaddr_in> = UnsafeMutablePointer<sockaddr_in>.allocate(capacity: MemoryLayout<sockaddr_in>.size)
			defer { sockref.deallocate(capacity: MemoryLayout<sockaddr_in>.size) }
			
			sockref.pointee.sin_family = sa_family_t(PF_INET)
			sockref.pointee.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
			sockref.pointee.sin_port = port
			sockref.pointee.sin_addr.s_addr = address.components(separatedBy: ".").enumerated().reduce(UInt32(0)) {
				$0.0 | ( UInt32($0.1.element) ?? 0 ) << ( UInt32($0.1.offset) << 3 )
			}
			
			let pair: Array<CMTime> = [
				launch, player.currentTime(), CMClockGetTime(clock)
			]
			guard MemoryLayout<CMTime>.stride * 3 == sendto(sock, pair, MemoryLayout<CMTime>.stride * 3, 0, UnsafePointer<sockaddr>(OpaquePointer(sockref)), socklen_t(MemoryLayout<sockaddr_in>.size)) else {
				assertionFailure("e1")
				return
			}
			
			timer.resume()
			
			"send done@\(Date())\r\n".data(using: .utf8)?.write(to: logger)
			
		}
		
		source.setEventHandler(handler: recv)
		timer.scheduleRepeating(deadline: DispatchTime.now(), interval: interval)
		timer.setEventHandler(handler: send)
		
		launch = CMClockGetTime(clock)
		source.resume()
		timer.resume()
		
	}
	public func load(urls: Array<URL>, mode: Mode, loop: Int, playlist: Array<Int> = Array<Int>(), error: ((AVKeyValueStatus)->())?) {
		let composition: AVMutableComposition = AVMutableComposition()
		let assets: Array<AVURLAsset> = urls.map { AVURLAsset(url: $0) }
		let semaphore: DispatchSemaphore = DispatchSemaphore(value: assets.count)
		assets.forEach {
			let assets: AVURLAsset = $0
			let key: String = "tracks"
			assets.loadValuesAsynchronously(forKeys: [key]) {
				switch assets.statusOfValue(forKey: key, error: nil) {
				case .cancelled:
					error?(.cancelled)
				case .failed:
					error?(.failed)
				case .loaded:
					semaphore.signal()
				case .loading:
					break
				case .unknown:
					error?(.unknown)
				}
			}
		}
		semaphore.wait()
		func seq(loop: Int, max: Int) -> Array<Int> {
			var last: Int = 0
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
				"failed inserting\r\n".data(using: .utf8)?.write(to: logger)
			}
		}
		let loop: AVPlayerLooper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: composition))
		switch mode {
		case let .Server(port):
			"player start as server mode\r\n".data(using: .utf8)?.write(to: logger)
			server(loop: loop, port: port)
		case let .Client(port, address, threshold, interval):
			"player start as client mode\r\n".data(using: .utf8)?.write(to: logger)
			client(duration: composition.duration, loop: loop, port: port, address: address, threshold: threshold, interval: interval)
		}
	}
	/*
	public func load(url: URL, mode: Mode, loop: Int, error: ((AVKeyValueStatus)->())?) {
	
	func prepare(assets: AVURLAsset) {
	let composition: AVMutableComposition = AVMutableComposition()
	Array<Void>(repeating: (), count: loop).forEach {
	do {
	let range: CMTimeRange = CMTimeRange(start: kCMTimeZero, duration: assets.duration)
	try composition.insertTimeRange(range, of: assets, at: composition.duration)
	} catch {
	"failed inserting\r\n".data(using: .utf8)?.write(to: logger)
	}
	}
	switch mode {
	case let .Server(port):
	server(loop: AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: composition)), port: port)
	case let .Client(port, address, threshold, interval):
	client(loop: AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: composition)), port: port, address: address, threshold: threshold, interval: interval)
	}
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
	*/
	func pause() {
		launch = kCMTimeZero
		player.pause()
	}
	func resume() {
		launch = CMClockGetTime(clock)
		player.play()
	}
}
private extension Data {
	func write(to: FileHandle) {
		to.write(self)
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
