// Assign an ICC profile to the INNOCN PU15-PRE and read back what is active.
//   csprofile             print the active profile and the display's gamma table
//   csprofile <file.icc>  make <file.icc> the display's profile
import Foundation
import ApplicationServices

let vendor: UInt32 = 0x25E3, model: UInt32 = 0x1501
var ids = [CGDirectDisplayID](repeating: 0, count: 16), n: UInt32 = 0
CGGetOnlineDisplayList(16, &ids, &n)
guard let did = ids.prefix(Int(n)).first(where: { CGDisplayVendorNumber($0) == vendor && CGDisplayModelNumber($0) == model }) else {
    print("PU15-PRE is not online"); exit(1)
}
let uuid = CGDisplayCreateUUIDFromDisplayID(did).takeRetainedValue()
let deviceClass = kColorSyncDisplayDeviceClass.takeUnretainedValue()

if CommandLine.arguments.count > 1 {
    let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
    let info = [kColorSyncDeviceDefaultProfileID.takeUnretainedValue(): url] as CFDictionary
    print(ColorSyncDeviceSetCustomProfiles(deviceClass, uuid, info) ? "assigned" : "ColorSyncDeviceSetCustomProfiles failed")
    Thread.sleep(forTimeInterval: 1.0)
}
if let dev = ColorSyncDeviceCopyDeviceInfo(deviceClass, uuid)?.takeRetainedValue() as? [String: Any] {
    for key in ["CustomProfiles", "FactoryProfiles"] {
        if let p = dev[key] as? [String: Any] { print(key, p.values.compactMap { ($0 as? [String: Any])?["DeviceProfileURL"] ?? $0 }) }
    }
}
var r = [CGGammaValue](repeating: 0, count: 256), g = r, b = r, count: UInt32 = 0
if CGGetDisplayTransferByTable(did, 256, &r, &g, &b, &count) == .success {
    print(String(format: "gamma table (%d): mid R %.4f G %.4f B %.4f   top R %.4f G %.4f B %.4f", count, r[128], g[128], b[128], r[Int(count) - 1], g[Int(count) - 1], b[Int(count) - 1]))
}
