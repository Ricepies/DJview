#ifndef DJVU_BRIDGE_H
#define DJVU_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DjVuDocContext DjVuDocContext;
typedef struct DjVuMultiPageEncoder DjVuMultiPageEncoder;

DjVuDocContext* djvu_doc_open(const char* path);
void djvu_doc_free(DjVuDocContext* ctx);
uint32_t djvu_doc_page_count(DjVuDocContext* ctx);
int32_t djvu_doc_get_page_dimension(DjVuDocContext* ctx, uint32_t page_idx, uint32_t* out_width, uint32_t* out_height, uint16_t* out_dpi);
int32_t djvu_doc_render_page_rgba(DjVuDocContext* ctx, uint32_t page_idx, uint32_t target_width, uint32_t target_height, uint32_t layer_mode, uint8_t* out_buf);
char* djvu_doc_get_bookmarks_json(DjVuDocContext* ctx);
char* djvu_doc_get_text_zones_json(DjVuDocContext* ctx, uint32_t page_idx);
char* djvu_doc_search_text_json(DjVuDocContext* ctx, const char* query);
int32_t djvu_doc_export_page(DjVuDocContext* ctx, uint32_t page_idx, uint32_t format, const char* out_path);
int32_t djvu_encode_rgba_to_djvu(const uint8_t* rgba_bytes, uint32_t width, uint32_t height, uint16_t dpi, const char* out_path);

DjVuMultiPageEncoder* djvu_encoder_create(uint16_t dpi);
int32_t djvu_encoder_add_png_page(DjVuMultiPageEncoder* encoder, const uint8_t* png_data, uint32_t png_len);
int32_t djvu_encoder_finish(DjVuMultiPageEncoder* encoder, const char* out_path);
void djvu_encoder_free(DjVuMultiPageEncoder* encoder);

void djvu_string_free(char* ptr);

#ifdef __cplusplus
}
#endif

#endif /* DJVU_BRIDGE_H */
