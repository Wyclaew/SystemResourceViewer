import SwiftUI

/// Unified header component for telemetry cards with SF Symbols and accessory slots.
public struct SectionHeaderView<Accessory: View>: View {
    private let title: String
    private let symbol: String
    private let symbolColor: Color
    private let accessory: Accessory

    public init(
        title: String,
        symbol: String,
        symbolColor: Color = .accentColor,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.symbol = symbol
        self.symbolColor = symbolColor
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(symbolColor)

            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)

            Spacer()

            accessory
        }
    }
}
