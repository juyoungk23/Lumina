//
//  Renderer.swift
//  Lumina
//
//  Created by Juyoung Kim on 1/2/26.
//

import MetalKit
import CoreVideo
import Photos
import CoreImage

class Renderer: NSObject, MTKViewDelegate {
    
    var parent: MetalView
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    
    // State variables
    var rotationAngle: Float = 0.0
    var scale: SIMD2<Float> = SIMD2<Float>(1.0, 1.0) // <--- New Scale State (Vector)
    var saturation: Float = 1.0
    var grainStrength: Float = 0.0 // NEW
    var time: Float = 0.0          // NEW (for animation)
    
    // 1. Pipeline State: Holds our compiled shader info
    var renderPipelineState: MTLRenderPipelineState?
    
    // 2. Texture Cache: An optimized way to convert Camera -> Metal
    var textureCache: CVMetalTextureCache?
    
    // 3. The current frame to draw
    var currentTexture: MTLTexture?
    
    init(_ parent: MetalView) {
        self.parent = parent
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device.makeCommandQueue()
        super.init()
        
        // Improve orientation handling
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        
        setupPipeline()
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        
        // Listen for the button press
        NotificationCenter.default.addObserver(forName: NSNotification.Name("CapturePhoto"), object: nil, queue: .main) { _ in
            self.capturePhoto()
        }
    }
    
    deinit {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
    
    func setupPipeline() {
        guard let library = device.makeDefaultLibrary() else { return }
        let vertexFunction = library.makeFunction(name: "vertexShader")
        let fragmentFunction = library.makeFunction(name: "fragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }
    
    // 4. This is the function the CameraService will call!
    func updateTexture(from pixelBuffer: CVPixelBuffer) {
        guard let textureCache = textureCache else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTextureOut: CVMetalTexture?
        
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTextureOut
        )
        
        if result == kCVReturnSuccess, let cvTexture = cvTextureOut {
            self.currentTexture = CVMetalTextureGetTexture(cvTexture)
        }
    }
    
    // Add this variable to remember the last VALID orientation
    var lastOrientation: UIDeviceOrientation = .portrait

    func updateRotation() {
        let currentOrientation = UIDevice.current.orientation
        
        // FIX: Ignore "Flat", "FaceUp", "Unknown" states.
        // If we hit those, keep using the last good orientation.
        if currentOrientation.isValidInterfaceOrientation {
            lastOrientation = currentOrientation
        }
        
        switch lastOrientation {
        case .portrait:
            rotationAngle = Float.pi / 2.0
        case .portraitUpsideDown:
            rotationAngle = -Float.pi / 2.0
        case .landscapeLeft:
            rotationAngle = 0
        case .landscapeRight:
            rotationAngle = Float.pi
        default:
            rotationAngle = Float.pi / 2.0
        }
    }
    
    func updateScale(viewSize: CGSize, texture: MTLTexture) {
        // Video dimensions (Usually 1920 x 1080)
        let vidWidth = Float(texture.width)
        let vidHeight = Float(texture.height)
        
        // Screen dimensions
        let screenWidth = Float(viewSize.width)
        let screenHeight = Float(viewSize.height)
        
        // Check if we are rotated (Portrait/PortraitUpsideDown)
        // 90 degrees or -90 degrees (pi/2)
        let isRotated = abs(rotationAngle - Float.pi/2.0) < 0.1 || abs(rotationAngle + Float.pi/2.0) < 0.1
        
        // If rotated, the "Effective" video dimensions are swapped
        let effectiveVidWidth = isRotated ? vidHeight : vidWidth
        let effectiveVidHeight = isRotated ? vidWidth : vidHeight
        
        let vidAspect = effectiveVidWidth / effectiveVidHeight
        let screenAspect = screenWidth / screenHeight
        
        // Aspect Fill Logic:
        // We want to scale the quad so it is larger than or equal to the screen in both dimensions
        // while maintaining the video aspect ratio.
        
        // Start with 1.0 scale (fills screen but stretched)
        var sx: Float = 1.0
        var sy: Float = 1.0
        
        // If we simply map Texture(Effective) -> Screen, the aspect ratio distortion is:
        // Screen is unit square in clip space.
        // We want effective image aspect `vidAspect` to appear correct on `screenAspect`.
        // The ratio of distortion is `vidAspect / screenAspect`.
        
        if vidAspect > screenAspect {
            // Video is wider than screen (e.g. 1.77 vs 0.56)
            // We need to scale X up to "crop" the sides, so height fits.
            // Wait, if we scale X up, we lose width info?
            // If we fit height (sy = 1.0), we must scale X so that aspect is correct.
            // visual_aspect = (sx * screenWidth) / (sy * screenHeight) = vidAspect
            // sx / sy * screenAspect = vidAspect
            // sx / sy = vidAspect / screenAspect
            // If sy = 1.0, sx = vidAspect / screenAspect
            
            // Wait, let's verify.
            // If vidAspect (1.77) > screenAspect (0.56).
            // sx = 1.77 / 0.56 = 3.16.
            // sy = 1.0.
            // Code scales quad X by 3.16. Y by 1.
            // Result: Wide but correct height. Sides cropped. Aspect ratio correct.
            
            sx = vidAspect / screenAspect
            sy = 1.0
        } else {
            // Video is taller/thinner than screen
            // We need to scale Y up to crop top/bottom.
            // Fit Width (sx = 1.0).
            // sy = sa / va ?
            // sx/sy = va/sa => 1/sy = va/sa => sy = sa/va
            
            sx = 1.0
            sy = screenAspect / vidAspect
        }
        
        scale = SIMD2<Float>(sx, sy)
    }
    
    // Call this from SwiftUI
    func capturePhoto() {
        guard let device = device,
              let commandQueue = commandQueue,
              let sourceTexture = currentTexture,
              let pipelineState = renderPipelineState else { return }
        
        print("Capturing Photo...")

        // 1. Create a Destination Texture (The "Canvas")
        // We make it the same size as the camera input
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: sourceTexture.width,
            height: sourceTexture.height,
            mipmapped: false
        )
        // We need to allow "RenderTarget" (drawing to it) and "ShaderRead" (reading from it)
        descriptor.usage = [.renderTarget, .shaderRead]
        
        guard let destinationTexture = device.makeTexture(descriptor: descriptor) else { return }
        
        // 2. Create a Render Pass (The "Instructions")
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = destinationTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        // 3. Create the Command Buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        
        // 4. Configure the Pipeline (Exactly like draw()!)
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFragmentTexture(sourceTexture, index: 0)
        
        // Send our uniforms
        // Note: For a photo, we typically want Rotation 0 (stored upright)
        // or we match the screen. Let's force it upright (0) for now.
        var photoRotation: Float = 0
        // Important: We need a "Photo Scale" which is usually 1.0 (Full Size)
        var photoScale = SIMD2<Float>(1.0, 1.0)
        
        
        renderEncoder.setVertexBytes(&photoRotation, length: MemoryLayout<Float>.size, index: 1)
        renderEncoder.setVertexBytes(&photoScale, length: MemoryLayout<SIMD2<Float>>.size, index: 2)
        renderEncoder.setFragmentBytes(&saturation, length: MemoryLayout<Float>.size, index: 0)
        renderEncoder.setFragmentBytes(&grainStrength, length: MemoryLayout<Float>.size, index: 1)
        renderEncoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 2)
        
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        // 5. Commit and Wait
        // We add a "Completion Block" to run when the GPU finishes
        commandBuffer.addCompletedHandler { buffer in
            // GPU is done! Now we are back on CPU.
            
            // Determine the correct orientation tag for the UIImage
            // User requested "Reverse Mirror" (so we use .mirrored variants to flip it back)
            // User reported Landscape was Upside Down (so we swap .up/.down)
            var imageOrientation: UIImage.Orientation = .rightMirrored // Default
            
            switch self.lastOrientation {
            case .portrait:
                imageOrientation = .leftMirrored
            case .portraitUpsideDown:
                imageOrientation = .rightMirrored
            case .landscapeLeft:
                imageOrientation = .downMirrored
            case .landscapeRight:
                imageOrientation = .upMirrored
            default:
                imageOrientation = .leftMirrored
            }
            
            // Convert to UIImage
            if let image = TextureUtils.toUIImage(texture: destinationTexture, orientation: imageOrientation) {
                self.saveToLibrary(image: image)
            }
        }
        
        commandBuffer.commit()
    }

    private func saveToLibrary(image: UIImage) {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized || status == .limited {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { success, error in
                    if success {
                        print("Success! Photo saved to library.")
                    } else {
                        print("Error saving photo: \(String(describing: error))")
                    }
                }
            }
        }
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let pipelineState = renderPipelineState,
              let texture = currentTexture else {
            return
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()
        time += 0.01

        updateRotation()
        // Calculate scale based on current view size
        updateScale(viewSize: view.drawableSize, texture: texture)
        
        let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        renderEncoder?.setRenderPipelineState(pipelineState)
        renderEncoder?.setFragmentTexture(texture, index: 0)
        
        renderEncoder?.setVertexBytes(&rotationAngle, length: MemoryLayout<Float>.size, index: 1)
        renderEncoder?.setVertexBytes(&scale, length: MemoryLayout<SIMD2<Float>>.size, index: 2)
        renderEncoder?.setFragmentBytes(&saturation, length: MemoryLayout<Float>.size, index: 0)
        renderEncoder?.setFragmentBytes(&grainStrength, length: MemoryLayout<Float>.size, index: 1)
        renderEncoder?.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 2)
        
        renderEncoder?.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        renderEncoder?.endEncoding()
        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    
}

extension UIDeviceOrientation {
    var isValidInterfaceOrientation: Bool {
        return self == .portrait || self == .landscapeLeft || self == .landscapeRight
    }
}
