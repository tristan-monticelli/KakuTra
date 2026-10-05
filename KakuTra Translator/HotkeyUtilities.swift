import AppKit
import Carbon
import Foundation

enum SingleKeyMapping {
    static func keyCode(for key: SingleKey) -> CGKeyCode {
        switch key {
        case .leftShift: return 56
        case .rightShift: return 60
        case .leftControl: return 59
        case .rightControl: return 62
        case .leftOption: return 58
        case .rightOption: return 61
        case .leftCommand: return 55
        case .rightCommand: return 54
        case .fn: return 63
        }
    }

    static func modifierFlag(for key: SingleKey) -> NSEvent.ModifierFlags {
        switch key {
        case .leftShift, .rightShift:
            return .shift
        case .leftControl, .rightControl:
            return .control
        case .leftOption, .rightOption:
            return .option
        case .leftCommand, .rightCommand:
            return .command
        case .fn:
            return .function
        }
    }
}

extension NSEvent.ModifierFlags {
    init(carbonFlags: UInt) {
        var flags: NSEvent.ModifierFlags = []
        if carbonFlags & UInt(cmdKey) != 0 { flags.insert(.command) }
        if carbonFlags & UInt(optionKey) != 0 { flags.insert(.option) }
        if carbonFlags & UInt(controlKey) != 0 { flags.insert(.control) }
        if carbonFlags & UInt(shiftKey) != 0 { flags.insert(.shift) }
        self = flags
    }
}
