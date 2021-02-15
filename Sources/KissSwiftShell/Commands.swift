//
// File.swift
//
// https://github.com/gary17/KissSwiftShell
// GNU General Public License v2.0
//
// Created by User on 2/15/21.
//

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
	public static func lsLA() throws -> ShCmd {
		return ShCmd("ls", ["-l", "-a"]) // FIXME: a complex sample for: 'find . -name "*pattern*" -type f -ls', etc.
	}
}
