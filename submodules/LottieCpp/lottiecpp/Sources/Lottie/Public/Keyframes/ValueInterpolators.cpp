#include "ValueInterpolators.hpp"

#if __APPLE__
#include <Accelerate/Accelerate.h>
#endif

namespace lottie {

#if __APPLE__

void batchInterpolate(std::vector<PathElement> const &from, std::vector<PathElement> const &to, BezierPath &resultPath, float amount) {
    int elementCount = (int)from.size();
    if (elementCount > (int)to.size()) {
        elementCount = (int)to.size();
    }
    
    static_assert(sizeof(PathElement) == 4 * 2 * 3);
    
    resultPath.setElementCount(elementCount);
    float floatAmount = (float)amount;
    vDSP_vintb((float *)&from[0], 1, (float *)&to[0], 1, &floatAmount, (float *)&resultPath.elements()[0], 1, elementCount * 2 * 3);
}

#else

void batchInterpolate(std::vector<PathElement> const &from, std::vector<PathElement> const &to, BezierPath &resultPath, float amount) {
    int elementCount = (int)from.size();
    if (elementCount > (int)to.size()) {
        elementCount = (int)to.size();
    }

    static_assert(sizeof(PathElement) == 4 * 2 * 3);

    resultPath.setElementCount(elementCount);
    
    float *fromValues = (float *)&from[0];
    float *toValues = (float *)&to[0];
    float *outValues = (float *)&resultPath.elements()[0];
    int numValues = elementCount * 2 * 3;
    
    for (int i = 0; i < numValues; i++) {
        outValues[i] = fromValues[i] + ((toValues[i] - fromValues[i]) * amount);
    }
}

#endif

}
