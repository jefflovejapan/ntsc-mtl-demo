//
//  ControlsView.swift
//  ntsc-mtl-demo
//
//  Created by Jeffrey Blagdon on 2024-06-13.
//

import SwiftUI

struct ControlsView: View {
    @Binding var showControls: Bool
    @Binding var enableFilter: Bool
    @Binding var resolution: CameraView.Resolution
    @Bindable var effect: NTSCEffect
    
    var body: some View {
        ScrollView {
            VStack {
                Toggle(isOn: $enableFilter, label: {
                    Text("Enable filter?")
                })
                HStack {
                    Text("Resolution")
                    Picker(selection: $resolution, content: {
                        ForEach(CameraView.Resolution.allCases) { res in
                            Text(name(resolution: res))
                                .tag(res)
                        }
                    }, label: {
                        Text("Resolution")
                    })
                }
                HStack {
                    Text("Use field")
                    Picker(selection: $effect.useField, content: {
                        ForEach(UseField.allCases) { useField in
                            Text(name(useField: useField))
                                .tag(useField)
                        }
                    }, label: { Text("Use field") })
                }
                VStack(alignment: .leading) {
                    Text("Bandwidth scale: \(effect.bandwidthScale.formatted(self.twoDecimalPoints))")
                    Slider.init(value: $effect.bandwidthScale, in: 0.125...8, label: {
                        Text(effect.bandwidthScale.formatted(.number))
                    })
                    .padding(.leading)
                }
                HStack {
                    Text("Input luma")
                    Spacer()
                    Picker(selection: $effect.inputLumaFilter, content: {
                        ForEach(LumaLowpass.allCases) { lowpass in
                            Text(name(lumaLowpass: lowpass))
                                .tag(lowpass)
                        }
                    }, label: {
                        Text("Input Luma")
                    })
                }
                HStack {
                    Text("Filter type")
                    Spacer()
                    Picker(selection: $effect.filterType, content: {
                        ForEach(FilterType.allCases) { filterType in
                            Text(name(filterType: filterType))
                                .tag(filterType)
                        }
                    }, label: {
                        Text("Filter Type")
                    })
                }
                HStack {
                    Text("Chroma lowpass in")
                    Spacer()
                    Picker(selection: $effect.chromaLowpassIn, content: {
                        ForEach(ChromaLowpass.allCases) { lp in
                            Text(name(chromaLowpass: lp))
                                .tag(lp)
                        }
                    }, label: {
                        Text("Chroma lowpass in")
                    })
                }
                
                HStack {
                    Text("Chroma phase shift")
                    Spacer()
                    Picker(selection: $effect.videoScanlinePhaseShift, content: {
                        ForEach(PhaseShift.allCases) { phaseShift in
                            Text(name(phaseShift: phaseShift))
                                .tag(phaseShift)
                        }
                    }, label: {
                        Text("Video scanline phase shift")
                    })
                }
                Stepper("Chroma phase shift offset: \(effect.videoScanlinePhaseShiftOffset)", value: $effect.videoScanlinePhaseShiftOffset, in: 0...4)
                VStack {
                    Text("Chroma phase error: \(effect.chromaPhaseError.formatted(self.twoDecimalPoints))")
                    Slider(value: $effect.chromaPhaseError, in: 0...1)
                        .padding(.leading)
                }
                VStack {
                    Text("Composite preemphasis: \(effect.compositePreemphasis.formatted(self.twoDecimalPoints))")
                    Slider(value: $effect.compositePreemphasis, in: -1...2)
                        .padding(.leading)
                }
                Toggle(isOn: $effect.headSwitchingEnabled, label: {
                    Text("Head switching")
                })
                if effect.headSwitchingEnabled {
                    Section("Head switching", content: {
                        Stepper(value: $effect.headSwitching.height, in: 0...24, label: {
                            Text("Height: \(effect.headSwitching.height)")
                        })
                        Stepper(value: $effect.headSwitching.offset, in: 0...24, label: {
                            Text("Offset: \(effect.headSwitching.offset)")
                        })
                        VStack {
                            Text("Horizontal shift: \(effect.headSwitching.horizShift.formatted(self.twoDecimalPoints))")
                            Slider(value: $effect.headSwitching.horizShift, in: -100...100)
                        }
                    })
                }
                VStack {
                    Text("Luma smear: \(effect.lumaSmear.formatted(self.twoDecimalPoints))")
                    Slider(value: $effect.lumaSmear, in: 0...1)
                        .padding(.leading)
                }
                Toggle(isOn: $effect.ringingEnabled, label: {
                    Text("Ringing")
                })

                if effect.ringingEnabled {
                    Section("Ringing", content: {
                        VStack {
                            Text("Frequency: \(effect.ringing.frequency.formatted(self.twoDecimalPoints))")
                            Slider(value: $effect.ringing.frequency, in: 0...1)
                        }
                        VStack {
                            Text("Power: \(effect.ringing.power.formatted(self.twoDecimalPoints))")
                            Slider(value: $effect.ringing.power, in: 1...10)
                        }
                        VStack {
                            Text("Intensity: \(effect.ringing.intensity.formatted(self.twoDecimalPoints))")
                            Slider(value: $effect.ringing.intensity, in: 0...10)
                        }  
                    })
                }
                VStack {
                    Text("Chroma phase noise: \(effect.chromaPhaseNoiseIntensity.formatted(self.twoDecimalPoints))")
                    Slider(value: $effect.chromaPhaseNoiseIntensity, in: 0...1)
                        .padding(.leading)
                }
                Section("Chroma delay", content: {
                    VStack {
                        Text("Horizontal offset: \(effect.chromaDelay.0.formatted(self.twoDecimalPoints))")
                        Slider(value: $effect.chromaDelay.0, in: -40...40)
                            .padding(.leading)
                    }
                    Stepper(value: $effect.chromaDelay.1, in: -20...20, label: {
                        Text("Vertical offset: \(effect.chromaDelay.1)")
                    })
                })
//                VStack(alignment: .leading) {
//                    Text("Luma smear")
//                    Slider.init(value: $effect.lumaSmear, in: 0...1, label: {
//                        Text(effect.lumaSmear.formatted(.number))
//                    })
//                    .padding(.leading)
//                }
                
                /*
                 What should actually be supported?
                 
                 - bandwidth scale
                 - input luma (LumaLowpass)
                 - luma box filter: LumaBoxTextureFilter
                - lumaNotchFilter: IIRTextureFilter
                 - chroma lowpass (ChromaLowpass)
                 - chroma into luma (PhaseShift, phaseShiftOffset)
                 - compositePreemphasis (IIR)
                 - compositeNoise
                 - ringing
                 */
            }
        }
    }
    
    private var twoDecimalPoints: FloatingPointFormatStyle<Float> {
        FloatingPointFormatStyle.number.precision(.fractionLength(2))
    }
    
    private func name(filterType: FilterType) -> String {
        switch filterType {
        case .constantK:
            return "Constant K"
        case .butterworth:
            return "Butterworth"
        }
    }
    
    private func name(lumaLowpass: LumaLowpass) -> String {
        switch lumaLowpass {
        case .none:
            return "None"
        case .box:
            return "Box"
        case .notch:
            return "Notch"
        }
    }
    
    private func name(phaseShift: PhaseShift) -> String {
        switch phaseShift {
        case .degrees0:
            "0"
        case .degrees90:
            "90"
        case .degrees180:
            "180"
        case .degrees270:
            "270"
        }
    }
    
    private func name(chromaLowpass: ChromaLowpass) -> String {
        switch chromaLowpass {
        case .none:
            return "None"
        case .light:
            return "Light"
        case .full:
            return "Full"
        }
    }
    
    private func name(useField: UseField) -> String {
        switch useField {
        case .alternating:
            return "Alternating (broken)"
        case .upper:
            return "Upper (broken)"
        case .lower:
            return "Lower (broken)"
        case .both:
            return "Both"
        case .interleavedUpper:
            return "Interleaved upper"
        case .interleavedLower:
            return "Interleaved lower"
        }
    }
    
    private func name(resolution: CameraView.Resolution) -> String {
        switch resolution {
        case .res4K:
            return "4K"
        case .res1080p:
            return "1080p"
        case .res720p:
            return "720p"
        case .resVGA:
            return "VGA"
        }
    }
}

#Preview {
    @State var showControls: Bool = true
    @State var enableFilter: Bool = false
    @State var effect: NTSCEffect = NTSCEffect()
    @State var resolution: CameraView.Resolution = .resVGA
    return ControlsView(showControls: $showControls, enableFilter: $enableFilter, resolution: $resolution, effect: effect)
}
