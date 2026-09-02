#include <LottieCpp/CanvasRenderer.h>

#include <cmath>

namespace lottie {

namespace {

// Values below that are invisible
static constexpr float minVisibleAlpha = 0.5f / 255.0f;

// Sometimes calculating path bounds is slower than just allocating the whole canvas
static constexpr float minGlobalRectCalculationSize = 200.0f;

struct TransformedPath {
    BezierPath path;
    Transform2D transform;
    
    TransformedPath(BezierPath const &path_, Transform2D const &transform_) :
    path(path_),
    transform(transform_) {
    }
};

static CGRect collectPathBoundingBoxes(std::shared_ptr<RenderTreeNodeContentItem> item, size_t subItemLimit, Transform2D const &parentTransform, bool skipApplyTransform, BezierPathsBoundingBoxContext &bezierPathsBoundingBoxContext) {
    //TODO:remove skipApplyTransform
    Transform2D effectiveTransform = parentTransform;
    if (!skipApplyTransform && item->isGroup) {
        effectiveTransform = item->transform * effectiveTransform;
    }
    
    size_t maxSubitem = std::min(item->subItems.size(), subItemLimit);
    
    CGRect boundingBox(0.0, 0.0, 0.0, 0.0);
    if (item->trimmedPaths) {
        for (const auto &path : item->trimmedPaths.value()) {
            if (path->needsBoundsRecalculation) {
                path->bounds = bezierPathsBoundingBoxParallel(bezierPathsBoundingBoxContext, path->path);
                path->needsBoundsRecalculation = false;
            }
            CGRect subpathBoundingBox = path->bounds.applyingTransform(effectiveTransform);
            if (boundingBox.empty()) {
                boundingBox = subpathBoundingBox;
            } else {
                boundingBox = boundingBox.unionWith(subpathBoundingBox);
            }
        }
    } else {
        if (item->path) {
            if (item->path->needsBoundsRecalculation) {
                item->path->bounds = bezierPathsBoundingBoxParallel(bezierPathsBoundingBoxContext, item->path->path);
                item->path->needsBoundsRecalculation = false;
            }
            boundingBox = item->path->bounds.applyingTransform(effectiveTransform);
        }
        
        for (size_t i = 0; i < maxSubitem; i++) {
            auto &subItem = item->subItems[i];
            
            CGRect subItemBoundingBox = collectPathBoundingBoxes(subItem, INT32_MAX, effectiveTransform, false, bezierPathsBoundingBoxContext);
            
            if (boundingBox.empty()) {
                boundingBox = subItemBoundingBox;
            } else {
                boundingBox = boundingBox.unionWith(subItemBoundingBox);
            }
        }
    }
    
    return boundingBox;
}

static void enumeratePaths(std::shared_ptr<RenderTreeNodeContentItem> item, size_t subItemLimit, Transform2D const &parentTransform, bool skipApplyTransform, std::function<void(BezierPath const &path, Transform2D const &transform)> const &onPath) {
    //TODO:remove skipApplyTransform
    Transform2D effectiveTransform = parentTransform;
    if (!skipApplyTransform && item->isGroup) {
        effectiveTransform = item->transform * effectiveTransform;
    }
    
    size_t maxSubitem = std::min(item->subItems.size(), subItemLimit);
    
    if (item->trimmedPaths) {
        for (const auto &path : item->trimmedPaths.value()) {
            onPath(path->path, effectiveTransform);
        }
        
        return;
    }
    
    if (item->path) {
        onPath(item->path->path, effectiveTransform);
    }
    
    for (size_t i = 0; i < maxSubitem; i++) {
        auto &subItem = item->subItems[i];
        
        enumeratePaths(subItem, INT32_MAX, effectiveTransform, false, onPath);
    }
}

}

static std::optional<CGRect> getRenderContentItemLocalRect(std::shared_ptr<RenderTreeNodeContentItem> const &contentItem, BezierPathsBoundingBoxContext &bezierPathsBoundingBoxContext) {
    std::optional<CGRect> localRect;
    for (const auto &shadingVariant : contentItem->shadings) {
        CGRect shapeBounds = collectPathBoundingBoxes(contentItem, shadingVariant->subItemLimit, Transform2D::identity(), true, bezierPathsBoundingBoxContext);
        
        if (shadingVariant->stroke) {
            shapeBounds = shapeBounds.insetBy(-shadingVariant->stroke->lineWidth / 2.0, -shadingVariant->stroke->lineWidth / 2.0);
        } else if (shadingVariant->fill) {
        } else {
            continue;
        }
        
        CGRect shapeLocalBounds = shapeBounds;
        if (localRect) {
            localRect = localRect->unionWith(shapeLocalBounds);
        } else {
            localRect = shapeLocalBounds;
        }
    }
    
    for (const auto &subItem : contentItem->subItems) {
        auto subLocalRect = getRenderContentItemLocalRect(subItem, bezierPathsBoundingBoxContext);
        if (subLocalRect) {
            CGRect transformedSubLocalRect = subLocalRect->applyingTransform(subItem->transform);
            if (localRect) {
                localRect = localRect->unionWith(transformedSubLocalRect);
            } else {
                localRect = transformedSubLocalRect;
            }
        }
    }
    
    return localRect;
}

static std::optional<CGRect> getRenderNodeLocalRect(std::shared_ptr<RenderTreeNode> const &node, bool isInvertedMatte, BezierPathsBoundingBoxContext &bezierPathsBoundingBoxContext) {
    if (node->isHidden() || node->alpha() < minVisibleAlpha) {
        return std::nullopt;
    }
    
    std::optional<CGRect> localRect;
    if (node->_contentItem) {
        localRect = getRenderContentItemLocalRect(node->_contentItem, bezierPathsBoundingBoxContext);
    }
    
    if (isInvertedMatte) {
        CGRect localBounds = CGRect(0.0f, 0.0f, node->size().x, node->size().y);
        if (localRect) {
            localRect = localRect->unionWith(localBounds);
        } else {
            localRect = localBounds;
        }
    }
    
    for (const auto &subNode : node->subnodes()) {
        auto subLocalRect = getRenderNodeLocalRect(subNode, false, bezierPathsBoundingBoxContext);
        if (subLocalRect) {
            auto transformedSubLocalRect = subLocalRect->applyingTransform(subNode->transform());
            if (localRect) {
                localRect = localRect->unionWith(transformedSubLocalRect);
            } else {
                localRect = transformedSubLocalRect;
            }
        }
    }
    
    return localRect;
}

namespace {

static void drawLottieContentItem(std::shared_ptr<Canvas> const &canvas, std::shared_ptr<RenderTreeNodeContentItem> item, float parentAlpha, Vector2D const &globalSize, Transform2D const &parentTransform, BezierPathsBoundingBoxContext &bezierPathsBoundingBoxContext, CanvasRenderer::Configuration const &configuration) {
    auto currentTransform = parentTransform;
    Transform2D localTransform = item->transform;
    currentTransform = localTransform * currentTransform;
    
    float normalizedOpacity = item->alpha;
    float layerAlpha = ((float)normalizedOpacity) * parentAlpha;
    
    if (normalizedOpacity == 0.0f) {
        return;
    }
    
    canvas->saveState();
    canvas->concatenate(item->transform);
    
    bool needsTempContext = false;
    if (!configuration.disableGroupTransparency) {
        needsTempContext = layerAlpha != 1.0 && item->drawContentCount > 1;
    }
    
    if (needsTempContext) {
        std::optional<CGRect> localRect;
        if (configuration.canUseMoreMemory && globalSize.x <= minGlobalRectCalculationSize && globalSize.y <= minGlobalRectCalculationSize) {
            localRect = CGRect::veryLarge();
        } else {
            localRect = getRenderContentItemLocalRect(item, bezierPathsBoundingBoxContext);
        }
        
        if (!localRect) {
            canvas->restoreState();
            return;
        }
        if (!canvas->pushLayer(localRect.value(), layerAlpha, std::nullopt)) {
            canvas->restoreState();
            return;
        }
    }
    
    float renderAlpha = 1.0;
    if (needsTempContext) {
        renderAlpha = 1.0;
    } else {
        renderAlpha = layerAlpha;
    }
    
    for (const auto &shading : item->shadings) {
        CanvasPathEnumerator iteratePaths;
        iteratePaths = [&](std::function<void(PathCommand const &)> &&iterate) {
            enumeratePaths(item, shading->subItemLimit, Transform2D::identity(), true, [&](BezierPath const &sourcePath, Transform2D const &transform) {
                auto path = sourcePath.copyUsingTransform(transform);
                
                PathCommand pathCommand;
                std::optional<PathElement> previousElement;
                for (const auto &element : path.elements()) {
                    if (previousElement.has_value()) {
                        if (previousElement->vertex.outTangentRelative().isZero() && element.vertex.inTangentRelative().isZero()) {
                            pathCommand.type = PathCommandType::LineTo;
                            pathCommand.points[0] = element.vertex.point;
                            iterate(pathCommand);
                        } else {
                            pathCommand.type = PathCommandType::CurveTo;
                            pathCommand.points[2] = element.vertex.point;
                            pathCommand.points[1] = element.vertex.inTangent;
                            pathCommand.points[0] = previousElement->vertex.outTangent;
                            iterate(pathCommand);
                        }
                    } else {
                        pathCommand.type = PathCommandType::MoveTo;
                        pathCommand.points[0] = element.vertex.point;
                        iterate(pathCommand);
                    }
                    previousElement = element;
                }
                if (path.closed().value_or(true)) {
                    pathCommand.type = PathCommandType::Close;
                    iterate(pathCommand);
                }
            });
        };
        
        if (shading->stroke) {
            if (shading->stroke->shading->type() == RenderTreeNodeContentItem::ShadingType::Solid) {
                RenderTreeNodeContentItem::SolidShading *solidShading = (RenderTreeNodeContentItem::SolidShading *)shading->stroke->shading.get();
                
                if (solidShading->opacity != 0.0) {
                    LineJoin lineJoin = LineJoin::Bevel;
                    switch (shading->stroke->lineJoin) {
                        case LineJoin::Bevel: {
                            lineJoin = LineJoin::Bevel;
                            break;
                        }
                        case LineJoin::Round: {
                            lineJoin = LineJoin::Round;
                            break;
                        }
                        case LineJoin::Miter: {
                            lineJoin = LineJoin::Miter;
                            break;
                        }
                        default: {
                            break;
                        }
                    }
                    
                    LineCap lineCap = LineCap::Square;
                    switch (shading->stroke->lineCap) {
                        case LineCap::Butt: {
                            lineCap = LineCap::Butt;
                            break;
                        }
                        case LineCap::Round: {
                            lineCap = LineCap::Round;
                            break;
                        }
                        case LineCap::Square: {
                            lineCap = LineCap::Square;
                            break;
                        }
                        default: {
                            break;
                        }
                    }
                    
                    std::vector<float> dashPattern;
                    if (!shading->stroke->dashPattern.empty()) {
                        dashPattern = shading->stroke->dashPattern;
                    }
                    
                    canvas->strokePath(iteratePaths, shading->stroke->lineWidth, lineJoin, lineCap, shading->stroke->dashPhase, dashPattern, Color(solidShading->color.r, solidShading->color.g, solidShading->color.b, solidShading->color.a * solidShading->opacity * renderAlpha));
                } else if (shading->stroke->shading->type() == RenderTreeNodeContentItem::ShadingType::Gradient) {
                    //TODO:gradient stroke
                }
            }
        } else if (shading->fill) {
            FillRule rule = FillRule::NonZeroWinding;
            switch (shading->fill->rule) {
                case FillRule::EvenOdd: {
                    rule = FillRule::EvenOdd;
                    break;
                }
                case FillRule::NonZeroWinding: {
                    rule = FillRule::NonZeroWinding;
                    break;
                }
                default: {
                    break;
                }
            }
            
            if (shading->fill->shading->type() == RenderTreeNodeContentItem::ShadingType::Solid) {
                RenderTreeNodeContentItem::SolidShading *solidShading = (RenderTreeNodeContentItem::SolidShading *)shading->fill->shading.get();
                if (solidShading->opacity != 0.0) {
                    canvas->fillPath(iteratePaths, rule, Color(solidShading->color.r, solidShading->color.g, solidShading->color.b, solidShading->color.a * solidShading->opacity * renderAlpha));
                }
            } else if (shading->fill->shading->type() == RenderTreeNodeContentItem::ShadingType::Gradient) {
                RenderTreeNodeContentItem::GradientShading *gradientShading = (RenderTreeNodeContentItem::GradientShading *)shading->fill->shading.get();
                
                if (gradientShading->opacity != 0.0) {
                    std::vector<Color> colors;
                    std::vector<float> locations;
                    for (const auto &color : gradientShading->colors) {
                        colors.push_back(Color(color.r, color.g, color.b, color.a * gradientShading->opacity * renderAlpha));
                    }
                    locations = gradientShading->locations;
                    
                    Gradient gradient(colors, locations);
                    Vector2D start(gradientShading->start.x, gradientShading->start.y);
                    Vector2D end(gradientShading->end.x, gradientShading->end.y);
                    
                    switch (gradientShading->gradientType) {
                        case GradientType::Linear: {
                            canvas->linearGradientFillPath(iteratePaths, rule, gradient, start, end);
                            break;
                        }
                        case GradientType::Radial: {
                            canvas->radialGradientFillPath(iteratePaths, rule, gradient, start, start.distanceTo(end));
                            break;
                        }
                        default: {
                            break;
                        }
                    }
                }
            }
        }
    }
    
    for (auto it = item->subItems.rbegin(); it != item->subItems.rend(); it++) {
        const auto &subItem = *it;
        drawLottieContentItem(canvas, subItem, renderAlpha, globalSize, currentTransform, bezierPathsBoundingBoxContext, configuration);
    }
    
    if (needsTempContext) {
        canvas->popLayer();
    }
    canvas->restoreState();
}

static bool clipToMaskItemIfPossible(std::shared_ptr<Canvas> const &canvas, std::shared_ptr<RenderTreeNodeContentItem> item, Transform2D const &parentTransform) {
    auto currentTransform = parentTransform;
    Transform2D localTransform = item->transform;
    currentTransform = localTransform * currentTransform;
    
    float normalizedOpacity = item->alpha;
    if (normalizedOpacity < 1.0f - minVisibleAlpha) {
        return false;
    }
    
    if (item->shadings.size() > 1) {
        return false;
    }
    
    for (const auto &shading : item->shadings) {
        CanvasPathEnumerator iteratePaths;
        iteratePaths = [&](std::function<void(PathCommand const &)> &&iterate) {
            enumeratePaths(item, shading->subItemLimit, Transform2D::identity(), true, [&](BezierPath const &sourcePath, Transform2D const &transform) {
                auto path = sourcePath.copyUsingTransform(transform);
                
                PathCommand pathCommand;
                std::optional<PathElement> previousElement;
                for (const auto &element : path.elements()) {
                    if (previousElement.has_value()) {
                        if (previousElement->vertex.outTangentRelative().isZero() && element.vertex.inTangentRelative().isZero()) {
                            pathCommand.type = PathCommandType::LineTo;
                            pathCommand.points[0] = element.vertex.point;
                            iterate(pathCommand);
                        } else {
                            pathCommand.type = PathCommandType::CurveTo;
                            pathCommand.points[2] = element.vertex.point;
                            pathCommand.points[1] = element.vertex.inTangent;
                            pathCommand.points[0] = previousElement->vertex.outTangent;
                            iterate(pathCommand);
                        }
                    } else {
                        pathCommand.type = PathCommandType::MoveTo;
                        pathCommand.points[0] = element.vertex.point;
                        iterate(pathCommand);
                    }
                    previousElement = element;
                }
                if (path.closed().value_or(true)) {
                    pathCommand.type = PathCommandType::Close;
                    iterate(pathCommand);
                }
            });
        };
        
        if (shading->stroke) {
            return false;
        } else if (shading->fill) {
            FillRule rule = FillRule::NonZeroWinding;
            switch (shading->fill->rule) {
                case FillRule::EvenOdd: {
                    rule = FillRule::EvenOdd;
                    break;
                }
                case FillRule::NonZeroWinding: {
                    rule = FillRule::NonZeroWinding;
                    break;
                }
                default: {
                    break;
                }
            }
            
            if (shading->fill->shading->type() == RenderTreeNodeContentItem::ShadingType::Solid) {
                RenderTreeNodeContentItem::SolidShading *solidShading = (RenderTreeNodeContentItem::SolidShading *)shading->fill->shading.get();
                if (solidShading->opacity <= 1.0f - minVisibleAlpha) {
                    return false;
                }
                return canvas->clipPath(iteratePaths, rule, currentTransform);
            } else if (shading->fill->shading->type() == RenderTreeNodeContentItem::ShadingType::Gradient) {
                return false;
            }
        }
    }
    
    for (auto it = item->subItems.rbegin(); it != item->subItems.rend(); it++) {
        const auto &subItem = *it;
        if (clipToMaskItemIfPossible(canvas, subItem, currentTransform)) {
            return true;
        }
    }
    
    return false;
}

static bool clipToMaskIfPossible(std::shared_ptr<Canvas> const &canvas, std::shared_ptr<RenderTreeNode> mask, bool invertMask, Transform2D const &parentTransform) {
    if (invertMask) {
        return false;
    }
    if (mask->alpha() < 1.0f - minVisibleAlpha) {
        return false;
    }
    if (mask->drawContentCount != 1) {
        return false;
    }
    
    auto currentTransform = parentTransform;
    Transform2D localTransform = mask->transform();
    currentTransform = localTransform * currentTransform;
    
    if (mask->_contentItem) {
        return clipToMaskItemIfPossible(canvas, mask->_contentItem, currentTransform);
    }
    
    for (const auto &subnode : mask->subnodes()) {
        if (clipToMaskIfPossible(canvas, subnode, invertMask, currentTransform)) {
            return true;
        }
    }
    
    return false;
}

static void renderLottieRenderNode(std::shared_ptr<RenderTreeNode> node, std::shared_ptr<Canvas> const &canvas, Vector2D const &globalSize, Transform2D const &parentTransform, float parentAlpha, BezierPathsBoundingBoxContext &bezierPathsBoundingBoxContext, CanvasRenderer::Configuration const &configuration) {
    float normalizedOpacity = node->alpha();
    float layerAlpha = ((float)normalizedOpacity) * parentAlpha;
    
    if (node->isHidden() || normalizedOpacity < minVisibleAlpha) {
        return;
    }
    
    auto currentTransform = parentTransform;
    Transform2D localTransform = node->transform();
    currentTransform = localTransform * currentTransform;
    
    bool masksToBounds = node->masksToBounds();
    if (masksToBounds) {
        CGRect effectiveGlobalBounds = CGRect(0.0f, 0.0f, node->size().x, node->size().y).applyingTransform(currentTransform);
        if (effectiveGlobalBounds.width <= 0.0f || effectiveGlobalBounds.height <= 0.0f) {
            return;
        }
        if (effectiveGlobalBounds.contains(CGRect(0.0, 0.0, globalSize.x, globalSize.y))) {
            masksToBounds = false;
        }
    }
    
    canvas->saveState();
    canvas->concatenate(node->transform());
    
    if (masksToBounds) {
        canvas->clip(lottie::CGRect(0.0f, 0.0f, node->size().x, node->size().y));
    }
    
    bool needsTempContext = false;
    bool didClipToMask = false;
    if (node->mask() && !node->mask()->isHidden() && node->mask()->alpha() >= minVisibleAlpha) {
        if (clipToMaskIfPossible(canvas, node->mask(), node->invertMask(), Transform2D::identity())) {
            didClipToMask = true;
        } else {
            needsTempContext = true;
        }
    }
    if (layerAlpha != 1.0 && node->drawContentCount > 1 && !configuration.disableGroupTransparency) {
        needsTempContext = true;
    }
    
    std::optional<CGRect> localRect;
    if (needsTempContext) {
        if (configuration.canUseMoreMemory && globalSize.x <= minGlobalRectCalculationSize && globalSize.y <= minGlobalRectCalculationSize) {
            localRect = CGRect::veryLarge();
        } else {
            localRect = getRenderNodeLocalRect(node, false, bezierPathsBoundingBoxContext);
        }
        if (!localRect) {
            canvas->restoreState();
            return;
        }
        
        if (!canvas->pushLayer(localRect.value(), layerAlpha, std::nullopt)) {
            canvas->restoreState();
            return;
        }
        
        // Will restore to this state when applying the mask over current contents
        canvas->saveState();
    }
    
    float renderAlpha = 1.0f;
    if (needsTempContext) {
        renderAlpha = 1.0f;
    } else {
        renderAlpha = layerAlpha;
    }
    
    if (node->_contentItem) {
        drawLottieContentItem(canvas, node->_contentItem, renderAlpha, globalSize, currentTransform, bezierPathsBoundingBoxContext, configuration);
    }
    
    for (const auto &subnode : node->subnodes()) {
        renderLottieRenderNode(subnode, canvas, globalSize, currentTransform, renderAlpha, bezierPathsBoundingBoxContext, configuration);
    }
    
    if (needsTempContext) {
        canvas->restoreState();
        
        if (!didClipToMask && (node->mask() && !node->mask()->isHidden() && node->mask()->alpha() >= minVisibleAlpha)) {
            canvas->pushLayer(localRect.value(), 1.0, node->invertMask() ? lottie::Canvas::MaskMode::Inverse : lottie::Canvas::MaskMode::Normal);
            
            if (node->mask() && !node->mask()->isHidden() && node->mask()->alpha() >= minVisibleAlpha) {
                renderLottieRenderNode(node->mask(), canvas, globalSize, currentTransform, 1.0, bezierPathsBoundingBoxContext, configuration);
            }
            
            canvas->popLayer();
        }
        canvas->popLayer();
    }
    
    canvas->restoreState();
}

}

class CanvasRenderer::Impl {
public:
    Impl() {
        _bezierPathsBoundingBoxContext = std::make_shared<BezierPathsBoundingBoxContext>();
    }
    
public:
    std::shared_ptr<BezierPathsBoundingBoxContext> bezierPathsBoundingBoxContext() const {
        return _bezierPathsBoundingBoxContext;
    }
    
private:
    std::shared_ptr<BezierPathsBoundingBoxContext> _bezierPathsBoundingBoxContext;
};

CanvasRenderer::CanvasRenderer() :
_impl(std::make_shared<Impl>()) {
}

void CanvasRenderer::render(std::shared_ptr<Renderer> renderer, std::shared_ptr<Canvas> canvas, Vector2D const &size, CanvasRenderer::Configuration const &configuration) {
    std::shared_ptr<RenderTreeNode> renderNode = renderer->renderNode();
    if (!renderNode) {
        return;
    }
    
    Vector2D scale = Vector2D(size.x / (float)renderer->size().x, size.y / (float)renderer->size().y);
    canvas->saveState();
    canvas->concatenate(Transform2D::makeScale(scale.x, scale.y));
    
    Transform2D rootTransform = Transform2D::identity().scaled(Vector2D(size.x / (float)renderer->size().x, size.y / (float)renderer->size().y));
    renderLottieRenderNode(renderNode, canvas, size, rootTransform, 1.0, *_impl->bezierPathsBoundingBoxContext().get(), configuration);
    
    canvas->restoreState();
}

}
