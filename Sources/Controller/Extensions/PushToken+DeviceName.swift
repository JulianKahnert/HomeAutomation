//
//  PushToken+DeviceName.swift
//  Controller
//

import Foundation
import HAModels
#if os(iOS)
import UIKit
#endif

extension PushToken {
    /// Name under which a device registers its push tokens at the server.
    ///
    /// The server identifies a device by this name. Since iOS 16 `UIDevice.current.name` returns only the
    /// generic model name ("iPhone"), so two iPhones would overwrite each other's tokens. The first
    /// characters of the vendor id make the name unique per install.
    static func deviceName(name: String, vendorId: UUID?) -> String {
        guard let vendorId else { return name }
        return "\(name) (\(vendorId.uuidString.prefix(8)))"
    }

    #if os(iOS)
    @MainActor
    static var currentDeviceName: String {
        deviceName(name: UIDevice.current.name, vendorId: UIDevice.current.identifierForVendor)
    }
    #endif
}
