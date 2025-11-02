import XCTest
import SwiftUI
import UIKit
@testable import PitTemp

@MainActor
final class MeasureViewSnapshotTests: XCTestCase {
    func testMeasureViewLightSnapshotRenders() {
        let fixtures = MeasureViewPreviewFixtures()
        let view = MeasureView()
            .environmentObject(fixtures.viewModel)
            .environmentObject(fixtures.folderBookmark)
            .environmentObject(fixtures.settings)
            .environmentObject(fixtures.bluetooth)
            .environmentObject(fixtures.registry)
            .environmentObject(fixtures.logStore)

        let renderer = ImageRenderer(content: view.frame(width: 390, height: 844))
        renderer.scale = 2
        let image = renderer.uiImage
        XCTAssertNotNil(image)
        if let image {
            let attachment = XCTAttachment(image: image)
            attachment.name = "MeasureView-Light"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testMeasureViewAccessibilitySnapshotRenders() {
        let fixtures = MeasureViewPreviewFixtures()
        let view = MeasureView()
            .environmentObject(fixtures.viewModel)
            .environmentObject(fixtures.folderBookmark)
            .environmentObject(fixtures.settings)
            .environmentObject(fixtures.bluetooth)
            .environmentObject(fixtures.registry)
            .environmentObject(fixtures.logStore)
            .environment(\.dynamicTypeSize, .accessibility3)
            .preferredColorScheme(.dark)

        let renderer = ImageRenderer(content: view.frame(width: 390, height: 844))
        renderer.scale = 2
        let image = renderer.uiImage
        XCTAssertNotNil(image)
        if let image {
            let attachment = XCTAttachment(image: image)
            attachment.name = "MeasureView-Accessibility"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
