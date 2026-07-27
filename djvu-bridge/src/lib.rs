use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;
use serde::Serialize;
use image::imageops::{resize, FilterType};
use image::RgbaImage;
use djvu_rs::{Document, TextZoneKind};
use djvu_rs::djvu_encode::{PageEncoder, EncodeQuality};

pub struct DjVuDocContext {
    doc: Document,
}

fn generate_temp_id() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_nanos();
    format!("{:x}", nanos)
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
    out_actual_width: *mut u32,
    out_actual_height: *mut u32,
) -> i32 {
    if ctx.is_null() || out_buf.is_null() {
        return -1;
    }

    let page = match (*ctx).doc.page(page_idx as usize) {
        Ok(p) => p,
        Err(_) => return -1,
    };

    // Render page at native 100% resolution to bypass djvu-rs's broken render_to_size downsampler on JB2/IW44 pages
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
                Ok(djvu_rs::Pixmap {
                    width: bw,
                    height: bh,
                    data,
                })
            } else {
                page.render()
            }
        }
        _ => page.render(),
    };

    let pixmap = match pixmap_res {
        Ok(pm) => pm,
        Err(_) => return -2,
    };

    // Resample native 100% render in Rust memory using imageops::resize if target dimensions are requested
    let (final_data, final_w, final_h) = if target_width > 0 && target_height > 0 && (pixmap.width != target_width || pixmap.height != target_height) {
        let (pw, ph) = (pixmap.width, pixmap.height);
        if let Some(large_img) = RgbaImage::from_raw(pw, ph, pixmap.data) {
            let small_img = resize(&large_img, target_width, target_height, FilterType::Triangle);
            let (w, h) = small_img.dimensions();
            (small_img.into_raw(), w, h)
        } else {
            (Vec::new(), 0, 0)
        }
    } else {
        let (w, h) = (pixmap.width, pixmap.height);
        (pixmap.data, w, h)
    };

    if !out_actual_width.is_null() {
        *out_actual_width = final_w;
    }
    if !out_actual_height.is_null() {
        *out_actual_height = final_h;
    }

    let copy_len = final_data.len();
    let out_slice = std::slice::from_raw_parts_mut(out_buf, copy_len);
    out_slice.copy_from_slice(&final_data);

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
pub unsafe extern "C" fn djvu_encode_rgba_to_djvu(
    rgba_bytes: *const u8,
    width: u32,
    height: u32,
    dpi: u16,
    out_path: *const c_char,
) -> i32 {
    if rgba_bytes.is_null() || out_path.is_null() || width == 0 || height == 0 {
        return -1;
    }

    let path_str = match CStr::from_ptr(out_path).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let len = (width * height * 4) as usize;
    let slice = std::slice::from_raw_parts(rgba_bytes, len);

    let pixmap = djvu_rs::Pixmap {
        width,
        height,
        data: slice.to_vec(),
    };

    let quality = djvu_rs::djvu_encode::classify_content(&pixmap);

    let single_page_djvu = match PageEncoder::from_pixmap(&pixmap)
        .with_dpi(if dpi == 0 { 300 } else { dpi })
        .with_quality(quality)
        .encode() {
            Ok(bytes) => bytes,
            Err(_) => match PageEncoder::from_pixmap(&pixmap)
                .with_dpi(if dpi == 0 { 300 } else { dpi })
                .with_quality(EncodeQuality::Photo)
                .encode() {
                    Ok(bytes) => bytes,
                    Err(_) => return -2,
                },
        };

    match std::fs::write(path_str, single_page_djvu) {
        Ok(_) => 0,
        Err(_) => -3,
    }
}

// MARK: - Production-Grade Directory / Image Stream DjVu Encoder Pipeline
#[no_mangle]
pub unsafe extern "C" fn djvu_convert_dir_to_djvu(
    dir_path: *const c_char,
    out_path: *const c_char,
    quality_mode: u32, // 0 = Lossless (B&W Manga JB2), 1 = Quality (Mixed), 2 = Photo
    dpi: u16,
) -> i32 {
    if dir_path.is_null() || out_path.is_null() {
        return -1;
    }

    let dir_str = match CStr::from_ptr(dir_path).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };
    let out_str = match CStr::from_ptr(out_path).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let mut image_paths: Vec<std::path::PathBuf> = Vec::new();
    let entries = match std::fs::read_dir(dir_str) {
        Ok(e) => e,
        Err(_) => return -2,
    };

    for entry in entries.flatten() {
        let p = entry.path();
        if p.is_file() {
            if let Some(ext) = p.extension() {
                let ext_str = ext.to_string_lossy().to_lowercase();
                if ext_str == "png" || ext_str == "jpg" || ext_str == "jpeg" || ext_str == "pnm" || ext_str == "tif" || ext_str == "tiff" {
                    image_paths.push(p);
                }
            }
        }
    }

    if image_paths.is_empty() {
        return -3;
    }

    image_paths.sort();

    let target_dpi = if dpi == 0 { 300 } else { dpi };
    let temp_dir = std::env::temp_dir().join(format!("djvu_chunks_{}", generate_temp_id()));
    if std::fs::create_dir_all(&temp_dir).is_err() {
        return -4;
    }

    let mut encoded_single_pages: Vec<std::path::PathBuf> = Vec::new();

    for (idx, img_p) in image_paths.iter().enumerate() {
        let dynamic_img = match image::open(img_p) {
            Ok(img) => img,
            Err(_) => continue,
        };

        let rgba_img = dynamic_img.to_rgba8();
        let (w, h) = rgba_img.dimensions();

        let pixmap = djvu_rs::Pixmap {
            width: w,
            height: h,
            data: rgba_img.into_raw(),
        };

        let quality = match quality_mode {
            0 => EncodeQuality::Lossless, // Clean B&W Manga Line Art -> Shared JB2
            1 => djvu_rs::djvu_encode::classify_content(&pixmap),
            2 => EncodeQuality::Photo,
            _ => EncodeQuality::Lossless,
        };

        let enc_res = PageEncoder::from_pixmap(&pixmap)
            .with_dpi(target_dpi)
            .with_quality(quality)
            .encode();

        let single_page_bytes = match enc_res {
            Ok(b) => b,
            Err(_) => match PageEncoder::from_pixmap(&pixmap)
                .with_dpi(target_dpi)
                .with_quality(EncodeQuality::Photo)
                .encode() {
                    Ok(b) => b,
                    Err(_) => continue,
                },
        };

        let chunk_path = temp_dir.join(format!("page_{:05}.djvu", idx + 1));
        if std::fs::write(&chunk_path, &single_page_bytes).is_ok() {
            encoded_single_pages.push(chunk_path);
        }
    }

    if encoded_single_pages.is_empty() {
        let _ = std::fs::remove_dir_all(&temp_dir);
        return -5;
    }

    let mut page_buffers = Vec::with_capacity(encoded_single_pages.len());
    for p_path in &encoded_single_pages {
        if let Ok(b) = std::fs::read(p_path) {
            page_buffers.push(b);
        }
    }

    let page_refs: Vec<&[u8]> = page_buffers.iter().map(|v| v.as_slice()).collect();

    let merged_djvu = match djvu_rs::djvm::merge(&page_refs) {
        Ok(bytes) => bytes,
        Err(_) => {
            let _ = std::fs::remove_dir_all(&temp_dir);
            return -6;
        }
    };

    let _ = std::fs::remove_dir_all(&temp_dir);

    // Validate merged DjVu structure
    if djvu_rs::Document::from_bytes(merged_djvu.clone()).is_err() {
        return -7;
    }

    match std::fs::write(out_str, merged_djvu) {
        Ok(_) => 0,
        Err(_) => -8,
    }
}

// MARK: - Zero-Copy Raw Image Dump PDF2DjVu Converter via pdfimages (with fallback)
#[no_mangle]
pub unsafe extern "C" fn djvu_convert_pdf_via_pdfimages(
    pdf_path: *const c_char,
    out_path: *const c_char,
    quality_mode: u32,
    dpi: u16,
) -> i32 {
    if pdf_path.is_null() || out_path.is_null() {
        return -1;
    }

    let pdf_str = match CStr::from_ptr(pdf_path).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };
    let out_str = match CStr::from_ptr(out_path).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let temp_ext_dir = std::env::temp_dir().join(format!("ext_pages_{}", generate_temp_id()));
    if std::fs::create_dir_all(&temp_ext_dir).is_err() {
        return -2;
    }

    let prefix = temp_ext_dir.join("page");

    // Execute pdfimages -png to dump embedded image streams directly to disk
    let pdfimages_status = std::process::Command::new("pdfimages")
        .arg("-png")
        .arg(pdf_str)
        .arg(&prefix)
        .status();

    let pdfimages_success = match pdfimages_status {
        Ok(st) => st.success(),
        Err(_) => false,
    };

    if !pdfimages_success {
        let _ = std::fs::remove_dir_all(&temp_ext_dir);
        return -100; // Code -100 signals pdfimages is missing or failed, fallback to Swift page stream rendering
    }

    let dir_c_str = CString::new(temp_ext_dir.to_str().unwrap()).unwrap();
    let out_c_str = CString::new(out_str).unwrap();

    let res = djvu_convert_dir_to_djvu(dir_c_str.as_ptr(), out_c_str.as_ptr(), quality_mode, dpi);
    let _ = std::fs::remove_dir_all(&temp_ext_dir);

    res
}

#[no_mangle]
pub unsafe extern "C" fn djvu_string_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}
