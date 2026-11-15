import SwiftUI
import WidgetKit

struct BeaconBatteriesEntry: TimelineEntry {
    let date: Date
    let payload: BeaconWidgetPayload
}

struct BeaconBatteriesProvider: TimelineProvider {
    func placeholder(in context: Context) -> BeaconBatteriesEntry {
        BeaconBatteriesEntry(date: Date(), payload: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BeaconBatteriesEntry) -> Void) {
        let payload = BeaconWidgetStore.load()
        completion(BeaconBatteriesEntry(
            date: Date(),
            payload: context.isPreview && payload.devices.isEmpty ? .sample : payload
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BeaconBatteriesEntry>) -> Void) {
        // Beacon reloads timelines when readings change; this is only a fallback.
        let entry = BeaconBatteriesEntry(date: Date(), payload: BeaconWidgetStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct BeaconBatteriesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BeaconBatteriesEntry

    var body: some View {
        Group {
            if entry.payload.devices.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "battery.0percent")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No devices reporting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else if family == .systemSmall {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(entry.payload.devices.prefix(4)) { device in
                        BatteryRing(device: device)
                    }
                }
            } else if family == .systemMedium {
                HStack(spacing: 10) {
                    ForEach(entry.payload.devices.prefix(4)) { device in
                        VStack(spacing: 6) {
                            BatteryRing(device: device)
                            Text("\(device.percent)%")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entry.payload.devices.prefix(6)) { device in
                        HStack(spacing: 10) {
                            BatteryRing(device: device)
                                .frame(width: 34, height: 34)
                            Text(device.name)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(device.percent)%")
                                .font(.callout.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

/// The ring Apple's own Batteries widget uses: a circular capacity gauge.
private struct BatteryRing: View {
    let device: BeaconWidgetDevice

    var body: some View {
        Gauge(value: Double(device.percent), in: 0...100) {
            Image(systemName: device.symbolName)
        } currentValueLabel: {
            Image(systemName: device.isCharging ? "bolt.fill" : device.symbolName)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(device.percent <= 20 && !device.isCharging ? .red : (device.isCharging ? .green : .primary))
        .accessibilityLabel(Text(device.name))
        .accessibilityValue(Text("\(device.percent)%"))
    }
}

struct BeaconBatteriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: BeaconWidgetStore.widgetKind, provider: BeaconBatteriesProvider()) { entry in
            BeaconBatteriesWidgetView(entry: entry)
        }
        .configurationDisplayName("Beacon Batteries")
        .description("Battery levels of your Bluetooth accessories, iPhone and Mac.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct BeaconWidgetBundle: WidgetBundle {
    var body: some Widget {
        BeaconBatteriesWidget()
        if #available(macOS 26.0, *) {
            BeaconRefreshControl()
            BeaconAudioLockControl()
        }
    }
}

extension BeaconWidgetPayload {
    static let sample = BeaconWidgetPayload(
        devices: [
            BeaconWidgetDevice(id: "1", name: "AirPods Pro", kind: .headphones, percent: 82, isCharging: false),
            BeaconWidgetDevice(id: "2", name: "Magic Keyboard", kind: .keyboard, percent: 64, isCharging: false),
            BeaconWidgetDevice(id: "3", name: "MX Master 3S", kind: .mouse, percent: 18, isCharging: false),
            BeaconWidgetDevice(id: "4", name: "iPhone", kind: .iPhone, percent: 47, isCharging: true),
        ],
        updatedAt: Date()
    )
}
