//
//  IPC.swift
//  YASMP
//
//  Created by Kota Nakano on 9/13/16.
//
//

import Foundation
import Darwin

class Socket {
	
	class var NET: Int32 { return 0 }
	class var SCK: Int32 { return 0 }
	class var PRT: Int32 { return 0 }
	
	let mySocket: Int32
	
	init() throws {
		let sock: Int32 = socket(self.dynamicType.NET, self.dynamicType.SCK, self.dynamicType.PRT)
		guard 0 < sock else {
			throw NSError(domain: "", code: 0, userInfo: nil)
		}
		mySocket = sock
	}
	deinit {
		close(mySocket)
	}
	func listens(length: Int) {
		listen(mySocket, Int32(length))
	}
	func sends(data: NSData) {
		send(mySocket, data.bytes, data.length, 0)
	}
	func sends(data: NSData, to: String, port: Int) {
		let buffer: [UInt8] = [UInt8](count: sizeof(sockaddr_in), repeatedValue: 0)
		let ref: UnsafeMutablePointer<sockaddr_in> = UnsafeMutablePointer<sockaddr_in>(buffer)
		
		ref.memory.sin_len = __uint8_t(buffer.count)
		ref.memory.sin_family = sa_family_t(AF_INET)
		ref.memory.sin_addr = in_addr(s_addr: in_addr_t(0))
		ref.memory.sin_len = __uint8_t(buffer.count)
		ref.memory.sin_port = UInt16(port)
		
		sendto(mySocket, data.bytes, data.length, 0, UnsafePointer<sockaddr>(ref), socklen_t(buffer.count))
		
	}
	func bin(port: Int) -> Bool {

		let buffer: [UInt8] = [UInt8](count: sizeof(sockaddr_in), repeatedValue: 0)
		let ref: UnsafeMutablePointer<sockaddr_in> = UnsafeMutablePointer<sockaddr_in>(buffer)
		
		ref.memory.sin_len = __uint8_t(buffer.count)
		ref.memory.sin_family = sa_family_t(AF_INET)
		ref.memory.sin_addr = in_addr(s_addr: in_addr_t(0))
		ref.memory.sin_len = __uint8_t(buffer.count)
		ref.memory.sin_port = UInt16(port)
		
		return 0 == bind(mySocket, UnsafeMutablePointer<sockaddr>(buffer), socklen_t(buffer.count))
		
	}
}
class UDPSocket: Socket {
	override class var NET: Int32 { return AF_INET }
	override class var SCK: Int32 { return SOCK_DGRAM }
	override class var PRT: Int32 { return IPPROTO_UDP }
	//++override class var PRT: Int32 { return SOCK_DGRAM }
	//override class var RRR: Int32 { return IPPROTO_UDP }
}
