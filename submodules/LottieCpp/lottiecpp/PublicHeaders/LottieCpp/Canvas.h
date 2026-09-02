#ifndef Canvas_h
#define Canvas_h

#ifdef __cplusplus

#include <memory>
#include <vector>
#include <cassert>
#include <functional>

namespace lottie {

class Gradient {
public:
    Gradient(std::vector<Color> const &colors, std::vector<float> const &locations) :
    _colors(colors),
    _locations(locations) {
#if DEBUG
        assert(_colors.size() == _locations.size());
#endif
    }
    
    std::vector<Color> const &colors() const {
        return _colors;
    }
    
    std::vector<float> const &locations() const {
        return _locations;
    }
    
private:
    std::vector<Color> _colors;
    std::vector<float> _locations;
};

enum class PathCommandType {
    MoveTo,
    LineTo,
    CurveTo,
    Close
};

typedef struct {
    PathCommandType type;
    Vector2D points[4];
} PathCommand;

typedef std::function<void(std::function<void(PathCommand const &)> &&)> CanvasPathEnumerator;

class Canvas {
public:
    enum class MaskMode {
        Normal,
        Inverse
    };
    
public:
    virtual ~Canvas() = default;
    
    virtual void saveState() = 0;
    virtual void restoreState() = 0;
    
    virtual void fillPath(CanvasPathEnumerator const &enumeratePath, FillRule fillRule, Color const &color) = 0;
    virtual void linearGradientFillPath(CanvasPathEnumerator const &enumeratePath, FillRule fillRule, Gradient const &gradient, Vector2D const &start, Vector2D const &end) = 0;
    virtual void radialGradientFillPath(CanvasPathEnumerator const &enumeratePath, FillRule fillRule, Gradient const &gradient, Vector2D const &center, float radius) = 0;
    
    virtual void strokePath(CanvasPathEnumerator const &enumeratePath, float lineWidth, LineJoin lineJoin, LineCap lineCap, float dashPhase, std::vector<float> const &dashPattern, Color const &color) = 0;
    virtual void linearGradientStrokePath(CanvasPathEnumerator const &enumeratePath, float lineWidth, LineJoin lineJoin, LineCap lineCap, float dashPhase, std::vector<float> const &dashPattern, Gradient const &gradient, Vector2D const &start, Vector2D const &end) = 0;
    virtual void radialGradientStrokePath(CanvasPathEnumerator const &enumeratePath, float lineWidth, LineJoin lineJoin, LineCap lineCap, float dashPhase, std::vector<float> const &dashPattern, Gradient const &gradient, Vector2D const &startCenter, float startRadius, Vector2D const &endCenter, float endRadius) = 0;
    
    virtual void clip(CGRect const &rect) = 0;
    virtual bool clipPath(CanvasPathEnumerator const &enumeratePath, FillRule fillRule, Transform2D const &transform) = 0;
    
    virtual void concatenate(Transform2D const &transform) = 0;
    
    virtual bool pushLayer(CGRect const &rect, float alpha, std::optional<MaskMode> maskMode) { return true; };
    virtual void popLayer() {};
};

}

#endif

#endif

