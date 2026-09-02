#ifndef LottieRenderer_h
#define LottieRenderer_h

#ifdef __cplusplus

#include <LottieCpp/Vectors.h>
#include <LottieCpp/RenderTreeNode.h>

#include <memory>

namespace lottie {

class Renderer {
class Impl;

public:
    ~Renderer() = default;
    
    static std::shared_ptr<Renderer> make(std::string const &jsonString);
    
public:
    int frameCount();
    int framesPerSecond();
    Vector2D size();
    
    void setFrame(float index);
    std::shared_ptr<RenderTreeNode> renderNode();

private:
    explicit Renderer(std::shared_ptr<Impl> impl);

private:
    std::shared_ptr<Impl> _impl;
};

}

#endif

#endif /* LottieRenderer_h */
