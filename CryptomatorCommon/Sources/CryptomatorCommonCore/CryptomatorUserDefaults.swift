//
//  CryptomatorSettings.swift
//  CryptomatorCommonCore
//
//  Created by Tobias Hagemann on 22.09.21.
//  Copyright © 2021 Skymatic GmbH. All rights reserved.
//

import CocoaLumberjackSwift
import Foundation

public protocol CryptomatorSettings {
	var debugModeEnabled: Bool { get set }
}

public class CryptomatorUserDefaults {
	public static let shared = CryptomatorUserDefaults()

	private var defaults = UserDefaults(suiteName: CryptomatorConstants.appGroupName)!

	#if DEBUG
	private static let debugModeEnabledDefaultValue = true
	#else
	private static let debugModeEnabledDefaultValue = false
	#endif

	private func read<T>(property: String = #function) -> T? {
		defaults.object(forKey: property) as? T
	}

	private func write<T>(value: T, to property: String = #function) {
		defaults.set(value, forKey: property)
		DDLogDebug("Setting \(property) was written with value \(value)")
	}
}

extension CryptomatorUserDefaults: CryptomatorSettings {
	public var debugModeEnabled: Bool {
		get { read() ?? CryptomatorUserDefaults.debugModeEnabledDefaultValue }
		set { write(value: newValue) }
	}
}
