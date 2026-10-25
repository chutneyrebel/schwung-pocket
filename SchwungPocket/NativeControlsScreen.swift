import SwiftUI

struct NativeControlsScreen: View {
    @ObservedObject var remoteStore: RemoteControlStore

    var body: some View {
        NavigationView {
            VStack {
                // Destination Grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                    ForEach(ControlDestination.allCases) { dest in
                        Button(action: { remoteStore.selectDestination(dest) }) {
                            Text(dest.rawValue)
                                .font(.caption)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(remoteStore.selectedDestination == dest ? Color.blue : Color(.tertiarySystemFill))
                                .foregroundColor(remoteStore.selectedDestination == dest ? .white : .primary)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding()

                if remoteStore.selectedDestination == .masterFx || remoteStore.selectedDestination == .tool {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("\(remoteStore.selectedDestination.rawValue) Remote Control Unavailable")
                            .font(.headline)
                        Text("Protocol traffic capture required for full verification.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(remoteStore.groupedParameters.keys.sorted(), id: \.self) { groupName in
                                Section(header: Text(groupName).font(.headline).padding(.horizontal)) {
                                    ForEach(remoteStore.groupedParameters[groupName] ?? []) { param in
                                        ParameterControlRow(param: param, remoteStore: remoteStore)
                                    }
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("SchwungTroller")
        }
    }
}

struct ParameterControlRow: View {
    let param: RemoteParameter
    @ObservedObject var remoteStore: RemoteControlStore

    var body: some View {
        HStack {
            Text(param.name)
                .font(.subheadline)
            Spacer()

            switch param.type {
            case .float, .integer:
                RotaryKnob(value: Binding(
                    get: { Float(param.value) ?? 0.0 },
                    set: { remoteStore.updateParameter(param.id, value: String($0)) }
                ), range: param.min...param.max)
                .frame(width: 50, height: 50)

            case .enumType:
                Picker(param.name, selection: Binding(
                    get: { param.value },
                    set: { remoteStore.updateParameter(param.id, value: $0) }
                )) {
                    ForEach(param.options, id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }
                .pickerStyle(.menu)

            case .filepath:
                Button("Select File") { /* Diagnostics handler */ }
                    .buttonStyle(.bordered)

            case .initType, .canvas, .unknown:
                Text("Read Only (\(param.value))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }
}
