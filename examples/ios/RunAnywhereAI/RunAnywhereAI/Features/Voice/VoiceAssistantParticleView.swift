import SwiftUI
import MetalKit
import Metal
import Combine

// MARK: - Metal Shader with Localized Touch Scatter
private let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float3 position [[attribute(0)]];
    float index [[attribute(1)]];
    float radiusOffset [[attribute(2)]];
    float seed [[attribute(3)]];
};

struct VertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float3 color;
    float alpha;
};

struct Uniforms {
    float time;
    float aspectRatio;
    float amplitude;
    float morphProgress;
    float scatterAmount;
    float2 touchPoint;    // Normalized touch position (-1 to 1)
    float3 baseColor;
    float isDarkMode;     // 1.0 for dark, 0.0 for light
};

float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

float noise(float3 x) {
    float3 p = floor(x);
    float3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float n = p.x + p.y * 57.0 + 113.0 * p.z;
    return mix(mix(mix(hash(n), hash(n + 1.0), f.x),
                   mix(hash(n + 57.0), hash(n + 58.0), f.x), f.y),
               mix(mix(hash(n + 113.0), hash(n + 114.0), f.x),
                   mix(hash(n + 170.0), hash(n + 171.0), f.x), f.y), f.z);
}

vertex VertexOut vertexShader(const device Vertex* vertices [[buffer(0)]],
                              constant Uniforms& u [[buffer(1)]],
                              uint vid [[vertex_id]]) {
    VertexOut out;

    Vertex v = vertices[vid];
    float3 spherePos = v.position;
    float t = u.time;
    float morph = u.morphProgress;
    float seed = v.seed;

    // === SPHERE STATE ===
    float sphereAngle = -t * 0.2;
    float cosA = cos(sphereAngle);
    float sinA = sin(sphereAngle);

    float3 rotatedSphere;
    rotatedSphere.x = spherePos.x * cosA - spherePos.z * sinA;
    rotatedSphere.y = spherePos.y;
    rotatedSphere.z = spherePos.x * sinA + spherePos.z * cosA;

    float sphereBreath = 1.0 + sin(t * 1.0) * 0.025;
    rotatedSphere *= sphereBreath;

    // === RING STATE ===
    float ringAngle = v.index * 3.14159 * 2.0 + t * 0.25;
    float baseRingRadius = 1.3;
    float audioPulse = u.amplitude * 0.4;
    float ringRadius = baseRingRadius + audioPulse + sin(t * 1.5) * 0.03;
    ringRadius += v.radiusOffset * 0.18;

    float3 ringPos;
    ringPos.x = cos(ringAngle) * ringRadius;
    ringPos.y = sin(ringAngle) * ringRadius;
    ringPos.z = 0.0;

    // === MORPH ===
    float personalSpeed = 0.6 + seed * 0.8;
    float personalMorph = clamp(morph * personalSpeed + (seed - 0.5) * 0.3, 0.0, 1.0);
    float smoothMorph = personalMorph * personalMorph * (3.0 - 2.0 * personalMorph);
    smoothMorph = smoothMorph * smoothMorph * (3.0 - 2.0 * smoothMorph);

    float wanderPhase = morph * (1.0 - morph) * 4.0;

    float3 wander;
    wander.x = noise(float3(seed * 100.0, t * 0.3, 0.0)) - 0.5;
    wander.y = noise(float3(seed * 100.0 + 50.0, t * 0.3, 0.0)) - 0.5;
    wander.z = noise(float3(seed * 100.0 + 100.0, t * 0.3, 0.0)) - 0.5;
    wander *= wanderPhase * 0.6;

    float spiralAngle = seed * 6.28 + t * 0.5;
    float spiralRadius = wanderPhase * 0.25;
    float3 spiral = float3(cos(spiralAngle) * spiralRadius, sin(spiralAngle) * spiralRadius, 0.0);

    float3 basePos = mix(rotatedSphere, ringPos, smoothMorph);
    float3 morphedPos = basePos + wander + spiral;

    // === LOCALIZED TOUCH SCATTER ===
    // Calculate screen position of this particle (matching touch coordinate system)
    float scale = 0.85;
    float tempZ = morphedPos.z + 2.5;
    float2 screenPos;
    screenPos.x = (morphedPos.x / tempZ) * scale;
    screenPos.y = (morphedPos.y / tempZ) * scale; // No aspect ratio here - touch coords are square

    // Distance from touch point
    float touchDist = length(screenPos - u.touchPoint);

    // Only affect particles near touch (radius ~0.3 in screen space)
    float touchRadius = 0.35;
    float touchInfluence = 1.0 - smoothstep(0.0, touchRadius, touchDist);
    touchInfluence *= u.scatterAmount;

    // Gentle outward push from touch point
    float2 pushDir = normalize(screenPos - u.touchPoint + 0.001);
    float pushAmount = touchInfluence * 0.15; // Subtle push

    morphedPos.x += pushDir.x * pushAmount;
    morphedPos.y += pushDir.y * pushAmount;

    // Tiny random jitter for organic feel
    morphedPos.x += (noise(float3(seed * 200.0, t * 2.0, 0.0)) - 0.5) * touchInfluence * 0.08;
    morphedPos.y += (noise(float3(seed * 200.0 + 100.0, t * 2.0, 0.0)) - 0.5) * touchInfluence * 0.08;

    float3 finalPos = morphedPos;

    // === PROJECTION ===
    float z = finalPos.z + 2.5;

    out.position.x = (finalPos.x / z) * scale;
    out.position.y = (finalPos.y / z) * scale * u.aspectRatio;
    out.position.z = 0.0;
    out.position.w = 1.0;

    // Size
    float baseSize = 7.0;
    float transitionGlow = 1.0 + wanderPhase * 0.4;
    out.pointSize = baseSize * (2.8 / z) * transitionGlow;
    out.pointSize *= (1.0 + touchInfluence * 0.3); // Slight size boost on touch
    out.pointSize = clamp(out.pointSize, 4.0, 14.0);

    // Color - Vibrant gold-orange dust (bright and luminous)
    float energy = smoothMorph * (0.5 + u.amplitude * 0.5);
    // Active: warm amber-orange
    float3 activeColor = float3(1.0, 0.55, 0.15); // Warm amber
    out.color = mix(u.baseColor, activeColor, energy);

    // Light mode: moderate brightness for rich saturated color, Dark mode: standard brightness
    float brightMultiplier = u.isDarkMode > 0.5 ? (1.5 + energy * 0.5) : (2.2 + energy * 0.6);
    out.color *= (brightMultiplier + touchInfluence * 0.3);

    // Full alpha for both modes for solid appearance
    float depthShade = 0.5 + 0.5 * (1.0 - (z - 1.8) / 2.0);
    float baseAlpha = 1.0;
    out.alpha = mix(depthShade * 0.8, baseAlpha, smoothMorph);

    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               float2 pointCoord [[point_coord]]) {
    float dist = length(pointCoord - 0.5) * 2.0;
    if (dist > 1.0) discard_fragment();

    float core = 1.0 - smoothstep(0.0, 0.4, dist);
    float glow = 1.0 - smoothstep(0.2, 1.0, dist);
    float alpha = core * 0.8 + glow * 0.4;

    float3 color = in.color * (0.7 + core * 0.3);

    return float4(color * alpha, alpha * in.alpha);
}
"""

// MARK: - Vertex Structure
private struct ParticleVertex {
    var position: SIMD3<Float>
    var index: Float
    var radiusOffset: Float
    var seed: Float
}

// MARK: - Uniforms
private struct ShaderUniforms {
    var time: Float
    var aspectRatio: Float
    var amplitude: Float
    var morphProgress: Float
    var scatterAmount: Float
    var touchPoint: SIMD2<Float>
    var baseColor: SIMD3<Float>
    var isDarkMode: Float
}

// MARK: - Renderer
final class SphereRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?

    private let startTime = Date()
    private let particleCount = 2000

    var amplitude: Float = 0.0
    var morphProgress: Float = 0.0
    var scatterAmount: Float = 0.0
    var touchPoint: SIMD2<Float> = .zero
    var isDarkMode: Bool = true
    // Vibrant logo orange - brighter and more saturated
    var baseColor: SIMD3<Float> = SIMD3<Float>(1.0, 0.5, 0.15) // Bright vivid orange
    private var aspectRatio: Float = 1.0

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        super.init()

        setupPipeline()
        generateParticles()
    }

    private func setupPipeline() {
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)

            let vertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].format = .float3
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            vertexDescriptor.attributes[1].format = .float
            vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
            vertexDescriptor.attributes[1].bufferIndex = 0
            vertexDescriptor.attributes[2].format = .float
            vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<Float>.stride
            vertexDescriptor.attributes[2].bufferIndex = 0
            vertexDescriptor.attributes[3].format = .float
            vertexDescriptor.attributes[3].offset = MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<Float>.stride * 2
            vertexDescriptor.attributes[3].bufferIndex = 0
            vertexDescriptor.layouts[0].stride = MemoryLayout<ParticleVertex>.stride

            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "vertexShader")
            desc.fragmentFunction = library.makeFunction(name: "fragmentShader")
            desc.vertexDescriptor = vertexDescriptor
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm

            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].rgbBlendOperation = .add
            desc.colorAttachments[0].alphaBlendOperation = .add
            desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            desc.colorAttachments[0].sourceAlphaBlendFactor = .one
            desc.colorAttachments[0].destinationRGBBlendFactor = .one
            desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("Pipeline error: \(error)")
        }
    }

    private func generateParticles() {
        var vertices: [ParticleVertex] = []

        let goldenRatio = (1.0 + sqrt(5.0)) / 2.0
        let angleIncrement = Float.pi * 2.0 * Float(goldenRatio)

        for i in 0..<particleCount {
            let t = Float(i) / Float(particleCount - 1)
            let inclination = acos(1.0 - 2.0 * t)
            let azimuth = angleIncrement * Float(i)

            let x = sin(inclination) * cos(azimuth)
            let y = sin(inclination) * sin(azimuth)
            let z = cos(inclination)

            let index = Float(i) / Float(particleCount)
            let radiusOffset = Float.random(in: -1.0...1.0)
            let seed = Float.random(in: 0.0...1.0)

            vertices.append(ParticleVertex(
                position: SIMD3<Float>(x, y, z),
                index: index,
                radiusOffset: radiusOffset,
                seed: seed
            ))
        }

        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<ParticleVertex>.stride,
            options: .storageModeShared
        )
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        aspectRatio = Float(size.width / size.height)
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let pipelineState = pipelineState,
              let vertexBuffer = vertexBuffer else { return }

        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        let time = Float(Date().timeIntervalSince(startTime))

        var uniforms = ShaderUniforms(
            time: time,
            aspectRatio: aspectRatio,
            amplitude: amplitude,
            morphProgress: morphProgress,
            scatterAmount: scatterAmount,
            touchPoint: touchPoint,
            // Light mode: darker/richer orange for saturation, Dark mode: brighter golden
            baseColor: isDarkMode ? SIMD3<Float>(1.0, 0.6, 0.1) : SIMD3<Float>(0.9, 0.4, 0.05),
            isDarkMode: isDarkMode ? 1.0 : 0.0
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: - SwiftUI View
#if os(iOS)
struct VoiceAssistantParticleView: UIViewRepresentable {
    var amplitude: Float
    var morphProgress: Float
    var scatterAmount: Float
    var touchPoint: SIMD2<Float>
    var isDarkMode: Bool

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.isOpaque = false
        view.layer.isOpaque = false
        view.backgroundColor = .clear

        if let device = view.device {
            context.coordinator.renderer = SphereRenderer(device: device)
            view.delegate = context.coordinator.renderer
        }

        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer?.amplitude = amplitude
        context.coordinator.renderer?.morphProgress = morphProgress
        context.coordinator.renderer?.scatterAmount = scatterAmount
        context.coordinator.renderer?.touchPoint = touchPoint
        context.coordinator.renderer?.isDarkMode = isDarkMode
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var renderer: SphereRenderer?
    }
}
#elseif os(macOS)
struct VoiceAssistantParticleView: NSViewRepresentable {
    var amplitude: Float
    var morphProgress: Float
    var scatterAmount: Float
    var touchPoint: SIMD2<Float>
    var isDarkMode: Bool

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.layer?.isOpaque = false

        if let device = view.device {
            context.coordinator.renderer = SphereRenderer(device: device)
            view.delegate = context.coordinator.renderer
        }

        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer?.amplitude = amplitude
        context.coordinator.renderer?.morphProgress = morphProgress
        context.coordinator.renderer?.scatterAmount = scatterAmount
        context.coordinator.renderer?.touchPoint = touchPoint
        context.coordinator.renderer?.isDarkMode = isDarkMode
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var renderer: SphereRenderer?
    }
}
#endif

// MARK: - Preview
struct VoiceAssistantMainPreview: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var amplitude: Float = 0.0
    @State private var isListening = false
    @State private var morphProgress: Float = 0.0
    @State private var scatterAmount: Float = 0.0
    @State private var touchPoint: SIMD2<Float> = .zero

    private let timer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()

    // Logo colors
    private let logoOrange = Color(red: 1.0, green: 0.42, blue: 0.21)  // #FF6B35
    private let logoCoral = Color(red: 1.0, green: 0.27, blue: 0.27)   // #FF4444

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Adaptive background
                (colorScheme == .dark ? Color.black : Color.white)
                    .ignoresSafeArea()

                // ✨ Magical multi-layer ambient glow

                // Layer 1: Deep inner glow (warm amber core)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.6, blue: 0.2).opacity(colorScheme == .dark ? 0.15 : 0.08),
                                Color(red: 1.0, green: 0.4, blue: 0.1).opacity(colorScheme == .dark ? 0.08 : 0.04),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 30,
                            endRadius: 120
                        )
                    )
                    .frame(width: 300, height: 300)
                    .blur(radius: 25)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                // Layer 2: Middle magical shimmer (golden dust halo)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.75, blue: 0.3).opacity(colorScheme == .dark ? Double(0.06 + morphProgress * 0.08) : Double(0.03 + morphProgress * 0.04)),
                                Color(red: 1.0, green: 0.5, blue: 0.15).opacity(colorScheme == .dark ? 0.04 : 0.02),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 80,
                            endRadius: 180
                        )
                    )
                    .frame(width: 400, height: 400)
                    .blur(radius: 35)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                // Layer 3: Outer subtle magic (rose-gold edge for mystical feel)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.clear,
                                Color(red: 1.0, green: 0.6, blue: 0.5).opacity(colorScheme == .dark ? Double(0.02 + morphProgress * 0.03) : 0.01),
                                Color(red: 0.95, green: 0.5, blue: 0.4).opacity(colorScheme == .dark ? 0.015 : 0.008),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 100,
                            endRadius: 250
                        )
                    )
                    .frame(width: 500, height: 500)
                    .blur(radius: 50)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)


                // Particle view - explicitly centered
                VoiceAssistantParticleView(
                    amplitude: amplitude,
                    morphProgress: morphProgress,
                    scatterAmount: scatterAmount,
                    touchPoint: touchPoint,
                    isDarkMode: colorScheme == .dark
                )
                .frame(width: 500, height: 500)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // Convert touch to normalized coordinates (-1 to 1)
                            // Frame is 500x500 centered in geometry
                            let frameSize: CGFloat = 500
                            let frameCenterX = geometry.size.width / 2
                            let frameCenterY = geometry.size.height / 2

                            // Position relative to frame center, normalized to -1...1
                            let normalizedX = Float((value.location.x - frameCenterX) / (frameSize / 2)) * 0.85
                            let normalizedY = Float((value.location.y - frameCenterY) / (frameSize / 2)) * -0.85 // Flip Y, apply scale

                            touchPoint = SIMD2<Float>(normalizedX, normalizedY)
                            scatterAmount = 1.0
                        }
                        .onEnded { _ in
                            // Let it fade naturally
                        }
                )

                // Controls
                VStack {
                    Spacer()

                    Text(isListening ? "Listening..." : "Touch to interact")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.bottom, 16)

                    Button(action: {
                        isListening.toggle()
                    }) {
                        ZStack {
                            if isListening {
                                Circle()
                                    .fill(Color.orange.opacity(0.25))
                                    .frame(width: 80, height: 80)
                                    .blur(radius: 12)
                            }

                            Circle()
                                .fill(Color.white.opacity(isListening ? 0.15 : 0.1))
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Image(systemName: isListening ? "waveform" : "mic.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(.white)
                                )
                        }
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .onReceive(timer) { _ in
            // Morph animation
            let targetMorph: Float = isListening ? 1.0 : 0.0
            let morphDiff = targetMorph - morphProgress
            morphProgress += morphDiff * 0.04
            morphProgress = max(0, min(1, morphProgress))

            // Gentle scatter decay
            if scatterAmount > 0.001 {
                scatterAmount *= 0.92
            } else {
                scatterAmount = 0
            }

            // Audio
            if isListening {
                let base: Float = 0.3
                let wave = sin(Float(Date().timeIntervalSince1970) * 5.0) * 0.2
                let random = Float.random(in: 0...0.2)
                amplitude = amplitude * 0.8 + (base + abs(wave) + random) * 0.2
            } else {
                amplitude = amplitude * 0.95
            }
        }
    }
}

#Preview {
    VoiceAssistantMainPreview()
}
