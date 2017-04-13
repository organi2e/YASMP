//
//  getopt.swift
//  YASMP
//
//  Created by Kota Nakano on 2017/02/20.
//
//

import Foundation

func getopt (arguments: Array<String>, parse: Dictionary<String,Array<Any>>) -> (Array<String>, Dictionary<String,Array<Any>>) {
	var keys: Dictionary<String, Array<Any>> = parse
	var opts: Dictionary<String, Array<Any>> = keys
	var rest: Array<String> = Array<String>()
	var argIndex = 1
	while argIndex < arguments.count {
		let key = arguments[argIndex]
		if keys.keys.contains(key) {
			if var value = keys[key]
			{
				if 0 < value.count
				{
					var valueIndex = 0
					while valueIndex < value.count {
						argIndex = argIndex + 1
						switch value[valueIndex] {
						case let x as Bool:
                            value[valueIndex] = Bool(arguments[argIndex]) ?? x
						case let x as Int:
							value[valueIndex] = Int(arguments[argIndex]) ?? x
						case let x as UInt:
							value[valueIndex] = UInt(arguments[argIndex]) ?? x
                        case let x as Int8:
                            value[valueIndex] = Int8(arguments[argIndex]) ?? x
                        case let x as Int16:
                            value[valueIndex] = Int16(arguments[argIndex]) ?? x
                        case let x as Int32:
                            value[valueIndex] = Int32(arguments[argIndex]) ?? x
                        case let x as Int64:
                            value[valueIndex] = Int64(arguments[argIndex]) ?? x
                        case let x as UInt8:
                            value[valueIndex] = UInt8(arguments[argIndex]) ?? x
                        case let x as UInt16:
                            value[valueIndex] = UInt16(arguments[argIndex]) ?? x
                        case let x as UInt32:
                            value[valueIndex] = UInt32(arguments[argIndex]) ?? x
                        case let x as UInt64:
							value[valueIndex] = UInt64(arguments[argIndex]) ?? x
						case let x as Float:
							value[valueIndex] = Float(arguments[argIndex]) ?? x
						case let x as Double:
							value[valueIndex] = Double(arguments[argIndex]) ?? x
						default:
							value[valueIndex] = arguments[argIndex]
						}
						valueIndex = valueIndex + 1
					}
					opts.updateValue(value, forKey: key)
				}
				else {
					opts.updateValue([true], forKey: key)
				}
			}
			keys.removeValue(forKey: key)
		}
		else {
			rest.append(key)
		}
		argIndex = argIndex + 1
	}
	return (rest, opts)
}
