#include <cups/raster.h>
#include <fcntl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 5) return 2;
    int fd = open(argv[1], O_RDONLY);
    if (fd < 0) return 3;
    cups_raster_t *r = cupsRasterOpen(fd, CUPS_RASTER_READ);
    cups_page_header2_t h;
    if (!r || !cupsRasterReadHeader2(r, &h)) return 4;
    double width = h.cupsPageSize[0] * 25.4 / 72.0;
    double height = h.cupsPageSize[1] * 25.4 / 72.0;
    int dpi = atoi(argv[4]);
    int ok = fabs(width - atof(argv[2])) < 0.6 && fabs(height - atof(argv[3])) < 0.6 &&
        h.PageSize[0] > 0 && h.PageSize[1] > 0 && h.cupsWidth > 0 && h.cupsHeight > 0 &&
        h.HWResolution[0] == dpi && h.HWResolution[1] == dpi && h.cupsNumColors == 1 &&
        (h.cupsBitsPerColor == 1 || h.cupsBitsPerColor == 8);
    unsigned char *row = malloc(h.cupsBytesPerLine);
    if (!row) return 5;
    unsigned rows = 0;
    unsigned long long dark = 0, light = 0;
    for (; rows < h.cupsHeight; rows++) {
        if (cupsRasterReadPixels(r, row, h.cupsBytesPerLine) != h.cupsBytesPerLine) break;
        for (unsigned x = 0; x < h.cupsWidth; x++) {
            unsigned value = h.cupsBitsPerColor == 1 ? ((row[x / 8] >> (7 - x % 8)) & 1) * 255 : row[x];
            if (value > 127) dark++; else light++;
        }
    }
    free(row);
    ok = ok && rows == h.cupsHeight && dark > 0 && light > 0;
    int extra = cupsRasterReadHeader2(r, &h);
    ok = ok && !extra;
    printf("%s: %.2f x %.2f mm, %d dpi, %u rows, mixed pixels, one page=%s\n", ok ? "PASS" : "FAIL", width, height, dpi, rows, extra ? "no" : "yes");
    cupsRasterClose(r);
    close(fd);
    return ok ? 0 : 1;
}
