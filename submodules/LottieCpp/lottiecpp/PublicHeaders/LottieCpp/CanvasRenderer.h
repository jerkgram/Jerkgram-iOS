#ifndef CanvasRenderer_h
#define CanvasRenderer_h

#ifdef __cplusplus

#include <LottieCpp/Renderer.h>
#include <LottieCpp/Canvas.h>

#include <memory>

namespace lottie {

class CanvasRenderer {
class Impl;

public:
struct Configuration {
    bool canUseMoreMemory = false;
    bool disableGroupTransparency = false;
};

public:
    CanvasRenderer();
    ~CanvasRenderer() = default;

    void render(std::shared_ptr<Renderer> renderer, std::shared_ptr<Canvas> canvas, Vector2D const &size, Configuration const &configuration);

private:
    std::shared_ptr<Impl> _impl;
};

}

#endif

#endif /* CanvasRenderer_h */
