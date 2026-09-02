#include <LottieCpp/VectorsCocoa.h>

#import <QuartzCore/QuartzCore.h>

namespace lottie {

::CATransform3D nativeTransform(Transform2D const &value) {
    CGAffineTransform at = CGAffineTransformMake(
        value.rows().columns[0][0], value.rows().columns[0][1],
        value.rows().columns[1][0], value.rows().columns[1][1],
        value.rows().columns[2][0], value.rows().columns[2][1]
    );
    return CATransform3DMakeAffineTransform(at);
}

Transform2D fromNativeTransform(::CATransform3D const &value) {
    CGAffineTransform at = CATransform3DGetAffineTransform(value);
    return Transform2D(
        LottieFloat3x3({
            lottieSimdMakeFloat3(at.a, at.b, 0.0),
            lottieSimdMakeFloat3(at.c, at.d, 0.0),
            lottieSimdMakeFloat3(at.tx, at.ty, 1.0)
        })
    );
}

}