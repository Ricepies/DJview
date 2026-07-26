#ifndef DJVU_BRIDGE_H
#define DJVU_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DjVuDocContext DjVuDocContext;

/**
 * Open a DjVu document from a file path.
 * Returns NULL on failure.
 */
DjVuDocContext* djvu_doc_open(const char* path);

/**
 * Free a DjVu document handle.
 */
void djvu_doc_free(DjVuDocContext* ctx);

/**
 * Get total number of pages in document.
 */
uint32_t djvu_doc_page_count(DjVuDocContext* ctx);

/**
 * Get width, height (in pixels) and DPI of specified 0-based page.
 * Returns 0 on success, negative on error.
 */
int32_t djvu_doc_get_page_dimension(DjVuDocContext* ctx, uint32_t page_idx, uint32_t* out_width, uint32_t* out_height, uint16_t* out_dpi);

/**
 * Render specified page to RGBA 32-bit pixel buffer.
 * out_buf must be pre-allocated with target_width * target_height * 4 bytes.
 * layer_mode: 0 = Composite, 1 = Foreground, 2 = Background, 3 = Mask/B&W.
 * Returns 0 on success.
 */
int32_t djvu_doc_render_page_rgba(DjVuDocContext* ctx, uint32_t page_idx, uint32_t target_width, uint32_t target_height, uint32_t layer_mode, uint8_t* out_buf);

/**
 * Get NAVM bookmarks (Table of Contents) as a JSON string.
 * Must be freed with djvu_string_free().
 */
char* djvu_doc_get_bookmarks_json(DjVuDocContext* ctx);

/**
 * Get text layer zones & bounding boxes for a page as a JSON string.
 * Must be freed with djvu_string_free().
 */
char* djvu_doc_get_text_zones_json(DjVuDocContext* ctx, uint32_t page_idx);

/**
 * Search full text across all pages for query string.
 * Returns JSON array of match objects.
 * Must be freed with djvu_string_free().
 */
char* djvu_doc_search_text_json(DjVuDocContext* ctx, const char* query);

/**
 * Export page to image file (0 = PNG, 1 = JPEG, 2 = PDF).
 * Returns 0 on success.
 */
int32_t djvu_doc_export_page(DjVuDocContext* ctx, uint32_t page_idx, uint32_t format, const char* out_path);

/**
 * Free a dynamically allocated string returned by FFI functions.
 */
void djvu_string_free(char* ptr);

#ifdef __cplusplus
}
#endif

#endif /* DJVU_BRIDGE_H */
