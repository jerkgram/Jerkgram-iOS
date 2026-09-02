#include <LottieCpp/Vectors.h>

#include "Lottie/Private/Parsing/JsonParsing.hpp"
#include "Lottie/Public/Keyframes/Interpolatable.hpp"

#include <math.h>
#include <cfloat>

namespace lottie {

Vector1D::Vector1D(lottiejson11::Json const &json) noexcept(false) {
    if (json.is_number()) {
        value = json.number_value();
    } else if (json.is_array()) {
        if (json.array_items().empty()) {
            throw LottieParsingException();
        }
        if (!json.array_items()[0].is_number()) {
            throw LottieParsingException();
        }
        value = json.array_items()[0].number_value();
    } else {
        throw LottieParsingException();
    }
}

lottiejson11::Json Vector1D::toJson() const {
    return lottiejson11::Json(value);
}

Vector2D::Vector2D(lottiejson11::Json const &json) noexcept(false) {
    x = 0.0;
    y = 0.0;
    
    if (json.is_array()) {
        int index = 0;
        
        if (json.array_items().size() > index) {
            if (!json.array_items()[index].is_number()) {
                throw LottieParsingException();
            }
            x = json.array_items()[index].number_value();
            index++;
        }
        
        if (json.array_items().size() > index) {
            if (!json.array_items()[index].is_number()) {
                throw LottieParsingException();
            }
            y = json.array_items()[index].number_value();
            index++;
        }
    } else if (json.is_object()) {
        auto xAny = getAny(json.object_items(), "x");
        if (xAny.is_number()) {
            x = xAny.number_value();
        } else if (xAny.is_array()) {
            if (xAny.array_items().empty()) {
                throw LottieParsingException();
            }
            if (!xAny.array_items()[0].is_number()) {
                throw LottieParsingException();
            }
            x = xAny.array_items()[0].number_value();
        }
        
        auto yAny = getAny(json.object_items(), "y");
        if (yAny.is_number()) {
            y = yAny.number_value();
        } else if (yAny.is_array()) {
            if (yAny.array_items().empty()) {
                throw LottieParsingException();
            }
            if (!yAny.array_items()[0].is_number()) {
                throw LottieParsingException();
            }
            y = yAny.array_items()[0].number_value();
        }
    } else {
        throw LottieParsingException();
    }
}

lottiejson11::Json Vector2D::toJson() const {
    lottiejson11::Json::object result;
    
    result.insert(std::make_pair("x", x));
    result.insert(std::make_pair("y", y));
    
    return lottiejson11::Json(result);
}

Vector3D::Vector3D(lottiejson11::Json const &json) noexcept(false) {
    if (!json.is_array()) {
        throw LottieParsingException();
    }
    
    int index = 0;
    
    x = 0.0;
    y = 0.0;
    z = 0.0;
    
    if (json.array_items().size() > index) {
        if (!json.array_items()[index].is_number()) {
            throw LottieParsingException();
        }
        x = json.array_items()[index].number_value();
        index++;
    }
    
    if (json.array_items().size() > index) {
        if (!json.array_items()[index].is_number()) {
            throw LottieParsingException();
        }
        y = json.array_items()[index].number_value();
        index++;
    }
    
    if (json.array_items().size() > index) {
        if (!json.array_items()[index].is_number()) {
            throw LottieParsingException();
        }
        z = json.array_items()[index].number_value();
        index++;
    }
}

lottiejson11::Json Vector3D::toJson() const {
    lottiejson11::Json::array result;
    
    result.push_back(lottiejson11::Json(x));
    result.push_back(lottiejson11::Json(y));
    result.push_back(lottiejson11::Json(z));
    
    return lottiejson11::Json(result);
}

Transform2D Transform2D::_identity = Transform2D(
    LottieFloat3x3({
        lottieSimdMakeFloat3(1.0f, 0.0f, 0.0f),
        lottieSimdMakeFloat3(0.0f, 1.0f, 0.0f),
        lottieSimdMakeFloat3(0.0f, 0.0f, 1.0f)
    })
);

Transform2D Transform2D::makeTranslation(float tx, float ty) {
    return Transform2D(LottieFloat3x3({
        lottieSimdMakeFloat3(1.0f, 0.0f, 0.0f),
        lottieSimdMakeFloat3(0.0f, 1.0f, 0.0f),
        lottieSimdMakeFloat3(tx, ty, 1.0f)
    }));
}

Transform2D Transform2D::makeScale(float sx, float sy) {
    return Transform2D(LottieFloat3x3({
        lottieSimdMakeFloat3(sx, 0.0f, 0.0f),
        lottieSimdMakeFloat3(0.0f, sy, 0.0f),
        lottieSimdMakeFloat3(0.0f, 0.0f, 1.0f)
    }));
}

Transform2D Transform2D::makeRotation(float radians) {
    float c = cos(radians);
    float s = sin(radians);
    
    return Transform2D(LottieFloat3x3({
        lottieSimdMakeFloat3(c, s, 0.0f),
        lottieSimdMakeFloat3(-s, c, 0.0f),
        lottieSimdMakeFloat3(0.0f, 0.0f, 1.0f)
    }));
}

Transform2D Transform2D::makeSkew(float skew, float skewAxis) {
    if (std::abs(skew) <= FLT_EPSILON && std::abs(skewAxis) <= FLT_EPSILON) {
        return Transform2D::identity();
    }
    
    float mCos = cos(degreesToRadians(skewAxis));
    float mSin = sin(degreesToRadians(skewAxis));
    float aTan = tan(degreesToRadians(skew));
    
    LottieFloat3x3 simd1 = LottieFloat3x3({
        lottieSimdMakeFloat3(mCos, -mSin, 0.0),
        lottieSimdMakeFloat3(mSin, mCos, 0.0),
        lottieSimdMakeFloat3(0.0, 0.0, 1.0)
    });
    
    LottieFloat3x3 simd2 = LottieFloat3x3({
        lottieSimdMakeFloat3(1.0, 0.0, 0.0),
        lottieSimdMakeFloat3(aTan, 1.0, 0.0),
        lottieSimdMakeFloat3(0.0, 0.0, 1.0)
    });
    
    LottieFloat3x3 simd3 = LottieFloat3x3({
        lottieSimdMakeFloat3(mCos, mSin, 0.0),
        lottieSimdMakeFloat3(-mSin, mCos, 0.0),
        lottieSimdMakeFloat3(0.0, 0.0, 1.0)
    });
    
    LottieFloat3x3 result = lottieSimdMul(lottieSimdMul(simd3, simd2), simd1);
    Transform2D resultTransform(result);
    
    return resultTransform;
}

Transform2D Transform2D::makeTransform(
    Vector2D const &anchor,
    Vector2D const &position,
    Vector2D const &scale,
    float rotation,
    std::optional<float> skew,
    std::optional<float> skewAxis
) {
    Transform2D result = Transform2D::identity();
    if (skew.has_value() && skewAxis.has_value()) {
        result = Transform2D::identity().translated(position).rotated(rotation).skewed(-skew.value(), skewAxis.value()).scaled(Vector2D(scale.x * 0.01, scale.y * 0.01)).translated(Vector2D(-anchor.x, -anchor.y));
    } else {
        result = Transform2D::identity().translated(position).rotated(rotation).scaled(Vector2D(scale.x * 0.01, scale.y * 0.01)).translated(Vector2D(-anchor.x, -anchor.y));
    }
    
    return result;
}

Transform2D Transform2D::rotated(float degrees) const {
    return Transform2D::makeRotation(degreesToRadians(degrees)) * (*this);
}

Transform2D Transform2D::translated(Vector2D const &translation) const {
    return Transform2D::makeTranslation(translation.x, translation.y) * (*this);
}

Transform2D Transform2D::scaled(Vector2D const &scale) const {
    return Transform2D::makeScale(scale.x, scale.y) * (*this);
}

Transform2D Transform2D::skewed(float skew, float skewAxis) const {
    return Transform2D::makeSkew(skew, skewAxis) * (*this);
}

float interpolate(float value, float to, float amount) {
    return value + ((to - value) * amount);
}

Vector1D interpolate(
    Vector1D const &from,
    Vector1D const &to,
    float amount
) {
    return Vector1D(interpolate(from.value, to.value, amount));
}

Vector2D interpolate(
    Vector2D const &from,
    Vector2D const &to,
    float amount
) {
    return Vector2D(interpolate(from.x, to.x, amount), interpolate(from.y, to.y, amount));
}


Vector3D interpolate(
    Vector3D const &from,
    Vector3D const &to,
    float amount
) {
    return Vector3D(interpolate(from.x, to.x, amount), interpolate(from.y, to.y, amount), interpolate(from.z, to.z, amount));
}

struct InterpolationPoint2D {
    InterpolationPoint2D(Vector2D const point_, float distance_) :
    point(point_), distance(distance_) {
    }
    
    Vector2D point;
    float distance;
};

namespace {
    float interpolateFloat(float value, float to, float amount) {
        return value + ((to - value) * amount);
    }
}

Vector2D Vector2D::pointOnPath(Vector2D const &to, Vector2D const &outTangent, Vector2D const &inTangent, float amount) const {
    auto a = interpolate(outTangent, amount);
    auto b = outTangent.interpolate(inTangent, amount);
    auto c = inTangent.interpolate(to, amount);
    auto d = a.interpolate(b, amount);
    auto e = b.interpolate(c, amount);
    auto f = d.interpolate(e, amount);
    return f;
}

Vector2D Vector2D::interpolate(Vector2D const &to, float amount) const {
    return Vector2D(
        interpolateFloat(x, to.x, amount),
        interpolateFloat(y, to.y, amount)
    );
}

Vector2D Vector2D::interpolate(
    Vector2D const &to,
    Vector2D const &outTangent,
    Vector2D const &inTangent,
    float amount,
    int maxIterations,
    int samples,
    float accuracy
) const {
    if (amount == 0.0) {
        return *this;
    }
    if (amount == 1.0) {
        return to;
    }
        
    if (colinear(outTangent, inTangent) && outTangent.colinear(inTangent, to)) {
        return interpolate(to, amount);
    }
        
    float step = 1.0 / (float)samples;
    
    std::vector<InterpolationPoint2D> points;
    points.push_back(InterpolationPoint2D(*this, 0.0));
    float totalLength = 0.0;
    
    Vector2D previousPoint = *this;
    float previousAmount = 0.0;
    
    int closestPoint = 0;
    
    while (previousAmount < 1.0) {
        previousAmount = previousAmount + step;
        
        if (previousAmount < amount) {
            closestPoint = closestPoint + 1;
        }
        
        auto newPoint = pointOnPath(to, outTangent, inTangent, previousAmount);
        auto distance = previousPoint.distanceTo(newPoint);
        totalLength = totalLength + distance;
        points.push_back(InterpolationPoint2D(newPoint, totalLength));
        previousPoint = newPoint;
    }
    
    float accurateDistance = amount * totalLength;
    auto point = points[closestPoint];
    
    bool foundPoint = false;
    
    float pointAmount = ((float)closestPoint) * step;
    float nextPointAmount = pointAmount + step;
    
    int refineIterations = 0;
    while (!foundPoint) {
        refineIterations = refineIterations + 1;
        /// First see if the next point is still less than the projected length.
        auto nextPoint = points[std::min(closestPoint + 1, (int)points.size() - 1)];
        if (nextPoint.distance < accurateDistance) {
            point = nextPoint;
            closestPoint = closestPoint + 1;
            pointAmount = ((float)closestPoint) * step;
            nextPointAmount = pointAmount + step;
            if (closestPoint == (int)points.size()) {
                foundPoint = true;
            }
            continue;
        }
        if (accurateDistance < point.distance) {
            closestPoint = closestPoint - 1;
            if (closestPoint < 0) {
                foundPoint = true;
                continue;
            }
            point = points[closestPoint];
            pointAmount = ((float)closestPoint) * step;
            nextPointAmount = pointAmount + step;
            continue;
        }
        
        /// Now we are certain the point is the closest point under the distance
        auto pointDiff = nextPoint.distance - point.distance;
        auto proposedPointAmount = remapFloat((accurateDistance - point.distance) / pointDiff, 0.0, 1.0, pointAmount, nextPointAmount);
        
        auto newPoint = pointOnPath(to, outTangent, inTangent, proposedPointAmount);
        auto newDistance = point.distance + point.point.distanceTo(newPoint);
        pointAmount = proposedPointAmount;
        point = InterpolationPoint2D(newPoint, newDistance);
        if (accurateDistance - newDistance <= accuracy ||
            newDistance - accurateDistance <= accuracy) {
            foundPoint = true;
        }
        
        if (refineIterations == maxIterations) {
            foundPoint = true;
        }
    }
    return point.point;
}

bool CGRect::intersects(CGRect const &other) const {
    if (x + width < other.x || other.x + other.width < x) {
        return false;
    }
    // Check if one rectangle is above the other
    if (y + height < other.y || other.y + other.height < y) {
        return false;
    }
    return true;
}

bool CGRect::contains(CGRect const &other) const {
    return (other.x >= x) &&
        (other.y >= y) &&
        (other.x + other.width <= x + width) &&
        (other.y + other.height <= y + height);
}

CGRect CGRect::intersection(CGRect const &other) const {
    if (!intersects(other)) {
        return CGRect(0, 0, 0, 0);
    }
    
    float intersectX = std::max(x, other.x);
    float intersectY = std::max(y, other.y);
    float intersectWidth = std::min(x + width, other.x + other.width) - intersectX;
    float intersectHeight = std::min(y + height, other.y + other.height) - intersectY;
    
    return CGRect(intersectX, intersectY, intersectWidth, intersectHeight);
}

CGRect CGRect::unionWith(CGRect const &other) const {
    float unionX = std::min(x, other.x);
    float unionY = std::min(y, other.y);
    float unionWidth = std::max(x + width, other.x + other.width) - unionX;
    float unionHeight = std::max(y + height, other.y + other.height) - unionY;
    
    return CGRect(unionX, unionY, unionWidth, unionHeight);
}

CGRect CGRect::applyingTransform(Transform2D const &transform) const {
    if (transform.isIdentity()) {
        return *this;
    }
    
    Vector2D sourceTopLeft = Vector2D(x, y);
    Vector2D sourceTopRight = Vector2D(x + width, y);
    Vector2D sourceBottomLeft = Vector2D(x, y + height);
    Vector2D sourceBottomRight = Vector2D(x + width, y + height);
    
    LottieFloat4 xs = lottieSimdMakeFloat4(sourceTopLeft.x, sourceTopRight.x, sourceBottomLeft.x, sourceBottomRight.x);
    LottieFloat4 ys = lottieSimdMakeFloat4(sourceTopLeft.y, sourceTopRight.y, sourceBottomLeft.y, sourceBottomRight.y);
    
    LottieFloat4 rx = xs * transform.rows().columns[0][0] + ys * transform.rows().columns[1][0] + transform.rows().columns[2][0];
    LottieFloat4 ry = xs * transform.rows().columns[0][1] + ys * transform.rows().columns[1][1] + transform.rows().columns[2][1];
    
    Vector2D topLeft = Vector2D(rx[0], ry[0]);
    Vector2D topRight = Vector2D(rx[1], ry[1]);
    Vector2D bottomLeft = Vector2D(rx[2], ry[2]);
    Vector2D bottomRight = Vector2D(rx[3], ry[3]);
    
    float minX = lottieSimdReduceMin(lottieSimdMakeFloat4(topLeft.x, topRight.x, bottomLeft.x, bottomRight.x));
    float minY = lottieSimdReduceMin(lottieSimdMakeFloat4(topLeft.y, topRight.y, bottomLeft.y, bottomRight.y));
    float maxX = lottieSimdReduceMax(lottieSimdMakeFloat4(topLeft.x, topRight.x, bottomLeft.x, bottomRight.x));
    float maxY = lottieSimdReduceMax(lottieSimdMakeFloat4(topLeft.y, topRight.y, bottomLeft.y, bottomRight.y));
    
    return CGRect(minX, minY, maxX - minX, maxY - minY);
}

}
