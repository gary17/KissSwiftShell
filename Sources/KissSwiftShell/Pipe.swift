//
// Pipe.swift
//
// https://github.com/gary17/KissSwiftShell
// GNU General Public License v2.0
//
// Created by User on 2/15/21.
//

import Foundation

extension Pipe {
	public func siphon() -> String? {
		let data = self.fileHandleForReading.readDataToEndOfFile()
		guard data.count > 0 else { return nil }
		return String(decoding: data, as: UTF8.self)
	}
	
	public func send(_ out: String) {
		if out.isEmpty == false, let binOut = out.data(using: .utf8) { self.fileHandleForWriting.write(binOut) }
	}
}
