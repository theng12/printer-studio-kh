#include <cups/raster.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int output_failed = 0;

static size_t consumer_put_bytes(void *info, const void *buffer, size_t count) {
    int fd = (int)(intptr_t)info;
    const uint8_t *p = (const uint8_t *)buffer;
    size_t written = 0;
    while (written < count) {
        ssize_t n = write(fd, p + written, count - written);
        if (n < 0) {
            if (errno == EINTR) continue;
            output_failed = 1;
            return written;
        }
        if (n == 0) { output_failed = 1; break; }
        written += (size_t)n;
    }
    return written;
}

static void provider_release_data(void *info, const void *data, size_t size) {
    (void)info;
    (void)size;
    free((void *)data);
}

int main(int argc, char **argv) {
    if (argc < 6 || argc > 7) {
        fprintf(stderr, "ERROR: [urftopdf] Usage: %s job-id user title copies options [filename]\n", argv[0]);
        return 1;
    }

    int in_fd = STDIN_FILENO;
    if (argc == 7) {
        in_fd = open(argv[6], O_RDONLY);
        if (in_fd < 0) {
            fprintf(stderr, "ERROR: [urftopdf] Unable to open input file \"%s\": %s\n", argv[6], strerror(errno));
            return 1;
        }
    }

    cups_raster_t *r = cupsRasterOpen(in_fd, CUPS_RASTER_READ);
    if (!r) {
        fprintf(stderr, "ERROR: [urftopdf] Unable to open raster stream: %s\n", strerror(errno));
        if (in_fd != STDIN_FILENO) close(in_fd);
        return 1;
    }

    cups_page_header2_t h;
    int page_count = 0;
    CGContextRef pdf = NULL;
    int status = 0;

    while (cupsRasterReadHeader2(r, &h)) {
        page_count++;

        if (h.cupsWidth == 0 || h.cupsHeight == 0) {
            fprintf(stderr, "ERROR: [urftopdf] Invalid positive dimensions on page %d: %u x %u\n",
                    page_count, h.cupsWidth, h.cupsHeight);
            status = 1;
            break;
        }

        if (h.HWResolution[0] == 0 || h.HWResolution[1] == 0) {
            fprintf(stderr, "ERROR: [urftopdf] Invalid resolution on page %d: %u x %u DPI\n",
                    page_count, h.HWResolution[0], h.HWResolution[1]);
            status = 1;
            break;
        }

        if (h.cupsColorOrder != CUPS_ORDER_CHUNKED) {
            fprintf(stderr, "ERROR: [urftopdf] Unsupported planar/banded pixel layout on page %d\n", page_count);
            status = 1;
            break;
        }

        CGColorSpaceRef cs = NULL;
        const CGFloat *decode = NULL;
        static const CGFloat decode_ink[2] = { 1.0, 0.0 };
        CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
        size_t min_bytes_per_line = 0;

        if (h.cupsColorSpace == CUPS_CSPACE_W) {
            // Luminance DeviceGray (0 = black, 255/1 = white)
            if (h.cupsBitsPerColor == 1 && h.cupsBitsPerPixel == 1) {
                cs = CGColorSpaceCreateDeviceGray();
                min_bytes_per_line = ((size_t)h.cupsWidth + 7) / 8;
            } else if (h.cupsBitsPerColor == 8 && h.cupsBitsPerPixel == 8) {
                cs = CGColorSpaceCreateDeviceGray();
                min_bytes_per_line = (size_t)h.cupsWidth;
            } else {
                fprintf(stderr, "ERROR: [urftopdf] Unsupported bit depth for luminance grayscale on page %d: bpc=%u, bpp=%u\n",
                        page_count, h.cupsBitsPerColor, h.cupsBitsPerPixel);
                status = 1;
                break;
            }
        } else if (h.cupsColorSpace == CUPS_CSPACE_SW ||
                   h.cupsColorSpace == CUPS_CSPACE_K ||
                   h.cupsColorSpace == CUPS_CSPACE_WHITE) {
            // libcups maps native Apple ink-gray streams to SW; 0 is white in those streams.
            if (h.cupsBitsPerColor == 1 && h.cupsBitsPerPixel == 1) {
                cs = CGColorSpaceCreateDeviceGray();
                decode = decode_ink;
                min_bytes_per_line = ((size_t)h.cupsWidth + 7) / 8;
            } else if (h.cupsBitsPerColor == 8 && h.cupsBitsPerPixel == 8) {
                cs = CGColorSpaceCreateDeviceGray();
                decode = decode_ink;
                min_bytes_per_line = (size_t)h.cupsWidth;
            } else {
                fprintf(stderr, "ERROR: [urftopdf] Unsupported bit depth for ink/gray space %u on page %d: bpc=%u, bpp=%u\n",
                        h.cupsColorSpace, page_count, h.cupsBitsPerColor, h.cupsBitsPerPixel);
                status = 1;
                break;
            }
        } else if (h.cupsColorSpace == CUPS_CSPACE_RGB ||
                   h.cupsColorSpace == CUPS_CSPACE_SRGB ||
                   h.cupsColorSpace == CUPS_CSPACE_ADOBERGB) {
            if (h.cupsBitsPerColor == 8 && h.cupsBitsPerPixel == 24) {
                cs = CGColorSpaceCreateDeviceRGB();
                min_bytes_per_line = (size_t)h.cupsWidth * 3;
            } else if (h.cupsBitsPerColor == 8 && h.cupsBitsPerPixel == 32) {
                cs = CGColorSpaceCreateDeviceRGB();
                bitmapInfo = kCGImageAlphaNoneSkipLast;
                min_bytes_per_line = (size_t)h.cupsWidth * 4;
            } else {
                fprintf(stderr, "ERROR: [urftopdf] Unsupported RGB bit depth on page %d: bpc=%u, bpp=%u\n",
                        page_count, h.cupsBitsPerColor, h.cupsBitsPerPixel);
                status = 1;
                break;
            }
        } else if (h.cupsColorSpace == CUPS_CSPACE_RGBA) {
            if (h.cupsBitsPerColor == 8 && h.cupsBitsPerPixel == 32) {
                cs = CGColorSpaceCreateDeviceRGB();
                bitmapInfo = kCGImageAlphaLast;
                min_bytes_per_line = (size_t)h.cupsWidth * 4;
            } else {
                fprintf(stderr, "ERROR: [urftopdf] Unsupported RGBA bit depth on page %d: bpc=%u, bpp=%u\n",
                        page_count, h.cupsBitsPerColor, h.cupsBitsPerPixel);
                status = 1;
                break;
            }
        } else {
            fprintf(stderr, "ERROR: [urftopdf] Unsupported cupsColorSpace %u on page %d\n",
                    h.cupsColorSpace, page_count);
            status = 1;
            break;
        }

        if (!cs) {
            fprintf(stderr, "ERROR: [urftopdf] Failed to create the page colour space\n");
            status = 1;
            break;
        }

        if ((size_t)h.cupsBytesPerLine < min_bytes_per_line) {
            fprintf(stderr, "ERROR: [urftopdf] Invalid cupsBytesPerLine on page %d: %u (expected >= %zu)\n",
                    page_count, h.cupsBytesPerLine, min_bytes_per_line);
            CGColorSpaceRelease(cs);
            status = 1;
            break;
        }

        if ((size_t)h.cupsHeight > 0 && SIZE_MAX / (size_t)h.cupsHeight < (size_t)h.cupsBytesPerLine) {
            fprintf(stderr, "ERROR: [urftopdf] Allocation size overflow on page %d: %u rows * %u bytes\n",
                    page_count, h.cupsHeight, h.cupsBytesPerLine);
            CGColorSpaceRelease(cs);
            status = 1;
            break;
        }

        size_t total_bytes = (size_t)h.cupsHeight * (size_t)h.cupsBytesPerLine;
        if (total_bytes > (size_t)1024 * 1024 * 1024) {
            fprintf(stderr, "ERROR: [urftopdf] Page allocation exceeds the 1 GiB limit on page %d: %zu bytes\n",
                    page_count, total_bytes);
            CGColorSpaceRelease(cs);
            status = 1;
            break;
        }

        uint8_t *page_data = malloc(total_bytes);
        if (!page_data) {
            fprintf(stderr, "ERROR: [urftopdf] Out of memory allocating %zu bytes for page %d\n",
                    total_bytes, page_count);
            CGColorSpaceRelease(cs);
            status = 1;
            break;
        }

        bool truncated = false;
        for (unsigned y = 0; y < h.cupsHeight; y++) {
            uint8_t *row_dest = page_data + (size_t)y * (size_t)h.cupsBytesPerLine;
            unsigned n = cupsRasterReadPixels(r, row_dest, h.cupsBytesPerLine);
            if (n != h.cupsBytesPerLine) {
                fprintf(stderr, "ERROR: [urftopdf] Truncated raster data on page %d: read %u of %u bytes at line %u of %u\n",
                        page_count, n, h.cupsBytesPerLine, y + 1, h.cupsHeight);
                truncated = true;
                break;
            }
        }

        if (truncated) {
            free(page_data);
            CGColorSpaceRelease(cs);
            status = 1;
            break;
        }

        double page_w_pt = (double)h.cupsWidth * 72.0 / (double)h.HWResolution[0];
        double page_h_pt = (double)h.cupsHeight * 72.0 / (double)h.HWResolution[1];
        CGRect mediaBox = CGRectMake(0, 0, page_w_pt, page_h_pt);

        if (!pdf) {
            CGDataConsumerCallbacks cb = { .putBytes = consumer_put_bytes, .releaseConsumer = NULL };
            CGDataConsumerRef consumer = CGDataConsumerCreate((void *)(intptr_t)STDOUT_FILENO, &cb);
            if (!consumer) {
                fprintf(stderr, "ERROR: [urftopdf] Failed to allocate PDF consumer\n");
                free(page_data); CGColorSpaceRelease(cs); status = 1; break;
            }
            pdf = CGPDFContextCreate(consumer, NULL, NULL);
            CGDataConsumerRelease(consumer);
            if (!pdf) {
                fprintf(stderr, "ERROR: [urftopdf] Failed to create CGPDFContext on page %d\n", page_count);
                free(page_data);
                CGColorSpaceRelease(cs);
                status = 1;
                break;
            }
        }

        CFDataRef boxData = CFDataCreate(NULL, (const UInt8 *)&mediaBox, sizeof(CGRect));
        if (!boxData) {
            fprintf(stderr, "ERROR: [urftopdf] Failed to allocate page geometry\n");
            free(page_data); CGColorSpaceRelease(cs); status = 1; break;
        }
        const void *keys[] = { kCGPDFContextMediaBox };
        const void *vals[] = { boxData };
        CFDictionaryRef pageDict = CFDictionaryCreate(NULL, keys, vals, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        if (!pageDict) {
            fprintf(stderr, "ERROR: [urftopdf] Failed to allocate PDF page metadata\n");
            CFRelease(boxData); free(page_data); CGColorSpaceRelease(cs); status = 1; break;
        }
        CGPDFContextBeginPage(pdf, pageDict);
        CFRelease(pageDict);
        CFRelease(boxData);

        CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, page_data, total_bytes, provider_release_data);
        if (!provider) {
            fprintf(stderr, "ERROR: [urftopdf] Failed to allocate image provider\n");
            free(page_data); CGColorSpaceRelease(cs); CGPDFContextEndPage(pdf); status = 1; break;
        }
        CGImageRef img = CGImageCreate(
            h.cupsWidth, h.cupsHeight,
            h.cupsBitsPerColor, h.cupsBitsPerPixel,
            h.cupsBytesPerLine, cs, bitmapInfo, provider, decode, false, kCGRenderingIntentDefault
        );

        if (!img) {
            fprintf(stderr, "ERROR: [urftopdf] Failed to create CGImage for page %d\n", page_count);
            CGDataProviderRelease(provider);
            CGColorSpaceRelease(cs);
            CGPDFContextEndPage(pdf);
            status = 1;
            break;
        }

        CGContextDrawImage(pdf, mediaBox, img);
        CGImageRelease(img);
        CGDataProviderRelease(provider);
        CGColorSpaceRelease(cs);

        CGPDFContextEndPage(pdf);
    }

    const char *raster_error = cupsRasterErrorString();
    if (status == 0 && raster_error && *raster_error) {
        fprintf(stderr, "ERROR: [urftopdf] Invalid/truncated page header: %s\n", raster_error);
        status = 1;
    }

    if (status == 0 && page_count == 0) {
        fprintf(stderr, "ERROR: [urftopdf] No valid pages found in raster input\n");
        status = 1;
    }

    if (pdf) {
        CGPDFContextClose(pdf);
        CGContextRelease(pdf);
    }

    if (output_failed) {
        fprintf(stderr, "ERROR: [urftopdf] Could not write the complete PDF output\n");
        status = 1;
    }
    cupsRasterClose(r);
    if (in_fd != STDIN_FILENO) close(in_fd);
    return status;
}
