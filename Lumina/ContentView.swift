//
//  ContentView.swift
//  Lumina
//
//  Created by Juyoung Kim on 1/2/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var cameraService = CameraService()
    @State private var currentFrame: CVPixelBuffer?
    @State private var saturation: Float = 1.0
    @State private var grainStrength: Float = 0.0
    
    var body: some View {
        ZStack {
            // Our Metal View fills the screen
            if let frame = currentFrame {
                MetalView(pixelBuffer: frame, saturation: saturation, grainStrength: grainStrength)
                    .edgesIgnoringSafeArea(.all)
            } else {
                Text("Waiting for camera...")
            }

            // Foreground: The UI Controls
            VStack {
                Spacer()
                
                Button(action: {
                    NotificationCenter.default.post(name: NSNotification.Name("CapturePhoto"), object: nil)
                }) {
                    Circle()
                        .strokeBorder(.white, lineWidth: 3)
                        .frame(width: 70, height: 70)
                        .overlay(Circle().fill(.white).padding(6))
                }
                
                // Controls Container
                VStack(alignment: .leading, spacing: 20) {
                    
                    // Saturation Control
                    VStack(alignment: .leading) {
                        Text("Saturation: \(String(format: "%.1f", saturation))")
                            .foregroundColor(.yellow)
                            .font(.caption).bold()
                        Slider(value: $saturation, in: 0.0...3.0)
                            .accentColor(.yellow)
                    }
                    
                    // Grain Control
                    VStack(alignment: .leading) {
                        Text("Film Grain: \(String(format: "%.2f", grainStrength))")
                            .foregroundColor(.white) // Use White to differentiate
                            .font(.caption).bold()
                        Slider(value: $grainStrength, in: 0.0...0.5) // 0.5 is usually plenty strong
                            .accentColor(.white)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(15)
                .padding()
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            // Listen to the camera service
            cameraService.onFrameCaptured = { buffer in
                // Update the state so the View re-renders
                self.currentFrame = buffer
            }
        }
    }
}

#Preview {
    ContentView()
}
