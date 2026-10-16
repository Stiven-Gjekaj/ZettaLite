// Compiler builtins that FFmpeg needs and that iOS 6 does not have.
// The clang of the current Xcode calls __extendhfsf2 to change a 16-bit
// float into a 32-bit float. The libSystem of iOS 6 does not export it.

#include <stdint.h>
#include <string.h>

float __extendhfsf2(uint16_t half) {
    uint32_t sign = (uint32_t)(half & 0x8000) << 16;
    uint32_t exponent = (half >> 10) & 0x1f;
    uint32_t mantissa = half & 0x3ff;
    uint32_t bits;
    if (exponent == 0) {
        if (mantissa == 0) {
            bits = sign;
        } else {
            // A subnormal half. Shift the mantissa until it is normal.
            exponent = 127 - 15 + 1;
            while (!(mantissa & 0x400)) {
                mantissa <<= 1;
                exponent--;
            }
            mantissa &= 0x3ff;
            bits = sign | (exponent << 23) | (mantissa << 13);
        }
    } else if (exponent == 0x1f) {
        bits = sign | 0x7f800000 | (mantissa << 13);  // Infinity or NaN.
    } else {
        bits = sign | ((exponent + 127 - 15) << 23) | (mantissa << 13);
    }
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}
