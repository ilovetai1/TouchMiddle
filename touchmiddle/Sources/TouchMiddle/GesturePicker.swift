import SwiftUI
import TouchMiddleCore

struct GesturePicker: View {
    @Binding var selection: GestureKind

    private struct Group {
        let title: String
        let gestures: [GestureKind]
    }

    // Presentation order is independent of enum declaration and recognition order.
    private static let groups: [Group] = [
        Group(title: "一般點按與長按", gestures: [
            .twoFingerDoubleTap,
            .threeFingerTap, .threeFingerDoubleTap, .threeFingerLongPress,
            .fourFingerTap
        ]),
        Group(title: "一指固定", gestures: [
            .oneFingerHoldLeftTap, .oneFingerHoldRightTap
        ]),
        Group(title: "兩指固定", gestures: [
            .twoFingerHoldLeftTap, .twoFingerHoldLeftDoubleTap,
            .twoFingerHoldRightTap, .twoFingerHoldRightDoubleTap,
            .twoFingerHoldSwipeUp, .twoFingerHoldSwipeDown
        ]),
        Group(title: "角落點按", gestures: [
            .topLeftTwoFingerTap, .topRightTwoFingerTap,
            .bottomLeftTwoFingerTap, .bottomRightTwoFingerTap
        ])
    ]

    var body: some View {
        Picker("手勢", selection: $selection) {
            ForEach(Self.groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.gestures) { gesture in
                        Text(gesture.title).tag(gesture)
                    }
                }
            }
        }
        .pickerStyle(.menu)
    }
}
