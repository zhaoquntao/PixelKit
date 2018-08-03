//
//  HxPxE.swift
//  Hexagon Pixel Engine
//
//  Created by Hexagons on 2018-07-20.
//  Copyright © 2018 Hexagons. All rights reserved.
//

import MetalKit

public class HxPxE {
    
    public static let main = HxPxE()
    
    public var delegate: HxPxEDelegate?
    
    var pixList: [PIX] = []
    
    var _fps: Int = 0
    public var fps: Int { return _fps }
    public var fpxMax: Int { if #available(iOS 10.3, *) { return UIScreen.main.maximumFramesPerSecond } else { return -1 } }
    public var frameIndex = 0
    var frameDate = Date()
    
    public enum BitMode: Int {
        case _8 = 8
        case _16 = 16
        var pixelFormat: MTLPixelFormat {
            switch HxPxE.main.bitMode {
            case ._8:
                return .bgra8Unorm // rgba8Unorm
            case ._16:
                return .rgba16Float
            }
        }
        var cameraPixelFormat: OSType {
            return kCVPixelFormatType_32BGRA
        }
    }
    public var bitMode: BitMode = ._8 // didSet
    
    struct Vertex {
        var x,y: Float
        var s,t: Float
        var buffer: [Float] {
            return [x,y,s,t]
        }
    }
    
    var metalDevice: MTLDevice?
    var commandQueue: MTLCommandQueue?
    var textureCache: CVMetalTextureCache?
    var metalLibrary: MTLLibrary?
    var quadVertexBuffer: MTLBuffer?
    var quadVertexShader: MTLFunction?
    var aLive: Bool {
        guard metalDevice != nil else { return false }
        guard commandQueue != nil else { return false }
        guard textureCache != nil else { return false }
        guard metalLibrary != nil else { return false }
        guard quadVertexBuffer != nil else { return false }
        guard quadVertexShader != nil else { return false }
        return true
    }
    
    var displayLink: CADisplayLink?
    
    public init() {
        
        metalDevice = MTLCreateSystemDefaultDevice()
        if metalDevice == nil {
            print("HxPxE ERROR:", "Metal Device:", "System Default Device not found.")
        } else {
            commandQueue = metalDevice!.makeCommandQueue()
            textureCache = makeTextureCache()
            metalLibrary = loadMetalShaderLibrary()
            if metalLibrary != nil {
                quadVertexBuffer = makeQuadVertexBuffer()
                quadVertexShader = loadQuadVertexShader()
            }
        }
        
        displayLink = CADisplayLink(target: self, selector: #selector(self.displayLinkCallback))
        displayLink!.add(to: RunLoop.main, forMode: .commonModes)
        
        if aLive {
            print("HxPxE is aLive")
        } else {
            print("HxPxE ERROR:", "Not aLive...")
        }
        
    }
    
    // MARK: Add / Remove
    
    func add(pix: PIX) {
        pixList.append(pix)
        pix.view.readyToRender = {
            self.render(pix)
        }
    }
    
    func remove(pix: PIX) {
        for (i, iPix) in pixList.enumerated() {
            if iPix == pix {
                pixList.remove(at: i)
                break
            }
        }
        pix.view.readyToRender = nil
    }
    
    // MARK: Frame Loop
    
    @objc func displayLinkCallback() {
        let frameTime = -frameDate.timeIntervalSinceNow
        _fps = Int(round(1 / frameTime))
        frameDate = Date()
        delegate?.hxpxeFrameLoop()
        checkNeedsRender()
        frameIndex += 1
    }
    
    func checkNeedsRender() {
        for pix in pixList {
            if pix.needsRender {
                pix.view.setNeedsDisplay() // mabey just render() for bg support
                pix.needsRender = false
            }
        }
    }
    
    // MARK: Quad
    
    func makeQuadVertexBuffer() -> MTLBuffer {
        let a = Vertex(x: -1.0, y: -1.0, s: 0.0, t: 1.0)
        let b = Vertex(x: 1.0, y: -1.0, s: 1.0, t: 1.0)
        let c = Vertex(x: -1.0, y: 1.0, s: 0.0, t: 0.0)
        let d = Vertex(x: 1.0, y: 1.0, s: 1.0, t: 0.0)
        let verticesArray: Array<Vertex> = [a,b,c,b,c,d]
        var vertexData = Array<Float>()
        for vertex in verticesArray {
            vertexData += vertex.buffer
        }
        let dataSize = vertexData.count * MemoryLayout.size(ofValue: vertexData[0])
        return metalDevice!.makeBuffer(bytes: vertexData, length: dataSize, options: [])!
    }
    
    func loadQuadVertexShader() -> MTLFunction? {
//        guard let quadVertexShaderSource = loadMetalShaderSource(named: "QuadVTX", fullName: true) else {
//            print("HxPxE ERROR:", "Quad:", "Source not loaded.")
//            return nil
//        }
//        guard let vtxMetalLibrary = try? metalDevice!.makeLibrary(source: quadVertexShaderSource, options: nil) else {
//            print("HxPxE ERROR:", "Quad:", "Library not created.")
//            return nil
//        }
        guard let vtxShader = metalLibrary!.makeFunction(name: "quadVTX") else {
            print("HxPxE ERROR:", "Quad:", "Function not made.")
            return nil
        }
        return vtxShader
    }
    
    // MARK: Cache
    
    func makeTextureCache() -> CVMetalTextureCache? {
        var textureCache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice!, nil, &textureCache) != kCVReturnSuccess {
            print("HxPxE ERROR:", "Cache:", "Creation failed.")
//            fatalError("Unable to allocate texture cache.") // CHECK
            return nil
        } else {
            return textureCache
        }
    }
    
    // MARK: Load Shaders
    
    func loadMetalShaderLibrary() -> MTLLibrary? {
        guard let libraryFile = Bundle(identifier: "se.hexagons.hxpxe")!.path(forResource: "HxPxE_Shaders", ofType: "metallib") else {
            print("HxPxE ERROR:", "Loading Metal Shaders Library:", "Not found.")
            return nil
        }
        do {
            return try metalDevice!.makeLibrary(filepath: libraryFile)
        } catch let error {
            print("HxPxE ERROR:", "Loading Metal Shaders Library:", "Make failed:", error.localizedDescription)
            return nil
        }
    }
    
//    func loadMetalShaderSource(named: String, fullName: Bool = false) -> String? {
//        let shaderFileName = fullName ? named : named.prefix(1).uppercased() + named.dropFirst() + "PIX"
//        print(">>>", shaderFileName)
//        // Bundle(identifier: "se.hexagons.hxpxe")
//        // Bundle(for: type(of: self))
//        // Bundle.main
//        guard let shaderPath = Bundle(identifier: "se.hexagons.hxpxe")!.path(forResource: shaderFileName, ofType: "metal") else {
//            print("HxPxE ERROR:", "Loading Metal Shader:", "Resource not found.")
//            return nil
//        }
//        guard let shaderSource = try? String(contentsOfFile: shaderPath, encoding: .utf8) else {
//            print("HxPxE ERROR:", "Loading Metal Shader:", "Resource corrupt.")
//            return nil
//        }
//        return shaderSource
//    }
    
    // MARK: Shader Pipeline
    
    func makeShaderPipeline(_ fragFuncPrefix: String/*, from source: String*/) -> MTLRenderPipelineState? {
//        var pixMetalLibrary: MTLLibrary? = nil
//        do {
//            pixMetalLibrary = try metalDevice!.makeLibrary(source: source, options: nil)
//        } catch {
//            print("HxPxE ERROR:", "Pipeline:", "PIX Metal Library corrupt:", error.localizedDescription)
//            return nil
//        }
        let fragFuncName = fragFuncPrefix + "PIX"
        guard let fragmentShader = metalLibrary!.makeFunction(name: fragFuncName) else {
            print("HxPxE ERROR:", "Pipeline:", "PIX Metal Function:", "Not found.")
            return nil
        }
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = quadVertexShader!
        pipelineStateDescriptor.fragmentFunction = fragmentShader
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = bitMode.pixelFormat
        pipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .blendAlpha
        do {
            return try metalDevice!.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        } catch {
            print("HxPxE ERROR:", "Pipeline:", "Make failed:", error.localizedDescription)
            return nil
        }
    }
    
    // MARK: Texture
    
    func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTextureOut: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, self.textureCache!, pixelBuffer, nil, HxPxE.main.bitMode.pixelFormat, width, height, 0, &cvTextureOut)
        guard let cvTexture = cvTextureOut, let inputTexture = CVMetalTextureGetTexture(cvTexture) else {
            print("HxPxE ERROR:", "Textrue:", "Creation failed.")
            return nil
        }
        return inputTexture
    }
    
    func copyTexture(from pix: PIX) -> MTLTexture? {
        if pix.texture == nil {
            return nil
        }
        let commandBuffer = commandQueue!.makeCommandBuffer()!
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: bitMode.pixelFormat, width: pix.texture!.width, height: pix.texture!.height, mipmapped: true)
        let textureCopy = metalDevice!.makeTexture(descriptor: descriptor)
        let blitEncoder = commandBuffer.makeBlitCommandEncoder()
        if textureCopy != nil && blitEncoder != nil {
            blitEncoder!.copy(from: pix.texture!, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: pix.texture!.width, height: pix.texture!.height, depth: 1), to: textureCopy!, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blitEncoder!.endEncoding()
            commandBuffer.commit()
            return textureCopy!
        } else {
            blitEncoder?.endEncoding()
            return nil
        }
    }
    
    func raw(texture: MTLTexture) -> Array<float4> {
        let pixelCount = texture.width * texture.height
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        var textureComponentsArray = Array<float4>(repeating: float4(0), count: pixelCount)
        textureComponentsArray.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: (MemoryLayout<float4>.size * texture.width), from: region, mipmapLevel: 0)
        }
        return textureComponentsArray
    }
    
    // MARK: Sampler
    
    func makeSampler(with mode: MTLSamplerAddressMode) -> MTLSamplerState {
        let samplerInfo = MTLSamplerDescriptor()
        samplerInfo.minFilter = .linear
        samplerInfo.magFilter = .linear
        samplerInfo.sAddressMode = mode
        samplerInfo.tAddressMode = mode
        return metalDevice!.makeSamplerState(descriptor: samplerInfo)!
    }
    
    // MARK: Render
    
    func render(_ pix: PIX) {
        
//        if self.pixelBuffer == nil && self.uses_source_texture {
//            AnalyticsAssistant.shared.logError("Render canceled: Source Texture is specified & Pixel Buffer is nil.")
//            return
//        }
        
        // MARK: Command Buffer
        
        guard let commandBuffer = commandQueue!.makeCommandBuffer() else {
            print("HxPxE ERROR:", "Render:", "Command Buffer:", "Make faild.", "PIX:", pix)
            return
        }
        
        // MARK: Input Texture
        
        var inputTexture: MTLTexture? = nil
        if let pixContent = pix as? PIXContent {
            guard let sourceTexture = makeTexture(from: pixContent.contentPixelBuffer!) else {
                print("HxPxE ERROR:", "Render:", "Texture Creation:", "Make faild.", "PIX:", pix)
                return
            }
            inputTexture = sourceTexture
        } else if let pixIn = pix as? PIX & PIXIn {
            let pixOut = pixIn.pixInList!.first!
            guard let pixOutTexture = pixOut.texture else {
                print("HxPxE ERROR:", "Render:", "PIX Out Texture:", "Not found.", "PIX:", pix)
                return
            }
            inputTexture = pixOutTexture // CHECK copy?
        }
        
        // MARK: Custom Render
        
        if pix.customRenderActive {
            guard let customRenderDelegate = pix.customRenderDelegate else {
                print("HxPxE ERROR:", "Render:", "CustomRenderDelegate not implemented.", "PIX:", pix)
                return
            }
            guard let customRenderdTexture = customRenderDelegate.customRender(inputTexture!, with: commandBuffer) else {
                print("HxPxE ERROR:", "Render:", "Custom Render faild.", "PIX:", pix)
                return
            }
            inputTexture = customRenderdTexture
        }
        
        // MARK: Current Drawable
        
        guard let currentDrawable: CAMetalDrawable = pix.view.currentDrawable else {
            print("HxPxE ERROR:", "Render:", "Current Drawable:", "Not found.", "PIX:", pix)
            return
        }
        
        // MARK: Command Encoder
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = currentDrawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            print("HxPxE ERROR:", "Render:", "Command Encoder:", "Make faild.", "PIX:", pix)
            return
        }
        commandEncoder.setRenderPipelineState(pix.pipeline!)
        
        // Wireframe Mode
//        commandEncoder.setTriangleFillMode(.lines)
        
        // MARK: Uniforms
        
        var unifroms: [Float] = pix.shaderUniforms.map { uniform -> Float in return Float(uniform) }
//        if self.shader == "gradient" || self.shader == "circle" || self.shader == "rectangle" || self.shader == "polygon" || self.shader == "noise" || self.shader == "resolution" {
//            unifroms.append(Float(currentDrawable.texture.width) / Float(currentDrawable.texture.height))
//        }
        if !unifroms.isEmpty {
            let uniformBuffer = metalDevice!.makeBuffer(length: MemoryLayout<Float>.size * unifroms.count, options: [])
            let bufferPointer = uniformBuffer?.contents()
            memcpy(bufferPointer, &unifroms, MemoryLayout<Float>.size * unifroms.count)
            commandEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        }
        
        // MARK: Texture
        
        commandEncoder.setFragmentTexture(inputTexture!, index: 0)
        
//        if let texture = sourceTexture ?? blur_texture ?? self.inputTexture {
//
//            if timeMachineTexture3d != nil {
//                commandEncoder!.setFragmentTexture(timeMachineTexture3d!, index: 0)
//            } else {
//                commandEncoder!.setFragmentTexture(texture , index: 0)
//            }
//            if self.secondInputTexture != nil {
//                commandEncoder!.setFragmentTexture(self.secondInputTexture!, index: 1)
//            }
//
//        } else if inputsTexture != nil {
//            commandEncoder!.setFragmentTexture(inputsTexture!, index: 0)
//        }
        
        // MARK: Encode
        
        commandEncoder.setFragmentSamplerState(pix.sampler!, index: 0)
        
        commandEncoder.setVertexBuffer(quadVertexBuffer!, offset: 0, index: 0)
        commandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: 2)
        
        commandEncoder.endEncoding()
        
        // MARK: Render
        
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()

        if commandBuffer.error != nil {
            print("HxPxE ERROR:", "Render:", "Failed:", commandBuffer.error!.localizedDescription)
        }
        
        pix.didRender(texture: currentDrawable.texture)
        
    }
    
}