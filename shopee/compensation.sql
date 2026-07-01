-- =============================================================================
-- TRA CỨU CHI TIẾT ĐƠN HÀNG ĐỀN BÙ - SHOPEE KA
-- LỌC THEO NGÀY DUYỆT EFORM
-- =============================================================================

SELECT
*
FROM iceberg.ka_shopee_core.tong_hop_den_bu_v4
WHERE
    ngay_duyet_eform >= DATE '2025-06-15';
