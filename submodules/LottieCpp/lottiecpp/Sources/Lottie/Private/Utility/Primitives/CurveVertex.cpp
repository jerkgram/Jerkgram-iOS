#include <LottieCpp/CurveVertex.h>

namespace lottie {

Vector2D transformVector(Vector2D const &v, Transform2D const &m) {
    float transformedX = m.rows().columns[0][0] * v.x + m.rows().columns[1][0] * v.y + m.rows().columns[2][0] * 1.0f;
    float transformedY = m.rows().columns[0][1] * v.x + m.rows().columns[1][1] * v.y + m.rows().columns[2][1] * 1.0f;
    return Vector2D(transformedX, transformedY);
}

}
