import SwiftUI

struct InlineErrorView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
    }
}
