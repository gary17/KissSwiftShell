//
// ShCmd.swift
//
// https://github.com/gary17/KissSwiftShell
// GNU General Public License v2.0
//
// Created by User on 2/15/21.
//

import Foundation

public class ShCmd: ShRunnable {
	// Process API uses optionals vs. empty collection instances; follow
	private init(resolver: @escaping PathResolver, args: [String]? = nil, env: [String : String]? = nil) {
		self.resolver = resolver
		self.args = args
		self.env = env
	}
	
	public convenience init(path: String, args: [String]? = nil, env: [String : String]? = nil) {
		self.init(resolver: { path }, args: args, env: env)
	}
	
	// potentially multiple points of failure; prefer a throwing over nullable initializer
	public convenience init(_ command: String, _ args: [String]? = nil, env: [String : String]? = nil,
		usePathCache: Bool = true) {

		let resolver: PathResolver = {
			// prefer guaranteed local cache performance over unguaranteed /usr/bin/env behavior
			if let path = /* check-and-read */ ShCmd.pathCache[command] {
				return path
			}
			else {
				let path = try ShCmd.which(command)
				ShCmd.pathCache[command] = path // cache-in

				return path
			}
		}
		
		if usePathCache {
			self.init(resolver: resolver, args: args, env: env)
		}
		else {
			// prefer optimistic /usr/bin/env performance over likely /usr/bin/which slowness
			self.init(path: Config.Tools.env, args: [command] + (args ?? []), env: env)
		}
	}
	
	public static func /* operator */ |(lhs: ShRunnable, rhs: ShCmd) -> ShCmdPair {
		return ShCmdPair(lhs, pipedTo: rhs)
	}

	@discardableResult
	public func run(pipedTo rhs: ShRunnable? = nil) throws -> ShRun.Result {
		do {
			let path = try resolver() // cannot throw out of a lazy property initializer
			process.executableURL = URL(fileURLWithPath: path)
		}

		// WARNING: the setter does not like nil; 'must provide array of arguments' or face NSInvalidArgumentException
		if let args = args { process.arguments = args }
		if let env = env { process.environment = env }

		let pipes = (stdout: Pipe(), stderr: Pipe()) // a FileHandle or a Pipe

		if var rhs = rhs { rhs.stdin = pipes.stdout }
		
		process.standardOutput = pipes.stdout
		process.standardError = pipes.stderr
		
		try process.run()
		process.waitUntilExit()
		
		assert(!process.isRunning) // or .terminationStatus coredumps (as of Swift 5.3, x86_64-unknown-linux-gnu)
		let stdout = rhs == nil ? pipes.stdout.siphon() : /* leave it up for the RHS to intake */ nil
		
		return (stdout: stdout, stderr: pipes.stderr.siphon(), rc: process.terminationStatus)
	}
	
#if false // FIXME: do me
	typealias RunHandler = (ShRun.Result) -> Void
	func runAsync(completionHandler: @escaping RunHandler, pipedTo rhs: ShRunnable? = nil) throws {
		process.terminationHandler = { (process) in
			// ...
		}
	}
#endif

	public var stdin: Pipe? {
		get { precondition(process.standardInput is Pipe); return process.standardInput as? Pipe }
		set { process.standardInput = newValue }
	}
	
	/*
	EXECUTABLE PATH RESOLUTION STRATEGY

	- environment: Intel i7 4/8, SSD, Ubuntu 20.04

	- cache-less, (always) resolved through /usr/bin/which: 1000 "ls" executions in 102.46841311454773 seconds
		- 50% performance loss, seems to degrade linearly from 100 to 1000 executions
	- cache-less, (always) resolved through /usr/bin/env: 1000 "ls" executions in 51.21672582626343 seconds
	- cache-ful, resolved (once) through /usr/bin/which: 1000 "ls" executions in 51.2522189617157 seconds
	*/

	private typealias PathResolver = () throws -> String
	private let resolver: PathResolver
	
	private let args: [String]?
	private let env: [String : String]?

	//
	
	private typealias PathCache = [String : String] // FIXME: LRU (memory)
	private /* shared */ static var pathCache: PathCache = [:] // e.g., "ls" >> /usr/bin/which >> "/bin/ls"
	
	//

	private let process = Process() // will spawn a subprocess
}

extension ShCmd
{
	internal enum /* namespace */ Config {
		enum /* namespace */ Tools {
			static let sh = "/bin/sh"
			static let env = "/usr/bin/env"
		}
	}
}
