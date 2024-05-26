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
    let size: CGSize
    private(set) lazy var filters = newFilters(size: size)
    
    init(size: CGSize) {
        self.size = size
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }
    
    class Filters {
        let toYIQ: ToYIQFilter
        let composeLuma: ComposeLumaFilter
        let lumaBoxBlur: CIFilter
        let lumaNotchBlur: IIRFilter
        let toRGB: ToRGBFilter
        
        init(
            toYIQ: ToYIQFilter,
            composeLuma: ComposeLumaFilter,
            lumaBoxBlur: CIFilter,
            lumaNotchBlur: IIRFilter,
            toRGB: ToRGBFilter
        ) {
            self.toYIQ = toYIQ
            self.composeLuma = composeLuma
            self.lumaBoxBlur = lumaBoxBlur
            self.lumaNotchBlur = lumaNotchBlur
            self.toRGB = toRGB
        }
    }
    
    private func newFilters(size: CGSize) -> Filters {
        return Filters(
            toYIQ: ToYIQFilter(),
            composeLuma: ComposeLumaFilter(),
            lumaBoxBlur: newBoxBlurFilter(),
            lumaNotchBlur: IIRFilter.lumaNotch(size: size),
            toRGB: ToRGBFilter()
        )
    }
    
    private func newBoxBlurFilter() -> CIFilter {
        let boxBlur = CIFilter.boxBlur()
        boxBlur.radius = 4
        return boxBlur
    }

    override var outputImage: CIImage? {
        guard let input = inputImage else {
            return nil
        }
        
        let maybeYIQ: CIImage?
        self.filters.toYIQ.inputImage = input
        maybeYIQ = self.filters.toYIQ.outputImage
        guard let yiq = maybeYIQ else {
            return nil
        }
        
        let lumaed: CIImage?
        switch effect.inputLumaFilter {
        case .box:
            self.filters.lumaBoxBlur.setValue(yiq, forKey: kCIInputImageKey)
            lumaed = self.filters.lumaBoxBlur.outputImage
        case .notch:
            self.filters.lumaNotchBlur.inputImage = yiq
            lumaed = self.filters.lumaNotchBlur.outputImage
        case .none:
            lumaed = yiq
        }
        guard let lumaed else {
            return nil
        }
        
        let lumaComposed: CIImage?
        self.filters.composeLuma.yImage = lumaed
        self.filters.composeLuma.iqImage = yiq
        lumaComposed = self.filters.composeLuma.outputImage
        guard let lumaComposed else {
            return nil
        }
        
        self.filters.toRGB.inputImage = lumaComposed
        let rgb = self.filters.toRGB.outputImage
        return rgb
    }
}
