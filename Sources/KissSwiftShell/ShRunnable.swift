//
// ShRunnable.swift
//
// https://github.com/gary17/KissSwiftShell
// GNU General Public License v2.0
//
// Created by User on 2/15/21.
//

import Foundation

public protocol ShRunnable { // FIXME: do not allow an API consumer pipe access or mutation
	// creational
	func piped(to rhs: ShRunnable) -> ShCmdPair
	
#if false
	// WARNING: Swift does not like a static operator defined on a protocol (with a default implementation
	// in a protocol extension), due to "Generic parameter 'Self' could not be inferred" (as of Swift 5.3)
	public static func /* operator */ |(lhs: ShRunnable, rhs: ShRunnable) -> ShCmdPair
#endif

	// functional
	@discardableResult func run(pipedTo rhs: ShRunnable?) throws -> ShRun.Result
	
	var stdin: Pipe? { get set }
}

extension ShRunnable {
	public func piped(to rhs: ShRunnable) -> ShCmdPair {
		return ShCmdPair(self, pipedTo: rhs)
	}
}
