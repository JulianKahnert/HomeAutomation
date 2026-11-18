//
//  MotionAtNightConstants.swift
//  HAModels
//

/// Lives in HAModels so the Controller can draw the threshold without linking every automation.
public enum MotionAtNightConstants {
    /// Illuminance below which motion turns the lights on.
    public static let thresholdInLux = 60.0
}
