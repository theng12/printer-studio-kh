#include <cups/raster.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>
#include <fcntl.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int parse_cspace(const char *cspace_str, cups_cspace_t *out_cs, int *out_luminance, int *out_rgb) {
    *out_luminance = 0;
    *out_rgb = 0;
    if (strcmp(cspace_str, "K") == 0) {
        *out_cs = CUPS_CSPACE_K;
    } else if (strcmp(cspace_str, "SW") == 0) {
        *out_cs = CUPS_CSPACE_SW;
    } else if (strcmp(cspace_str, "W") == 0) {
        *out_cs = CUPS_CSPACE_W;
        *out_luminance = 1;
    } else if (strcmp(cspace_str, "RGB") == 0) {
        *out_cs = CUPS_CSPACE_RGB;
        *out_rgb = 1;
    } else if (strcmp(cspace_str, "SRGB") == 0) {
        *out_cs = CUPS_CSPACE_SRGB;
        *out_rgb = 1;
    } else {
        return 0;
    }
    return 1;
}

static int write_asymmetric_page(cups_raster_t *r, cups_cspace_t cs, int is_luminance, int is_rgb, unsigned bpp, unsigned w, unsigned h, unsigned dpi, unsigned page_index) {
    cups_page_header2_t hdr;
    memset(&hdr, 0, sizeof(hdr));
    strncpy(hdr.MediaClass, "PwgRaster", sizeof(hdr.MediaClass));
    hdr.cupsBitsPerColor = is_rgb ? 8 : (bpp == 1 ? 1 : 8);
    hdr.cupsBitsPerPixel = bpp;
    hdr.cupsBytesPerLine = (w * bpp + 7) / 8;
    hdr.cupsColorOrder = CUPS_ORDER_CHUNKED;
    hdr.cupsColorSpace = cs;
    hdr.cupsWidth = w;
    hdr.cupsHeight = h;
    hdr.HWResolution[0] = dpi;
    hdr.HWResolution[1] = dpi;
    hdr.cupsPageSize[0] = (float)w * 72.0f / (float)dpi;
    hdr.cupsPageSize[1] = (float)h * 72.0f / (float)dpi;

    if (!cupsRasterWriteHeader2(r, &hdr)) return 0;

    unsigned char *row = calloc(hdr.cupsBytesPerLine, 1);
    if (!row) return 0;

    unsigned mark_w = w / 4;
    unsigned mark_h = h / 4;
    if (mark_w == 0) mark_w = 1;
    if (mark_h == 0) mark_h = 1;

    for (unsigned y = 0; y < h; y++) {
        memset(row, 0, hdr.cupsBytesPerLine);
        int in_mark_y = (y < mark_h);

        for (unsigned x = 0; x < w; x++) {
            // For page 0: mark is top-left
            // For page > 0: mark is top-left with width scaled by page_index to make pages distinct
            unsigned p_mark_w = mark_w / (page_index + 1);
            if (p_mark_w == 0) p_mark_w = 1;
            int in_mark = in_mark_y && (x < p_mark_w);

            if (bpp == 1) {
                int bit = is_luminance ? (!in_mark) : in_mark;
                if (bit) row[x / 8] |= (1 << (7 - (x % 8)));
            } else if (bpp == 8) {
                row[x] = is_luminance ? (in_mark ? 0x00 : 0xff) : (in_mark ? 0xff : 0x00);
            } else if (bpp == 24) {
                uint8_t val = in_mark ? 0x00 : 0xff;
                row[x * 3 + 0] = val;
                row[x * 3 + 1] = val;
                row[x * 3 + 2] = val;
            }
        }
        cupsRasterWritePixels(r, row, hdr.cupsBytesPerLine);
    }

    free(row);
    return 1;
}

static int generate_asymmetric(const char *path, const char *cspace_str, unsigned bpp, unsigned w, unsigned h, unsigned dpi, unsigned pages) {
    cups_cspace_t cs;
    int is_luminance = 0, is_rgb = 0;
    if (!parse_cspace(cspace_str, &cs, &is_luminance, &is_rgb)) {
        fprintf(stderr, "Unknown colorspace: %s\n", cspace_str);
        return 1;
    }

    FILE *fp = fopen(path, "wb");
    if (!fp) {
        perror("fopen");
        return 1;
    }

    cups_raster_t *r = cupsRasterOpen(fileno(fp), CUPS_RASTER_WRITE);
    if (!r) {
        fclose(fp);
        return 2;
    }

    for (unsigned p = 0; p < pages; p++) {
        if (!write_asymmetric_page(r, cs, is_luminance, is_rgb, bpp, w, h, dpi, p)) {
            cupsRasterClose(r);
            fclose(fp);
            return 3;
        }
    }

    cupsRasterClose(r);
    fclose(fp);
    printf("Generated raster %s: %ux%u @ %u dpi, cs=%s, bpp=%u, pages=%u\n",
           path, w, h, dpi, cspace_str, bpp, pages);
    return 0;
}

static int make_invalid(const char *path, const char *type) {
    FILE *fp = fopen(path, "wb");
    if (!fp) return 1;
    cups_raster_t *r = cupsRasterOpen(fileno(fp), CUPS_RASTER_WRITE);
    if (!r) { fclose(fp); return 2; }

    cups_page_header2_t hdr;
    memset(&hdr, 0, sizeof(hdr));
    strncpy(hdr.MediaClass, "PwgRaster", sizeof(hdr.MediaClass));
    hdr.cupsBitsPerColor = 8;
    hdr.cupsBitsPerPixel = 8;
    hdr.cupsColorOrder = CUPS_ORDER_CHUNKED;

    if (strcmp(type, "zero-dim") == 0) {
        hdr.cupsColorSpace = CUPS_CSPACE_SW;
        hdr.cupsWidth = 0;
        hdr.cupsHeight = 100;
        hdr.cupsBytesPerLine = 1;
        hdr.HWResolution[0] = 203;
        hdr.HWResolution[1] = 203;
    } else if (strcmp(type, "zero-dpi") == 0) {
        hdr.cupsColorSpace = CUPS_CSPACE_SW;
        hdr.cupsWidth = 100;
        hdr.cupsHeight = 100;
        hdr.cupsBytesPerLine = 100;
        hdr.HWResolution[0] = 0;
        hdr.HWResolution[1] = 0;
    } else if (strcmp(type, "planar") == 0) {
        hdr.cupsColorSpace = CUPS_CSPACE_RGB;
        hdr.cupsBitsPerPixel = 24;
        hdr.cupsColorOrder = CUPS_ORDER_PLANAR;
        hdr.cupsWidth = 100;
        hdr.cupsHeight = 100;
        hdr.cupsBytesPerLine = 100;
        hdr.HWResolution[0] = 203;
        hdr.HWResolution[1] = 203;
    } else if (strcmp(type, "cmyk") == 0) {
        hdr.cupsColorSpace = CUPS_CSPACE_CMYK;
        hdr.cupsWidth = 100;
        hdr.cupsHeight = 100;
        hdr.cupsBytesPerLine = 400;
        hdr.HWResolution[0] = 203;
        hdr.HWResolution[1] = 203;
    } else {
        fprintf(stderr, "Unknown invalid type: %s\n", type);
        cupsRasterClose(r);
        fclose(fp);
        return 1;
    }

    cupsRasterWriteHeader2(r, &hdr);
    unsigned char buf[400] = {0};
    cupsRasterWritePixels(r, buf, hdr.cupsBytesPerLine);
    cupsRasterClose(r);
    fclose(fp);
    return 0;
}

static int verify_pdf(const char *pdf_path, size_t expected_pages, double expected_w_pt, double expected_h_pt) {
    CFStringRef str = CFStringCreateWithCString(NULL, pdf_path, kCFStringEncodingUTF8);
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, str, kCFURLPOSIXPathStyle, false);
    CGPDFDocumentRef doc = CGPDFDocumentCreateWithURL(url);
    CFRelease(url);
    CFRelease(str);

    if (!doc) {
        fprintf(stderr, "FAIL: Unable to open PDF: %s\n", pdf_path);
        return 1;
    }

    size_t pages = CGPDFDocumentGetNumberOfPages(doc);
    if (pages != expected_pages) {
        fprintf(stderr, "FAIL: Expected %zu pages, found %zu in %s\n", expected_pages, pages, pdf_path);
        CGPDFDocumentRelease(doc);
        return 2;
    }

    for (size_t i = 1; i <= pages; i++) {
        CGPDFPageRef page = CGPDFDocumentGetPage(doc, i);
        CGRect box = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
        if (fabs(box.size.width - expected_w_pt) > 0.25 || fabs(box.size.height - expected_h_pt) > 0.25) {
            fprintf(stderr, "FAIL: Page %zu geometry %.2f x %.2f pt differs from expected %.2f x %.2f pt\n",
                    i, box.size.width, box.size.height, expected_w_pt, expected_h_pt);
            CGPDFDocumentRelease(doc);
            return 3;
        }
    }

    printf("PASS: PDF %s geometry verified: %zu page(s), %.2f x %.2f pt\n",
           pdf_path, pages, expected_w_pt, expected_h_pt);
    CGPDFDocumentRelease(doc);
    return 0;
}

static int verify_rendered_raster(const char *path, unsigned expected_w, unsigned expected_h, unsigned expected_dpi) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "FAIL: Cannot open raster: %s\n", path);
        return 1;
    }

    cups_raster_t *r = cupsRasterOpen(fd, CUPS_RASTER_READ);
    if (!r) {
        close(fd);
        return 2;
    }

    cups_page_header2_t h;
    if (!cupsRasterReadHeader2(r, &h)) {
        fprintf(stderr, "FAIL: Unable to read raster header from %s\n", path);
        cupsRasterClose(r);
        close(fd);
        return 3;
    }

    if (h.cupsWidth != expected_w || h.cupsHeight != expected_h) {
        fprintf(stderr, "FAIL: Raster dimensions %ux%u do not match expected %ux%u in %s\n",
                h.cupsWidth, h.cupsHeight, expected_w, expected_h, path);
        cupsRasterClose(r);
        close(fd);
        return 4;
    }

    if (h.HWResolution[0] != expected_dpi || h.HWResolution[1] != expected_dpi) {
        fprintf(stderr, "FAIL: Resolution %ux%u DPI does not match expected %u DPI in %s\n",
                h.HWResolution[0], h.HWResolution[1], expected_dpi, path);
        cupsRasterClose(r);
        close(fd);
        return 5;
    }

    unsigned char *row = malloc(h.cupsBytesPerLine);
    if (!row) {
        cupsRasterClose(r);
        close(fd);
        return 6;
    }

    int first_dark_y = -1, last_dark_y = -1;
    int first_dark_x = -1, last_dark_x = -1;
    unsigned long long dark_pixels = 0;
    unsigned long long total_pixels = (unsigned long long)h.cupsWidth * h.cupsHeight;

    for (unsigned y = 0; y < h.cupsHeight; y++) {
        if (cupsRasterReadPixels(r, row, h.cupsBytesPerLine) != h.cupsBytesPerLine) {
            fprintf(stderr, "FAIL: Premature EOF reading line %u of %s\n", y, path);
            free(row);
            cupsRasterClose(r);
            close(fd);
            return 7;
        }

        for (unsigned x = 0; x < h.cupsWidth; x++) {
            unsigned val = 0;
            if (h.cupsBitsPerPixel == 1) {
                val = ((row[x / 8] >> (7 - (x % 8))) & 1) ? 255 : 0;
            } else if (h.cupsBitsPerPixel == 8) {
                val = row[x];
            } else if (h.cupsBitsPerPixel == 24) {
                val = (row[x * 3] == 0 && row[x * 3 + 1] == 0 && row[x * 3 + 2] == 0) ? 255 : 0;
            }

            if (val > 127) {
                dark_pixels++;
                if (first_dark_y < 0) first_dark_y = y;
                last_dark_y = y;
                if (first_dark_x < 0 || (int)x < first_dark_x) first_dark_x = x;
                if ((int)x > last_dark_x) last_dark_x = x;
            }
        }
    }
    free(row);

    int extra = cupsRasterReadHeader2(r, &h);
    cupsRasterClose(r);
    close(fd);

    if (extra) {
        fprintf(stderr, "FAIL: Expected 1 page, found additional page in %s\n", path);
        return 8;
    }

    if (dark_pixels == 0) {
        fprintf(stderr, "FAIL: No dark ink detected on page in %s\n", path);
        return 9;
    }

    if (first_dark_y > (int)(expected_h / 8) || last_dark_y > (int)(expected_h / 2) ||
        first_dark_x > (int)(expected_w / 8) || last_dark_x > (int)(expected_w / 2)) {
        fprintf(stderr, "FAIL: Mark orientation mismatch in %s: y=[%d, %d] (max %u), x=[%d, %d] (max %u)\n",
                path, first_dark_y, last_dark_y, expected_h / 2, first_dark_x, last_dark_x, expected_w / 2);
        return 10;
    }

    printf("PASS: Raster %s verified: %ux%u @ %u DPI, 1 page, orientation top-left (y=[%d,%d], x=[%d,%d]), ink polarity correct (%llu/%llu dark pixels)\n",
           path, expected_w, expected_h, expected_dpi, first_dark_y, last_dark_y, first_dark_x, last_dark_x,
           dark_pixels, total_pixels);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: TestURFToPDF <command> [args...]\n");
        return 1;
    }

    if (strcmp(argv[1], "generate-asymmetric") == 0) {
        if (argc != 8 && argc != 9) {
            fprintf(stderr, "Usage: TestURFToPDF generate-asymmetric <path> <cspace> <bpp> <w> <h> <dpi> [pages]\n");
            return 1;
        }
        unsigned pages = (argc == 9) ? (unsigned)atoi(argv[8]) : 1;
        return generate_asymmetric(argv[2], argv[3], (unsigned)atoi(argv[4]), (unsigned)atoi(argv[5]), (unsigned)atoi(argv[6]), (unsigned)atoi(argv[7]), pages);
    } else if (strcmp(argv[1], "make-invalid") == 0) {
        if (argc != 4) {
            fprintf(stderr, "Usage: TestURFToPDF make-invalid <path> <zero-dim|zero-dpi|cmyk>\n");
            return 1;
        }
        return make_invalid(argv[2], argv[3]);
    } else if (strcmp(argv[1], "verify-pdf") == 0) {
        if (argc != 6) {
            fprintf(stderr, "Usage: TestURFToPDF verify-pdf <path> <pages> <w_pt> <h_pt>\n");
            return 1;
        }
        return verify_pdf(argv[2], (size_t)atoi(argv[3]), atof(argv[4]), atof(argv[5]));
    } else if (strcmp(argv[1], "verify-rendered-raster") == 0) {
        if (argc != 6) {
            fprintf(stderr, "Usage: TestURFToPDF verify-rendered-raster <path> <w> <h> <dpi>\n");
            return 1;
        }
        return verify_rendered_raster(argv[2], (unsigned)atoi(argv[3]), (unsigned)atoi(argv[4]), (unsigned)atoi(argv[5]));
    } else {
        fprintf(stderr, "Unknown command: %s\n", argv[1]);
        return 1;
    }
}
