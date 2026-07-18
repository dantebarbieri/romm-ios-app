import Foundation

protocol PGameLaunchSourcePreference: AnyObject {
    func source(for romID: Int) -> GameLaunchSource?
    func setSource(_ source: GameLaunchSource?, for romID: Int)
}
