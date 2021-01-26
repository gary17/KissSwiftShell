#!/usr/bin/env swift

import Foundation

enum /* namespace */ Sh {
	enum RunError: Error { case commandNotFound(command: String) }
	typealias Outcome = (stdout: String?, stderr: String?, rc: /* Process.terminationStatus */ Int32)

	@discardableResult // FYI: Process API uses optionals vs. empty collection instances, follow
	static func run(path: String, args: [String]? = nil, env: [String : String]? = nil) throws -> Outcome {
		let process = Process() // spawn a subprocess
		process.executableURL = URL(fileURLWithPath: path)
		process.arguments = args

		let pipes = (stdout: Pipe(), stderr: Pipe())

		process.environment = env

		process.standardOutput = pipes.stdout
		process.standardError = pipes.stderr
		
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

	static func which(_ command: String) throws -> String? {
		// the command: (/bin/sh -l -c "which ls") expands "ls" into "/bin/ls"
		let out = try Sh.run(path: "/bin/sh" , args: ["-l", "-c", "which \(command)"])

		guard let stdout = out.stdout else { return nil }
		return stdout.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines)
	}

	@discardableResult
	static func run(_ command: String, _ args: [String]? = nil, usePathCache: Bool = true) throws -> Outcome {

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

			var path: String
			if let hit = /* check-and-read */ pathCache[command] { path = hit }
			else {
				guard let lookup = try Sh.which(command) else { throw RunError.commandNotFound(command: command) }
				pathCache[command] = lookup // cache-in
				path = lookup
			}
			return try Sh.run(path: path, args: args)
		}
		else {			
			// prefer optimistic /usr/bin/env performance over likely /usr/bin/which slowness

			return try Sh.run(path: "/usr/bin/env", args: [command] + (args ?? []))
		}
	}

	typealias PathCache = [String : String] // FIXME: LRU (memory)
	private static var pathCache: [String : String] = [:] // e.g., "ls" >> /usr/bin/which >> "/bin/ls"
}

extension Sh.RunError: LocalizedError {
	var errorDescription: String? {
		switch self {
			case .commandNotFound(let command):
				return NSLocalizedString("command '\(command)' not found", comment: "")
		}
	}
}

do {
	let start = Date().timeIntervalSince1970

		do
		{
			let outcome = try Sh.run("ls", nil, usePathCache: false)
			if outcome.rc == 0, let stdout = outcome.stdout { print(stdout) }
		}

		do
		{
			let outcome = try Sh.run("ls", ["-l"])
			if outcome.rc == 0, let stdout = outcome.stdout { print(stdout) }
		}

		do
		{
			try Sh.run("ls65536")
		}
		catch {
			print(error.localizedDescription)
		}

	let end = Date().timeIntervalSince1970

	print("executed since [\(Date(timeIntervalSince1970: start))] for [\(end - start)] seconds. done.")
}
catch {
	fatalError(error.localizedDescription) // vs. exit(911)
}
