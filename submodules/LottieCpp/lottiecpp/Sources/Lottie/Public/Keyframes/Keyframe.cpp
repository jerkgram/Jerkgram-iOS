#include "Keyframe.hpp"

#include <cfloat>
#include <cmath>
#include <algorithm>

namespace lottie {

static float eval_poly(float t, float m, float b) {
    return std::fmaf(m, t, b);
}

static float eval_poly(float t, float m, float b, float c) {
    float a = std::fmaf(m, t, b);
    return std::fmaf(t, a, c);
}

static float eval_poly(float t, float m, float b, float c, float d) {
    float e = std::fmaf(m, t, b);
    float a = std::fmaf(e, t, c);
    return std::fmaf(t, a, d);
}

static float cubic_solver(float A, float B, float C, float D) {
    float t = -D;
    
    float A3 = 3.0f * A;
    float A6 = 6.0f * A;
    float B2 = 2.0f * B;

    const int MAX_ITERS = 8;
    for (int iters = 0; iters < MAX_ITERS; iters++) {
        float f = eval_poly(t, A, B, C, D); // f = At^3 + Bt^2 + Ct + D
        if (std::fabs(f) <= 0.00005f) {
            break;
        }
        float fp = eval_poly(t, A3, B2, C); // f' = 3At^2 + 2Bt + C
        float fpp = eval_poly(t, A6, B2); // f'' = 6At + 2B

        float numer = 2.0f * fp * f;
        float denom = std::fma(2.0f * fp, fp, -(f * fpp));

        t -= numer / denom;
    }
    
    t = std::clamp(t, 0.0f, 1.0f);

    return t;
}

inline bool isApproximatelyEqual(float value, float other) {
    return std::abs(value - other) <= FLT_EPSILON;
}

float cubicBezierInterpolate(float value, Vector2D const &P1, Vector2D const &P2) {
    float t = 0.0;
    if (isApproximatelyEqual(value, 0.0f)) {
        // Handle corner cases explicitly to prevent rounding errors
        t = 0.0;
    } else if (isApproximatelyEqual(value, 1.0f)) {
        t = 1.0;
    } else {
        // Calculate t
        float a = 3 * P1.x - 3 * P2.x + 1.0f;
        float b = -6 * P1.x + 3 * P2.x;
        float c = 3 * P1.x;
        
        float tTemp = cubic_solver(a, b, c, -value);
        
        if (isApproximatelyEqual(tTemp, -1.0f)) {
            return -1.0;
        }
        t = tTemp;
    }
    
    // Calculate y from t
    float oneMinusT = 1.0 - t;
    float result = 3 * t * (oneMinusT * oneMinusT) * P1.y + 3 * (t * t) * (1 - t) * P2.y + (t * t * t);
    
    return result;
}

}
