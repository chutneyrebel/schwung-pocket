import SwiftUI

public struct NativeControlsScreen: View {
    @EnvironmentObject public var remoteStore: RemoteControlStore

    public init() {}

    public var body: some View {
        NavigationView {
            VStack {
                // Destination Grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                    ForEach(Destination.allCases) { dest in
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

                if remoteStore.selectedDestination == .masterFX || remoteStore.selectedDestination == .tool {
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
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(groupName)
                                        .font(.headline)
                                        .padding(.horizontal)

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

public struct ParameterControlRow: View {
    public let param: ParameterModel
    @ObservedObject public var remoteStore: RemoteControlStore

    public var body: some View {
        HStack {
            Text(param.name)
                .font(.subheadline)
            Spacer()

            switch param.type {
            case .floatParam:
                Slider(value: Binding(
                    get: { param.floatValue },
                    set: { val in
                        remoteStore.updateParameter(param.id, value: String(val))
                    }
                ), in: param.minValue...param.maxValue)
                .frame(width: 140)

            case .enumParam:
                Picker(param.name, selection: Binding(
                    get: { param.enumValue },
                    set: { val in
                        remoteStore.updateParameter(param.id, value: String(val))
                    }
                )) {
                    ForEach(0..<param.options.count, id: \.self) { idx in
                        Text(param.options[idx]).tag(idx)
                    }
                }
                .pickerStyle(.menu)

            case .filepathParam, .initParam, .canvasParam, .unknown:
                Text("Read Only")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }
}