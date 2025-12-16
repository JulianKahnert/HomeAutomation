//
//  IkeaLightBulbWhite.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 16.12.25.
//

import Shared

/// IKEA white light bulb that uses brightness control for turning off.
/// Some IKEA light bulbs do not turn off properly when only turnOff is called.
public final class IkeaLightBulbWhite: SwitchDevice, @unchecked Sendable {

    /// Turns off the light by setting brightness to 0 instead of using the power switch.
    override public func turnOff(with hm: HomeManagable) async {
        guard brightnessId != nil else {
            // Fallback to standard turn off if brightness control is not available
            await super.turnOff(with: hm)
            return
        }
        await setBrightness(to: 0, with: hm)
    }
}
