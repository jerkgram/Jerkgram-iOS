import Foundation
import SwiftSignalKit
import Postbox
import TelegramApi

public enum NotificationTokenType {
    case aps(encrypt: Bool)
    case voip
}

func _internal_unregisterNotificationToken(account: Account, token: Data, type: NotificationTokenType, otherAccountUserIds: [PeerId.Id]) -> Signal<Never, NoError> {
    let mappedType: Int32
    switch type {
        case .aps:
            mappedType = 1
        case .voip:
            mappedType = 9
    }
    return account.network.request(Api.functions.account.unregisterDevice(tokenType: mappedType, token: hexString(token), otherUids: otherAccountUserIds.map({ $0._internalGetInt64Value() })))
    |> retryRequest
    |> ignoreValues
}

func _internal_registerNotificationToken(account: Account, token: Data, type: NotificationTokenType, sandbox: Bool, otherAccountUserIds: [PeerId.Id], excludeMutedChats: Bool) -> Signal<Bool, NoError> {
    let ghostBaseRegisterDeviceKind: String
    switch type {
        case .aps:
            ghostBaseRegisterDeviceKind = "Type1"
        case .voip:
            ghostBaseRegisterDeviceKind = "Type9"
    }

    GhostBaseV10EPushProbeCore.record("registerDeviceEntry")
    GhostBaseV10EPushProbeCore.record("registerDevice" + ghostBaseRegisterDeviceKind + "Entry")
    GhostBaseV10EPushProbeCore.set("LastRegisterDeviceKind", ghostBaseRegisterDeviceKind)
    GhostBaseV10EPushProbeCore.set("LastRegisterDeviceSandbox", sandbox ? "true" : "false")
    GhostBaseV10EPushProbeCore.set("LastRegisterDeviceTokenLength", "\(token.count)")
    return masterNotificationsKey(account: account, ignoreDisabled: false)
    |> mapToSignal { masterKey -> Signal<Bool, NoError> in
        let mappedType: Int32
        var keyData = Data()
        switch type {
            case let .aps(encrypt):
                mappedType = 1
                if encrypt {
                    keyData = masterKey.data
                }
            case .voip:
                mappedType = 9
                keyData = masterKey.data
        }
        var flags: Int32 = 0
        if excludeMutedChats {
            flags |= 1 << 0
        }
        GhostBaseV10EPushProbeCore.record("registerDeviceRequest")
        GhostBaseV10EPushProbeCore.record("registerDevice" + ghostBaseRegisterDeviceKind + "Request")
        GhostBaseV10EPushProbeCore.set("LastRegisterDeviceType", "\(mappedType)")
        GhostBaseV10EPushProbeCore.set("LastRegisterDeviceTypeRaw", "\(mappedType)")
        GhostBaseV10EPushProbeCore.setRegisterDeviceTypeSummary(lastType: mappedType, kind: ghostBaseRegisterDeviceKind)
        GhostBaseV10EPushProbeCore.set("LastRegisterDeviceSecretLength", "\(keyData.count)")
        return account.network.request(Api.functions.account.registerDevice(flags: flags, tokenType: mappedType, token: hexString(token), appSandbox: sandbox ? .boolTrue : .boolFalse, secret: Buffer(data: keyData), otherUids: otherAccountUserIds.map({ $0._internalGetInt64Value() })))
        |> map { _ -> Bool in
            GhostBaseV10EPushProbeCore.record("registerDeviceSuccess")
            GhostBaseV10EPushProbeCore.record("registerDevice" + ghostBaseRegisterDeviceKind + "Success")
            GhostBaseV10EPushProbeCore.set("LastRegisterDevice" + ghostBaseRegisterDeviceKind + "Error", "none")
            GhostBaseV10EPushProbeCore.setRegisterDeviceTypeSummary(lastType: mappedType, kind: ghostBaseRegisterDeviceKind)
            return true
        }
        |> `catch` { error -> Signal<Bool, NoError> in
            GhostBaseV10EPushProbeCore.set("LastRegisterDeviceError", error.errorDescription)
            if error.errorDescription == "TOKEN_WAS_INVALIDATED" {
                GhostBaseV10EPushProbeCore.record("registerDeviceInvalidated")
                GhostBaseV10EPushProbeCore.record("registerDevice" + ghostBaseRegisterDeviceKind + "Invalidated")
                GhostBaseV10EPushProbeCore.setRegisterDeviceTypeSummary(lastType: mappedType, kind: ghostBaseRegisterDeviceKind)
                return .single(false)
            } else {
                GhostBaseV10EPushProbeCore.record("registerDeviceError")
                GhostBaseV10EPushProbeCore.record("registerDevice" + ghostBaseRegisterDeviceKind + "Error")
                GhostBaseV10EPushProbeCore.setRegisterDeviceTypeSummary(lastType: mappedType, kind: ghostBaseRegisterDeviceKind)
                return .single(true)
            }
        }
    }
}
