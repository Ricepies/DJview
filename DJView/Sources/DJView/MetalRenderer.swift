import Foundation
import MetalKit
import AppKit

public final class MetalPageRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var samplerState: MTLSamplerState?
    private var texture: MTLTexture?

    public var shaderMode: ColorShaderMode = .normal

    public init?(metalView: MTKView) {
        guard let defaultDevice = MTLCreateSystemDefaultDevice(),
              let queue = defaultDevice.makeCommandQueue() else {
            return nil
        }
        self.device = defaultDevice
        self.commandQueue = queue

        metalView.device = defaultDevice
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = true
        metalView.enableSetNeedsDisplay = false
        metalView.isPaused = false

        super.init()
        metalView.delegate = self
        setupPipeline()
        setupSampler()
    }

    private func setupPipeline() {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex VertexOut vertexShader(uint vertexID [[vertex_id]]) {
            float2 positions[4] = {
                float2(-1.0, -1.0),
                float2( 1.0, -1.0),
                float2(-1.0,  1.0),
                float2( 1.0,  1.0)
            };
            float2 texCoords[4] = {
                float2(0.0, 1.0),
                float2(1.0, 1.0),
                float2(0.0, 0.0),
                float2(1.0, 0.0)
            };

            VertexOut out;
            out.position = float4(positions[vertexID], 0.0, 1.0);
            out.texCoord = texCoords[vertexID];
            return out;
        }

        fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                     texture2d<float> colorTexture [[texture(0)]],
                                     sampler textureSampler [[sampler(0)]],
                                     constant int& mode [[buffer(0)]]) {
            float4 color = colorTexture.sample(textureSampler, in.texCoord);

            if (mode == 1) {
                // Invert (Dark Mode)
                return float4(1.0 - color.r, 1.0 - color.g, 1.0 - color.b, color.a);
            } else if (mode == 2) {
                // Sepia
                float r = (color.r * 0.393) + (color.g * 0.769) + (color.b * 0.189);
                float g = (color.r * 0.349) + (color.g * 0.686) + (color.b * 0.168);
                float b = (color.r * 0.272) + (color.g * 0.534) + (color.b * 0.131);
                return float4(clamp(r, 0.0, 1.0), clamp(g, 0.0, 1.0), clamp(b, 0.0, 1.0), color.a);
            } else if (mode == 3) {
                // Grayscale
                float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));
                return float4(gray, gray, gray, color.a);
            } else if (mode == 4) {
                // High Contrast
                float3 centered = color.rgb - 0.5;
                float3 contrast = clamp(centered * 1.5 + 0.5, 0.0, 1.0);
                return float4(contrast, color.a);
            }

            return color;
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunction = library.makeFunction(name: "vertexShader")
            let fragmentFunction = library.makeFunction(name: "fragmentShader")

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create Metal pipeline state: \(error)")
        }
    }

    private func setupSampler() {
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        self.samplerState = device.makeSamplerState(descriptor: samplerDesc)
    }

    public func updateTexture(rgbaData: Data, width: Int, height: Int) {
        guard width > 0 && height > 0 else { return }

        if let tex = texture, tex.width == width && tex.height == height {
            rgbaData.withUnsafeBytes { ptr in
                if let baseAddress = ptr.baseAddress {
                    tex.replace(
                        region: MTLRegionMake2D(0, 0, width, height),
                        mipmapLevel: 0,
                        withBytes: baseAddress,
                        bytesPerRow: width * 4
                    )
                }
            }
            return
        }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]
        textureDescriptor.storageMode = .shared // Apple Silicon Zero-Copy Unified Memory

        guard let newTexture = device.makeTexture(descriptor: textureDescriptor) else { return }

        rgbaData.withUnsafeBytes { ptr in
            if let baseAddress = ptr.baseAddress {
                newTexture.replace(
                    region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0,
                    withBytes: baseAddress,
                    bytesPerRow: width * 4
                )
            }
        }

        self.texture = newTexture
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let pipelineState = pipelineState,
              let samplerState = samplerState,
              let texture = texture,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)

        var modeValue: Int32 = 0
        switch shaderMode {
        case .normal: modeValue = 0
        case .invert: modeValue = 1
        case .sepia: modeValue = 2
        case .grayscale: modeValue = 3
        case .highContrast: modeValue = 4
        }

        encoder.setFragmentBytes(&modeValue, length: MemoryLayout<Int32>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
