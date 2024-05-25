//
//  HDRZebraFilter.swift
//  ntsc-mtl-demo
//
//  Created by Jeffrey Blagdon on 2024-05-23.
//

import CoreImage
import Foundation
import CoreImage.CIFilterBuiltins

class NTSCFilter: CIFilter {
    var inputImage: CIImage?
    var effect: NTSCEffect = .default
    static var kernels: Kernels = newKernels()
    struct Kernels {
        var toYIQ: CIColorKernel
        var blue: CIColorKernel
        var composeLuma: CIColorKernel
        var lumaNotch: CIKernel
        var toRGB: CIColorKernel
        var fun: CIKernel
    }
    
    private static func newKernels() -> Kernels {
        let url = Bundle.main.url(forResource: "default", withExtension: "metallib")!
        let data = try! Data(contentsOf: url)
        return Kernels(
            toYIQ: try! CIColorKernel(functionName: "ToYIQ", fromMetalLibraryData: data),
            blue: try! CIColorKernel(functionName: "Blue", fromMetalLibraryData: data), 
            composeLuma: try! CIColorKernel(functionName: "ComposeLuma", fromMetalLibraryData: data),
            lumaNotch: try! CIKernel(functionName: "LumaNotch", fromMetalLibraryData: data),
            toRGB: try! CIColorKernel(functionName: "ToRGB", fromMetalLibraryData: data),
            fun: try! CIKernel(functionName: "Fun", fromMetalLibraryData: data)
        )
    }

    override var outputImage: CIImage? {
        guard let input = inputImage else {
            return nil
        }

        guard let convertedToYIQ = Self.kernels.toYIQ.apply(extent: input.extent, arguments: [input]) else {
            return nil
        }
        let lumaed: CIImage?
        switch effect.inputLumaFilter {
        case .box:
            let boxBlur = CIFilter.boxBlur()
            boxBlur.inputImage = input
            boxBlur.radius = 4
            guard let blurred = boxBlur.outputImage else {
                return nil
            }
            
            lumaed = Self.kernels.composeLuma.apply(extent: input.extent, arguments: [blurred, convertedToYIQ])
        case .notch:
            lumaed = Self.kernels.lumaNotch.apply(extent: convertedToYIQ.extent, roiCallback: { _, rect in rect }, arguments: [convertedToYIQ])
        case .none:
            lumaed = convertedToYIQ
        }
        guard let lumaed else {
            return nil
        }
        
        guard let convertedToRGB = Self.kernels.toRGB.apply(extent: lumaed.extent, arguments: [lumaed]) else {
            return nil
        }
        
        return convertedToRGB
    }
}
