import SwiftUI
import UIKit

/// Mũi tên đỏ chỉ vị trí hiện tại. Giữ rồi kéo để chọn nơi muốn đến.
struct RedArrowMarker: View {
    var heading: Double
    /// Khi đang đi theo đường: icon phương tiện (đi bộ, chạy, xe đạp, ô tô). Nil thì hiện mũi tên.
    var modeIcon: String? = nil
    var isDragging: Bool
    var onDragBegan: () -> Void
    var onDragMoved: (CGPoint) -> Void
    var onDragEnded: () -> Void

    private let red = Color(red: 0.92, green: 0.20, blue: 0.20)

    var body: some View {
        ZStack {
            Circle()
                .fill(red.opacity(isDragging ? 0.30 : 0.18))
                .frame(width: isDragging ? 76 : 60, height: isDragging ? 76 : 60)
            Circle()
                .fill(.white)
                .frame(width: 34, height: 34)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            if let modeIcon {
                Image(systemName: modeIcon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(red)
            } else {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(red)
                    .rotationEffect(.degrees(heading))
            }
        }
        .scaleEffect(isDragging ? 1.15 : 1)
        .contentShape(Circle())
        .gesture(dragGesture)
        .animation(.easeOut(duration: 0.15), value: isDragging)
        .accessibilityLabel("Vị trí của bạn")
        .accessibilityHint("Giữ rồi kéo tới nơi muốn đến.")
    }

    private var dragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    if let drag {
                        if !isDragging {
                            onDragBegan()
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        onDragMoved(drag.location)
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                if isDragging { onDragEnded() }
            }
    }
}
