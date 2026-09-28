import SwiftUI
import AppKit

enum PreviewKind: String {
    case original = "Original"
    case pro = "Procesado Pro"
    case ai = "IA"
}

struct PreviewLightboxItem: Identifiable {
    let kind: PreviewKind
    let image: NSImage
    let badge: String?
    let summary: String?

    var id: PreviewKind { kind }
}

struct PreviewLightboxView: View {
    let items: [PreviewLightboxItem]
    @Binding var selectedKind: PreviewKind

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var zoomScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero

    private var selectedIndex: Int {
        items.firstIndex(where: { $0.kind == selectedKind }) ?? 0
    }

    private var selectedItem: PreviewLightboxItem? {
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    var body: some View {
        VStack(spacing: 12) {
            header

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.92))

                if let item = selectedItem {
                    GeometryReader { geometry in
                        ScrollView([.horizontal, .vertical]) {
                            Image(nsImage: item.image)
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: max(geometry.size.width - 80, 320) * zoomScale,
                                    height: max(geometry.size.height - 80, 320) * zoomScale
                                )
                                .offset(
                                    x: accumulatedOffset.width + dragOffset.width,
                                    y: accumulatedOffset.height + dragOffset.height
                                )
                                .gesture(dragGesture)
                                .padding(40)
                        }
                    }
                }
            }
            .frame(minWidth: 900, minHeight: 560)
            .overlay(alignment: .leading) {
                if items.count > 1 {
                    navigationButton(systemImage: "chevron.left", action: goToPrevious)
                        .padding(.leading, 14)
                }
            }
            .overlay(alignment: .trailing) {
                if items.count > 1 {
                    navigationButton(systemImage: "chevron.right", action: goToNext)
                        .padding(.trailing, 14)
                }
            }
        }
        .padding(18)
        .frame(minWidth: 980, minHeight: 680)
        .focusable()
        .focused($isFocused)
        .onAppear {
            isFocused = true
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                goToPrevious()
            case .right:
                goToNext()
            default:
                break
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let item = selectedItem {
                Text(item.kind.rawValue)
                    .font(.system(size: 17, weight: .bold))

                if let badge = item.badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(badge == "IA" ? Color.purple.opacity(0.14) : Color.blue.opacity(0.12))
                        .foregroundColor(badge == "IA" ? .purple : .blue)
                        .clipShape(Capsule())
                }

                Text("\(selectedIndex + 1)/\(items.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button("1:1") {
                    resetViewport(to: 1.0)
                }
                .buttonStyle(.bordered)

                Button("Ajustar") {
                    resetViewport(to: 0.9)
                }
                .buttonStyle(.bordered)

                Button("Cerrar") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                accumulatedOffset.width += value.translation.width
                accumulatedOffset.height += value.translation.height
                dragOffset = .zero
            }
    }

    private func navigationButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.borderedProminent)
    }

    private func goToPrevious() {
        guard items.count > 1 else { return }
        let newIndex = selectedIndex == 0 ? items.count - 1 : selectedIndex - 1
        selectedKind = items[newIndex].kind
        resetViewport(to: 1.0)
    }

    private func goToNext() {
        guard items.count > 1 else { return }
        let newIndex = selectedIndex == items.count - 1 ? 0 : selectedIndex + 1
        selectedKind = items[newIndex].kind
        resetViewport(to: 1.0)
    }

    private func resetViewport(to scale: CGFloat) {
        zoomScale = scale
        dragOffset = .zero
        accumulatedOffset = .zero
    }
}

struct BeforeAfterSliderView: View {
    let originalImage: NSImage
    let processedImage: NSImage
    let processedLabel: String
    let processedBadge: String?
    @Binding var position: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let clampedPosition = min(max(position, 0.0), 1.0)
            let dividerX = max(0, min(geometry.size.width, geometry.size.width * clampedPosition))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("Before / After")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    Spacer()

                    comparisonPill(title: "Original", badge: nil)
                    comparisonPill(title: processedLabel, badge: processedBadge)
                }

                ZStack {
                    imageLayer(image: originalImage)

                    imageLayer(image: processedImage)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: dividerX)
                        }

                    Rectangle()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: 2)
                        .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 0)
                        .position(x: dividerX, y: geometry.size.height / 2)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 26, height: 26)
                        .overlay {
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.black.opacity(0.75))
                        }
                        .shadow(color: .black.opacity(0.16), radius: 5, x: 0, y: 1)
                        .position(x: dividerX, y: geometry.size.height / 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let newPosition = value.location.x / max(geometry.size.width, 1)
                            position = min(max(newPosition, 0.0), 1.0)
                        }
                )

                Slider(value: $position, in: 0...1)
                    .controlSize(.small)
            }
        }
    }

    private func imageLayer(image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.04))
    }

    private func comparisonPill(title: String, badge: String?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)

            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor(for: badge).opacity(0.14))
                    .foregroundColor(badgeColor(for: badge))
                    .clipShape(Capsule())
            }
        }
    }

    private func badgeColor(for badge: String) -> Color {
        switch badge {
        case "IA":
            return .purple
        case "IA→PRO", "IA-R":
            return .orange
        default:
            return .blue
        }
    }
}
