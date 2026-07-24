import Foundation

@MainActor
protocol ShatlTerminationPreparing: AnyObject {
    func prepareForTermination() async
}

@MainActor
protocol ShatlUserAttentionHandling: AnyObject {
    func setApplicationUserAttentionActive(_ isActive: Bool)
    func clearUserEventBadge()
}
