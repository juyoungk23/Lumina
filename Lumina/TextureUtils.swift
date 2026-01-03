//
//  TextureUtils.swift
//  Lumina
//
//  Created by Juyoung Kim on 1/2/26.
//

import MetalKit
import CoreImage

class TextureUtils {
    // A shared context for reuse (creating this is expensive, so we keep one)
    static let context = CIContext()
    
    static func toUIImage(texture: MTLTexture, orientation: UIImage.Orientation) -> UIImage? {
        // 1. Create a CIImage from the Metal Texture
        // We tell it the color space is generic RGB so colors look right
        guard let ciImage = CIImage(mtlTexture: texture, options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]) else {
            return nil
        }
        
        // 2. Flip it? (Metal textures are often upside down compared to UIKit)
        // Usually CIImage handles this, but if your photo comes out upside down, flip it here.
        let orientedImage = ciImage.oriented(forExifOrientation: 1)
        
        // 3. Render to CGImage (The raw bitmap data)
        guard let cgImage = context.createCGImage(orientedImage, from: orientedImage.extent) else {
            return nil
        }
        
        // 4. Convert to UIImage with the correct orientation and scale
        // scale: 1.0 is standard. orientation: passed in from Renderer.
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
    }
}
