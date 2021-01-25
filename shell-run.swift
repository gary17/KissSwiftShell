#!/usr/bin/env swift

import Foundation

enum /* namespace */ Sh {
	typealias Result = (stdout: String?, stderr: String?, rc: Int32)
	
	static func which(_ command: String) throws -> String? {
		// the command: (/bin/sh -l -c "which ls") expands "ls" into "/bin/ls"
		let out = try Sh.run(path: "/bin/sh" , args: ["-l", "-c", "which \(command)"])

		guard let stdout = out.stdout else { return nil }
		return stdout.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines)
	}
	
	static func run(path: String, args: [String] = []) throws -> Result {
		let process = Process() // spawn a subprocess
		process.executableURL = URL(fileURLWithPath: path)
		process.arguments = args

		let pipes = (stdout: Pipe(), stderr: Pipe())

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

	static func run(_ command: String, args: [String] = []) throws -> Result {
		// FYI: alternatively, use Sh.which(_) and run(path:, args:)
		return try Sh.run(path: "/usr/bin/env", args: [command] + args)
	}
}

do {
	let out = try Sh.run("ls", args: ["-l"])
	if out.rc == 0, let stdout = out.stdout { print(stdout) }
}
catch {
	fatalError(error.localizedDescription) // vs. exit(911)
}
