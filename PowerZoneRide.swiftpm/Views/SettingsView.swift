import SwiftUI

/// FTP, the meter connection, and the on-device parser check.
struct SettingsView: View {
    @ObservedObject var meter: PowerMeterService
    @AppStorage("ftp") private var ftp: Double = 200

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("FTP")
                    Spacer()
                    TextField("Watts", value: $ftp, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Text("W").foregroundStyle(.secondary)
                }
                Stepper("Adjust", value: $ftp, in: 50...600, step: 5)
                    .labelsHidden()
            } header: {
                Text("Functional Threshold Power")
            } footer: {
                Text("Every target in a workout is a percentage of this number. Take an FTP test in a Power Zone class and enter the result here.")
            }

            Section("Your Zones") {
                ForEach(1...7, id: \.self) { z in
                    let range = PowerZones.wattRange(zone: z, ftp: ftp)
                    HStack {
                        Circle().fill(PowerZones.color(zone: z)).frame(width: 10, height: 10)
                        Text("Zone \(z)")
                        Spacer()
                        Text(z == 7 ? "\(Int(range.lowerBound))+ W"
                                    : "\(Int(range.lowerBound))–\(Int(range.upperBound)) W")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }

            Section("Power Meter") {
                NavigationLink {
                    MeterConnectionView(meter: meter)
                } label: {
                    HStack {
                        Text(meter.connectedName ?? "Connect")
                        Spacer()
                        Text(meter.state.label).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                NavigationLink("Run Parser Self-Test") { ParserSelfTestView() }
            } footer: {
                Text("Checks the workout parsers against saved copies of the website. Run this if workouts stop loading — a failure here means the site changed its page format.")
            }

            Section {
                Link("app.homefitnessbuddy.com",
                     destination: URL(string: "https://app.homefitnessbuddy.com/peloton/powerzone/")!)
            } header: {
                Text("Data Source")
            } footer: {
                Text("Workouts come from Home Fitness Buddy's free Power Zone tool, fetched on this iPad for personal use. Peloton is a trademark of Peloton Interactive, Inc.; this app is not affiliated with Peloton or Home Fitness Buddy.")
            }
        }
        .navigationTitle("Settings")
    }
}

/// Scan-and-pick screen, and the place to confirm the meter works before a ride.
struct MeterConnectionView: View {
    @ObservedObject var meter: PowerMeterService

    var body: some View {
        List {
            Section {
                HStack {
                    Text(meter.state.label)
                    Spacer()
                    if meter.isReceivingData {
                        Text("\(meter.watts) W · \(meter.cadence) rpm")
                            .monospacedDigit().foregroundStyle(.green)
                    }
                }
                if meter.connectedName != nil {
                    Button("Disconnect", role: .destructive) { meter.disconnect() }
                }
            } header: {
                Text("Status")
            } footer: {
                Text("Spin the cranks to wake the meter — pedal-based meters sleep when they're still and won't advertise until they're moving.")
            }

            Section("Nearby") {
                if meter.discovered.isEmpty {
                    Text("No devices yet").foregroundStyle(.secondary)
                }
                ForEach(meter.discovered) { d in
                    Button {
                        meter.connect(d.id)
                    } label: {
                        HStack {
                            Text(d.name)
                            Spacer()
                            Text("\(d.rssi) dBm").foregroundStyle(.secondary).font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle("Power Meter")
        .toolbar {
            Button("Scan") { meter.startScanning() }
        }
        .onAppear { meter.startScanning() }
        .onDisappear { meter.stopScanning() }
    }
}
