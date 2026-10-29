import ChatCore
import SwiftUI

struct INDChatTextInput: View {
    @Binding var text: String
    let enabled: Bool
    let showEmoji: Bool
    let theme: INDChatTheme
    let placeholder: String
    let send: () -> Void
    @State private var isEmojiPickerVisible = false

    private let emojis = ["😀", "😂", "😍", "👍", "🙏", "🎉", "❤️", "😊", "😢", "👏", "🤔", "🔥"]

    var body: some View {
        VStack(spacing: 8) {
            if isEmojiPickerVisible {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                    ForEach(emojis, id: \.self) { emoji in
                        Button(emoji) { text.append(emoji) }
                            .font(.title2)
                            .accessibilityLabel("Insertar \(emoji)")
                    }
                }
                .padding(12)
                .background(Color(hex: theme.surfaceColorHex))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            HStack(alignment: .bottom, spacing: 8) {
                if showEmoji {
                    Button { isEmojiPickerVisible.toggle() } label: {
                        Image(systemName: isEmojiPickerVisible ? "keyboard" : "face.smiling")
                            .font(.title3)
                            .foregroundStyle(Color(hex: theme.mutedTextColorHex))
                            .frame(width: 38, height: 38)
                    }
                    .accessibilityLabel(isEmojiPickerVisible ? "Ocultar emojis" : "Mostrar emojis")
                }
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(hex: theme.surfaceColorHex), in: Capsule())
                    .disabled(!enabled)
                    .accessibilityLabel("Message")
                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color(hex: theme.primaryColorHex), in: Circle())
                }
                .disabled(!enabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(enabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1 : 0.5)
                .accessibilityLabel("Send message")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 14)
        .background(Color(hex: theme.surfaceColorHex))
    }
}

extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)
        let red, green, blue: Double
        switch value.count {
        case 3:
            red = Double((number >> 8) & 0xF) * 17 / 255
            green = Double((number >> 4) & 0xF) * 17 / 255
            blue = Double(number & 0xF) * 17 / 255
        default:
            red = Double((number >> 16) & 0xFF) / 255
            green = Double((number >> 8) & 0xFF) / 255
            blue = Double(number & 0xFF) / 255
        }
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
