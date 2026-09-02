#include <LottieCpp/NullCanvasImpl.h>

namespace lottie {

namespace {

void addEnumeratedPath(CanvasPathEnumerator const &enumeratePath) {
    //enumeratePath([&](PathCommand const &command) {
    //});
}

}

NullCanvasImpl::NullCanvasImpl(int width, int height) :
_transform(lottie::Transform2D::identity()) {
}

NullCanvasImpl::~NullCanvasImpl() {
}

void NullCanvasImpl::saveState() {
}

void NullCanvasImpl::restoreState() {
}

void NullCanvasImpl::fillPath(CanvasPathEnumerator const &enumeratePath, lottie::FillRule fillRule, lottie::Color const &color) {
    addEnumeratedPath(enumeratePath);
}

void NullCanvasImpl::linearGradientFillPath(CanvasPathEnumerator const &enumeratePath, lottie::FillRule fillRule, Gradient const &gradient, lottie::Vector2D const &start, lottie::Vector2D const &end) {
    addEnumeratedPath(enumeratePath);
}

void NullCanvasImpl::radialGradientFillPath(CanvasPathEnumerator const &enumeratePath, lottie::FillRule fillRule, Gradient const &gradient, Vector2D const &center, float radius) {
    addEnumeratedPath(enumeratePath);
}

void NullCanvasImpl::strokePath(CanvasPathEnumerator const &enumeratePath, float lineWidth, lottie::LineJoin lineJoin, lottie::LineCap lineCap, float dashPhase, std::vector<float> const &dashPattern, lottie::Color const &color) {
    addEnumeratedPath(enumeratePath);
}

void NullCanvasImpl::linearGradientStrokePath(CanvasPathEnumerator const &enumeratePath, float lineWidth, lottie::LineJoin lineJoin, lottie::LineCap lineCap, float dashPhase, std::vector<float> const &dashPattern, Gradient const &gradient, lottie::Vector2D const &start, lottie::Vector2D const &end) {
    addEnumeratedPath(enumeratePath);
}

void NullCanvasImpl::radialGradientStrokePath(CanvasPathEnumerator const &enumeratePath, float lineWidth, lottie::LineJoin lineJoin, lottie::LineCap lineCap, float dashPhase, std::vector<float> const &dashPattern, Gradient const &gradient, lottie::Vector2D const &startCenter, float startRadius, lottie::Vector2D const &endCenter, float endRadius) {
    addEnumeratedPath(enumeratePath);
}

void NullCanvasImpl::clip(CGRect const &rect) {
}

bool NullCanvasImpl::clipPath(CanvasPathEnumerator const &enumeratePath, FillRule fillRule, Transform2D const &transform) {
    return true;
}

void NullCanvasImpl::concatenate(lottie::Transform2D const &transform) {
}

void NullCanvasImpl::flush() {
}

}
