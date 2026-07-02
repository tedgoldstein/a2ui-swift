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

import Testing
import SwiftUI
import A2UISwiftCore
import A2UISwiftUI

private final class SwiftUIMediaURLRecorder: @unchecked Sendable {
    var requests: [(URL, A2UIURLPurpose)] = []
}

@Suite("SwiftUI media policy")
struct SwiftUIMediaPolicyTests {
    @MainActor
    @Test("Image rendering delegates media URL resolution to host services")
    func imageRenderingDelegatesMediaURLResolution() throws {
        let recorder = SwiftUIMediaURLRecorder()
        let hostServices = A2UIHostServices(mediaURL: { url, purpose in
            recorder.requests.append((url, purpose))
            throw A2uiExpressionError("Denied by test host.", expression: "url")
        })
        let surface = SurfaceModel(id: "swiftui-media", catalog: Catalog(id: "test"), hostServices: hostServices)
        let vm = SurfaceViewModel(surface: surface)
        try vm.processMessage(.updateComponents(UpdateComponentsPayload(
            surfaceId: surface.id,
            components: [
                RawComponent(
                    id: "root",
                    component: "Image",
                    properties: ["url": .string("https://media.example/image.png")]
                ),
            ]
        )))

        let view = A2UISurfaceView(viewModel: vm, scrolls: false)
            .frame(width: 120, height: 120)
        let renderer = ImageRenderer(content: view)
        _ = renderer.cgImage

        #expect(recorder.requests.map(\.0.absoluteString) == ["https://media.example/image.png"])
        #expect(recorder.requests.map(\.1) == [.image])
    }
}
