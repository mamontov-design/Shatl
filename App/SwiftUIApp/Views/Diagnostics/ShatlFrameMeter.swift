// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

#if DEBUG
import AppKit
import Combine
import QuartzCore
import SwiftUI

/// Debug builds only: whether the frame meter is on, kept between launches.
final class ShatlFrameDiagnosticsSettings: ObservableObject {
    static let shared = ShatlFrameDiagnosticsSettings()
    private static let enabledKey = "ShatlDebug.frameDiagnosticsEnabled"

    private let defaults: UserDefaults

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }
}

/// The F key on any keyboard layout, pressed alone and not while typing,
/// puts a mark into the hitch log.
enum ShatlFrameMarkerKey {
    /// `kVK_ANSI_F`: the key's place, not its letter, so a Russian layout works too.
    static let keyCode: UInt16 = 3

    static func matches(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        isRepeat: Bool,
        isEditingText: Bool
    ) -> Bool {
        keyCode == Self.keyCode
            && !isRepeat
            && !isEditingText
            && modifierFlags.intersection([.command, .option, .control, .shift, .function]).isEmpty
    }
}

/// Main thread time between two frames: how long it was busy, and how much
/// of that it computed. The rest it spent blocked, which on a frame is mostly
/// waiting for the window server to take the previous frame.
struct ShatlMainThreadTime: Equatable {
    var wall: Double = 0
    var cpu: Double = 0

    var waiting: Double {
        max(0, wall - cpu)
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(wall: lhs.wall + rhs.wall, cpu: lhs.cpu + rhs.cpu)
    }
}

/// Cards in the list, and how many of them download or check their files.
struct ShatlFrameCardCounts: Equatable {
    var total = 0
    var active = 0
}

/// What the owner was looking at: the metrics mode, the window and the cards.
struct ShatlFrameContext: Equatable {
    var metricsMode = "-"
    var windowSize = "-"
    var cards = ShatlFrameCardCounts()

    var logFields: [String] {
        [
            "metrics=\(metricsMode)",
            "window=\(windowSize)",
            "cards=\(cards.total)",
            "active=\(cards.active)",
        ]
    }
}

/// A frame that came at least half a frame late, and what happened meanwhile.
struct ShatlFrameHitch {
    var time: Date
    var frameDuration: Double
    var nominalFrameDuration: Double
    var removedPartsName = "-"
    var isScrolling: Bool
    var mainThread: ShatlMainThreadTime
    var longestSlice: ShatlMainThreadTime
    var counters: [Int]
    var spans: [ShatlFrameTrace.Span]
    var context = ShatlFrameContext()
    /// Animations running while the frame was late, as `kind:animations/cards`.
    var animations = "-"
    var animatingCards = 0
    /// Points per second over the last quarter second.
    var scrollSpeed = 0

    static func isHitch(frameDuration: Double, nominalFrameDuration: Double) -> Bool {
        frameDuration > nominalFrameDuration * 1.5
    }

    var missedFrames: Int {
        max(1, Int((frameDuration / nominalFrameDuration).rounded()) - 1)
    }

    func logLine(timeFormatter: DateFormatter) -> String {
        var fields: [String] = [
            "frame.hitch",
            "at=\(timeFormatter.string(from: time))",
            "frame.ms=\(Self.milliseconds(frameDuration))",
            "missed=\(missedFrames)",
            "removed=\(removedPartsName)",
            "scrolling=\(isScrolling ? "yes" : "no")",
            "scroll.speed=\(scrollSpeed)",
        ] + context.logFields + [
            "main.ms=\(Self.milliseconds(mainThread.wall))",
            "main.cpu.ms=\(Self.milliseconds(mainThread.cpu))",
            "main.waiting.ms=\(Self.milliseconds(mainThread.waiting))",
            "slice.ms=\(Self.milliseconds(longestSlice.wall))",
            "slice.cpu.ms=\(Self.milliseconds(longestSlice.cpu))",
            "slice.waiting.ms=\(Self.milliseconds(longestSlice.waiting))",
        ]
        for counter in ShatlFrameTrace.Counter.allCases where counters.indices.contains(counter.rawValue) {
            fields.append("\(counter.logName)=\(counters[counter.rawValue])")
        }
        fields.append("spans=\(spanSummary)")
        fields.append("anims=\(animations)")
        fields.append("anims.cards=\(animatingCards)")
        return fields.joined(separator: " ")
    }

    private var spanSummary: String {
        guard !spans.isEmpty else { return "-" }

        var totals: [(name: String, duration: Double)] = []
        for span in spans {
            if let index = totals.firstIndex(where: { $0.name == span.name }) {
                totals[index].duration += span.duration
            } else {
                totals.append((span.name, span.duration))
            }
        }
        return totals.map { "\($0.name):\(Self.milliseconds($0.duration))" }.joined(separator: ",")
    }

    static func milliseconds(_ seconds: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), seconds * 1000)
    }
}

/// Watches frames while a meter is on screen. A display link ticks once per
/// screen refresh; a late tick means the frame was held back. Run loop
/// observers measure each pass of the main thread in wall and CPU time, so a
/// hitch log says whether the main thread computed or waited.
///
/// One session serves every meter view: SwiftUI can briefly keep two during
/// a transition, and the view that leaves must not end the other's session.
final class ShatlFrameMonitor: NSObject {
    static let shared = ShatlFrameMonitor()

    private let logger: ShatlFileLogger
    private let clockFormatter = ShatlFrameMonitor.formatter("HH:mm:ss.S")
    private let logTimeFormatter = ShatlFrameMonitor.formatter("HH:mm:ss.SSS")

    private let views = NSHashTable<ShatlFrameMeterView>.weakObjects()
    private weak var displayLinkView: ShatlFrameMeterView?
    private var displayLink: CADisplayLink?
    private var runLoopObservers: [CFRunLoopObserver] = []
    private var eventMonitor: Any?
    private var isRecording = false

    private var lastFrameTimestamp: CFTimeInterval = 0
    private var recentFrameDurations: [(timestamp: CFTimeInterval, duration: CFTimeInterval)] = []
    private var recentHitchTimes: [CFTimeInterval] = []
    private var lastTextUpdate: CFTimeInterval = 0
    private var markShownUntil: CFTimeInterval = 0
    private var lastScrollEventTime: CFTimeInterval = 0
    private var hasLoggedRefreshRate = false

    private var summaryStart: CFTimeInterval = 0
    private var summaryFrames = 0
    private var summaryHitches = 0
    private var summaryWorstFrame: CFTimeInterval = 0
    private var summaryMainThread = ShatlMainThreadTime()
    /// Frames and late frames while the list scrolled: runs with more or less
    /// scrolling compare by these, not by the late frames of the whole summary.
    private var summaryScrollFrames = 0
    private var summaryScrollHitches = 0
    private var summaryScrollDistance: Double = 0
    private var summaryMaxScrollSpeed: Double = 0
    /// Points the wheel moved the list since the last frame, up and down added.
    private var pendingScrollDistance: Double = 0
    private var recentScrollDistances: [(timestamp: CFTimeInterval, distance: Double)] = []

    private var sliceStartWall: Double = 0
    private var sliceStartCPU: Double = 0
    private var frameMainThread = ShatlMainThreadTime()
    private var longestSlice = ShatlMainThreadTime()

    private static let textInterval: CFTimeInterval = 0.25
    private static let summaryInterval: CFTimeInterval = 10
    private static let scrollingWindow: CFTimeInterval = 0.25
    private static let markShowDuration: CFTimeInterval = 1

    init(logger: ShatlFileLogger = .frameDiagnostics) {
        self.logger = logger
        super.init()
    }

    // MARK: - Meter views

    func attach(_ view: ShatlFrameMeterView) {
        views.add(view)
        beginRecording()
        if displayLinkView?.window == nil {
            startDisplayLink(in: view)
        }
    }

    func detach(_ view: ShatlFrameMeterView) {
        views.remove(view)
        guard displayLinkView === view || displayLinkView == nil else { return }

        displayLink?.invalidate()
        displayLink = nil
        displayLinkView = nil
        lastFrameTimestamp = 0
        if let nextView = views.allObjects.first(where: { $0.window != nil }) {
            startDisplayLink(in: nextView)
        } else {
            stop()
        }
    }

    private func startDisplayLink(in view: ShatlFrameMeterView) {
        displayLink?.invalidate()
        let displayLink = view.displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
        displayLinkView = view
        lastFrameTimestamp = 0
    }

    // MARK: - Session

    /// Everything but the display link, which needs a meter on screen.
    func beginRecording() {
        guard !isRecording else { return }

        isRecording = true
        startSlice(at: ShatlFrameTrace.now())
        ShatlFrameTrace.setEnabled(true)
        logger.setEnabled(true)
        installRunLoopObservers()
        installEventMonitor()
        log("frame.meter.started")
    }

    func stop() {
        guard isRecording else { return }

        isRecording = false
        displayLink?.invalidate()
        displayLink = nil
        displayLinkView = nil
        for observer in runLoopObservers {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
        runLoopObservers.removeAll()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        ShatlFrameTrace.setEnabled(false)
        // Written before the log closes, or the line would be dropped.
        logger.write(level: .info, category: "Frames", message: "frame.meter.stopped", flush: true)
        logger.setEnabled(false)

        lastFrameTimestamp = 0
        recentFrameDurations.removeAll()
        recentHitchTimes.removeAll()
        recentScrollDistances.removeAll()
        hasLoggedRefreshRate = false
        summaryStart = 0
        summaryFrames = 0
        summaryHitches = 0
        summaryWorstFrame = 0
        summaryMainThread = ShatlMainThreadTime()
        summaryScrollFrames = 0
        summaryScrollHitches = 0
        summaryScrollDistance = 0
        summaryMaxScrollSpeed = 0
        frameMainThread = ShatlMainThreadTime()
        longestSlice = ShatlMainThreadTime()
    }

    // MARK: - Frames

    @objc private func displayLinkDidFire(_ link: CADisplayLink) {
        recordFrame(
            timestamp: link.timestamp,
            nominalDuration: link.targetTimestamp - link.timestamp
        )
    }

    func recordFrame(timestamp: CFTimeInterval, nominalDuration: CFTimeInterval) {
        let nominal = max(nominalDuration, 1.0 / 240)
        let work = ShatlFrameTrace.drain()
        let mainThread = frameMainThread
        let slice = longestSlice
        frameMainThread = ShatlMainThreadTime()
        longestSlice = ShatlMainThreadTime()

        guard lastFrameTimestamp > 0 else {
            lastFrameTimestamp = timestamp
            if summaryStart == 0 {
                summaryStart = timestamp
            }
            // Scrolling before the first frame is not this session's.
            pendingScrollDistance = 0
            return
        }

        let frameDuration = timestamp - lastFrameTimestamp
        let previousFrameTimestamp = lastFrameTimestamp
        lastFrameTimestamp = timestamp
        if !hasLoggedRefreshRate {
            hasLoggedRefreshRate = true
            log("frame.meter.display hz=\(Int((1 / nominal).rounded()))")
        }

        recentFrameDurations.append((timestamp, frameDuration))
        recentFrameDurations.removeAll { timestamp - $0.timestamp > 1 }
        recentHitchTimes.removeAll { timestamp - $0 > 2 }
        summaryFrames += 1
        summaryWorstFrame = max(summaryWorstFrame, frameDuration)
        summaryMainThread = summaryMainThread + mainThread
        let isLate = ShatlFrameHitch.isHitch(frameDuration: frameDuration, nominalFrameDuration: nominal)
        let frameScrollDistance = pendingScrollDistance
        pendingScrollDistance = 0
        recentScrollDistances.append((timestamp, frameScrollDistance))
        recentScrollDistances.removeAll { timestamp - $0.timestamp > Self.scrollingWindow }
        let scrollSpeed = recentScrollDistances.reduce(0) { $0 + $1.distance } / Self.scrollingWindow
        summaryScrollDistance += frameScrollDistance
        summaryMaxScrollSpeed = max(summaryMaxScrollSpeed, scrollSpeed)
        if isScrolling {
            summaryScrollFrames += 1
            summaryScrollHitches += isLate ? 1 : 0
        }

        if isLate {
            summaryHitches += 1
            recentHitchTimes.append(timestamp)
            let animations = ShatlFrameTrace.runningAnimations(from: previousFrameTimestamp, to: timestamp)
            let hitch = ShatlFrameHitch(
                time: Date(),
                frameDuration: frameDuration,
                nominalFrameDuration: nominal,
                removedPartsName: TorrentCardDebugOptions.shared.logName,
                isScrolling: isScrolling,
                mainThread: mainThread,
                longestSlice: slice,
                counters: work.counters,
                spans: work.spans,
                context: context,
                animations: animations.summary,
                animatingCards: animations.cards,
                scrollSpeed: Int(scrollSpeed.rounded())
            )
            log(hitch.logLine(timeFormatter: logTimeFormatter))
        }

        if timestamp - summaryStart >= Self.summaryInterval {
            logSummary(until: timestamp)
        }

        if timestamp - lastTextUpdate >= Self.textInterval {
            lastTextUpdate = timestamp
            let text = displayText(now: timestamp)
            for view in views.allObjects {
                view.show(text)
            }
        }
    }

    private func logSummary(until timestamp: CFTimeInterval) {
        let seconds = timestamp - summaryStart
        let fields: [String] = [
            "frame.summary",
            "seconds=\(Int(seconds.rounded()))",
            "frames=\(summaryFrames)",
            "hitches=\(summaryHitches)",
            "worst.ms=\(ShatlFrameHitch.milliseconds(summaryWorstFrame))",
            "scroll.frames=\(summaryScrollFrames)",
            "scroll.hitches=\(summaryScrollHitches)",
            "scroll.distance=\(Int(summaryScrollDistance.rounded()))",
            "scroll.speed.max=\(Int(summaryMaxScrollSpeed.rounded()))",
            "main.busy.percent=\(Self.percent(summaryMainThread.wall, of: seconds))",
            "main.cpu.percent=\(Self.percent(summaryMainThread.cpu, of: seconds))",
            "main.waiting.percent=\(Self.percent(summaryMainThread.waiting, of: seconds))",
            "removed=\(TorrentCardDebugOptions.shared.logName)",
        ] + context.logFields + [
            "anims.started=\(ShatlFrameTrace.drainStartedAnimations())",
        ]
        log(fields.joined(separator: " "))
        summaryStart = timestamp
        summaryFrames = 0
        summaryHitches = 0
        summaryWorstFrame = 0
        summaryMainThread = ShatlMainThreadTime()
        summaryScrollFrames = 0
        summaryScrollHitches = 0
        summaryScrollDistance = 0
        summaryMaxScrollSpeed = 0
    }

    private func displayText(now: CFTimeInterval) -> String {
        let localeOverride = views.allObjects.first?.localeOverride ?? .system
        let worstFrame = recentFrameDurations.map(\.duration).max() ?? 0
        var text = L10n.format(
            "debug.frame_meter.summary",
            localeOverride: localeOverride,
            defaultValue: "%1$@ · %2$ld к/с · макс %3$ld мс · %4$@",
            listDisplayName,
            recentFrameDurations.count,
            Int((worstFrame * 1000).rounded()),
            clockFormatter.string(from: Date())
        )
        if now < markShownUntil {
            text += " · " + L10n.string(
                "debug.frame_meter.marked",
                localeOverride: localeOverride,
                defaultValue: "метка"
            )
        }
        return text
    }

    // MARK: - Run loop

    /// A slice of main thread work ends before the thread sleeps, or when the
    /// run loop exits to hand AppKit an event, which AppKit then handles
    /// outside the loop: that handling belongs to the next slice. Sleep is
    /// not work, so a slice starts again when the thread wakes.
    private func installRunLoopObservers() {
        addObserver(.afterWaiting, order: CFIndex.min) { monitor, wall, cpu in
            monitor.startSlice(at: wall, cpu: cpu)
        }
        // After Core Animation's commit at order 2 000 000.
        addObserver([.beforeWaiting, .exit], order: 2_000_001) { monitor, wall, cpu in
            monitor.finishSlice(at: wall, cpu: cpu)
        }
    }

    private func addObserver(
        _ activity: CFRunLoopActivity,
        order: CFIndex,
        _ handler: @escaping (ShatlFrameMonitor, Double, Double) -> Void
    ) {
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            activity.rawValue,
            true,
            order
        ) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self, ShatlFrameTrace.now(), Self.mainThreadCPUTime())
            }
        }
        guard let observer else { return }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        runLoopObservers.append(observer)
    }

    private func startSlice(at wall: Double, cpu: Double = ShatlFrameMonitor.mainThreadCPUTime()) {
        sliceStartWall = wall
        sliceStartCPU = cpu
    }

    private func finishSlice(at wall: Double, cpu: Double) {
        let slice = ShatlMainThreadTime(
            wall: max(0, wall - sliceStartWall),
            cpu: max(0, cpu - sliceStartCPU)
        )
        frameMainThread = frameMainThread + slice
        if slice.wall > longestSlice.wall {
            longestSlice = slice
        }
        startSlice(at: wall, cpu: cpu)
    }

    /// CPU time of the calling thread; the observers run on the main thread.
    private static func mainThreadCPUTime() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1_000_000_000
    }

    // MARK: - Events

    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                return self.handle(event)
            }
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .scrollWheel:
            ShatlFrameTrace.count(.scrollEvents)
            lastScrollEventTime = ShatlFrameTrace.now()
            // Points for a trackpad or a smooth wheel; a notched wheel sends lines.
            let lineHeight: CGFloat = 10
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * lineHeight
            pendingScrollDistance += abs(Double(delta))
            return event
        case .keyDown:
            guard ShatlFrameMarkerKey.matches(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags,
                isRepeat: event.isARepeat,
                isEditingText: event.window?.firstResponder is NSText
            ) else {
                return event
            }
            mark()
            return nil
        default:
            return event
        }
    }

    private func mark() {
        let worstFrame = recentFrameDurations.map(\.duration).max() ?? 0
        log(
            "frame.mark at=\(logTimeFormatter.string(from: Date())) "
                + "removed=\(TorrentCardDebugOptions.shared.logName) "
                + "scrolling=\(isScrolling ? "yes" : "no") worst.last_second.ms=\(ShatlFrameHitch.milliseconds(worstFrame)) "
                + "hitches.last_2s=\(recentHitchTimes.count)"
        )
        markShownUntil = ShatlFrameTrace.now() + Self.markShowDuration
        lastTextUpdate = 0
    }

    // MARK: - Helpers

    private var isScrolling: Bool {
        ShatlFrameTrace.now() - lastScrollEventTime < Self.scrollingWindow
    }

    private var context: ShatlFrameContext {
        let meter = displayLinkView ?? views.allObjects.first
        var context = ShatlFrameContext()
        context.metricsMode = meter?.metricsMode.map { $0 == .detailed ? "detailed" : "simplified" } ?? "-"
        if let size = meter?.window?.frame.size {
            context.windowSize = "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
        }
        context.cards = meter?.cardCounts?() ?? ShatlFrameCardCounts()
        return context
    }

    private var listDisplayName: String {
        let meter = displayLinkView ?? views.allObjects.first
        let counts = meter?.cardCounts?() ?? ShatlFrameCardCounts()
        let removedCount = TorrentCardDebugOptions.shared.removedParts.count
        let localeOverride = meter?.localeOverride ?? .system
        var name = L10n.format(
            "debug.frame_meter.cards",
            localeOverride: localeOverride,
            defaultValue: "%1$ld карт. · %2$ld акт.",
            counts.total,
            counts.active
        )
        if removedCount > 0 {
            name += " · " + L10n.format(
                "debug.frame_meter.removed_parts",
                localeOverride: localeOverride,
                defaultValue: "убрано: %ld",
                removedCount
            )
        }
        return name
    }

    private func log(_ message: String) {
        logger.write(level: .info, category: "Frames", message: message)
    }

    private static func percent(_ part: Double, of whole: Double) -> Int {
        whole > 0 ? Int((part / whole * 100).rounded()) : 0
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}

/// A small dark label in the corner of the list. It is AppKit so that its
/// updates never pass through SwiftUI: the meter must not load the frames it
/// measures.
final class ShatlFrameMeterView: NSView {
    var localeOverride: AppLocaleOverride = .system
    var metricsMode: MetricsPresentationMode?
    /// Read when a line is logged, so the counts are those of that moment.
    var cardCounts: (() -> ShatlFrameCardCounts)?

    private let monitor: ShatlFrameMonitor
    private let bubble = NSView()
    private let label = NSTextField(labelWithString: "")
    private static let padding = NSSize(width: 8, height: 3)

    init(monitor: ShatlFrameMonitor = .shared) {
        self.monitor = monitor
        super.init(frame: .zero)
        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        bubble.layer?.cornerRadius = 7
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byClipping
        bubble.addSubview(label)
        addSubview(bubble)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            monitor.attach(self)
        } else {
            monitor.detach(self)
        }
    }

    override func layout() {
        super.layout()
        let textSize = label.intrinsicContentSize
        let width = min(bounds.width, textSize.width + Self.padding.width * 2)
        let height = min(bounds.height, textSize.height + Self.padding.height * 2)
        bubble.frame = NSRect(x: bounds.width - width, y: 0, width: width, height: height)
        label.frame = NSRect(
            x: Self.padding.width,
            y: (height - textSize.height) / 2,
            width: width - Self.padding.width * 2,
            height: textSize.height
        )
    }

    func show(_ text: String) {
        guard label.stringValue != text else { return }
        label.stringValue = text
        needsLayout = true
    }
}

struct ShatlFrameMeter: NSViewRepresentable {
    let localeOverride: AppLocaleOverride
    let metricsMode: MetricsPresentationMode
    let cardCounts: () -> ShatlFrameCardCounts

    func makeNSView(context: Context) -> ShatlFrameMeterView {
        let view = ShatlFrameMeterView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: ShatlFrameMeterView, context: Context) {
        view.localeOverride = localeOverride
        view.metricsMode = metricsMode
        view.cardCounts = cardCounts
    }
}
#endif
