use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;
use serde::Serialize;
use djvu_rs::{Document, TextZoneKind};

pub struct DjVuDocContext {
    doc: Document,
}

#[derive(Serialize)]
struct BookmarkNode {
    title: String,
    page_num: Option<usize>,
    url: Option<String>,
    children: Vec<BookmarkNode>,
}

#[derive(Serialize)]
struct TextZoneInfo {
    kind: String,
    text: String,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    children: Vec<TextZoneInfo>,
}

#[derive(Serialize)]
struct SearchResultItem {
    page: usize,
    text: String,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
}

fn convert_bookmark(bm: &djvu_rs::Bookmark) -> BookmarkNode {
    let p_num = if bm.url.starts_with('#') {
        bm.url[1..].parse::<usize>().ok()
    } else {
        bm.url.parse::<usize>().ok()
    };
    BookmarkNode {
        title: bm.title.clone(),
        page_num: p_num,
        url: Some(bm.url.clone()),
        children: bm.children.iter().map(convert_bookmark).collect(),
    }
}

fn convert_text_zone(zone: &djvu_rs::TextZone) -> TextZoneInfo {
    let kind_str = match zone.kind {
        TextZoneKind::Page => "page",
        TextZoneKind::Column => "column",
        TextZoneKind::Region => "region",
        TextZoneKind::Line => "line",
        TextZoneKind::Word => "word",
        TextZoneKind::Character => "character",
        _ => "other",
    };
    TextZoneInfo {
        kind: kind_str.to_string(),
        text: zone.text.clone(),
        x: zone.rect.x,
        y: zone.rect.y,
        width: zone.rect.width,
        height: zone.rect.height,
        children: zone.children.iter().map(convert_text_zone).collect(),
    }
}

fn search_zone_recursive(zone: &djvu_rs::TextZone, query: &str, page_idx: usize, results: &mut Vec<SearchResultItem>) {
    if zone.kind == TextZoneKind::Word || zone.kind == TextZoneKind::Line {
        if zone.text.to_lowercase().contains(query) {
            results.push(SearchResultItem {
                page: page_idx,
                text: zone.text.clone(),
                x: zone.rect.x,
                y: zone.rect.y,
                width: zone.rect.width,
                height: zone.rect.height,
            });
        }
    }
    for child in &zone.children {
        search_zone_recursive(child, query, page_idx, results);
    }
}

#[no_mangle]
pub unsafe extern "C" fn djvu_doc_open(path: *const c_char) -> *mut DjVuDocContext {
    if path.is_null() {
        return ptr::null_mut();
    }
    let c_str = match CStr::from_ptr(path).to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let doc = match Document::open(c_str) {
        Ok(d) => d,
        Err(_) => match Document::open_dir(c_str) {
            Ok(d) => d,
            Err(_) => return ptr::null_mut(),
        },
    };

    Box::into_raw(Box::new(DjVuDocContext { doc }))
}

#[no_mangle]
pub unsafe extern "C" fn djvu_doc_free(ctx: *mut DjVuDocContext) {
    if !ctx.is_null() {
        drop(Box::from_raw(ctx));
    }
}

#[no_mangle]
pub unsafe extern "C" fn djvu_doc_page_count(ctx: *mut DjVuDocContext) -> u32 {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).doc.page_count() as u32
}

#[no_mangle]
pub unsafe extern "C" fn djvu_doc_get_page_dimension(
    ctx: *mut DjVuDocContext,
    page_idx: u32,
    out_width: *mut u32,
    out_height: *mut u32,
    out_dpi: *mut u16,
) -> i32 {
    if ctx.is_null() {
        return -1;
    }
    let page = match (*ctx).doc.page(page_idx as usize) {
        Ok(p) => p,
        Err(_) => return -1,
    };

    if !out_width.is_null() {
        *out_width = page.display_width();
    }
    if !out_height.is_null() {
        *out_height = page.display_height();
    }
    if !out_dpi.is_null() {
        *out_dpi = page.dpi();
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn djvu_doc_render_page_rgba(
    ctx: *mut DjVuDocContext,
    page_idx: u32,
    target_width: u32,
    target_height: u32,
    layer_mode: u32,
    out_buf: *mut u8,
) -> i32 {
    if ctx.is_null() || out_buf.is_null() {
        return -1;
    }

    let page = match (*ctx).doc.page(page_idx as usize) {
        Ok(p) => p,
        Err(_) => return -1,
    };

    let pixmap_res = match layer_mode {
        3 => {
            if let Ok(Some(bitmap)) = page.decode_mask() {
                let bw = bitmap.width;
                let bh = bitmap.height;
                let mut data = vec![0u8; (bw * bh * 4) as usize];
                for y in 0..bh {
                    for x in 0..bw {
                        let bit = bitmap.get(x, y);
                        let val = if bit { 0u8 } else { 255u8 };
                        let idx = ((y * bw + x) * 4) as usize;
                        data[idx] = val;
                        data[idx + 1] = val;
                        data[idx + 2] = val;
                        data[idx + 3] = 255;
                    }
                }
                let pm = djvu_rs::Pixmap {
                    width: bw,
                    height: bh,
                    data,
                };
                if target_width > 0 && target_height > 0 && (bw != target_width || bh != target_height) {
                    page.render_to_size(target_width, target_height)
                } else {
                    Ok(pm)
                }
            } else {
                page.render_to_size(target_width, target_height)
            }
        }
        _ => page.render_to_size(target_width, target_height),
    };

    let pixmap = match pixmap_res {
        Ok(pm) => pm,
        Err(_) => return -2,
    };

    let expected_len = (pixmap.width * pixmap.height * 4) as usize;
    let out_slice = std::slice::from_raw_parts_mut(out_buf, expected_len);
    out_slice.copy_from_slice(&pixmap.data);

    0
}

#[no_mangle]
pub unsafe extern "C" fn djvu_doc_get_bookmarks_json(ctx: *mut DjVuDocContext) -> *mut c_char {
    if ctx.is_null() {
        return ptr::null_mut();
    }

    let bookmarks = match (*ctx).doc.bookmarks() {
        Ok(bm) => bm,
        Err(_) => Vec::new(),
    };

    let nodes: Vec<BookmarkNode> = bookmarks.iter().map(convert_bookmark).collect();
    let json_str = serde_json::to_string(&nodes).unwrap_or_else(|_| "[]".to_string());

    CString::new(json_str).map(|cs| cs.into_raw()).unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn djvu_doc_get_text_zones_json(ctx: *mut DjVuDocContext, page_idx: u32) -> *mut c_char {
    if ctx.is_null() {
        return ptr::null_mut();
    }

    let page = match (*ctx).doc.page(page_idx as usize) {
        Ok(p) => p,
        Err(_) => return ptr::null_mut(),
    };

    let text_layer = match page.text_layer() {
        Ok(Some(tl)) => tl,
        _ => return CString::new("null").unwrap().into_raw(),
    };

    let zone_infos: Vec<TextZoneInfo> = text_layer.zones.iter().map(convert_text_zone).collect();
    let json_str = serde_json::to_string(&zone_infos).unwrap_or_else(|_| "[]".to_string());

    CString::new(json_str).map(|cs| cs.into_raw()).unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn djvu_doc_search_text_json(ctx: *mut DjVuDocContext, query: *const c_char) -> *mut c_char {
    if ctx.is_null() || query.is_null() {
        return ptr::null_mut();
    }

    let query_str = match CStr::from_ptr(query).to_str() {
        Ok(s) => s.to_lowercase(),
        Err(_) => return ptr::null_mut(),
    };

    if query_str.is_empty() {
        return CString::new("[]").unwrap().into_raw();
    }

    let total_pages = (*ctx).doc.page_count();
    let mut results = Vec::new();

    for i in 0..total_pages {
        if let Ok(page) = (*ctx).doc.page(i) {
            if let Ok(Some(tl)) = page.text_layer() {
                for zone in &tl.zones {
                    search_zone_recursive(zone, &query_str, i, &mut results);
                }
            }
        }
    }

    let json_str = serde_json::to_string(&results).unwrap_or_else(|_| "[]".to_string());
    CString::new(json_str).map(|cs| cs.into_raw()).unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn djvu_doc_export_page(
    ctx: *mut DjVuDocContext,
    page_idx: u32,
    format: u32, // 0 = PNG, 1 = JPEG
    out_path: *const c_char,
) -> i32 {
    if ctx.is_null() || out_path.is_null() {
        return -1;
    }

    let path_str = match CStr::from_ptr(out_path).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let page = match (*ctx).doc.page(page_idx as usize) {
        Ok(p) => p,
        Err(_) => return -1,
    };

    let dw = page.display_width();
    let dh = page.display_height();

    let pixmap = match page.render_to_size(dw, dh) {
        Ok(pm) => pm,
        Err(_) => return -2,
    };

    let img_buf: image::ImageBuffer<image::Rgba<u8>, _> = match image::ImageBuffer::from_raw(pixmap.width, pixmap.height, pixmap.data) {
        Some(b) => b,
        None => return -3,
    };

    let save_res = match format {
        0 => img_buf.save_with_format(path_str, image::ImageFormat::Png),
        1 => {
            let rgb_img = image::DynamicImage::ImageRgba8(img_buf).to_rgb8();
            rgb_img.save_with_format(path_str, image::ImageFormat::Jpeg)
        }
        _ => img_buf.save_with_format(path_str, image::ImageFormat::Png),
    };

    if save_res.is_ok() { 0 } else { -4 }
}

#[no_mangle]
pub unsafe extern "C" fn djvu_string_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}
