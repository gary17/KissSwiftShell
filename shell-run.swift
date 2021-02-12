#!/usr/bin/env swift

import Foundation

extension Pipe {
	func siphon() -> String? {
		let data = self.fileHandleForReading.readDataToEndOfFile()
		guard data.count > 0 else { return nil }
		return String(decoding: data, as: UTF8.self)
	}
	
	func send(_ out: String) {
		if out.isEmpty == false, let binOut = out.data(using: .utf8) { self.fileHandleForWriting.write(binOut) }
	}
}

extension String {
	func trimmed() -> String {
		return self.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines)
	}
}

enum /* namespace */ ShRun {
	enum Failure: Error { case systemError, commandNotFound(command: String) }

	typealias Status = Int32 // follow Process.terminationStatus
	typealias Result = (stdout: String?, stderr: String?, rc: Status)
}

protocol ShRunnable { // FIXME: do not allow an API consumer pipe access or mutation
	// creational
	func piped(to rhs: ShRunnable) -> ShCmdPair
	
#if false
	// WARNING: Swift does not like a static operator defined on a protocol (with a default implementation
	// in a protocol extension), due to "Generic parameter 'Self' could not be inferred" (as of Swift 5.3)
	static func /* operator */ |(lhs: ShRunnable, rhs: ShRunnable) -> ShCmdPair
#endif

	// functional
	@discardableResult func run(pipedTo rhs: ShRunnable?) throws -> ShRun.Result
	
	var stdin: Pipe? { get set }
}

extension ShRunnable {
	func piped(to rhs: ShRunnable) -> ShCmdPair {
		return ShCmdPair(self, pipedTo: rhs)
	}
}

class ShCmd: ShRunnable {
	// Process API uses optionals vs. empty collection instances; follow
	private init(resolver: @escaping PathResolver, args: [String]? = nil, env: [String : String]? = nil) {
		self.resolver = resolver
		self.args = args
		self.env = env
	}
	
	convenience init(path: String, args: [String]? = nil, env: [String : String]? = nil) {
		self.init(resolver: { path }, args: args, env: env)
	}
	
	// potentially multiple points of failure; prefer a throwing over nullable initializer
	convenience init(_ command: String, _ args: [String]? = nil, env: [String : String]? = nil,
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
	
	static func /* operator */ |(lhs: ShRunnable, rhs: ShCmd) -> ShCmdPair {
		return ShCmdPair(lhs, pipedTo: rhs)
	}

	@discardableResult
	func run(pipedTo rhs: ShRunnable? = nil) throws -> ShRun.Result {
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

	internal var stdin: Pipe? {
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
	private enum /* namespace */ Config {
		enum /* namespace */ Tools {
			static let sh = "/bin/sh"
			static let env = "/usr/bin/env"
		}
	}
}

extension ShRun.Failure: LocalizedError {
	var errorDescription: String? {
		switch self {
			case .systemError:
				return NSLocalizedString("unexpected system error", comment: "")
			case .commandNotFound(let command):
				return NSLocalizedString("command '\(command)' not found", comment: "")
		}
	}
}

extension ShCmd {
	// special commands
	static func which(_ command: String) throws -> String {
		// the command: (/bin/sh -l -c "which ls") expands "ls" into "/bin/ls"
		let cmd = ShCmd(path: Config.Tools.sh, args: ["-l", "-c", "which \(command)"])
		
		let result = try cmd.run()
		
		// WARNING: missing shell or missing (non- built-in) which might return 127
		guard result.rc == 0, let stdout = result.stdout
			else { throw ShRun.Failure.commandNotFound(command: command) } // user error
		
		let path = stdout.trimmed()
		
		// sanity
		guard path.split(whereSeparator: \.isNewline).count == 1
			else { throw ShRun.Failure.systemError } // call devops

		return path
	}
}

extension ShCmd {
	// wrap complex commands into argument-safe factories
	static func lsLA() throws -> ShCmd {
		return ShCmd("ls", ["-l", "-a"]) // FIXME: a complex sample for: 'find . -name "*pattern*" -type f -ls', etc.
	}
}

class ShCmdPair: ShRunnable {
	var pair: (lhs: ShRunnable, rhs: ShRunnable)

	init(_ lhs: ShRunnable, pipedTo rhs: ShRunnable) {
		pair.lhs = lhs
		pair.rhs = rhs
	}
	
	@discardableResult
	func run(pipedTo rhs: ShRunnable? = nil) throws -> ShRun.Result {
		let result = try pair.lhs.run(pipedTo: pair.rhs)
		guard result.rc == 0 else { /* interrupt execution chain */ return result }

		return try pair.rhs.run(pipedTo: rhs)
	}
	
	internal var stdin: Pipe? {
		get { return pair.lhs.stdin }
		set { pair.lhs.stdin = newValue }
	}
}

class ShClosure: ShRunnable {
	// allow a binary, pipe-based (incremental) interface
	typealias RunClosure = (_ stdin: Pipe?, _ stdout: Pipe, _ stderr: Pipe) throws -> ShRun.Status

	// allow a textual, string-based (all-or-nothing) interface
	typealias RunClosure2 = (_ stdin: String?) throws -> ShRun.Result

	init(_ closure: @escaping RunClosure) {
		self.closure = closure
	}

	convenience init(_ closure: @escaping RunClosure2) {
		let inner: RunClosure = { (stdin, stdout, stderr) in
			let result = try closure(stdin?.siphon())
			if let text = result.stdout { stdout.send(text) }
			if let text = result.stderr { stderr.send(text) }
			return result.rc
		}
		self.init(inner)
	}

	static func /* operator */ |(lhs: ShRunnable, rhs: ShClosure) -> ShCmdPair {
		return ShCmdPair(lhs, pipedTo: rhs)
	}

	@discardableResult func run(pipedTo rhs: ShRunnable? = nil) throws -> ShRun.Result {
		let pipes = (stdout: Pipe(), stderr: Pipe()) // a FileHandle or a Pipe

		if var rhs = rhs { rhs.stdin = pipes.stdout }
		
		// analogous to setting Process.standardOutput, Process.standardError
		let rc = try closure(stdin, pipes.stdout, pipes.stderr)
		
		// WARNING: close explicitly or read will hang
		pipes.stdout.fileHandleForWriting.closeFile()
		pipes.stderr.fileHandleForWriting.closeFile()

		let stdout = rhs == nil ? pipes.stdout.siphon() : /* leave it up for the RHS to intake */ nil
		return (stdout: stdout, stderr: pipes.stderr.siphon(), rc: rc)
	}
	
	private let closure: RunClosure
	
	//
	
	internal var stdin: Pipe? // ShRunnable
}

//

do {
	let start = Date().timeIntervalSince1970

		typealias sh = ShCmd

		do {
			let result = try sh("ls").run()
			if result.rc == 0, let stdout = result.stdout { print(stdout.trimmed()) }
		}
		
		do {
			let result = try sh("ls", nil, usePathCache: false).run()
			if result.rc == 0, let stdout = result.stdout { print(stdout.trimmed()) }
		}

		do {
			let result = try sh("ls", ["-l"]).run()
			if result.rc == 0, let stdout = result.stdout { print(stdout.trimmed()) }
		}

		do {
			let result = try sh.lsLA().run()
			if result.rc == 0, let stdout = result.stdout { print(stdout.trimmed()) }
		}

		do {
			try sh("ls65535").run()
		}
		catch { // intended, catch and carry on with subsequent tests
			print(error.localizedDescription)
		}

		do {
			let result = try
				sh("echo", ["1:2:3"])
					.piped(to: sh("rev"))
					.piped(to: sh("cut", ["-d", ":", "-f", "1"]))
						.run()

			if result.rc == 0, let stdout = result.stdout { print(stdout.trimmed()) }
		}
		
		do {
			let result = try (
				sh("echo", ["a:b:c"]) | sh("rev") | sh("cut", ["-d", ":", "-f", "1"])
			)
			.run()

			if result.rc == 0, let stdout = result.stdout { print(stdout.trimmed()) }
		}
		
		typealias cl = ShClosure

		do {
			let result = try (
				cl { (_, stdout, _) in
					let out = [ "i", "ii", "iii" ].reduce("", { $0.isEmpty ? $1 : $0 + ":" + $1 })
					stdout.send(out)
					return 0
				} |
				sh("rev")
			)
			.run()
			
			if result.rc == 0, let stdout = result.stdout { print(stdout.trimmed()) }
		}

		do {
			let result = try (
				cl { (_) in
					let out = [ "v", "vi", "vii" ].reduce("", { $0.isEmpty ? $1 : $0 + ":" + $1 })
					return (stdout: out, stderr: nil, rc: 0)
				} |
				sh("rev")
			)
			.run()
			
			if result.rc == 0, let stdout = result.stdout { print(stdout.trimmed()) }
		}

		do {
			let result = try (
				sh("echo", ["A:B:C"]) |
				sh("rev") |
				cl { (stdin, stdout, _) in
					let `in` = stdin?.siphon()?.trimmed()
					let out = `in`?.split(separator: ":").last.map { String($0) }
					if let out = out { stdout.send(out) }
					return 0
				}
			)
			.run()
			
			if result.rc == 0, let stdout = result.stdout { print(stdout.trimmed()) }
		}

		do {
			let result = try (
				sh("echo", ["D:E:F"]) |
				sh("rev") |
				cl { (stdin) in
					let out = stdin?.trimmed().split(separator: ":").last.map { String($0) }
					return (stdout: out, stderr: nil, rc: 0)
				}
			)
			.run()
			
			if result.rc == 0, let stdout = result.stdout { print(stdout.trimmed()) }
		}

	// FIXME: sh("?") | swiftDump("file.txt") or sh("?") >> "file.txt"
	// FIXME: launch two processes in parallel and wait until they both complete

	let end = Date().timeIntervalSince1970

	print("executed since [\(Date(timeIntervalSince1970: start))] for [\(end - start)] seconds. done.")

	// set $? explicitly, i.e., "./script.swift && echo completed successfully"
	exit(0)
}
catch {
	if let data = (error.localizedDescription + "\n").data(using: .utf8) { FileHandle.standardError.write(data) }
	exit(127)
}
