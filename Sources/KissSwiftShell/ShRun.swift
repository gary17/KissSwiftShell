//
// ShRun.swift
//
// https://github.com/gary17/KissSwiftShell
// GNU General Public License v2.0
//
// Created by User on 2/15/21.
//

import Foundation

public enum /* namespace */ ShRun {
	public enum Failure: Error { case systemError, commandNotFound(command: String) }

	public typealias Status = Int32 // follow Process.terminationStatus
	public typealias Result = (stdout: String?, stderr: String?, rc: Status)
}

extension ShRun.Failure: LocalizedError {
	public var errorDescription: String? {
		switch self {
			case .systemError:
				return NSLocalizedString("unexpected system error", comment: "")
			case .commandNotFound(let command):
				return NSLocalizedString("command '\(command)' not found", comment: "")
		}
	}
}
