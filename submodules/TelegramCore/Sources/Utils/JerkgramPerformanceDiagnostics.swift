import Foundation
import Darwin

/// Temporary, opt-in diagnostic capture. No disk/network writes or frame logging.
public final class JerkgramPerformanceDiagnostics {
    public static let shared = JerkgramPerformanceDiagnostics()
    public static let snapshotChanged = Notification.Name("JerkgramPerformanceSnapshotChanged")
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "Jerkgram.performance.capture", qos: .utility)
    private let capacity = 512
    private let maxCaptureSeconds = 600.0
    private var lines: [String] = []
    private var dropped = 0
    private var timings: [String: (count: Int, maxMs: Double, slow: Int)] = [:]
    private var lastSlowAt: [String: Double] = [:]
    private var slowEvents = 0
    private var suppressedSlowEvents = 0
    private let slowEventLimit = 96
    private var timingKeysRejected = 0
    private var visibleRoute = "unclassified"
    private weak var visibleRouteOwner: AnyObject?
    private var routeReleasesIgnored = 0
    private var operationsObserved: UInt64 = 0
    private var lastDetailedMainSpan: (start: Double, end: Double)?
    private var nestedSlowEventsSuppressed = 0
    // Fixed aggregates do not compete for the legacy 32-key timing dictionary.
    // All retained timeline rows together, including telemetry/details, stay512.
    private let telemetryBlockSeconds = 5.0
    private let detailWindowSeconds = 20.0
    private var captureBoundaries: [String] = []
    private var stoppedDuration = 0.0
    private struct OperationSummary {
        var count = 0
        var mainCount = 0
        var workerCount = 0
        var mainMax = 0.0
        var workerMax = 0.0
        var slow = 0
        var worstAt = 0
        var worstRoute = "unclassified"
        var maxMs = 0.0
    }
    private var operationSummaries: [Operation: OperationSummary] = [:]
    private var fixedOverflow: [String: OperationSummary] = [:]
    private var unsupportedTimingSamplesDropped = 0
    private struct TelemetryBlock {
        var samples = 0
        var cpuMax: Double?
        var peakRSS: Int64 = -1
        var thermalMax = 0
        var waitSamples = 0
        var waitMax = 0.0
        var waitAt = 0
        var waitFinishedAt = 0
        var waitRoute = "unclassified"
        var routes: Set<String> = [] // Only the eight already-sanitized routes.
    }
    private var telemetryBlocks: [Int: TelemetryBlock] = [:] // At most120.
    private struct DetailSample {
        let id: Int
        let duration: Double
        let main: Bool
        let line: String
    }
    private var detailSequence = 0
    private var operationWorst: [Operation: DetailSample] = [:] // At most29.
    private var windowWorst: [Int: DetailSample] = [:] // 30 windows x2 groups.
    private var retainedSamples: [Int: DetailSample] = [:] // De-duplicated <=89.
    private var sampleReferences: [Int: Int] = [:] // At most two references/id.
    private var legacySlowLines: [String] = []
    private var legacyDetailsEvicted = 0
    public enum Operation: String, CaseIterable {
        case inputText, inputLayout, inputDecorate, keyboardLayout
        case historyUpdate, historyVisible, historyLayout, historyScroll
        case chatOpen, mediaState, mediaFill
        case historyPrepare, historyComplete, historyApply, historyMap
        case historyCoreTransaction, historyRowLayout, historyRowBuild
        case inputSend, inputState, sendEnqueue, sendDispatch
        case historyBackendCore, historyBackendLegacy
        case historyNodeCreate, historyNodeSetup, historyNodeCompute, historyNodeApply, sendCurrent
        fileprivate var isInputOrSend: Bool {
            switch self {
            case .inputText, .inputLayout, .inputDecorate, .keyboardLayout, .inputSend, .inputState, .sendEnqueue, .sendDispatch, .sendCurrent: return true
            default: return false
            }
        }
        fileprivate var isHistoryContainer: Bool {
            switch self {
            case .historyRowBuild, .historyRowLayout, .historyCoreTransaction, .historyApply, .historyBackendCore, .historyUpdate, .historyPrepare:
                return true
            default:
                return false
            }
        }
        fileprivate var bit: UInt64 {
            switch self {
            case .inputText: return 1 << 0
            case .inputLayout: return 1 << 1
            case .inputDecorate: return 1 << 2
            case .keyboardLayout: return 1 << 3
            case .historyUpdate: return 1 << 4
            case .historyVisible: return 1 << 5
            case .historyLayout: return 1 << 6
            case .historyScroll: return 1 << 7
            case .chatOpen: return 1 << 8
            case .mediaState: return 1 << 9
            case .mediaFill: return 1 << 10
            case .historyPrepare: return 1 << 11
            case .historyComplete: return 1 << 12
            case .historyApply: return 1 << 13
            case .historyMap: return 1 << 14
            case .historyCoreTransaction: return 1 << 15
            case .historyRowLayout: return 1 << 16
            case .historyRowBuild: return 1 << 17
            case .inputSend: return 1 << 18
            case .inputState: return 1 << 19
            case .sendEnqueue: return 1 << 20
            case .sendDispatch: return 1 << 21
            case .historyBackendCore: return 1 << 22
            case .historyBackendLegacy: return 1 << 23
            case .historyNodeCreate: return 1 << 24
            case .historyNodeSetup: return 1 << 25
            case .historyNodeCompute: return 1 << 26
            case .historyNodeApply: return 1 << 27
            case .sendCurrent: return 1 << 28
            }
        }
    }
    public struct OperationToken {
        fileprivate let operation: Operation
        fileprivate let startedAt: Double
        fileprivate let generation: Int
    }
    public func reserveClientWork() {
        self.lock.lock(); defer { self.lock.unlock() }
        guard self.running, self.timings["client.work"] == nil, self.timings.count < 32 else { return }
        self.timings["client.work"] = (count: 0, maxMs: 0, slow: 0)
    }
    public func beginOperation(_ operation: Operation) -> OperationToken? {
        self.lock.lock(); defer { self.lock.unlock() }
        guard self.running else { return nil }
        self.operationsObserved |= operation.bit
        return OperationToken(operation: operation, startedAt: ProcessInfo.processInfo.systemUptime, generation: self.generation)
    }
    public func endOperation(_ token: OperationToken?) {
        guard let token else { return }
        self.measure("client.work", milliseconds: (ProcessInfo.processInfo.systemUptime - token.startedAt) * 1000, startedAt: token.startedAt, owner: 0, detail: token.operation, sessionGeneration: token.generation)
    }
    public func measureOperation<T>(_ operation: Operation, _ work: () -> T) -> T {
        let token = self.beginOperation(operation)
        defer { self.endOperation(token) }
        return work()
    }
    private struct RefreshStats {
        var samples = 0
        var maxGapMs = 0.0
        var missedOpportunities = 0
        var over16 = 0
        var over33 = 0
        var over50 = 0
        var minExpectedMs = Double.greatestFiniteMagnitude
        var maxExpectedMs = 0.0
    }
    private var frameIntervals: [String: RefreshStats] = [:] // Eight fixed route labels.
    private var lastRefreshTimestamp: Double?
    private var lastRefreshTarget: Double?
    private var running = false
    private var started = 0.0
    private var generation = 0
    private var pendingPulse = false
    private var timer: DispatchSourceTimer?
    private var inactiveObserver: NSObjectProtocol?

    public var isRecording: Bool {
        self.lock.lock(); defer { self.lock.unlock() }
        return self.running
    }

    public var status: String {
        self.lock.lock(); defer { self.lock.unlock() }
        let duration = self.running ? ProcessInfo.processInfo.systemUptime - self.started : self.stoppedDuration
        let stored = self.lines.count + self.telemetryBlocks.count + self.retainedDetailCountLocked + self.captureBoundaries.count
        return "\(self.running ? "RECORDING" : "STOPPED") · \(Int(duration))s / 600s · \(stored)/\(self.capacity) stored blocks/events · auxiliaryDropped=\(self.dropped)"
    }

    public func start() {
        precondition(Thread.isMainThread)
        if self.isRecording { return }
        if let observer = self.inactiveObserver { NotificationCenter.default.removeObserver(observer) }
        self.inactiveObserver = nil
        self.lock.lock()
        self.lines.removeAll(keepingCapacity: true)
        self.timings.removeAll(keepingCapacity: true)
        self.lastSlowAt.removeAll(keepingCapacity: true)
        self.timingKeysRejected = 0
        self.routeReleasesIgnored = 0
        self.operationsObserved = 0
        self.lastDetailedMainSpan = nil
        self.nestedSlowEventsSuppressed = 0
        self.operationSummaries.removeAll(keepingCapacity: true)
        self.fixedOverflow.removeAll(keepingCapacity: true)
        self.unsupportedTimingSamplesDropped = 0
        self.telemetryBlocks.removeAll(keepingCapacity: true)
        self.operationWorst.removeAll(keepingCapacity: true)
        self.windowWorst.removeAll(keepingCapacity: true)
        self.retainedSamples.removeAll(keepingCapacity: true)
        self.sampleReferences.removeAll(keepingCapacity: true)
        self.legacySlowLines.removeAll(keepingCapacity: true)
        self.legacyDetailsEvicted = 0
        self.detailSequence = 0
        self.stoppedDuration = 0
        self.captureBoundaries = ["capture start; CPU percent:100=one logical core; RSS=peak bytes; wait=main queue latency, not GPU utilization"]
        self.frameIntervals.removeAll(keepingCapacity: true)
        self.lastRefreshTimestamp = nil
        self.lastRefreshTarget = nil
        self.slowEvents = 0
        self.suppressedSlowEvents = 0
        self.dropped = 0
        self.started = ProcessInfo.processInfo.systemUptime
        self.generation += 1
        let epoch = self.generation
        self.running = true
        self.pendingPulse = false
        self.lock.unlock()
        self.inactiveObserver = NotificationCenter.default.addObserver(forName: Notification.Name("UIApplicationDidEnterBackgroundNotification"), object: nil, queue: .main) { [weak self] _ in
            self?.stop(reason: "application background")
        }
        let timer = DispatchSource.makeTimerSource(queue: self.queue)
        timer.schedule(deadline: .now(), repeating: 1.0, leeway: .milliseconds(100))
        var previousCPU: Double?
        var previousTime: Double?
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            var usage = rusage()
            let result = getrusage(RUSAGE_SELF, &usage)
            let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000.0
            let percent: Double?
            if result == 0, let previousCPU, let previousTime, now > previousTime {
                percent = max(0.0, (cpu - previousCPU) / (now - previousTime) * 100.0)
            } else { percent = nil }
            if result == 0 { previousCPU = cpu; previousTime = now }
            // External OS state access stays outside the lock shared by UI spans.
            let thermal = ProcessInfo.processInfo.thermalState.rawValue
            self.lock.lock()
            guard self.running && self.generation == epoch else { self.lock.unlock(); return }
            let expired = now - self.started >= self.maxCaptureSeconds
            if expired {
                self.stoppedDuration = min(self.maxCaptureSeconds, now - self.started)
                self.captureBoundaries.append("capture stop: 10 minute limit (utility queue)")
                self.trimAuxiliaryLinesLocked()
                self.running = false
                self.generation += 1
                self.pendingPulse = false
                let expiredTimer = self.timer
                self.timer = nil
                self.lock.unlock()
                expiredTimer?.cancel()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.lock.lock()
                    let sameSession = self.generation == epoch + 1 && !self.running
                    self.lock.unlock()
                    guard sameSession else { return }
                    if let observer = self.inactiveObserver { NotificationCenter.default.removeObserver(observer) }
                    self.inactiveObserver = nil
                    NotificationCenter.default.post(name: Self.snapshotChanged, object: nil)
                }
                return
            }
            self.recordUtilitySampleLocked(now: now, cpuPercent: percent, peakRSS: result == 0 ? Int64(usage.ru_maxrss) : -1, thermal: thermal)
            let submit = !self.pendingPulse
            let submittedRoute = self.visibleRoute
            if submit { self.pendingPulse = true }
            self.lock.unlock()
            if submit {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let finished = ProcessInfo.processInfo.systemUptime
                    self.lock.lock()
                    guard self.running && self.generation == epoch else { self.lock.unlock(); return }
                    self.pendingPulse = false
                    self.recordMainWaitLocked(submittedAt: now, finishedAt: finished, route: submittedRoute)
                    self.lock.unlock()
                }
            }
        }
        self.lock.lock()
        self.timer = timer
        self.lock.unlock()
        timer.resume()
        NotificationCenter.default.post(name: Self.snapshotChanged, object: nil)
    }

    public func stop(reason: String = "user") {
        precondition(Thread.isMainThread)
        self.lock.lock()
        if self.running {
            self.stoppedDuration = min(self.maxCaptureSeconds, ProcessInfo.processInfo.systemUptime - self.started)
            self.captureBoundaries.append("capture stop: \(reason)")
            self.trimAuxiliaryLinesLocked()
        }
        self.running = false
        self.generation += 1
        self.pendingPulse = false
        let timer = self.timer
        self.timer = nil
        self.lock.unlock()
        timer?.cancel()
        if let observer = self.inactiveObserver { NotificationCenter.default.removeObserver(observer) }
        self.inactiveObserver = nil
        NotificationCenter.default.post(name: Self.snapshotChanged, object: nil)
    }

    public func record(_ text: String) {
        self.lock.lock(); defer { self.lock.unlock() }
        guard self.running else { return }
        self.appendLocked("t=\(Int(ProcessInfo.processInfo.systemUptime - self.started))s " + String(text.prefix(2048)))
    }

    public func measure(_ stage: String, milliseconds: Double, startedAt: Double? = nil, owner: Int? = nil, detail: Operation? = nil, sessionGeneration: Int? = nil) {
        self.lock.lock(); defer { self.lock.unlock() }
        guard self.running else { return }
        if let sessionGeneration, sessionGeneration != self.generation { return }
        guard milliseconds.isFinite, milliseconds >= 0 else { return }
        if let detail { self.recordOperationLocked(detail, milliseconds: milliseconds, startedAt: startedAt) }
        guard self.timings[stage] != nil || self.timings.count < 32 else {
            self.timingKeysRejected += 1
            // Known production stages remain fully aggregated even when the
            // legacy dynamic table is full. Unknown/unbounded labels stay rejected.
            guard self.recordFixedOverflowLocked(stage, milliseconds: milliseconds, startedAt: startedAt) else {
                self.unsupportedTimingSamplesDropped += 1
                return
            }
            self.retainSlowLocked(stage, milliseconds: milliseconds, startedAt: startedAt, owner: owner, detail: detail, sessionGeneration: sessionGeneration)
            return
        }
        let old = self.timings[stage] ?? (count: 0, maxMs: 0.0, slow: 0)
        self.timings[stage] = (old.count + 1, max(old.maxMs, milliseconds), old.slow + (milliseconds >= 16.7 ? 1 : 0))
        self.retainSlowLocked(stage, milliseconds: milliseconds, startedAt: startedAt, owner: owner, detail: detail, sessionGeneration: sessionGeneration)
    }

    private func retainSlowLocked(_ stage: String, milliseconds: Double, startedAt: Double?, owner: Int?, detail: Operation?, sessionGeneration: Int?) {
        // Only completed measured spans; no stack suspension, frame callbacks,
        // extra timer, disk I/O or peer identifiers. All bounds share this lock.
        guard milliseconds >= 16.7, let startedAt, startedAt >= self.started, let owner else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // JG156 nested detail: aggregates above always count every span. Only
        // a real main-thread history wrapper dominated by an already-emitted
        // child loses its duplicate event; unrelated/worker/manual spans remain.
        if sessionGeneration != nil, Thread.isMainThread, let detail, detail.isHistoryContainer,
           let child = self.lastDetailedMainSpan, child.start >= startedAt,
           child.end <= now, now - child.end <= 0.002 {
            let childDuration = (child.end - child.start) * 1000.0
            if childDuration >= milliseconds * 0.90 {
                self.nestedSlowEventsSuppressed += 1
                return
            }
        }
        let slowKey = detail?.rawValue ?? stage
        if let detail {
            let retained = self.retainDetailLocked(detail, milliseconds: milliseconds, startedAt: startedAt, stage: stage, owner: owner)
            if retained && Thread.isMainThread { self.lastDetailedMainSpan = (start: startedAt, end: startedAt + milliseconds / 1000.0) }
            return
        }
        guard self.slowEvents < self.slowEventLimit,
              self.lastSlowAt[slowKey].map({ now - $0 >= 1.0 }) ?? true else {
            self.suppressedSlowEvents += 1
            return
        }
        self.lastSlowAt[slowKey] = now
        self.slowEvents += 1
        if Thread.isMainThread { self.lastDetailedMainSpan = (start: startedAt, end: startedAt + milliseconds / 1000.0) }
        let line = self.slowLineLocked(stage: stage, owner: owner, startedAt: startedAt, milliseconds: milliseconds, operation: "none")
        self.legacySlowLines.append(line)
        self.trimAuxiliaryLinesLocked()
    }

    // Route labels are fixed categories, never controller/peer/message identifiers.
    public func setVisibleRoute(_ route: String, owner: AnyObject? = nil) {
        precondition(Thread.isMainThread)
        let safe = ["settings", "profile", "chatList", "chat", "about", "settingsSubpage", "transition", "unclassified"].contains(route) ? route : "unclassified"
        self.lock.lock(); defer { self.lock.unlock() }
        self.visibleRouteOwner = owner
        guard self.visibleRoute != safe else { return }
        self.visibleRoute = safe
        self.lastRefreshTimestamp = nil
        self.lastRefreshTarget = nil
        if self.running {
            self.appendLocked("route=\(safe) atMs=\(Int((ProcessInfo.processInfo.systemUptime - self.started) * 1000))")
        }
    }

    public func clearVisibleRoute(owner: AnyObject) {
        precondition(Thread.isMainThread)
        self.lock.lock(); defer { self.lock.unlock() }
        guard self.visibleRouteOwner === owner else {
            if self.running { self.routeReleasesIgnored += 1 }
            return
        }
        self.visibleRouteOwner = nil
        self.visibleRoute = "transition"
        self.lastRefreshTimestamp = nil
        self.lastRefreshTarget = nil
        if self.running {
            self.appendLocked("route=transition atMs=\(Int((ProcessInfo.processInfo.systemUptime - self.started) * 1000))")
        }
    }

    // Display-link refresh opportunities, NOT rendered FPS or GPU measurements.
    // One fixed aggregate per route; no event/string allocation for each callback.
    public func sampleRefreshOpportunity(timestamp: Double, targetTimestamp: Double) {
        precondition(Thread.isMainThread)
        guard timestamp.isFinite, targetTimestamp.isFinite, targetTimestamp > timestamp else { return }
        self.lock.lock(); defer { self.lock.unlock() }
        guard self.running else { return }
        let expected = targetTimestamp - timestamp
        guard expected >= 0.001, expected <= 1.0 else { return }
        var stats = self.frameIntervals[self.visibleRoute] ?? RefreshStats()
        stats.samples += 1
        stats.minExpectedMs = min(stats.minExpectedMs, expected * 1000)
        stats.maxExpectedMs = max(stats.maxExpectedMs, expected * 1000)
        if let previous = self.lastRefreshTimestamp, let previousTarget = self.lastRefreshTarget, timestamp > previous {
            let gap = (timestamp - previous) * 1000
            stats.maxGapMs = max(stats.maxGapMs, gap)
            stats.over16 += gap >= 16.7 ? 1 : 0
            stats.over33 += gap >= 33.4 ? 1 : 0
            stats.over50 += gap >= 50.0 ? 1 : 0
            // Compare against the previously advertised deadline; dynamic display
            // rates/OS scheduling can influence this estimate independently of rendering.
            let late = timestamp - previousTarget
            if late > expected * 0.25 {
                stats.missedOpportunities += max(0, Int((late / expected).rounded()))
            }
        }
        self.lastRefreshTimestamp = timestamp
        self.lastRefreshTarget = targetTimestamp
        self.frameIntervals[self.visibleRoute] = stats
    }

    private func updatedSummary(_ old: OperationSummary, milliseconds: Double, startedAt: Double?) -> OperationSummary {
        var value = old
        value.count += 1
        if Thread.isMainThread {
            value.mainCount += 1; value.mainMax = max(value.mainMax, milliseconds)
        } else {
            value.workerCount += 1; value.workerMax = max(value.workerMax, milliseconds)
        }
        value.slow += milliseconds >= 16.7 ? 1 : 0
        if milliseconds >= value.maxMs {
            value.maxMs = milliseconds
            value.worstAt = Int(max(0, (startedAt ?? ProcessInfo.processInfo.systemUptime) - self.started) * 1000)
            value.worstRoute = self.visibleRoute
        }
        return value
    }

    private func recordOperationLocked(_ operation: Operation, milliseconds: Double, startedAt: Double?) {
        self.operationSummaries[operation] = self.updatedSummary(self.operationSummaries[operation] ?? OperationSummary(), milliseconds: milliseconds, startedAt: startedAt)
    }

    private static let fixedProductionStages: Set<String> = {
        let common = ["layout", "data", "background", "transition", "play", "attach", "detach", "preferences", "alpha", "sourceReadyWall"]
        let settings = ["bgPreferences", "bgResolve", "bgApply", "header", "sections", "panesAndTail", "navigation", "scrollHeader", "scrollPanes", "headerPhonePreference", "headerAvatar", "headerCover", "sectionsBuild", "sectionsRegularUpdate", "sectionsRegularPlacement", "sectionsRegularRemoval", "sectionsEditingBuild", "sectionsEditingUpdate", "sectionsEditingPlacement", "sectionsEditingRemoval"]
        let image = ["avatarDiskLoad", "avatarDiskStore", "wallpaperImage", "gradientImage", "sampledTint"]
        var result: Set<String> = ["client.work", "chat.layout", "chatList.layout"]
        for context in ["settings", "peer", "pending"] { for stage in common { result.insert(context + "." + stage) } }
        for stage in settings { result.insert("settings." + stage) }
        for thread in ["main", "worker"] { for stage in image { result.insert(thread + "." + stage) } }
        return result // Exactly63 fixed source labels, no customer-provided keys.
    }()

    private func recordFixedOverflowLocked(_ stage: String, milliseconds: Double, startedAt: Double?) -> Bool {
        guard Self.fixedProductionStages.contains(stage) else { return false }
        self.fixedOverflow[stage] = self.updatedSummary(self.fixedOverflow[stage] ?? OperationSummary(), milliseconds: milliseconds, startedAt: startedAt)
        return true
    }

    private func recordUtilitySampleLocked(now: Double, cpuPercent: Double?, peakRSS: Int64, thermal: Int) {
        let elapsed = now - self.started
        guard elapsed.isFinite, elapsed >= 0, elapsed < self.maxCaptureSeconds else { return }
        let index = Int(elapsed / self.telemetryBlockSeconds)
        var block = self.telemetryBlocks[index] ?? TelemetryBlock()
        block.samples += 1
        if let cpuPercent, cpuPercent.isFinite { block.cpuMax = max(block.cpuMax ?? 0, cpuPercent) }
        block.peakRSS = max(block.peakRSS, peakRSS)
        block.thermalMax = max(block.thermalMax, thermal)
        block.routes.insert(self.visibleRoute)
        self.telemetryBlocks[index] = block
        self.trimAuxiliaryLinesLocked()
    }

    private func recordMainWaitLocked(submittedAt: Double, finishedAt: Double, route: String) {
        let elapsed = submittedAt - self.started
        guard elapsed.isFinite, elapsed >= 0, elapsed < self.maxCaptureSeconds, finishedAt.isFinite else { return }
        let index = Int(elapsed / self.telemetryBlockSeconds)
        var block = self.telemetryBlocks[index] ?? TelemetryBlock()
        let wait = max(0, (finishedAt - submittedAt) * 1000)
        block.waitSamples += 1
        if wait >= block.waitMax {
            block.waitMax = wait; block.waitAt = Int(elapsed * 1000); block.waitRoute = route
            block.waitFinishedAt = Int((finishedAt - self.started) * 1000)
        }
        block.routes.insert(route)
        self.telemetryBlocks[index] = block
        self.trimAuxiliaryLinesLocked()
    }

    private func retainedDetailLinesLocked() -> [String] {
        return self.legacySlowLines + self.retainedSamples.keys.sorted().map { self.retainedSamples[$0]!.line }
    }

    private var retainedDetailCountLocked: Int { self.legacySlowLines.count + self.retainedSamples.count }

    private func slowLineLocked(stage: String, owner: Int, startedAt: Double, milliseconds: Double, operation: String) -> String {
        let beginMs = Int((startedAt - self.started) * 1000.0)
        let endMs = Int((startedAt - self.started) * 1000.0 + milliseconds)
        return "slow stage=\(stage) owner=\(owner) startMs=\(beginMs) endMs=\(endMs) durationMs=\(Int(milliseconds)) operation=\(operation) route=\(self.visibleRoute) thread=\(Thread.isMainThread ? "main" : "worker")"
    }

    private func addReferenceLocked(_ sample: DetailSample) {
        self.sampleReferences[sample.id, default: 0] += 1
        self.retainedSamples[sample.id] = sample
    }

    private func removeReferenceLocked(_ sample: DetailSample) {
        let count = self.sampleReferences[sample.id]! - 1
        if count == 0 {
            self.sampleReferences.removeValue(forKey: sample.id)
            self.retainedSamples.removeValue(forKey: sample.id)
        } else { self.sampleReferences[sample.id] = count }
    }

    private func retainDetailLocked(_ operation: Operation, milliseconds: Double, startedAt: Double, stage: String, owner: Int) -> Bool {
        let main = Thread.isMainThread
        let replaceOperation = self.operationWorst[operation].map({ milliseconds > $0.duration }) ?? true
        let elapsed = startedAt - self.started
        var selectedWindow: Int?
        if elapsed >= 0, elapsed < self.maxCaptureSeconds {
            let window = Int(elapsed / self.detailWindowSeconds) * 2 + (operation.isInputOrSend ? 1 : 0)
            let old = self.windowWorst[window]
            // A worker's expensive synchronous span must not displace a main
            // span from the scheduling window; per-operation maxima retain both
            // thread aggregates independently above.
            if old == nil || (main && !old!.main) || (main == old!.main && milliseconds > old!.duration) {
                selectedWindow = window
            }
        }
        guard replaceOperation || selectedWindow != nil else { self.suppressedSlowEvents += 1; return false }
        // Reject unselected repeated spans before allocating a line. Counting
        // during capture is O(1); sorting is performed only during export.
        self.detailSequence += 1
        let line = self.slowLineLocked(stage: stage, owner: owner, startedAt: startedAt, milliseconds: milliseconds, operation: operation.rawValue)
        let sample = DetailSample(id: self.detailSequence, duration: milliseconds, main: main, line: line)
        if replaceOperation {
            if let old = self.operationWorst[operation] { self.removeReferenceLocked(old) }
            self.operationWorst[operation] = sample; self.addReferenceLocked(sample)
        }
        if let window = selectedWindow {
            if let old = self.windowWorst[window] { self.removeReferenceLocked(old) }
            self.windowWorst[window] = sample; self.addReferenceLocked(sample)
        }
        while self.retainedDetailCountLocked > self.slowEventLimit {
            // Real operation evidence has reserved29+60 slots; legacy generic
            // span examples use only the remaining budget, without starving input.
            self.legacySlowLines.removeFirst(); self.legacyDetailsEvicted += 1
        }
        self.slowEvents = self.retainedDetailCountLocked
        self.trimAuxiliaryLinesLocked()
        return true
    }

    private func trimAuxiliaryLinesLocked() {
        let limit = self.capacity - self.telemetryBlocks.count - self.retainedDetailCountLocked - self.captureBoundaries.count
        if self.lines.count > limit {
            let removed = self.lines.count - limit
            self.lines.removeFirst(removed); self.dropped += removed
        }
    }

    private func appendLocked(_ line: String) {
        self.lines.append(line)
        self.trimAuxiliaryLinesLocked()
    }

    public func report() -> String {
        self.lock.lock(); defer { self.lock.unlock() }
        let info = Bundle.main.infoDictionary ?? [:]
        let duration = self.running ? ProcessInfo.processInfo.systemUptime - self.started : self.stoppedDuration
        let header = "Jerkgram P0 diagnostics v8\napp=\(info["CFBundleIdentifier"] ?? "unknown") version=\(info["CFBundleShortVersionString"] ?? "unknown") build=\(info["CFBundleVersion"] ?? "unknown")\nOS=\(ProcessInfo.processInfo.operatingSystemVersionString) cores=\(ProcessInfo.processInfo.activeProcessorCount)\nrecording=\(self.running) dropped=\(self.dropped) durationSeconds=\(Int(duration)) auxiliaryDropped=\(self.dropped) telemetryBlocks=\(self.telemetryBlocks.count) unsupportedTimingSamplesDropped=\(self.unsupportedTimingSamplesDropped) legacyDetailsEvicted=\(self.legacyDetailsEvicted)\nNo message/account/phone content. GPU utilization NOT measured.\n"
        let measurements = self.timings.keys.sorted().map { key -> String in
            let value = self.timings[key]!
            return "\(key): calls=\(value.count) maxMs=\(Int(value.maxMs)) slow>=16.7ms=\(value.slow)"
        }.joined(separator: "\n")
        let refresh = self.frameIntervals.keys.sorted().map { route -> String in
            let value = self.frameIntervals[route]!
            return "refresh route=\(route) samples=\(value.samples) maxGapMs=\(String(format: "%.2f", value.maxGapMs)) expectedMs=\(String(format: "%.2f", value.minExpectedMs))...\(String(format: "%.2f", value.maxExpectedMs)) gaps>=16.7/33.4/50=\(value.over16)/\(value.over33)/\(value.over50) missedOpportunitiesEstimated=\(value.missedOpportunities)"
        }.joined(separator: "\n")
        let entered = Operation.allCases.filter { self.operationsObserved & $0.bit != 0 }.map { $0.rawValue }.joined(separator: ",")
        func summary(_ prefix: String, _ value: OperationSummary) -> String {
            return "\(prefix) samples=\(value.count) mainSamples=\(value.mainCount) workerSamples=\(value.workerCount) mainMaxMs=\(Int(value.mainMax)) workerMaxMs=\(Int(value.workerMax)) slow>=16.7ms=\(value.slow) worstAtMs=\(value.worstAt) worstRoute=\(value.worstRoute)"
        }
        let operations = Operation.allCases.compactMap { operation -> String? in
            guard let value = self.operationSummaries[operation] else { return nil }
            return summary("operationSummary operation=\(operation.rawValue)", value)
        }.joined(separator: "\n")
        let overflow = self.fixedOverflow.keys.sorted().map { summary("fixedStageOverflow stage=\($0)", self.fixedOverflow[$0]!) }.joined(separator: "\n")
        let telemetry = self.telemetryBlocks.keys.sorted().map { index -> String in
            let value = self.telemetryBlocks[index]!
            let cpu = value.cpuMax.map { String(format: "%.1f", $0) } ?? "unavailable/first"
            return "telemetry window=\(index * 5)...\((index + 1) * 5)s samples=\(value.samples) cpuPct=\(cpu) cpuMaxPct=\(cpu) peakRSSBytes=\(value.peakRSS) thermalMax=\(value.thermalMax) mainQueueWaitMs=\(Int(value.waitMax.rounded())) waitSamples=\(value.waitSamples) submittedAtMs=\(value.waitAt) finishedAtMs=\(value.waitFinishedAt) route=\(value.waitRoute) routes=\(value.routes.sorted().joined(separator: ","))"
        }
        let timeline = self.captureBoundaries + telemetry + self.retainedDetailLinesLocked() + self.lines
        return header + "Refresh callbacks measure scheduling opportunities, NOT rendered FPS.\nclient.work combines operations; detail labels identify only slow synchronous spans, not async completion or individual fast-call counts.\noperationsEntered=\(entered) (entry coverage only; inclusive spans overlap)\nroute=\(self.visibleRoute) timingKeysRejected=\(self.timingKeysRejected) routeReleasesIgnored=\(self.routeReleasesIgnored)\n" + refresh + "\n" + measurements + "\n" + operations + "\n" + overflow + "\nslowEvents=\(self.slowEvents) suppressedSlowEvents=\(self.suppressedSlowEvents) limit=\(self.slowEventLimit) nestedSlowEventsSuppressed=\(self.nestedSlowEventsSuppressed)\nRetention: 1Hz sampling; 5s maxima blocks (not averages); details=worst per operation plus separate20s input/other windows, NOT every slow call. Known overflow stages retain samples; unsupported labels are counted as dropped. Inclusive operation spans overlap; do not sum. Timeline sections are grouped, use timestamps.\n--- timeline ---\n" + timeline.joined(separator: "\n")
    }
}
