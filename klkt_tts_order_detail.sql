-- =============================================================================
-- TRUY VẤN CHI TIẾT ĐƠN HÀNG TTS VÀ BIẾN ĐỘNG ĐO ĐẠC KLKT — N-1
-- TIÊU CHUẨN MẪU: ĐỦ 4 CHIỀU (W-L-W-H > 0) TRÊN CÙNG MỘT KHO (không cần cùng phút)
-- TIÊU CHUẨN GAP: CHÊNH LỆCH CÂN NẶNG (weight-only, không yêu cầu dim)
-- HẠT DỮ LIỆU (GRAIN): CHI TIẾT ĐẾN TỪNG MÃ ĐƠN HÀNG (ORDER_CODE)
--
-- ĐIỀU KIỆN LỌC KIỂM TOÁN CHẶT CHẼ (KAS AUDIT CONDITIONS):
--   1. Ngày hoàn thành thành công (Deli/Return) = N-1
--   2. Đơn hàng bắt buộc đã được đo đủ 4 chiều tại ít nhất 1 kho (tiêu chuẩn V2)
--   3. Đơn hàng BẮT BUỘC có sai số cân thuộc 1 trong 2 nhóm:
--      - GAP 1: >= 2 lần cân tại cùng 1 kho (chênh lệch lần cuối - lần đầu)
--      - GAP 2: Được cân tại cả 2 kho HY và XA (chênh lệch lần cân cuối giữa 2 kho)
--
-- TEAM PHÂN TÍCH: KAS DATA GOVERNANCE & STRATEGIC PLANNING
-- =============================================================================

WITH date_config AS (
    SELECT
        CAST(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Ho_Chi_Minh' AS DATE) - INTERVAL '1' DAY  AS start_date,
        CAST(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Ho_Chi_Minh' AS DATE) - INTERVAL '1' DAY  AS end_date,
        CAST(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Ho_Chi_Minh' AS DATE) - INTERVAL '30' DAY AS partition_start  -- mở rộng 30 ngày để đủ buffer đơn leadtime dài
),

-- [BƯỚC 1] Tập mẫu đơn hàng hoàn tất toàn quốc — success_date = N-1
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

-- [BƯỚC 2] Thu thập dữ liệu đo đạc thô từ thiết bị DWS, Matrix, cân tự động
-- Fix: tất cả nhánh dùng >= d.partition_start thay vì >= d.start_date
-- để bắt được log đo đạc xảy ra trước ngày hoàn thành (đơn leadtime dài)
raw_measurements AS (
    -- Feeder cân tại Xuyên Á
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
      AND h.location_id = '1626'
      AND h.order_code IS NOT NULL
      AND CAST(h.date_partition AS DATE) >= d.partition_start  -- fix

    UNION ALL

    -- Feeder cân tại Hưng Yên
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
      AND h.location_id = '21365000'
      AND h.order_code IS NOT NULL
      AND CAST(h.date_partition AS DATE) >= d.partition_start  -- fix

    UNION ALL

    -- Cân tại Hưng Yên (WEIGHING_PARCEL)
    SELECT
        h.order_code, h.location_id, h.last_updated_time,
        TRY(CAST(JSON_EXTRACT_SCALAR(h.data, '$.weight') AS DOUBLE)),
        NULL, NULL, NULL
    FROM "dw-ghn".data_auto_sorting.data_sorting_history h
    INNER JOIN base_orders b ON h.order_code = b.ordercode
    CROSS JOIN date_config d
    WHERE h.action = 'WEIGHING_PARCEL'
      AND h.location_id = '21365000'
      AND h.order_code IS NOT NULL
      AND CAST(h.date_partition AS DATE) >= d.partition_start  -- fix

    UNION ALL

    -- DWS kích thước tại cả 2 kho
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
      AND CAST(h.date_partition AS DATE) >= d.partition_start  -- fix

    UNION ALL

    -- Matrix (cân + kích thước) tại cả 2 kho
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
      AND CAST(h.date_partition AS DATE) >= d.partition_start  -- fix
),

-- [BƯỚC 3A] Xác định đơn đủ điều kiện vào tệp mẫu — đủ 4 chiều tại cùng 1 kho, không cần cùng phút
-- Dùng để: lọc tệp mẫu + derive id_ktc
valid_4d AS (
    SELECT
        order_code,
        location_id
    FROM raw_measurements
    GROUP BY order_code, location_id
    HAVING MAX(raw_weight_gram) > 0
       AND MAX(raw_length_mm) > 0
       AND MAX(raw_width_mm) > 0
       AND MAX(raw_height_mm) > 0
),

-- [BƯỚC 3B] Tái dựng từng lần cân theo phút — weight-only, không yêu cầu đủ 4 chiều
-- Dùng để: tính pass_count, first/last weight cho gap1 và gap2
-- Join theo order_code (không theo location_id) để bắt được weight tại kho không đủ 4 chiều
valid_weight AS (
    SELECT
        r.order_code,
        r.location_id,
        DATE_TRUNC('minute', r.last_updated_time) AS measured_time,
        ROUND(MAX(r.raw_weight_gram) / 1000.0, 3) AS klkt_rdc_kg
    FROM raw_measurements r
    INNER JOIN (
        SELECT DISTINCT order_code FROM valid_4d
    ) v ON r.order_code = v.order_code
    GROUP BY r.order_code, r.location_id, DATE_TRUNC('minute', r.last_updated_time)
    HAVING MAX(r.raw_weight_gram) > 0
),

-- [BƯỚC 4] Metrics first/last/pass_count theo từng kho — dùng cho cả gap1 và gap2
warehouse_metrics AS (
    SELECT
        order_code,
        MIN_BY(
            CASE WHEN location_id = '21365000' THEN klkt_rdc_kg END,
            CASE WHEN location_id = '21365000' THEN measured_time END
        ) AS klkt_first_HY,
        MAX_BY(
            CASE WHEN location_id = '21365000' THEN klkt_rdc_kg END,
            CASE WHEN location_id = '21365000' THEN measured_time END
        ) AS klkt_last_HY,
        COUNT(DISTINCT CASE WHEN location_id = '21365000' THEN measured_time END) AS pass_count_HY,

        MIN_BY(
            CASE WHEN location_id = '1626' THEN klkt_rdc_kg END,
            CASE WHEN location_id = '1626' THEN measured_time END
        ) AS klkt_first_XA,
        MAX_BY(
            CASE WHEN location_id = '1626' THEN klkt_rdc_kg END,
            CASE WHEN location_id = '1626' THEN measured_time END
        ) AS klkt_last_XA,
        COUNT(DISTINCT CASE WHEN location_id = '1626' THEN measured_time END) AS pass_count_XA
    FROM valid_weight
    GROUP BY order_code
),

-- [BƯỚC 5] Tính GAP theo logic kiểm toán KAS
gap_calculations AS (
    SELECT
        w.order_code,
        w.klkt_last_HY,
        w.klkt_last_XA,

        -- GAP 1: chênh lệch cân nội kho (lần cuối - lần đầu), cần >= 2 lần cân
        CASE
            WHEN w.pass_count_HY >= 2 AND w.pass_count_XA >= 2
                THEN GREATEST(ABS(w.klkt_last_HY - w.klkt_first_HY), ABS(w.klkt_last_XA - w.klkt_first_XA))
            WHEN w.pass_count_HY >= 2
                THEN ABS(w.klkt_last_HY - w.klkt_first_HY)
            WHEN w.pass_count_XA >= 2
                THEN ABS(w.klkt_last_XA - w.klkt_first_XA)
            ELSE NULL
        END AS gap1_val,

        -- GAP 2: chênh lệch cân chéo 2 kho (lần cân cuối HY vs lần cân cuối XA)
        CASE
            WHEN w.klkt_last_HY IS NOT NULL AND w.klkt_last_XA IS NOT NULL
                THEN ABS(w.klkt_last_HY - w.klkt_last_XA)
            ELSE NULL
        END AS gap2_val
    FROM warehouse_metrics w
)

-- [BƯỚC 6] Xuất dữ liệu chi tiết ở mức mã đơn hàng
-- Chỉ lấy đơn có gap1 HOẶC gap2 hợp lệ
SELECT
    b.ordercode,
    b.success_date,
    b.client_type,
    b.journey_type,
    CASE
        WHEN g.klkt_last_HY IS NOT NULL AND g.klkt_last_XA IS NOT NULL THEN 'HY + XA'
        WHEN g.klkt_last_HY IS NOT NULL                                THEN '21365000'
        WHEN g.klkt_last_XA IS NOT NULL                                THEN '1626'
    END                                         AS id_ktc,
    ROUND(g.klkt_last_HY, 3)                    AS rdc_last_measured_HY_kg,
    ROUND(g.klkt_last_XA, 3)                    AS rdc_last_measured_XA_kg,
    ROUND(g.gap1_val, 3)                        AS intra_warehouse_gap1_kg,
    ROUND(g.gap2_val, 3)                        AS cross_warehouse_gap2_kg
FROM base_orders b
INNER JOIN gap_calculations g ON b.ordercode = g.order_code
WHERE g.gap1_val IS NOT NULL
   OR g.gap2_val IS NOT NULL
ORDER BY
    b.success_date ASC,
    b.ordercode ASC;
