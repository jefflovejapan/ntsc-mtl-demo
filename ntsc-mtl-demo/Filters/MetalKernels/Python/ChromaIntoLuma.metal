//
//  ChromaIntoLuma.metal
//  ntsc-mtl-demo
//
//  Created by Jeffrey Blagdon on 2024-06-24.
//

#include <metal_stdlib>
using namespace metal;

constant half4 UMult = half4(1.h, 0.h, -1.h, 0.h);
constant half4 VMult = half4(0.h, 1.h, 0.h, -1.h);

enum ChromaPhaseShift {
    ChromaPhaseShift0  = 0,
    ChromaPhaseShift90 = 1,
    ChromaPhaseShift180 = 2,
    ChromaPhaseShift270 = 3
};

int delay(uint y, ChromaPhaseShift phaseShift, int phaseShiftOffset) {
    int fieldNo = y % 2;
    switch (phaseShift) {
        case ChromaPhaseShift0:
            return (fieldNo + phaseShiftOffset + (y >> 1)) & 3;
        case ChromaPhaseShift90:
            return (fieldNo + phaseShiftOffset + (y >> 1)) & 3;
        case ChromaPhaseShift180:
            return ((((fieldNo + y) & 2) + phaseShiftOffset) & 3);
        case ChromaPhaseShift270:
            return ((fieldNo + phaseShiftOffset) & 3);
        default:
            return 0;
    }
}

kernel void chromaIntoLuma
(
 texture2d<half, access::read> input [[texture(0)]],
 texture2d<half, access::write> output [[texture(1)]],
 constant ChromaPhaseShift &phaseShift [[buffer(0)]],
 constant int &phaseShiftOffset [[buffer(1)]],
 constant half &subcarrierAmplitude [[buffer(2)]],
 uint2 gid [[thread_position_in_grid]]
 ) {
    int chromaXDelay = delay(gid.y, phaseShift, phaseShiftOffset);
    half iFactor = UMult[(gid.x + chromaXDelay) % 4];
    half qFactor = VMult[(gid.x + chromaXDelay) % 4];
    half4 inPx = input.read(gid);
    
    half inI = inPx.y;
    half chroma = (inI * subcarrierAmplitude * iFactor);
    half inQ = inPx.z;
    chroma += (inQ * subcarrierAmplitude * qFactor);
    inPx.x += chroma;
    output.write(inPx, gid);
}