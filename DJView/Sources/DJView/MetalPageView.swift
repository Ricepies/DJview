import SwiftUI
import MetalKit

public struct MetalPageView: NSViewRepresentable {
    public let rawData: Data?
    public let width: Int
    public let height: Int
    public let shaderMode: ColorShaderMode

    public init(rawData: Data?, width: Int, height: Int, shaderMode: ColorShaderMode) {
        self.rawData = rawData
        self.width = width
        self.height = height
        self.shaderMode = shaderMode
    }

    public class Coordinator {
        var renderer: MetalPageRenderer?
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true

        if let renderer = MetalPageRenderer(metalView: mtkView) {
            context.coordinator.renderer = renderer
            renderer.shaderMode = shaderMode
            if let data = rawData, width > 0, height > 0 {
                renderer.updateTexture(rgbaData: data, width: width, height: height, metalView: mtkView)
            }
        }

        return mtkView
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        renderer.shaderMode = shaderMode
        if let data = rawData, width > 0, height > 0 {
            renderer.updateTexture(rgbaData: data, width: width, height: height, metalView: nsView)
        }
        nsView.needsDisplay = true
    }
}
