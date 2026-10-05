//
//  DictionarySettingsView.swift
//  KakuTra
//
//  Japanese immersion dictionary settings tab.
//

import AppKit
import SwiftUI

struct DictionarySettingsView: View {
    @EnvironmentObject var model: AppModel
    var hidesScrollIndicator: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DictionarySettingsSection()
            }
            .padding()
            .background(
                ScrollViewScrollerConfigurator(
                    hidesVerticalScroller: hidesScrollIndicator
                )
            )
        }
        .scrollIndicators(hidesScrollIndicator ? .hidden : .automatic, axes: .vertical)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
