//
// ShCmdPair.swift
//
// https://github.com/gary17/KissSwiftShell
// GNU General Public License v2.0
//
// Created by User on 2/15/21.
//

import Foundation

public class ShCmdPair: ShRunnable {
	var pair: (lhs: ShRunnable, rhs: ShRunnable)

	init(_ lhs: ShRunnable, pipedTo rhs: ShRunnable) {
		pair.lhs = lhs
		pair.rhs = rhs
	}
	
	@discardableResult
	public func run(pipedTo rhs: ShRunnable? = nil) throws -> ShRun.Result {
		let result = try pair.lhs.run(pipedTo: pair.rhs)
		guard result.rc == 0 else { /* interrupt execution chain */ return result }

		return try pair.rhs.run(pipedTo: rhs)
	}
	
	public var stdin: Pipe? {
		get { return pair.lhs.stdin }
		set { pair.lhs.stdin = newValue }
	}
}
