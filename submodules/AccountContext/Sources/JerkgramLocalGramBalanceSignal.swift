import Foundation
import SwiftSignalKit

extension JerkgramLocalGramBalance {
    // Presentation-only stream. Subscribers retain the original engine state;
    // this scalar never flows into purchase, transfer or revenue authorization.
    public static func displayedBalance(accountPeerId: Int64, native: Signal<Int64, NoError>) -> Signal<Int64, NoError> {
        let local = Signal<Int64?, NoError> { subscriber in
            let publish = {
                subscriber.putNext(Self.visualBalance(accountPeerId: accountPeerId))
            }
            let observers = [Self.changed, Notification.Name("JerkgramSettingsDidImport")].map { name in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { notification in
                    guard (notification.userInfo?["accountPeerId"] as? NSNumber)?.int64Value == accountPeerId else { return }
                    publish()
                }
            }
            publish()
            return ActionDisposable {
                for observer in observers { NotificationCenter.default.removeObserver(observer) }
            }
        }
        return combineLatest(native, local)
        |> map { native, local in local ?? native }
        |> distinctUntilChanged
    }
}
