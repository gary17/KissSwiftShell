//
// main.swift
//
// https://github.com/gary17/KissSwiftShell
// GNU General Public License v2.0
//
// Created by User on 2/15/21.
//

import Foundation
import KissSwiftShell

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
	// FIXME: use Result<>
	// FIXME: convert into XCTest test cases in KissSwiftShell

	let end = Date().timeIntervalSince1970

	print("executed since [\(Date(timeIntervalSince1970: start))] for [\(end - start)] seconds. done.")

	// set $? explicitly, i.e., "./script.swift && echo completed successfully"
	exit(0)
}
catch {
	if let data = (error.localizedDescription + "\n").data(using: .utf8) { FileHandle.standardError.write(data) }
	exit(127)
}
