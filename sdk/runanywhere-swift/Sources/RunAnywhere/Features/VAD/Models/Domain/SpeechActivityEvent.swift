//
//  SpeechActivityEvent.swift
//  RunAnywhere SDK
//
//  Events representing speech activity state changes
//

import Foundation

/// Events representing speech activity state changes
public enum SpeechActivityEvent: String, Sendable {
    /// Speech has started
    case started

    /// Speech has ended
    case ended
}
