use djvu_bridge::*;
use std::ffi::CString;

#[test]
fn test_ffi_null_handling() {
    unsafe {
        let count = djvu_doc_page_count(std::ptr::null_mut());
        assert_eq!(count, 0);

        let res = djvu_doc_export_page(std::ptr::null_mut(), 0, 1, std::ptr::null());
        assert_eq!(res, -1);
    }
}
