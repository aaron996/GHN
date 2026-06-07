-- =============================================================================
-- PHÂN TÍCH HIỆU SUẤT ĐO ĐẠC KLKT KHÁCH HÀNG TTS — THÁNG 5/2026 (GRAIN: NGÀY)
-- TIÊU CHUẨN ĐO ĐẠC NGHIÊM NGẶT: ĐỦ 4 CHIỀU (W-L-W-H > 0) TRÊN CÙNG MỘT KHO
-- THIẾT KẾ MẪU SỐ TOÀN QUỐC & PHÂN TÁCH BIẾN SỐ ĐO ĐẠC NỘI BỘ THEO TỪNG KHO
-- LOGIC KIỂM TOÁN THIẾT BỊ (STRATEGIC AUDIT LOGIC):
--   - GAP_HY: SAI LỆCH GIỮA LẦN ĐO ĐẦU VS LẦN ĐO CUỐI TẠI KHO HƯNG YÊN (21365000)
--   - GAP_XY: SAI LỆCH GIỮA LẦN ĐO ĐẦU VS LẦN ĐO CUỐI TẠI KHO XUYÊN Á (1626)
--   - GAP_2_KHO: SAI LỆCH LẦN ĐO CUỐI TẠI HY VS LẦN ĐO CUỐI TẠI XA (LIÊN MIỀN)
-- TEAM PHÂN TÍCH: KAS DATA GOVERNANCE & STRATEGIC PLANNING
-- =============================================================================

WITH date_config AS (
    SELECT
        DATE '2026-05-01'  AS start_date,
        DATE '2026-05-31'  AS end_date,
        DATE '2026-03-01'  AS partition_start
),

-- [BƯỚC 1] Xác định tập mẫu đơn hàng hoàn tất toàn quốc của TTS (Mẫu số nền)
base_orders AS (
    SELECT
        b.ordercode,
        CASE
            WHEN b.clientid = 3819710 THEN 'TTS_Exp'
            WHEN b.clientid = 4447237 THEN 'TTS_Bulky'
        END                                             AS client_type,
        CASE
            WHEN b.currentstatus = 'delivered' THEN 'deli'
            WHEN b.currentstatus = 'returned'  THEN 'return'
        END                                             AS journey_type,
        b.currentstatus,
        CAST(
            CASE
                WHEN b.currentstatus = 'delivered' THEN b.enddeliverytime
                WHEN b.currentstatus = 'returned'  THEN b.endreturntime
            END
        AS DATE)                                        AS success_date,
        b.startreturntime
    FROM "ghn-reporting".ka.dtm_ka_v3_createddate b
    CROSS JOIN date_config d
    WHERE b.clientid IN (3819710, 4447237)
      AND b.currentstatus IN ('delivered', 'returned')
      AND (
          (b.currentstatus = 'delivered'
              AND b.enddeliverytime IS NOT NULL
              AND CAST(b.enddeliverytime AS DATE) BETWEEN d.start_date AND d.end_date)
          OR
          (b.currentstatus = 'returned'
              AND b.endreturntime IS NOT NULL
              AND CAST(b.endreturntime AS DATE) BETWEEN d.start_date AND d.end_date)
      )
      AND b.createddate_partition >= d.partition_start
),

-- [BƯỚC 2] Thu thập dữ liệu đo đạc raw từ hệ thống DWS / Matrix
raw_measurements AS (
    SELECT
        h.order_code, h.location_id, h.last_updated_time,
        TRY(CAST(JSON_EXTRACT_SCALAR(h.data, '$.feederWeight') AS DOUBLE)) AS raw_weight_gram,
        CAST(NULL AS DOUBLE) AS raw_length_mm,
        CAST(NULL AS DOUBLE) AS raw_width_mm,
        CAST(NULL AS DOUBLE) AS raw_height_mm
    FROM "dw-ghn".data_auto_sorting.data_sorting_history h
    INNER JOIN base_orders b ON h.order_code = b.ordercode
    CROSS JOIN date_config d
    WHERE h.action = 'SORTING_PARCEL'
      AND h.location_id = '1626' -- Kho Xuyên Á (XY)
      AND h.order_code IS NOT NULL
      AND CAST(h.date_partition AS DATE) >= d.start_date

    UNION ALL

    SELECT
        h.order_code, h.location_id, h.last_updated_time,
        TRY(CAST(JSON_EXTRACT_SCALAR(h.data, '$.weight') AS DOUBLE)),
        NULL, NULL, NULL
    FROM "dw-ghn".data_auto_sorting.data_sorting_history h
    INNER JOIN base_orders b ON h.order_code = b.ordercode
    CROSS JOIN date_config d
    WHERE h.action = 'WEIGHING_PARCEL'
      AND h.location_id = '21365000' -- Kho Hưng Yên (HY)
      AND h.order_code IS NOT NULL
      AND CAST(h.date_partition AS DATE) >= d.start_date

    UNION ALL

    SELECT
        h.order_code, h.location_id, h.last_updated_time,
        NULL,
        TRY(CAST(JSON_EXTRACT_SCALAR(h.data, '$.dwsLength') AS DOUBLE)),
        TRY(CAST(JSON_EXTRACT_SCALAR(h.data, '$.dwsWidth')  AS DOUBLE)),
        TRY(CAST(JSON_EXTRACT_SCALAR(h.data, '$.dwsHeight') AS DOUBLE))
    FROM "dw-ghn".data_auto_sorting.data_sorting_history h
    INNER JOIN base_orders b ON h.order_code = b.ordercode
    CROSS JOIN date_config d
    WHERE h.action = 'DWS_PARCEL'
      AND h.location_id IN ('1626', '21365000')
      AND h.order_code IS NOT NULL
      AND CAST(h.date_partition AS DATE) >= d.start_date

    UNION ALL

    SELECT
        h.order_code, h.location_id, h.last_updated_time,
        TRY(CAST(JSON_EXTRACT_SCALAR(h.data, '$.dwsWeight') AS DOUBLE)),
        TRY(CAST(JSON_EXTRACT_SCALAR(h.data, '$.dwsLength') AS DOUBLE)),
        TRY(CAST(JSON_EXTRACT_SCALAR(h.data, '$.dwsWidth')  AS DOUBLE)),
        TRY(CAST(JSON_EXTRACT_SCALAR(h.data, '$.dwsHeight') AS DOUBLE))
    FROM "dw-ghn".data_auto_sorting.data_sorting_history h
    INNER JOIN base_orders b ON h.order_code = b.ordercode
    CROSS JOIN date_config d
    WHERE h.action = 'MATRIX_SCANNED_PARCEL'
      AND h.location_id IN ('1626', '21365000')
      AND h.order_code IS NOT NULL
      AND CAST(h.date_partition AS DATE) >= d.start_date
),

-- [BƯỚC 3] Tái dựng các lần đo đơn lẻ hợp lệ 4 chiều (Làm tròn theo phút để map chéo log)
valid_measurements AS (
    SELECT
        order_code,
        location_id,
        DATE_TRUNC('minute', last_updated_time) AS measured_time,
        GREATEST(
            MAX(raw_weight_gram) / 1000.0,
            (MAX(raw_length_mm) * MAX(raw_width_mm) * MAX(raw_height_mm)) / 6000000.0
        ) AS klkt_rdc_kg
    FROM raw_measurements
    GROUP BY order_code, location_id, DATE_TRUNC('minute', last_updated_time)
    HAVING MAX(raw_weight_gram) > 0
       AND MAX(raw_length_mm) > 0
       AND MAX(raw_width_mm) > 0
       AND MAX(raw_height_mm) > 0
),

-- [BƯỚC 4] Tìm mốc đo đầu, mốc đo cuối và số lần đo tại từng kho riêng biệt (HY & XY)
warehouse_metrics AS (
    SELECT
        order_code,
        -- Các thông số đo lường tại kho Hưng Yên (HY - 21365000)
        MIN_BY(
            CASE WHEN location_id = '21365000' THEN klkt_rdc_kg END, 
            CASE WHEN location_id = '21365000' THEN measured_time END
        ) AS klkt_first_HY,
        MAX_BY(
            CASE WHEN location_id = '21365000' THEN klkt_rdc_kg END, 
            CASE WHEN location_id = '21365000' THEN measured_time END
        ) AS klkt_last_HY,
        COUNT(DISTINCT CASE WHEN location_id = '21365000' THEN measured_time END) AS pass_count_HY,

        -- Các thông số đo lường tại kho Xuyên Á (XY - 1626)
        MIN_BY(
            CASE WHEN location_id = '1626' THEN klkt_rdc_kg END, 
            CASE WHEN location_id = '1626' THEN measured_time END
        ) AS klkt_first_XA,
        MAX_BY(
            CASE WHEN location_id = '1626' THEN klkt_rdc_kg END, 
            CASE WHEN location_id = '1626' THEN measured_time END
        ) AS klkt_last_XA,
        COUNT(DISTINCT CASE WHEN location_id = '1626' THEN measured_time END) AS pass_count_XA
    FROM valid_measurements
    GROUP BY order_code
),

-- [BƯỚC 5] Thực hiện tính toán chỉ số GAP_HY, GAP_XY độc lập và GAP_2_KHO liên vùng
gap_calculations AS (
    SELECT
        w.order_code,
        w.klkt_last_HY,
        w.klkt_last_XA,
        
        -- GAP_HY: Chỉ số sai lệch nội bộ kho Hưng Yên (Yêu cầu tối thiểu có 2 lần đo hợp lệ)
        CASE 
            WHEN w.pass_count_HY >= 2 THEN ABS(w.klkt_last_HY - w.klkt_first_HY)
            ELSE NULL
        END AS gap_HY_val,

        -- GAP_XY: Chỉ số sai lệch nội bộ kho Xuyên Á (Yêu cầu tối thiểu có 2 lần đo hợp lệ)
        CASE 
            WHEN w.pass_count_XA >= 2 THEN ABS(w.klkt_last_XA - w.klkt_first_XA)
            ELSE NULL
        END AS gap_XY_val,

        -- GAP_2_KHO: Sai lệch giữa lần đo cuối tại HY vs lần đo cuối tại XY
        -- Điều kiện chặt chẽ: Kiện hàng bắt buộc phải đi qua và đo đạc hợp lệ tại cả hai kho
        CASE 
            WHEN w.klkt_last_HY IS NOT NULL AND w.klkt_last_XA IS NOT NULL 
                THEN ABS(w.klkt_last_HY - w.klkt_last_XA)
            ELSE NULL
        END AS gap_2_kho_val
    FROM warehouse_metrics w
)

-- [BƯỚC 6] Tổng hợp kết quả báo cáo phục vụ vận hành và kiểm toán thiết bị DWS
SELECT
    b.success_date,
    b.client_type,
    b.journey_type,
    
    -- MẪU SỐ: Tổng lượng đơn hoàn tất toàn quốc
    COUNT(DISTINCT b.ordercode)                                         AS mau_total_toan_quoc,

    -- TỬ SỐ: Số đơn đo đạc thành công và hợp lệ tại từng kho
    COUNT(DISTINCT CASE WHEN g.klkt_last_HY IS NOT NULL THEN b.ordercode END) AS tu_do_dac_HY,
    COUNT(DISTINCT CASE WHEN g.klkt_last_XA IS NOT NULL THEN b.ordercode END) AS tu_do_dac_XA,

    -- PHÂN NHÓM SAI LỆCH GAP NỘI BỘ HƯNG YÊN (GAP_HY)
    COUNT(DISTINCT CASE WHEN g.gap_HY_val IS NOT NULL AND g.gap_HY_val < 1.0 
                        THEN b.ordercode END)                           AS gap_HY_duoi_1kg,
    COUNT(DISTINCT CASE WHEN g.gap_HY_val IS NOT NULL AND g.gap_HY_val >= 1.0 AND g.gap_HY_val <= 2.0 
                        THEN b.ordercode END)                           AS gap_HY_1_den_2kg,
    COUNT(DISTINCT CASE WHEN g.gap_HY_val IS NOT NULL AND g.gap_HY_val > 2.0 
                        THEN b.ordercode END)                           AS gap_HY_tren_2kg,

    -- PHÂN NHÓM SAI LỆCH GAP NỘI BỘ XUYÊN Á (GAP_XY)
    COUNT(DISTINCT CASE WHEN g.gap_XY_val IS NOT NULL AND g.gap_XY_val < 1.0 
                        THEN b.ordercode END)                           AS gap_XY_duoi_1kg,
    COUNT(DISTINCT CASE WHEN g.gap_XY_val IS NOT NULL AND g.gap_XY_val >= 1.0 AND g.gap_XY_val <= 2.0 
                        THEN b.ordercode END)                           AS gap_XY_1_den_2kg,
    COUNT(DISTINCT CASE WHEN g.gap_XY_val IS NOT NULL AND g.gap_XY_val > 2.0 
                        THEN b.ordercode END)                           AS gap_XY_tren_2kg,

    -- PHÂN NHÓM SAI LỆCH GAP GIỮA 2 KHO (GAP_2_KHO)
    COUNT(DISTINCT CASE WHEN g.gap_2_kho_val IS NOT NULL AND g.gap_2_kho_val < 1.0 
                        THEN b.ordercode END)                           AS gap_2_kho_duoi_1kg,
    COUNT(DISTINCT CASE WHEN g.gap_2_kho_val IS NOT NULL AND g.gap_2_kho_val >= 1.0 AND g.gap_2_kho_val <= 2.0 
                        THEN b.ordercode END)                           AS gap_2_kho_1_den_2kg,
    COUNT(DISTINCT CASE WHEN g.gap_2_kho_val IS NOT NULL AND g.gap_2_kho_val > 2.0 
                        THEN b.ordercode END)                           AS gap_2_kho_tren_2kg

FROM base_orders b
LEFT JOIN gap_calculations g ON b.ordercode = g.order_code
GROUP BY
    b.success_date,
    b.client_type,
    b.journey_type
ORDER BY
    b.success_date,
    b.client_type,
    b.journey_type;
