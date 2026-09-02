#ifndef LottieSimd_h
#define LottieSimd_h

#if __APPLE__

#include <simd/simd.h>

#define LottieFloat3 simd_float3
#define LottieFloat4 simd_float4
#define LottieFloat3x3 simd_float3x3
#define lottieSimdMakeFloat3 simd_make_float3
#define lottieSimdMakeFloat4 simd_make_float4
#define lottieSimdMul simd_mul
#define lottieSimdReduceMin simd_reduce_min
#define lottieSimdReduceMax simd_reduce_max
#define lottieSimdDeterminant simd_determinant
#define lottieSimdInverse simd_inverse
#define lottieSimdEqual simd_equal

#else

#ifdef __cplusplus

#ifndef MIN
#define MIN(a,b) (a<b?a:b)
#endif

#ifndef MAX
#define MAX(a,b) (a>b?a:b)
#endif

struct LottieFloat3 {
    float components[3];
    
    float operator[](int index) const {
        return components[index];
    }
};

struct LottieFloat4{
    float components[4];
    
    float operator[](int index) const {
        return components[index];
    }
    
    LottieFloat4 operator*(float scalar) const {
        LottieFloat4 result = { components[0] * scalar, components[1] * scalar, components[2] * scalar, components[3] * scalar };
        return result;
    }
    
    LottieFloat4 operator+(LottieFloat4 other) const {
        LottieFloat4 result = { components[0] + other.components[0], components[1] + other.components[1], components[2] + other.components[2], components[3] + other.components[3] };
        return result;
    }
    
    LottieFloat4 operator+(float scalar) const {
        LottieFloat4 result = { components[0] + scalar, components[1] + scalar, components[2] + scalar, components[3] + scalar };
        return result;
    }
};

#else

typedef struct {
    float components[3];
} LottieFloat3;

typedef struct {
    float components[4];
} LottieFloat4;

#endif

typedef struct {
    LottieFloat3 columns[3];
} LottieFloat3x3;

inline LottieFloat3 lottieSimdMakeFloat3(float a, float b, float c) {
    LottieFloat3 result;
    result.components[0] = a;
    result.components[1] = b;
    result.components[2] = c;
    return result;
}

inline LottieFloat4 lottieSimdMakeFloat4(float a, float b, float c, float d) {
    LottieFloat4 result;
    result.components[0] = a;
    result.components[1] = b;
    result.components[2] = c;
    result.components[3] = d;
    return result;
}

inline LottieFloat3x3 lottieSimdMul(LottieFloat3x3 a, LottieFloat3x3 b) {
    LottieFloat3x3 result;
    for (int i = 0; i < 3; ++i) {
        for (int j = 0; j < 3; ++j) {
            result.columns[i].components[j] =
            a.columns[0].components[j] * b.columns[i].components[0] +
            a.columns[1].components[j] * b.columns[i].components[1] +
            a.columns[2].components[j] * b.columns[i].components[2];
        }
    }
    
    return result;
}

inline float lottieSimdReduceMin(LottieFloat4 value) {
    float result = value.components[0];
    result = MIN(result, value.components[1]);
    result = MIN(result, value.components[2]);
    result = MIN(result, value.components[3]);
    return result;
}

inline float lottieSimdReduceMax(LottieFloat4 value) {
    float result = value.components[0];
    result = MAX(result, value.components[1]);
    result = MAX(result, value.components[2]);
    result = MAX(result, value.components[3]);
    return result;
}

inline float lottieSimdDeterminant(LottieFloat3x3 m) {
    float a = m.columns[0].components[0];
    float b = m.columns[1].components[0];
    float c = m.columns[2].components[0];
    float d = m.columns[0].components[1];
    float e = m.columns[1].components[1];
    float f = m.columns[2].components[1];
    float g = m.columns[0].components[2];
    float h = m.columns[1].components[2];
    float i = m.columns[2].components[2];
    
    float result = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    
    return result;
}

inline LottieFloat3x3 lottieSimdInverse(LottieFloat3x3 m) {
    LottieFloat3x3 result;
    
    float a = m.columns[0].components[0];
    float b = m.columns[1].components[0];
    float c = m.columns[2].components[0];
    float d = m.columns[0].components[1];
    float e = m.columns[1].components[1];
    float f = m.columns[2].components[1];
    float g = m.columns[0].components[2];
    float h = m.columns[1].components[2];
    float i = m.columns[2].components[2];
    
    float det = lottieSimdDeterminant(m);
    if (det == 0) {
        LottieFloat3x3 identity = {{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}};
        return identity;
    }
    
    float invDet = 1.0f / det;
    
    result.columns[0].components[0] = (e * i - f * h) * invDet;
    result.columns[1].components[0] = (c * h - b * i) * invDet;
    result.columns[2].components[0] = (b * f - c * e) * invDet;
    
    result.columns[0].components[1] = (f * g - d * i) * invDet;
    result.columns[1].components[1] = (a * i - c * g) * invDet;
    result.columns[2].components[1] = (c * d - a * f) * invDet;
    
    result.columns[0].components[2] = (d * h - e * g) * invDet;
    result.columns[1].components[2] = (b * g - a * h) * invDet;
    result.columns[2].components[2] = (a * e - b * d) * invDet;
    
    return result;
}

inline bool lottieSimdEqual(LottieFloat3x3 a, LottieFloat3x3 b) {
    for (int i = 0; i < 3; ++i) {
        for (int j = 0; j < 3; ++j) {
            if (a.columns[i].components[j] != b.columns[i].components[j]) {
                return false;
            }
        }
    }
    return true;
}

#endif

#endif /* LottieSimd_h */
