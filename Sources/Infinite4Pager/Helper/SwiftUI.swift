//
//  SwiftUI.swift
//  Infinite4Pager
//
//  Created by Yang Xu on 2024/7/9.
//

import SwiftUI

extension View {
  @ViewBuilder
  func clipped(disable: Bool) -> some View {
    if disable {
      self
    } else {
      clipped()
    }
  }

  @ViewBuilder
  func frame(size: CGSize) -> some View {
    frame(width: size.width, height: size.height)
  }
}

struct MainPageOffsetInfo: Equatable {
  let mainPagePercent: Double
  let direction: PageViewDirection
}

extension EnvironmentValues {
 
    @Entry var mainPageOffsetInfo: MainPageOffsetInfo? = .init(mainPagePercent: 0, direction: .none)
    @Entry var pageType: PageType = .current
}

extension EnvironmentValues {
    
    @Entry public var infinite4PagerCurrentIndex = Infinite4PagerReducer.Point<Int>(horizontal: 0, vertical: 0)
    
    @Entry public var infinite4PagerIsDragging = false
}

struct OnPageVisibleModifier: ViewModifier {
  @Environment(\.mainPageOffsetInfo) var info
  @Environment(\.pageType) var pageType
  let perform: (Double?) -> Void
  func body(content: Content) -> some View {
    content
      .task(id: info) {
        if let info {
          perform(valueTransform(info))
        }
      }
  }

  // 根据 pageType 对可见度进行转换
  func valueTransform(_ info: MainPageOffsetInfo) -> Double? {
    let percent = info.mainPagePercent
    switch (pageType, info.direction) {
    case (.current, _):
      return 1.0 - abs(percent)
    case (.leading, .left), (.leading, .right),
        (.top, .top), (.top, .bottom):
      if percent > 0 {
        return 1 - (1 - percent)
      } else {
        return 0
      }
    case (.trailing, .left), (.trailing, .right),
        (.bottom, .top), (.bottom, .bottom):
      if percent < 0 {
        return 1 - (1 + percent)
      } else {
        return 0
      }
    default:
      return nil
    }
  }
}

extension View {
  /// 当前视图的可见尺寸比例
  /// 视图的尺寸为容器尺寸
  @ViewBuilder
  public func onPageVisible(_ perform: @escaping (Double?) -> Void) -> some View {
    modifier(OnPageVisibleModifier(perform: perform))
  }
}
