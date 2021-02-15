//
// ShClosure.swift
//
// https://github.com/gary17/KissSwiftShell
// GNU General Public License v2.0
//
// Created by User on 2/15/21.
//

import Foundation

public class ShClosure: ShRunnable {
	// allow a binary, pipe-based (incremental) interface
	public typealias RunClosure = (_ stdin: Pipe?, _ stdout: Pipe, _ stderr: Pipe) throws -> ShRun.Status

	// allow a textual, string-based (all-or-nothing) interface
	public typealias RunClosure2 = (_ stdin: String?) throws -> ShRun.Result

	public init(_ closure: @escaping RunClosure) {
		self.closure = closure
	}

	public convenience init(_ closure: @escaping RunClosure2) {
		let inner: RunClosure = { (stdin, stdout, stderr) in
			let result = try closure(stdin?.siphon())
			if let text = result.stdout { stdout.send(text) }
			if let text = result.stderr { stderr.send(text) }
			return result.rc
		}
		self.init(inner)
	}

	public static func /* operator */ |(lhs: ShRunnable, rhs: ShClosure) -> ShCmdPair {
		return ShCmdPair(lhs, pipedTo: rhs)
	}

	@discardableResult public func run(pipedTo rhs: ShRunnable? = nil) throws -> ShRun.Result {
		let pipes = (stdout: Pipe(), stderr: Pipe()) // a FileHandle or a Pipe

		if var rhs = rhs { rhs.stdin = pipes.stdout }
		
		// analogous to setting Process.standardOutput, Process.standardError
		let rc = try closure(stdin, pipes.stdout, pipes.stderr)
		
		// WARNING: close explicitly or read will hang
		pipes.stdout.fileHandleForWriting.closeFile() // FIXME: verify whether not already closed (?)
		pipes.stderr.fileHandleForWriting.closeFile()

		let stdout = rhs == nil ? pipes.stdout.siphon() : /* leave it up for the RHS to intake */ nil
		return (stdout: stdout, stderr: pipes.stderr.siphon(), rc: rc)
	}
	
	private let closure: RunClosure
	
	//
	
	public var stdin: Pipe? // ShRunnable
}
