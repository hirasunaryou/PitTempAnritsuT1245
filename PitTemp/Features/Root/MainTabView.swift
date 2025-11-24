//
//  MainTabView.swift
//  PitTemp
//
// MainTabView.swift


import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var vm: SessionViewModel
    @State private var sel = 0

    var body: some View {
        TabView(selection: $sel) {
            MeasureView().tabItem { Label("Measure", systemImage: "dot.scope") }.tag(0)
            LibraryView().tabItem { Label("Library", systemImage: "table") }.tag(1)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
        }
        .modifier(StopHIDWhenNotMeasuring(sel: $sel))
    }
}

private struct StopHIDWhenNotMeasuring: ViewModifier {
    @Binding var sel: Int
    @EnvironmentObject var vm: SessionViewModel

    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.onChange(of: sel) { old, new in
                if new != 0 { vm.stopAll() }
            }
        } else {
            content.onChange(of: sel) { new in
                if new != 0 { vm.stopAll() }
            }
        }
    }
}
