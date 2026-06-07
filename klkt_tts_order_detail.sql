-- =============================================================================
-- TRUY VẤN CHI TIẾT ĐƠN HÀNG TTS VÀ BIẾN ĐỘNG ĐO ĐẠC KLKT — CUỐI THÁNG 5/2026
-- TIÊU CHUẨN ĐO ĐẠC NGHIÊM NGẶT: ĐỦ 4 CHIỀU (W-L-W-H > 0) TRÊN CÙNG MỘT KHO
-- HẠT DỮ LIỆU (GRAIN): CHI TIẾT ĐẾN TỪNG MÃ ĐƠN HÀNG (ORDER_CODE)
-- 
-- ĐIỀU KIỆN LỌC KIỂM TOÁN CHẶT CHẼ (KAS AUDIT CONDITIONS):
--   1. Ngày hoàn thành thành công (Deli/Return) trong khoảng: 25/05/2026 - 31/05/2026
--   2. Đơn hàng bắt buộc đi qua ít nhất 1 trong 2 kho trọng điểm: Hưng Yên (21365000) hoặc Xuyên Á (1626)
--   3. Đơn hàng BẮT BUỘC phải xuất hiện sai số đo đạc thuộc 1 trong 2 nhóm:
--      - Có GAP 1: Ít nhất 2 lần đo hợp lệ tại cùng 1 kho (phát hiện lỗi ổn định thiết bị)
--      - Có GAP 2: Được đo hợp lệ tại cả 2 kho HY và XA (phát hiện lỗi lệch chuẩn liên miền)
--
-- CẢI TIẾN ĐỊNH DẠNG (DATA GOVERNANCE):
--   - Áp dụng ROUND(..., 3) cho tất cả các trường trọng lượng thập phân để triệt tiêu
--     sai số dấu thập phân IEEE 754 (Float Noise) và tránh lỗi nhận diện sai dấu ngăn cách của Excel.
--
-- TEAM PHÂN TÍCH: KAS DATA GOVERNANCE & STRATEGIC PLANNING
-- =============================================================================

WITH date_config AS (
    SELECT
        DATE '2026-05-25'  AS start_date, -- Giới hạn từ ngày 25/05
        DATE '2026-05-31'  AS end_date,   -- Đến ngày 31/05
        DATE '2026-03-01'  AS partition_start
),

-- [BƯỚC 1] Tập mẫu đơn hàng hoàn tất toàn quốc thoả mãn điều kiện khung thời gian và tuyến bưu cục
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
      -- Điều kiện thời gian: Khung ngày hoàn thành từ 25 - 31/05
      AND (
          (b.currentstatus = 'delivered'
              AND b.enddeliverytime IS NOT NULL
              AND CAST(b.enddeliverytime AS DATE) BETWEEN d.start_date AND d.end_date)
          OR
          (b.currentstatus = 'returned'
              AND b.endreturntime IS NOT NULL
              AND CAST(b.endreturntime AS DATE) BETWEEN d.start_date AND d.end_date)
      )
      -- Điều kiện kho bãi: Bắt buộc đơn đi qua ít nhất 1 trong 2 kho trung chuyển (Hưng Yên hoặc Xuyên Á)
      AND (
             b.firstsortingcenterid  IN (1626, 21365000)
          OR b.secondsortingcenterid IN (1626, 21365000)
          OR b.thirdsortingcenterid  IN (1626, 21365000)
          OR b.lastsortingcenterid   IN (1626, 21365000)
      )
      AND b.createddate_partition >= d.partition_start
),

-- [BƯỚC 2] Thu thập dữ liệu đo đạc thô từ thiết bị DWS, Matrix, cân tự động
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
      AND h.location_id = '1626' -- Kho Xuyên Á
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
      AND h.location_id = '21365000' -- Kho Hưng Yên
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

-- [BƯỚC 3] Gom nhóm bất đồng bộ và chuẩn hóa lượt đo (Passes) hợp lệ 4 chiều tại từng kho
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

-- [BƯỚC 4] Xác định kết quả lần đo đầu/cuối và số lần đi qua máy quét tại từng kho (HY & XA)
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

        -- Các thông số đo lường tại kho Xuyên Á (XA - 1626)
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

-- [BƯỚC 5] Tính toán giá trị GAP theo logic kiểm toán dữ liệu của KAS
gap_calculations AS (
    SELECT
        w.order_code,
        w.klkt_last_HY,
        w.klkt_last_XA,
        
        -- GAP 1: Sai lệch đo đạc nội bộ của cùng một kho (HY hoặc XA)
        -- Điều kiện: Kho đó bắt buộc phải có ít nhất 2 lượt đo (passes) hợp lệ. 
        -- Nếu cả hai kho đều thỏa mãn điều kiện, lấy giá trị sai lệch lớn nhất để làm chỉ số rủi ro thiết bị.
        -- Trả về NULL nếu không có kho nào ghi nhận >= 2 lần đo.
        CASE 
            WHEN w.pass_count_HY >= 2 AND w.pass_count_XA >= 2 
                THEN GREATEST(ABS(w.klkt_last_HY - w.klkt_first_HY), ABS(w.klkt_last_XA - w.klkt_first_XA))
            WHEN w.pass_count_HY >= 2 
                THEN ABS(w.klkt_last_HY - w.klkt_first_HY)
            WHEN w.pass_count_XA >= 2 
                THEN ABS(w.klkt_last_XA - w.klkt_first_XA)
            ELSE NULL
        END AS gap1_val,

        -- GAP 2: Sai lệch đo lường chéo liên miền giữa lần đo cuối tại HY vs lần đo cuối tại XA
        -- Điều kiện: Đơn hàng bắt buộc phải có thông số đo đạc hợp lệ tại cả hai đầu kho.
        -- Trả về NULL nếu đơn không đi qua hoặc không được quét thành công tại một trong hai kho.
        CASE 
            WHEN w.klkt_last_HY IS NOT NULL AND w.klkt_last_XA IS NOT NULL 
                THEN ABS(w.klkt_last_HY - w.klkt_last_XA)
            ELSE NULL
        END AS gap2_val
    FROM warehouse_metrics w
)

-- [BƯỚC 6] Xuất dữ liệu chi tiết ở mức mã đơn hàng (Raw Order Level)
-- Áp dụng bộ lọc nghiêm ngặt: Chỉ lấy đơn hàng có Gap 1 HOẶC Gap 2 hợp lệ
SELECT
    b.ordercode,
    b.success_date,
    b.client_type,
    b.journey_type,
    ROUND(g.klkt_last_HY, 3)                AS rdc_last_measured_HY_kg,
    ROUND(g.klkt_last_XA, 3)                AS rdc_last_measured_XA_kg,
    ROUND(g.gap1_val, 3)                    AS intra_warehouse_gap1_kg,
    ROUND(g.gap2_val, 3)                    AS cross_warehouse_gap2_kg
FROM base_orders b
INNER JOIN gap_calculations g ON b.ordercode = g.order_code
WHERE g.gap1_val IS NOT NULL 
   OR g.gap2_val IS NOT NULL
ORDER BY
    b.success_date ASC,
    b.ordercode ASC;
