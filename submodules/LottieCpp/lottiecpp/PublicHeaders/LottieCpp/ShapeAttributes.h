#ifndef ShapeAttributes_h
#define ShapeAttributes_h

#ifdef __cplusplus

namespace lottie {

enum class FillRule: int {
    None = 0,
    NonZeroWinding = 1,
    EvenOdd = 2
};

enum class LineCap: int {
    None = 0,
    Butt = 1,
    Round = 2,
    Square = 3
};

enum class LineJoin: int {
    None = 0,
    Miter = 1,
    Round = 2,
    Bevel = 3
};

enum class GradientType: int {
    None = 0,
    Linear = 1,
    Radial = 2
};

enum class TrimType: int {
    Simultaneously = 1,
    Individually = 2
};

struct TrimParams {
    float start = 0.0;
    float end = 0.0;
    float offset = 0.0;
    TrimType type = TrimType::Simultaneously;
    
    TrimParams(float start_, float end_, float offset_, TrimType type_) :
    start(start_),
    end(end_),
    offset(offset_),
    type(type_) {
    }
    
    bool operator==(TrimParams const &rhs) const {
        if (start != rhs.start) {
            return false;
        }
        if (end != rhs.end) {
            return false;
        }
        if (offset != rhs.offset) {
            return false;
        }
        if (type != rhs.type) {
            return false;
        }
        return true;
    }
    
    bool operator!=(TrimParams const &rhs) const {
        return !(*this == rhs);
    }
};

}

#endif

#endif /* LottieColor_h */
