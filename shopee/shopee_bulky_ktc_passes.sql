-- =============================================================================
-- PHÂN TÍCH TẦN SUẤT ĐƠN HÀNG ĐI QUA KHO TRUNG CHUYỂN (KTC) - SHOPEE BULKY (MÃ 3892833)
-- HẠT DỮ LIỆU (GRAIN): TUẦN (WEEK_START), NHÓM KHÁCH HÀNG, LOẠI DỊCH VỤ, TỈNH VÀ TUYẾN
-- =============================================================================

WITH ktc AS (
  SELECT
      warehouse_id
    , warehouse_name
    , region_shortname
  FROM iceberg.dwh.dim_warehouse
  WHERE warehouse_type = 'KTC'
)

, data_inside_filtered AS (
  SELECT
      h.order_code      AS ordercode
    , CAST(h.warehouse_id AS INT) AS warehouseid
    , h.action_time     AS createdtime
    , h.package_code    AS packagecode
    , h.action_category
    , trip_code
  FROM iceberg.clean.inside_package_history h
  WHERE h.dt >= '2026-05-18'
    AND h.dt <  CAST(CURRENT_DATE AS VARCHAR)
)

, nhap_kien_ra_kien_du AS (
  SELECT ordercode, warehouseid, createdtime
  FROM data_inside_filtered
  WHERE action_category = 'unpack'
)

, nhap_kien_normal AS (
  SELECT ordercode, warehouseid, createdtime, packagecode, trip_code
  FROM data_inside_filtered
  WHERE action_category = 'receive'
)

, xuat_kien AS (
  SELECT ordercode, warehouseid, MIN(createdtime) AS xuat_time
  FROM data_inside_filtered
  WHERE action_category = 'export'
  GROUP BY 1, 2
)

, data_trip_raw AS (
  SELECT
      transportation_code             AS trip_code
    , CAST(location_id AS INT)        AS warehouse_id
    , CAST(created_time AS TIMESTAMP) AS check_in_at
  FROM iceberg.raw.pickup_delivery__dtr_insidev3__transportation_history h
  WHERE h.dt >= '2026-05-18'
    AND h.dt <  CAST(CURRENT_DATE AS VARCHAR)
    AND action_type = 'VEHICLE_ARRIVE'
)

, nhap_kien AS (
  SELECT ordercode, warehouseid, MIN(nhap_time) AS nhap_time
  FROM (
    SELECT
        ordercode
      , warehouseid
      , COALESCE(b.check_in_at, a.createdtime) AS nhap_time
    FROM nhap_kien_normal a
    LEFT JOIN data_trip_raw b
      ON  a.warehouseid = b.warehouse_id
      AND a.trip_code   = b.trip_code

    UNION

    SELECT ordercode, warehouseid, createdtime AS nhap_time
    FROM nhap_kien_ra_kien_du
  )
  GROUP BY 1, 2
)

, all_orders_info AS (
  SELECT
      o.order_code                                               AS ordercode
    , o.client_id
    , 'Shopee Bulky'                                             AS client_channel
    , o.weight
    , o.deliver_warehouse_id
    , COALESCE(GREATEST(o.weight, o.converted_weight), 0)        AS max_weight
    , CASE
        WHEN COALESCE(GREATEST(o.weight, o.converted_weight), 0) >= 20000
          THEN 'hang_nang'
        ELSE 'hang_nhe'
      END                                                        AS service_type
    , sp.deliveryprovince                                        AS deli_province
    , sp.externallane                                            AS externallane
  FROM iceberg.clean.online_core_corev2_shippingorder_enddeliverytime o
  LEFT JOIN "ghn-reporting"."ka"."dtm_ka_shopee" sp
    ON o.order_code = sp.ordercode
  LEFT JOIN iceberg.dwh.dim_warehouse dw
    ON dw.warehouse_id = o.deliver_warehouse_id
  WHERE o.dt >= '2026-05-18'
    AND o.dt <  CAST(CURRENT_DATE AS VARCHAR)
    AND o.client_id = 3892833
    AND sp.loaddate BETWEEN DATE '2026-05-18' AND CURRENT_DATE - INTERVAL '1' DAY
    AND COALESCE(dw.warehouse_name, '') NOT LIKE '%Ahamove%'
)

, orders_ktc_passed AS (
  SELECT
      aoi.ordercode
    , COALESCE(COUNT(DISTINCT nk.warehouseid), 0) AS ktc_pass_count
  FROM nhap_kien nk
  JOIN ktc
    ON  nk.warehouseid = ktc.warehouse_id
  JOIN all_orders_info aoi
    ON  nk.ordercode = aoi.ordercode
  WHERE nk.nhap_time < (
    SELECT MIN(nk2.nhap_time)
    FROM nhap_kien nk2
    WHERE nk2.ordercode   = nk.ordercode
      AND nk2.warehouseid = aoi.deliver_warehouse_id
  )
  GROUP BY aoi.ordercode
)

, orders_nhap_delivery_warehouse AS (
  SELECT
      aoi.ordercode
    , aoi.client_id
    , aoi.client_channel
    , aoi.service_type
    , aoi.deli_province
    , aoi.externallane
    , DATE(MIN(nk.nhap_time)) AS created_date
  FROM nhap_kien nk
  JOIN all_orders_info aoi
    ON  nk.ordercode   = aoi.ordercode
    AND nk.warehouseid = aoi.deliver_warehouse_id
  GROUP BY
      aoi.ordercode
    , aoi.client_id
    , aoi.client_channel
    , aoi.service_type
    , aoi.deli_province
    , aoi.externallane
)

SELECT
    DATE_TRUNC('week', od.created_date)  AS week_start
  , od.client_id
  , od.client_channel
  , od.service_type
  , od.deli_province
  , od.externallane
  , CASE
      WHEN okp.ktc_pass_count IS NULL OR okp.ktc_pass_count = 0 THEN '0_lan'
      WHEN okp.ktc_pass_count = 1 THEN '1_lan'
      WHEN okp.ktc_pass_count = 2 THEN '2_lan'
      WHEN okp.ktc_pass_count = 3 THEN '3_lan'
      WHEN okp.ktc_pass_count = 4 THEN '4_lan'
      ELSE '>=5_lan'
    END                                  AS ktc_pass
  , COUNT(od.ordercode)                  AS total_orders
FROM orders_nhap_delivery_warehouse od
LEFT JOIN orders_ktc_passed okp
  ON od.ordercode = okp.ordercode
WHERE od.created_date >= DATE '2026-05-18'
  AND od.created_date <  CURRENT_DATE
GROUP BY 1, 2, 3, 4, 5, 6, 7
ORDER BY 1, total_orders DESC;
