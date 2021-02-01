#!/usr/bin/env swift

import Foundation

class ShCmd {
	enum RunError: Error { case systemError, commandNotFound(command: String) }

	typealias RunResult = (stdout: String?, stderr: String?, rc: /* Process.terminationStatus */ Int32)

	// Process API uses optionals vs. empty collection instances; follow
	init(path: String, args: [String]? = nil, env: [String : String]? = nil) {
		process.executableURL = URL(fileURLWithPath: path) // will spawn a subprocess
		
		process.arguments = args
		process.environment = env

		process.standardOutput = pipes.stdout // a FileHandle or a Pipe
		process.standardError = pipes.stderr
	}
	
	// potentially multiple points of failure; prefer a throwing over nullable initializer
	convenience init(_ command: String, _ args: [String]? = nil, env: [String : String]? = nil,
		usePathCache: Bool = true) throws {
		
		/*

		EXECUTABLE PATH RESOLUTION STRATEGY

		- environment: Intel i7 4/8, SSD, Ubuntu 20.04

		- cache-less, (always) resolved through /usr/bin/which: 1000 "ls" executions in 102.46841311454773 seconds
			- 50% performance loss, seems to degrade linearly from 100 to 1000 executions
		- cache-less, (always) resolved through /usr/bin/env: 1000 "ls" executions in 51.21672582626343 seconds
		- cache-ful, resolved (once) through /usr/bin/which: 1000 "ls" executions in 51.2522189617157 seconds

		*/

		if usePathCache {
			// prefer guaranteed local cache performance over unguaranteed /usr/bin/env behavior
			if let path = /* check-and-read */ ShCmd.pathCache[command] {
				self.init(path: path, args: args, env: env)
			}
			else {
				let path = try ShCmd.which(command)
				ShCmd.pathCache[command] = path // cache-in

				self.init(path: path, args: args, env: env)
			}
		}
		else {
			// prefer optimistic /usr/bin/env performance over likely /usr/bin/which slowness
			self.init(path: Config.Tools.env, args: [command] + (args ?? []), env: env)
		}
	}
	
	@discardableResult
	func run() throws -> RunResult {
		try process.run()

		/* nested */ func siphon(_ pipe: Pipe) -> String? {
			let data = pipe.fileHandleForReading.readDataToEndOfFile()
			guard data.count > 0 else { return nil }
			return String(decoding: data, as: UTF8.self)
		}

		process.waitUntilExit()

		assert(!process.isRunning) // or .terminationStatus coredumps (as of Swift 5.3, x86_64-unknown-linux-gnu)
		return (siphon(pipes.stdout), siphon(pipes.stderr), process.terminationStatus)
	}

	private let pipes = (stdout: Pipe(), stderr: Pipe())
	private let process = Process() // spawn a subprocess

	private typealias PathCache = [String : String] // FIXME: LRU (memory)
	private /* shared */ static var pathCache: PathCache = [:] // e.g., "ls" >> /usr/bin/which >> "/bin/ls"
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
	// special commands
	static func which(_ command: String) throws -> String {
		// the command: (/bin/sh -l -c "which ls") expands "ls" into "/bin/ls"
		let cmd = ShCmd(path: Config.Tools.sh, args: ["-l", "-c", "which \(command)"])
		
		let result = try cmd.run()
		
		// WARNING: missing shell or missing (non- built-in) which might return 127
		guard result.rc == 0, let stdout = result.stdout
			else { throw RunError.commandNotFound(command: command) } // user error
		
		let path = stdout.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines)
		
		// sanity
		guard path.split(whereSeparator: \.isNewline).count == 1
			else { throw RunError.systemError } // call devops

		return path
	}
}

extension ShCmd {
	// wrap complex commands into argument-safe factories
	static func lsLA() throws -> ShCmd {
		return try ShCmd("ls", ["-l", "-a"]) // FIXME: a complex sample for: 'find . -name "*pattern*" -type f -ls', etc.
	}
}

do {
	let start = Date().timeIntervalSince1970

		do {
			let result = try ShCmd("ls", nil, usePathCache: false).run()
			if result.rc == 0, let stdout = result.stdout { print(stdout) }
		}

		do {
			let result = try ShCmd("ls", ["-l"]).run()
			if result.rc == 0, let stdout = result.stdout { print(stdout) }
		}

		do {
			let result = try ShCmd.lsLA().run()
			if result.rc == 0, let stdout = result.stdout { print(stdout) }
		}

		do {
			try ShCmd("ls65535").run()
		}
		catch { // intended, catch and carry on with subsequent tests
			print(error.localizedDescription)
		}

	let end = Date().timeIntervalSince1970

	print("executed since [\(Date(timeIntervalSince1970: start))] for [\(end - start)] seconds. done.")
}
catch {
	fatalError(error.localizedDescription) // vs. exit(911)
}
