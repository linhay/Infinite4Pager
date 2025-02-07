//
//  Infinite4Pager.swift
//  Infinite4Pager
//
//  Created by Yang Xu on 2024/7/8.
//

import SwiftUI

enum PageType {
    case current, leading, trailing, top, bottom
}

@Observable
public class Infinite4PagerReducer {
    
    public struct Point<V: Equatable>: Equatable {
        public var horizontal: V
        public var vertical: V
        
        public init(horizontal: V, vertical: V) {
            self.horizontal = horizontal
            self.vertical = vertical
        }
    }
    
    public var offset: CGSize = .zero
    public var dragDirection: PageViewDirection = .none
    public var size: CGSize = .zero
    
    public var current: Point<Int>
    /// 总视图数量，nil 为无限
    public let total: Point<Int?>
    /// 横向翻页位移阈值，松开手指后，预测距离超过容器宽度的百分比，超过即翻页
    public var thresholdRatio: Point<CGFloat>
    public let animation: Animation
    public let edgeBouncyAnimation: Animation = .smooth
    
    /// 启用后，将生成更多的站位视图（ 为开启生成 4 个，开启后创建 8 个）。可以改善因滑动速度过快或弹性动画回弹效果过大产生的单元格空隙
    let enableClipped: Bool
    /// 是否启用视图可见感知
    let enablePageVisibility: Bool
    
    public init(current: Point<Int> = .init(horizontal: 0, vertical: 0),
                total: Point<Int?> = .init(horizontal: nil, vertical: nil),
                thresholdRatio: Point<CGFloat> = .init(horizontal: 0.33, vertical: 0.25),
                enableClipped: Bool = true,
                enablePageVisibility: Bool = false,
                animation: Animation = .easeOut(duration: 0.22)) {
        self.current = current
        self.total = total
        self.thresholdRatio = thresholdRatio
        self.enableClipped = enableClipped
        self.enablePageVisibility = enablePageVisibility
        self.animation = animation
    }
    
    // 根据 container size 和 offset，计算主视图的可见参考值
    // 0 = 完全可见，横向时, -1 左侧完全移出，+1 右侧完全移出
    // 纵向时， -1 向上完全移出，+1 向下完全移出
    func mainPagePercent() -> Double {
        switch dragDirection {
        case .left, .right:
            offset.width / size.width
        case .bottom, .top:
            offset.height / size.height
        case .none:
            0
        }
    }
    
    // 判断是否为边界视图
    func isAtBoundary(direction: Int) -> Bool {
        switch dragDirection {
        case .left, .right:
            if let total = total.horizontal {
                // 有限水平页面的情况
                return (current.horizontal == 0 && direction < 0)
                || (current.horizontal == total - 1 && direction > 0)
                
            } else {
                // 无限水平滚动的情况
                return false
            }
        case .top, .bottom:
            if let total = total.vertical {
                // 有限垂直页面的情况
                return (current.vertical == 0 && direction < 0)
                || (current.vertical == total - 1 && direction > 0)
            } else {
                // 无限垂直滚动的情况
                return false
            }
        case .none:
            return false
        }
    }
    
    func onDragChanged(translation: CGSize) {
        
        if dragDirection == .none {
            if abs(translation.width) > abs(translation.height) {
                dragDirection = translation.width > 0 ? .right : .left
            } else {
                dragDirection = translation.height > 0 ? .bottom : .top
            }
        }
        
        if dragDirection.isHorizontal {
            let limitedX = boundedDragOffset(
                translation.width,
                pageSize: size.width,
                currentPage: current.horizontal,
                totalPages: total.horizontal
            )
            offset = CGSize(width: limitedX, height: 0)
        } else if dragDirection.isVertical {
            let limitedY = boundedDragOffset(
                translation.height,
                pageSize: size.height,
                currentPage: current.vertical,
                totalPages: total.vertical
            )
            offset = CGSize(width: 0, height: limitedY)
        } else {
            offset = .zero
        }
    }
    
    func onDragEnd(predictedEndTranslation: CGSize) {
        let pageSize       = dragDirection.isHorizontal ? size.width : size.height
        let currentPage    = dragDirection.isHorizontal ? current.horizontal : current.vertical
        let totalPages     = dragDirection.isHorizontal ? total.horizontal : total.vertical
        let thresholdRatio = dragDirection.isHorizontal ? thresholdRatio.horizontal : thresholdRatio.vertical
        
        let translation = dragDirection.isHorizontal ? predictedEndTranslation.width : predictedEndTranslation.height
        let boundedTranslation = boundedDragOffset(translation, pageSize: pageSize, currentPage: currentPage, totalPages: totalPages)
        
        let direction = -Int(translation / abs(translation))
        
        let isAtBoundary = isAtBoundary(direction: direction)
        if abs(boundedTranslation) > pageSize * thresholdRatio, !isAtBoundary {
            let newOffset = CGSize(
                width: dragDirection.isHorizontal ? CGFloat(-direction) * pageSize : 0,
                height: dragDirection.isVertical ? CGFloat(-direction) * pageSize : 0
            )
            
            withAnimation(animation) {
                offset = newOffset
            } completion: { [weak self] in
                guard let self = self else { return }
                if dragDirection.isHorizontal {
                    if let total = total.horizontal {
                        // 有限页面的情况
                        current.horizontal = (current.horizontal + (direction == 1 ? 1 : -1) + total) % total
                    } else {
                        // 无限滚动的情况
                        current.horizontal += direction == 1 ? 1 : -1
                    }
                }
                
                if dragDirection.isVertical {
                    if let total = total.vertical {
                        // 有限页面的情况
                        current.vertical = (current.vertical + (direction == 1 ? 1 : -1) + total) % total
                    } else {
                        // 无限滚动的情况
                        current.vertical += direction == 1 ? 1 : -1
                    }
                }
                dragDirection = .none
            }
        } else {
            withAnimation(edgeBouncyAnimation) {
                offset = .zero
                dragDirection = .none
            }
        }
    }
    
    func boundedDragOffset(_ offset: CGFloat,
                           pageSize: CGFloat,
                           currentPage: Int,
                           totalPages: Int?) -> CGFloat {
        let maxThreshold = pageSize / 2
        
        if let total = totalPages {
            if (currentPage == 0 && offset > 0) || (currentPage == total - 1 && offset < 0) {
                let absOffset = abs(offset)
                let progress = min(absOffset / maxThreshold, 1.0)
                
                // 使用更线性的阻尼函数
                let dampeningFactor = 1 - progress * 0.5
                
                let dampendOffset = absOffset * dampeningFactor
                return offset > 0 ? dampendOffset : -dampendOffset
            }
        }
        return offset
    }
    
}

public struct Infinite4Pager<Content: View>: View {
    
    @State private var store: Infinite4PagerReducer
    @GestureState private var isDragging = false
    @Environment(\.scenePhase) var scenePhase
    @State private var cancelByDrag = false
    /// 一个闭包，用于生成对应单元格的页面，参数为当前单元格的横竖位置
    let getPage: (_ index: Infinite4PagerReducer.Point<Int>) -> Content
    
    public init(store: Infinite4PagerReducer = Infinite4PagerReducer(),
                @ViewBuilder getPage: @escaping (_ index: Infinite4PagerReducer.Point<Int>) -> Content) {
        self.store = store
        self.getPage = getPage
    }
    
    public var body: some View {
        CurrentPageView(store: store, getPage: getPage)
            .disabled(isDragging)
            .geometryGroup()
            .offset(x: store.offset.width, y: store.offset.height)
            .simultaneousGesture(
                DragGesture()
                    .updating($isDragging) { _, isDragging, _ in
                        if !isDragging {
                            isDragging = true
                        }
                    }
                    .onChanged { value in
                        store.onDragChanged(translation: value.translation)
                    }
                    .onEnded { value in
                        store.onDragEnd(predictedEndTranslation: value.predictedEndTranslation)
                        cancelByDrag = true
                    }
            )
            .onChange(of: isDragging) {
                // 处理系统对拖动手势的打断
                if !isDragging {
                    if !cancelByDrag {
                        withAnimation(store.edgeBouncyAnimation) {
                            store.offset = .zero
                        }
                    } else {
                        cancelByDrag = false
                    }
                }
            }
            .onChange(of: store.current) {
                store.offset = .zero
            }
            .environment(\.infinite4PagerIsDragging, isDragging)
            .environment(\.infinite4PagerCurrentIndex, store.current)
            .transformEnvironment(\.mainPageOffsetInfo) { value in
                if store.enablePageVisibility {
                    value = MainPageOffsetInfo(mainPagePercent: store.mainPagePercent(),
                                               direction: store.dragDirection)
                }
            }
            .clipped(disable: !store.enableClipped)
            .background(
                GeometryReader { proxy in
                    let size = proxy.size
                    Color.clear
                        .task(id: size) { store.size = size }
                }
            )
    }
    
    
}

public enum PageViewDirection {
    case top, bottom, left, right, none
    var isHorizontal: Bool {
        self == .left || self == .right
    }
    var isVertical: Bool {
        self == .top || self == .bottom
    }
}

struct CurrentPageView<Content: View>: View {
    
    @State var store: Infinite4PagerReducer
    let getPage: (_ index: Infinite4PagerReducer.Point<Int>) -> Content
    @Environment(\.mainPageOffsetInfo) var info
    
    init(store: Infinite4PagerReducer, getPage: @escaping (_ index: Infinite4PagerReducer.Point<Int>) -> Content) {
        self.store = store
        self.getPage = getPage
    }
    
    var body: some View {
        Color.clear
            .overlay(alignment: .center) {
                Grid(alignment: .center, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        Color.clear
                            .frame(size: store.size)
                        // top
                        getAdjacentPage(direction: .top, offset: -1)
                            .frame(size: store.size)
                            .environment(\.pageType, .top)
                        Color.clear
                            .frame(size: store.size)
                    }
                    GridRow {
                        // leading
                        getAdjacentPage(direction: .left, offset: -1)
                            .frame(size: store.size)
                            .environment(\.pageType, .leading)
                        // current
                        getPage(store.current)
                            .frame(size: store.size)
                            .environment(\.pageType, .current)
                        // trailing
                        getAdjacentPage(direction: .right, offset: 1)
                            .frame(size: store.size)
                            .environment(\.pageType, .trailing)
                    }
                    GridRow {
                        Color.clear
                            .frame(size: store.size)
                        // bottom
                        getAdjacentPage(direction: .bottom, offset: 1)
                            .frame(size: store.size)
                            .environment(\.pageType, .bottom)
                        Color.clear
                            .frame(size: store.size)
                    }
                }
            }
            .contentShape(Rectangle())
            .id("\(store.current.horizontal),\(store.current.vertical)")
    }
    
    private func getAdjacentPage(direction: PageViewDirection, offset: Int) -> some View {
        let nextPage: Int?
        let currentPage: Int
        let totalPages: Int?
        
        switch direction {
        case .left, .right:
            currentPage = store.current.horizontal
            totalPages = store.total.horizontal
            nextPage = getNextPage(currentPage, total: totalPages, direction: offset)
        case .top, .bottom:
            currentPage = store.current.vertical
            totalPages = store.total.vertical
            nextPage = getNextPage(currentPage, total: totalPages, direction: offset)
        case .none:
            fatalError()
        }
        
        return Group {
            if let nextPage = nextPage {
                Color.clear
                    .overlay(
                        direction.isHorizontal
                        ? getPage(.init(horizontal: nextPage, vertical: store.current.vertical))
                        : getPage(.init(horizontal: store.current.horizontal, vertical: nextPage))
                    )
            } else {
                Color.clear
            }
        }
    }
    
    private func getNextPage(_ current: Int, total: Int?, direction: Int) -> Int? {
        if let total = total {
            let next = current + direction
            return (0 ..< total).contains(next) ? next : nil
        }
        return current + direction
    }
}

#Preview {
    let store = Infinite4PagerReducer(current: .init(horizontal: 2, vertical: 2),
                                      total: .init(horizontal: nil, vertical: nil),
                                      enableClipped: false,
                                      enablePageVisibility: true)
    let colors = [Color.red, .green, .blue, .yellow, .purple]
    Infinite4Pager(store: store) { index in
        colors[abs(index.horizontal + index.vertical) % colors.count]
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading) {
                    Text("index: h(\(index.horizontal))-v(\(index.vertical))")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("direction: \(store.dragDirection)")
                    Text(String(format: "offset: %.2f, %.2f",
                                store.offset.width,
                                store.offset.height))
                }
                .fontDesign(.monospaced)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(.black))
                .padding()
                .scenePadding()
            }
    }
    .ignoresSafeArea()
}
