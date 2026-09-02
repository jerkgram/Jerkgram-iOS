#ifndef TgVoipWebrtc_LibYuvBinding_h
#define TgVoipWebrtc_LibYuvBinding_h

#import <Foundation/Foundation.h>

@interface LibYUVConverter : NSObject

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
                   height:(int)height;

@end


#endif
