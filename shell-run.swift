#!/usr/bin/env swift

import Foundation

extension Pipe {
	func siphon() -> String? {
		let data = self.fileHandleForReading.readDataToEndOfFile()
		guard data.count > 0 else { return nil }
		return String(decoding: data, as: UTF8.self)
	}
}

extension String {
	func trimmed() -> String {
		return self.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines)
	}
}

protocol ShRunnable {
	func piped(to rhs: ShCmd) -> ShCmdPair
	@discardableResult func run(pipedTo rhs: ShCmd?) throws -> ShCmd.RunResult
}

extension ShRunnable {
	func piped(to rhs: ShCmd) -> ShCmdPair {
		return ShCmdPair(self, pipedTo: rhs)
	}
}

class ShCmd: ShRunnable {
	enum RunError: Error { case systemError, commandNotFound(command: String) }
	struct RunResult { let stdout: String?, stderr: String?, rc: /* follows Process.terminationStatus */ Int32 }

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
	
	@discardableResult
	func run(pipedTo rhs: ShCmd? = nil) throws -> RunResult {
		do {
			let path = try resolver() // cannot throw out of a lazy property initializer
			process.executableURL = URL(fileURLWithPath: path)
		}

		// WARNING: the setter does not like nil; 'must provide array of arguments' or face NSInvalidArgumentException
		if let args = args { process.arguments = args }
		if let env = env { process.environment = env }

		let pipes = (stdout: Pipe(), stderr: Pipe()) // a FileHandle or a Pipe

		process.standardOutput = pipes.stdout
		process.standardError = pipes.stderr
	
		if let rhs = rhs { rhs.process.standardInput = pipes.stdout }
		
		// FYI: it does not matter whether you run the first process and wait until it completes before
		// running the second one, or launch two processes in parallel and wait until they both complete

		try process.run()
		process.waitUntilExit()
		
		assert(!process.isRunning) // or .terminationStatus coredumps (as of Swift 5.3, x86_64-unknown-linux-gnu)
		let stdout = rhs == nil ? pipes.stdout.siphon() : /* leave it up for the RHS to intake */ nil
		
		return RunResult(stdout: stdout, stderr: pipes.stderr.siphon(), rc: process.terminationStatus)
	}
	
#if false // FIXME: do me
	typealias RunHandler = (RunResult) -> Void
	func runAsync(completionHandler: @escaping RunHandler, pipedTo rhs: ShCmd? = nil) throws {
		process.terminationHandler = { (process) in
			// ...
		}
	}
#endif

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

extension ShCmd.RunError: LocalizedError {
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
	static func /* operator */ |(lhs: ShRunnable, rhs: ShCmd) -> ShCmdPair {
		return ShCmdPair(lhs, pipedTo: rhs)
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
			else { throw RunError.commandNotFound(command: command) } // user error
		
		let path = stdout.trimmed()
		
		// sanity
		guard path.split(whereSeparator: \.isNewline).count == 1
			else { throw RunError.systemError } // call devops

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
	let pair: (lhs: ShRunnable, rhs: ShCmd)

	init(_ lhs: ShRunnable, pipedTo rhs: ShCmd) {
		pair.lhs = lhs
		pair.rhs = rhs
	}
	
	@discardableResult
	func run(pipedTo rhs: ShCmd? = nil) throws -> ShCmd.RunResult {
		let result = try pair.lhs.run(pipedTo: pair.rhs)
		guard result.rc == 0 else { /* interrupt execution chain */ return result }

		return try pair.rhs.run(pipedTo: rhs)
	}
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

	let end = Date().timeIntervalSince1970

	print("executed since [\(Date(timeIntervalSince1970: start))] for [\(end - start)] seconds. done.")
}
catch {
	fatalError(error.localizedDescription) // vs. exit(911)
}
