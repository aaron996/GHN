-- =============================================================================
-- PHÂN TÍCH HIỆU SUẤT PICKUP SHOPEE KA VÀ SỰ CỐ NHÂN VIÊN (NVGSC)
-- HẠT DỮ LIỆU (GRAIN): NGÀY, TỈNH/THÀNH, QUẬN/HUYỆN LẤY HÀNG
-- =============================================================================

WITH orders_nvgsc AS (
    SELECT DISTINCT order_code
    FROM "iceberg"."raw"."lastmile_lastmile_trip_v2_production_tripitem"
    WHERE dt >= '2026-06-01'
      AND type = 'PICK'
      AND fail_note = 'Nhân viên gặp sự cố'
),

base AS (
    SELECT
        a.ordercode,
        a.pickprovince,
        a.pickdistrict,
        v.isexpecteddropoff,
        v.currentstatus,
        v.canceltime,
        v.firstupdatedpickeduptime AS first_valid_pickup_time,
        CASE 
            WHEN CAST(v.orderdate AS DATE) = CAST(v.createddate AS DATE) 
                 AND HOUR(v.createddate) >= 19 
            THEN CAST(v.orderdate AS DATE) + INTERVAL '1' DAY
            ELSE CAST(v.orderdate AS DATE)
        END AS order_date,
        CASE WHEN n.order_code IS NOT NULL THEN 1 ELSE 0 END AS has_nvgsc
    FROM "ghn-reporting".ka.dtm_ka_shopee a
    JOIN "ghn-reporting".ka.dtm_ka_v3_createddate v
        ON a.ordercode = v.ordercode
       AND v.createddate_partition >= DATE '2026-06-01'
    LEFT JOIN orders_nvgsc n
        ON a.ordercode = n.order_code
    WHERE a.loaddate  >= DATE '2026-06-01'
      AND a.clientid IN ('18692', '3892833')
      AND CASE 
            WHEN v.pickwh LIKE '%Ahamove%'    THEN 'AHAMOVE'
            WHEN v.pickwh LIKE '%Key Account%' THEN 'KA'
            ELSE 'OTHER'
          END NOT IN ('KA', 'AHAMOVE')
)

SELECT
    order_date,
    pickprovince,
    pickdistrict,

    COUNT(DISTINCT CASE
        WHEN (currentstatus = 'cancel' AND DATE(canceltime) > order_date) OR currentstatus != 'cancel'
        THEN ordercode
    END) AS pu_total_orders,

    COUNT(CASE
        WHEN ((currentstatus = 'cancel' AND DATE(canceltime) > order_date) OR currentstatus != 'cancel')
             AND COALESCE(isexpecteddropoff, false) = false
             AND DATE(first_valid_pickup_time) <= order_date
        THEN 1
    END) AS ontime_pu_orders,

    SUM(has_nvgsc) AS don_co_attempt_nvgsc,

    SUM(CASE 
            WHEN DATE(first_valid_pickup_time) > order_date
             AND has_nvgsc = 1
            THEN 1 ELSE 0 END) AS don_late_va_nvgsc

FROM base
GROUP BY 1, 2, 3
ORDER BY order_date DESC, pu_total_orders DESC;
