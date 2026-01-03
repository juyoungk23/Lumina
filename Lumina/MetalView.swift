//
//  MetalView.swift
//  Lumina
//
//  Created by Juyoung Kim on 1/2/26.
//

import SwiftUI
import MetalKit

struct MetalView: UIViewRepresentable {
    
    // We create a binding so ContentView can pass the pixel buffer here
    var pixelBuffer: CVPixelBuffer?
    var saturation: Float
    var grainStrength: Float
    
    func makeCoordinator() -> Renderer {
        Renderer(self)
    }
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.framebufferOnly = false // Allow us to write textures
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.saturation = saturation
        context.coordinator.grainStrength = grainStrength
        // Whenever SwiftUI detects a new pixelBuffer, send it to the Renderer
        if let buffer = pixelBuffer {
            context.coordinator.updateTexture(from: buffer)
        }
    }
}
