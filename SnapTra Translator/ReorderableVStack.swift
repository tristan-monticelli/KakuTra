//
//  ReorderableVStack.swift
//  KakuTra
//

import SwiftUI

struct ReorderableVStack<Content: View, Item: Identifiable & Equatable>: View {
    @Binding var items: [Item]
    @ViewBuilder let content: (Binding<Item>, Int) -> Content
    let onMove: (IndexSet, Int) -> Void
    @State private var draggingItem: Item?
    @State private var draggedIndex: Int?
    @State private var targetIndex: Int?
    @State private var itemFrames: [Int: CGRect] = [:]
    @State private var dragPosition: CGPoint?

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                ForEach(Array($items.enumerated()), id: \.element.id) { index, item in
                    ZStack(alignment: .top) {
                        content(item, index)
                            .opacity(draggedIndex == index ? 0.3 : 1)
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .preference(key: ItemFrameKey.self, value: [index: geo.frame(in: .named("reorderableContainer"))])
                                }
                            )

                        // Insertion indicator above current item
                        if let target = targetIndex, target == index, draggedIndex != index {
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(height: 2)
                                .shadow(color: Color.accentColor.opacity(0.5), radius: 2)
                                .offset(y: -5)
                        }

                        // Insertion indicator at the end (after last item)
                        if index == items.count - 1,
                           let target = targetIndex,
                           target == items.count,
                           draggedIndex != items.count - 1 {
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(height: 2)
                                .shadow(color: Color.accentColor.opacity(0.5), radius: 2)
                                .offset(y: geoHeight(for: index) - 3)
                        }
                    }
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 5, coordinateSpace: .named("reorderableContainer"))
                            .onChanged { value in
                                if draggedIndex == nil {
                                    draggedIndex = index
                                    draggingItem = items[index]
                                    // Initialize drag position to item's center
                                    if let frame = itemFrames[index] {
                                        dragPosition = CGPoint(x: frame.midX, y: frame.midY)
                                    }
                                }

                                // Update drag position to follow mouse
                                dragPosition = value.location

                                // Calculate target index based on actual frame positions
                                let target = calculateTargetIndex(at: value.location)
                                if target != targetIndex {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        targetIndex = target
                                    }
                                }
                            }
                            .onEnded { _ in
                                if let from = draggedIndex, let to = targetIndex {
                                    let actualTo = to > from ? to : to
                                    if from != actualTo && from != actualTo - 1 {
                                        withAnimation(.spring(duration: 0.3)) {
                                            onMove(IndexSet([from]), actualTo)
                                        }
                                    }
                                }
                                draggingItem = nil
                                draggedIndex = nil
                                targetIndex = nil
                                dragPosition = nil
                            }
                    )
                }
            }
            .coordinateSpace(name: "reorderableContainer")
            .onPreferenceChange(ItemFrameKey.self) { frames in
                itemFrames = frames
            }

            // Floating dragged item that follows mouse
            if let draggedIndex = draggedIndex,
               let item = draggingItem,
               let position = dragPosition,
               let frame = itemFrames[draggedIndex] {
                content(Binding(
                    get: { item },
                    set: { _ in }
                ), draggedIndex)
                .frame(width: frame.width, height: frame.height)
                .position(x: position.x, y: position.y)
                .scaleEffect(1.03)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.6), lineWidth: 2)
                )
                .opacity(0.95)
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.05), value: position)
            }
        }
    }

    private func geoHeight(for index: Int) -> CGFloat {
        itemFrames[index]?.height ?? 76
    }

    private func calculateTargetIndex(at point: CGPoint) -> Int {
        guard !itemFrames.isEmpty else { return 0 }

        let sortedFrames = itemFrames.sorted { $0.key < $1.key }

        // Handle before first item
        if let first = sortedFrames.first, point.y < first.value.midY {
            return first.key
        }

        // Handle between items
        for (i, frame) in sortedFrames {
            guard let next = sortedFrames.first(where: { $0.key > i }) else { continue }
            let midY = (frame.midY + next.value.midY) / 2
            if point.y >= frame.midY && point.y < midY {
                return next.key
            }
        }

        // Handle after last item
        if let last = sortedFrames.last {
            return last.key + 1
        }

        return 0
    }
}

struct ItemFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
