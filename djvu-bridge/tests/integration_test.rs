use djvu_bridge::*;
use std::ffi::CString;

#[test]
fn test_ffi_null_handling() {
    unsafe {
        let ctx = djvu_doc_open(std::ptr::null());
        assert!(ctx.is_null());

        let count = djvu_doc_page_count(ctx);
        assert_eq!(count, 0);

        djvu_doc_free(ctx);
    }
}
