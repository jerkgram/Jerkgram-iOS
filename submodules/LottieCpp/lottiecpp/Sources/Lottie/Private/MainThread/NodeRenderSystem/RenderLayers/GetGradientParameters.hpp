#ifndef ShapeRenderLayer_hpp
#define ShapeRenderLayer_hpp

#include <LottieCpp/Color.h>
#include "Lottie/Private/MainThread/NodeRenderSystem/Protocols/NodeOutput.hpp"
#include "Lottie/Public/Primitives/GradientColorSet.hpp"

namespace lottie {

void getGradientParameters(int numberOfColors, GradientColorSet const &colors, std::vector<Color> &outColors, std::vector<float> &outLocations);

}

#endif /* ShapeRenderLayer_hpp */
