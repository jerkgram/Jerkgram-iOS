#import <TgVoipWebrtc/LibYuvBinding.h>

#include "third_party/libyuv/include/libyuv/convert_from.h"


@implementation LibYUVConverter

+ (BOOL)I420ToNV12WithSrcY:(const uint8_t *)src_y
               srcStrideY:(int)src_stride_y
                    srcU:(const uint8_t *)src_u
               srcStrideU:(int)src_stride_u
                    srcV:(const uint8_t *)src_v
               srcStrideV:(int)src_stride_v
                    dstY:(uint8_t *)dst_y
               dstStrideY:(int)dst_stride_y
                   dstUV:(uint8_t *)dst_uv
               dstStrideUV:(int)dst_stride_uv
                    width:(int)width
                   height:(int)height {
    // Call the actual libyuv function
    int result = libyuv::I420ToNV12(src_y, src_stride_y, src_u, src_stride_u, src_v, src_stride_v,
                                   dst_y, dst_stride_y, dst_uv, dst_stride_uv, width, height);

    // Return YES if the conversion was successful, NO otherwise
    return result == 0;
}

@end
