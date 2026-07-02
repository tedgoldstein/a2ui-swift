// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#if (canImport(UIKit) && !os(watchOS)) || canImport(AppKit)
import XCTest
import A2UISwiftCore
@testable import A2UIPlatform

private final class MediaURLRecorder: @unchecked Sendable {
    var requests: [(URL, A2UIURLPurpose)] = []
}

final class A2UIMediaPolicyTests: XCTestCase {

    func testPlatformMediaComponentsDelegateURLResolutionToHostServices() throws {
        let recorder = MediaURLRecorder()
        let hostServices = A2UIHostServices(mediaURL: { url, purpose in
            recorder.requests.append((url, purpose))
            throw A2uiExpressionError("Denied by test host.", expression: "url")
        })
        let surface = SurfaceModel(id: "media-policy", hostServices: hostServices)
        try surface.componentsModel.addComponent(ComponentModel(
            id: "root",
            type: "Column",
            properties: ["children": .array([.string("image"), .string("audio"), .string("video")])]
        ))
        try surface.componentsModel.addComponent(ComponentModel(
            id: "image",
            type: "Image",
            properties: ["url": .string("https://media.example/image.png")]
        ))
        try surface.componentsModel.addComponent(ComponentModel(
            id: "audio",
            type: "AudioPlayer",
            properties: ["url": .string("https://media.example/audio.mp3")]
        ))
        try surface.componentsModel.addComponent(ComponentModel(
            id: "video",
            type: "Video",
            properties: ["url": .string("https://media.example/video.mp4")]
        ))

        let host = A2UISurfaceHostView()
        host.render(surface: surface, rootComponentId: "root")

        XCTAssertEqual(recorder.requests.map(\.0.absoluteString), [
            "https://media.example/image.png",
            "https://media.example/audio.mp3",
            "https://media.example/video.mp4",
        ])
        XCTAssertEqual(recorder.requests.map(\.1), [.image, .audio, .video])
    }
}

#endif
