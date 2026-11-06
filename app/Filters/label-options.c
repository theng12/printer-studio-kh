#include <cups/cups.h>
#include <cups/ppd.h>
#include <cups/pwg.h>
#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int fail(const char *message) {
    fprintf(stderr, "ERROR: Printer Studio KH label media: %s\n", message);
    return 1;
}

static int dimension(const char *collection, const char *key, long *result) {
    const char *p = collection;
    int found = 0;
    while ((p = strstr(p, key))) {
        if (p != collection && p[-1] != '{' && !isspace((unsigned char)p[-1])) {
            p += strlen(key);
            continue;
        }
        char *end;
        errno = 0;
        long value = strtol(p + strlen(key), &end, 10);
        if (errno || end == p + strlen(key) || value <= 0 ||
            (*end && *end != '}' && !isspace((unsigned char)*end)) || found++) return 0;
        *result = value;
        p = end;
    }
    return found == 1;
}

static ppd_size_t *matching_size(ppd_file_t *ppd, double width, double height) {
    for (int i = 0; i < ppd->num_sizes; i++) {
        ppd_size_t *size = ppd->sizes + i;
        if (strcmp(size->name, "Custom") && size->width > 0 && size->length > 0 &&
            fabs(size->width - width) < 0.6 && fabs(size->length - height) < 0.6) return size;
    }
    return NULL;
}

int main(int argc, char **argv) {
    if (argc != 2) return fail("expected the job options");
    const char *path = getenv("PPD");
    if (!path || !*path) return fail("printer PPD is unavailable");
    ppd_file_t *ppd = ppdOpenFile(path);
    if (!ppd) return fail("could not open the printer PPD");
    cups_option_t *options = NULL;
    int count = cupsParseOptions(argv[1], 0, &options);
    ppdMarkDefaults(ppd);
    cupsMarkOptions(ppd, count, options);
    const char *collection = cupsGetOption("media-col", count, options);
    const char *page = cupsGetOption("PageSize", count, options);
    const char *media = cupsGetOption("media", count, options);
    ppd_size_t *size = NULL;
    char custom[128] = "";
    if (collection) {
        long x, y;
        if (!dimension(collection, "x-dimension=", &x) || !dimension(collection, "y-dimension=", &y)) {
            ppdClose(ppd); cupsFreeOptions(count, options);
            return fail("media-col must contain positive x-dimension and y-dimension");
        }
        double width = (double)x * 72.0 / 2540.0, height = (double)y * 72.0 / 2540.0;
        size = matching_size(ppd, width, height);
        if (!size && ppd->custom_max[0] > 0 && ppd->custom_max[1] > 0 &&
            width >= ppd->custom_min[0] && width <= ppd->custom_max[0] &&
            height >= ppd->custom_min[1] && height <= ppd->custom_max[1]) {
            snprintf(custom, sizeof(custom), "Custom.%.6fx%.6f", width, height);
            size = ppdPageSize(ppd, custom);
        }
    } else if (page) {
        size = ppdPageSize(ppd, page);
    } else if (media) {
        size = ppdPageSize(ppd, media);
        if (!size) {
            const pwg_media_t *pwg = pwgMediaForPWG(media);
            if (!pwg) pwg = pwgMediaForLegacy(media);
            if (pwg) size = matching_size(ppd, (double)pwg->width * 72.0 / 2540.0, (double)pwg->length * 72.0 / 2540.0);
        }
    } else {
        size = ppdPageSize(ppd, NULL);
    }
    if (!size || !isfinite(size->width) || !isfinite(size->length) || size->width <= 0 || size->length <= 0) {
        ppdClose(ppd); cupsFreeOptions(count, options);
        return fail("no supported page matches this job; add/select that stock size in Printer Studio KH");
    }
    const char *name = size->name;
    if (!strcmp(name, "Custom")) {
        if (ppd->custom_max[0] <= 0 || ppd->custom_max[1] <= 0 ||
            size->width < ppd->custom_min[0] || size->width > ppd->custom_max[0] ||
            size->length < ppd->custom_min[1] || size->length > ppd->custom_max[1]) {
            ppdClose(ppd); cupsFreeOptions(count, options);
            return fail("custom page exceeds the printer PPD limits");
        }
        // A bare Custom loses the dimensions; preserve them in the page keyword.
        snprintf(custom, sizeof(custom), "Custom.%.6fx%.6f", size->width, size->length);
        name = custom;
    }
    for (const unsigned char *p = (const unsigned char *)name; *p; p++) {
        if (!isalnum(*p) && *p != '_' && *p != '-' && *p != '.') {
            ppdClose(ppd); cupsFreeOptions(count, options);
            return fail("unsupported PPD page keyword");
        }
    }
    // Last option wins in cupsParseOptions; keep all other job choices intact.
    printf("%s PageSize=%s PageRegion=%s\n", argv[1], name, name);
    ppdClose(ppd);
    cupsFreeOptions(count, options);
    return ferror(stdout) ? 1 : 0;
}
