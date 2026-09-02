#include <LottieCpp/Renderer.h>

#include <LottieCpp/lottiejson11.hpp>
#include "Lottie/Private/Model/Animation.hpp"
#include "Lottie/Private/MainThread/LayerContainers/MainThreadAnimationLayer.hpp"

namespace lottie {

class Renderer::Impl {
public:
    Impl(std::shared_ptr<Animation> animation) :
    _animation(animation) {
        _layer = std::make_shared<MainThreadAnimationLayer>(
            *_animation.get(),
            std::make_shared<BlankImageProvider>(),
            std::make_shared<DefaultTextProvider>(),
            std::make_shared<DefaultFontProvider>()
        );
    }
    
public:
    int frameCount() {
        return (int)(_animation->endFrame - _animation->startFrame);
    }
    
    int framesPerSecond() {
        return (int)_animation->framerate;
    }
    
    Vector2D size() {
        return Vector2D(_animation->width, _animation->height);
    }
    
    void setFrame(float index) {
        _layer->setCurrentFrame(_animation->startFrame + index);
    }
    
    std::shared_ptr<RenderTreeNode> renderNode() {
        return _layer->renderTreeNode();
    }
    
private:
    std::shared_ptr<Animation> _animation;
    std::shared_ptr<MainThreadAnimationLayer> _layer;
};

Renderer::Renderer(std::shared_ptr<Impl> impl) :
_impl(impl) {
}

std::shared_ptr<Renderer> Renderer::make(std::string const &jsonString) {
    std::string errorText;
    auto json = lottiejson11::Json::parse(jsonString, errorText);
    if (!json.is_object()) {
        return nullptr;
    }
    
    std::shared_ptr<Animation> animation;
    try {
        animation = Animation::fromJson(json.object_items());
    } catch(...) {
        return nullptr;
    }
    if (!animation) {
        return nullptr;
    }
    
    auto impl = std::make_shared<Impl>(animation);
    return std::shared_ptr<Renderer>(new Renderer(impl));
}

int Renderer::frameCount() {
    return _impl->frameCount();
}

int Renderer::framesPerSecond() {
    return _impl->framesPerSecond();
}

Vector2D Renderer::size() {
    return _impl->size();
}

void Renderer::setFrame(float index) {
    _impl->setFrame(index);
}

std::shared_ptr<RenderTreeNode> Renderer::renderNode() {
    return _impl->renderNode();
}

}
