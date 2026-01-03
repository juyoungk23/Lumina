//
//  CameraService.swift
//  Lumina
//
//  Created by Juyoung Kim on 1/2/26.
//

import AVFoundation
import UIKit
import Combine

// 1. This class manages the camera session
class CameraService: NSObject, ObservableObject {
    
    // The "Session" is the manager that coordinates data flow
    let session = AVCaptureSession()
    
    // We need a dedicated background queue so camera processing
    // doesn't freeze the UI (Main Thread)
    private let queue = DispatchQueue(label: "camera.queue")
    
    // This closure (callback) will send the pixel buffer to our Metal Renderer later
    var onFrameCaptured: ((CVPixelBuffer) -> Void)?
    
    override init() {
        super.init()
        // We start permission check immediately
        checkPermissions()
    }
    
    // 2. Check if we are allowed to use the camera
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            // Ask for permission
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.setupCamera() }
            }
        case .authorized:
            self.setupCamera()
        default:
            print("Camera permission denied.")
        }
    }
    
    // 3. Set up the Inputs and Outputs
    func setupCamera() {
        session.beginConfiguration()
        
        // A. Setup Input (The Physical Camera)
        // We want the wide angle camera on the back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        // B. Setup Output (The Data Stream)
        let output = AVCaptureVideoDataOutput()
        
        // CRITICAL: We drop frames if the engine is too slow, otherwise memory explodes
        output.alwaysDiscardsLateVideoFrames = true
        
        // CRITICAL: We request BGRA format (Blue, Green, Red, Alpha)
        // This is the format Metal prefers for textures
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        // Set 'self' as the delegate to receive the data on our background queue
        output.setSampleBufferDelegate(self, queue: queue)
        
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        
        session.commitConfiguration()
        
        // Start the flow of data
        Task(priority: .background) {
            self.session.startRunning()
        }
    }
}

// 4. Handle the Data Stream
extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // This function is called ~60 times per second!
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // Extract the raw pixel data from the safe wrapper
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Send it to whoever is listening (Our Metal Renderer will listen here later)
        onFrameCaptured?(pixelBuffer)
    }
}
