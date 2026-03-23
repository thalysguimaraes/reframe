import SwiftUI

struct StatusBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Text("In")
                    .foregroundStyle(.secondary)
                Text("\(model.stats.inputFPS, format: .number.precision(.fractionLength(1))) fps")
            }
            HStack(spacing: 4) {
                Text("Out")
                    .foregroundStyle(.secondary)
                Text("\(model.stats.outputFPS, format: .number.precision(.fractionLength(1))) fps")
            }
            HStack(spacing: 4) {
                Text("Face")
                    .foregroundStyle(.secondary)
                Text("\(model.stats.faceConfidence, format: .number.precision(.fractionLength(2)))")
            }
            HStack(spacing: 4) {
                Text("Crop")
                    .foregroundStyle(.secondary)
                Text("\(model.stats.cropCoverage * 100, format: .number.precision(.fractionLength(0)))%")
            }
            Spacer()
            Text(model.statusMessage)
                .foregroundStyle(.tertiary)
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
