#include <cups/raster.h>
#include <fcntl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
    if (argc != 4) return 2;
    int fd = open(argv[1], O_RDONLY);
    if (fd < 0) return 3;
    cups_raster_t *r = cupsRasterOpen(fd, CUPS_RASTER_READ);
    cups_page_header2_t h;
    if (!r || !cupsRasterReadHeader2(r, &h)) return 4;
    double w = h.cupsPageSize[0] * 25.4 / 72.0;
    double height = h.cupsPageSize[1] * 25.4 / 72.0;
    int ok = fabs(w - atof(argv[2])) < 0.6 && fabs(height - atof(argv[3])) < 0.6 && h.cupsWidth > 0 && h.cupsHeight > 0;
    printf("Raster page %.2f x %.2f mm; %u x %u pixels; %s\n", w, height, h.cupsWidth, h.cupsHeight, ok ? "PASS" : "FAIL");
    unsigned char *row = malloc(h.cupsBytesPerLine);
    if (!row) return 5;
    unsigned rows = 0;
    for (; rows < h.cupsHeight; rows++) {
        if (cupsRasterReadPixels(r, row, h.cupsBytesPerLine) != h.cupsBytesPerLine) break;
    }
    free(row);
    ok = ok && rows == h.cupsHeight;
    int extra = cupsRasterReadHeader2(r, &h);
    ok = ok && !extra;
    printf("Decoded %u rows; additional page: %s; %s\n", rows, extra ? "YES" : "no", ok ? "PASS" : "FAIL");
    cupsRasterClose(r);
    close(fd);
    return ok ? 0 : 1;
}
