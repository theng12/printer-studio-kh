use super::MonoPage;

/// Generate a simple "I'm alive" test page: a frame around the printable area,
/// crosshairs through the center, and a stack of resolution-marking bars in each corner.
///
/// At 600 DPI on US Letter: 5100 × 6600 px (8.5" × 11" minus implicit margins).
pub fn test_page(width_px: u32, height_px: u32, dpi: u32) -> MonoPage {
    let mut page = MonoPage::blank(width_px, height_px, dpi);

    // Outer frame, 4 pixels thick, inset 1/4 inch from each edge.
    let margin = dpi / 4;
    let thickness = 4u32;
    draw_rect(&mut page, margin, margin, width_px - margin, height_px - margin, thickness);

    // Crosshairs through center.
    let cx = width_px / 2;
    let cy = height_px / 2;
    let arm = dpi; // 1 inch arms
    draw_h_line(&mut page, cx - arm, cy, 2 * arm, thickness);
    draw_v_line(&mut page, cx, cy - arm, 2 * arm, thickness);

    // Corner resolution bars: 8 horizontal bars stepping down in spacing.
    for &corner in &[(margin + 30, margin + 30), (width_px - margin - 200, margin + 30)] {
        let (x0, y0) = corner;
        for i in 0..8 {
            let len = 150;
            let y = y0 + i * 12;
            draw_h_line(&mut page, x0, y, len, (8 - i).max(1));
        }
    }

    page
}

fn draw_rect(page: &mut MonoPage, x0: u32, y0: u32, x1: u32, y1: u32, thickness: u32) {
    draw_h_line(page, x0, y0, x1 - x0, thickness);
    draw_h_line(page, x0, y1 - thickness, x1 - x0, thickness);
    draw_v_line(page, x0, y0, y1 - y0, thickness);
    draw_v_line(page, x1 - thickness, y0, y1 - y0, thickness);
}

fn draw_h_line(page: &mut MonoPage, x: u32, y: u32, length: u32, thickness: u32) {
    for t in 0..thickness {
        for dx in 0..length {
            page.set_pixel(x + dx, y + t, true);
        }
    }
}

fn draw_v_line(page: &mut MonoPage, x: u32, y: u32, length: u32, thickness: u32) {
    for t in 0..thickness {
        for dy in 0..length {
            page.set_pixel(x + t, y + dy, true);
        }
    }
}
