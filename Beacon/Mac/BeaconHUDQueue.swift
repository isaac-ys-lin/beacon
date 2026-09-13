import Foundation

/// Ordering only: this does not execute hardware commands or manufacture their results.
enum BeaconHUDEvent: Equatable {
    case battery(BatteryAlertEvent)
    case connection(BluetoothConnectionOperation)

    var operation: BluetoothConnectionOperation? {
        if case let .connection(operation) = self { return operation }
        return nil
    }
}

struct BeaconHUDEntry: Equatable, Identifiable {
    let id: UUID
    let event: BeaconHUDEvent

    init(event: BeaconHUDEvent) {
        self.event = event
        id = event.operation?.id ?? UUID()
    }
}

/// Operations take priority over battery reminders. Only updates to the same
/// operation can replace its visible progress/result; other events wait their turn.
struct BeaconHUDQueue {
    private(set) var current: BeaconHUDEntry?
    private(set) var waiting: [BeaconHUDEntry] = []
    private var dismissedProgress: Set<UUID> = []

    mutating func submit(_ event: BeaconHUDEvent) {
        let entry = BeaconHUDEntry(event: event)
        if let operation = event.operation {
            if operation.phase.isInProgress && dismissedProgress.contains(operation.id) { return }
            if !operation.phase.isInProgress { dismissedProgress.remove(operation.id) }
        }
        if current?.id == entry.id { current = entry; return }
        if let index = waiting.firstIndex(where: { $0.id == entry.id }) {
            waiting[index] = entry
            return
        }
        guard let current else { self.current = entry; return }
        if event.operation != nil && current.event.operation == nil {
            waiting.insert(current, at: waiting.firstIndex { $0.event.operation == nil } ?? waiting.endIndex)
            self.current = entry
        } else if event.operation != nil {
            waiting.insert(entry, at: waiting.firstIndex { $0.event.operation == nil } ?? waiting.endIndex)
        } else {
            waiting.append(entry)
        }
    }

    mutating func dismiss() {
        if let operation = current?.event.operation, operation.phase.isInProgress {
            // Dismissing progress does not cancel a command. Its final result still appears.
            dismissedProgress.insert(operation.id)
        }
        current = waiting.isEmpty ? nil : waiting.removeFirst()
    }
}
