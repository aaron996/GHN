-- =============================================================================
-- PHÂN TÍCH HIỆU SUẤT TRANSIT SLA HÀNG TUẦN - SHOPEE BULKY (MÃ 3892833)
-- HẠT DỮ LIỆU (GRAIN): TUẦN (WEEK_START), TỈNH/THÀNH GIAO, TUYẾN NGOÀI (EXTERNAL LANE)
-- =============================================================================

WITH slatime_filtered AS (
  SELECT
      o.order_code
    , sp.deadlinedeliverysla                                     AS sla_time
    , o.deliver_warehouse_id
    , o.pick_warehouse_id
    , w.province_id
    , w.warehouse_name
    , o.end_pick_time
    , o.pick_station_id
    , CAST(DATE(DATE_ADD('day', -1, sp.deadlinedeliverysla)) AS TIMESTAMP)
        + INTERVAL '15' HOUR                                     AS deadline_network
    , CAST(DATE(o.end_pick_time) AS TIMESTAMP)
        + INTERVAL '21' HOUR                                     AS deadline_lc
    , CAST(DATE(o.end_pick_time) AS TIMESTAMP)
        + INTERVAL '21' HOUR                                     AS deadline_dong_kien
    , o.end_delivery_time
    , o.status
    , o.first_delivered_time
    , o.client_id
    , sp.deliveryprovince                                        AS deli_province
    , sp.externallane                                            AS externallane

  FROM iceberg.clean.online_core_corev2_shippingorder_createddate o

  LEFT JOIN "ghn-reporting"."ka"."dtm_ka_shopee" sp
    ON o.order_code = sp.ordercode

  LEFT JOIN iceberg.dwh.dim_warehouse AS w
    ON w.warehouse_id = o.deliver_warehouse_id

  WHERE 1 = 1
    AND o.dt >= CAST(DATE_ADD('day', -60, CURRENT_DATE) AS VARCHAR)
    AND o.dt <  CAST(CURRENT_DATE AS VARCHAR)
    AND sp.loaddate BETWEEN CURRENT_DATE - INTERVAL '60' DAY
                        AND CURRENT_DATE - INTERVAL '1' DAY
    AND o.end_pick_time IS NOT NULL
    AND o.client_id = 3892833
    AND COALESCE(w.warehouse_name, '') NOT LIKE '%Ahamove%'
)

, relevant_orders AS (
  SELECT DISTINCT order_code
  FROM slatime_filtered
)

, data_inside_filtered AS (
  SELECT
      h.order_code                     AS ordercode
    , TRY(CAST(h.warehouse_id AS INT)) AS warehouseid
    , h.action_time                    AS createdtime
    , h.package_code                   AS packagecode
    , h.action_category

  FROM iceberg.clean.inside_package_history h

  INNER JOIN relevant_orders ro
    ON h.order_code = ro.order_code

  WHERE h.dt >= CAST(DATE_ADD('day', -60, CURRENT_DATE) AS VARCHAR)
    AND h.dt <  CAST(CURRENT_DATE AS VARCHAR)
)

, ra_kien_du AS (
  SELECT ordercode, warehouseid, createdtime
  FROM data_inside_filtered
  WHERE action_category = 'unpack'
)

, nhan_kien AS (
  SELECT ordercode, warehouseid, createdtime, packagecode
  FROM data_inside_filtered
  WHERE action_category = 'receive'
)

, xuat_kien AS (
  SELECT ordercode, warehouseid, createdtime, packagecode
  FROM data_inside_filtered
  WHERE action_category = 'export'
)

, data_trip_raw AS (
  SELECT
      AT_TIMEZONE(
        FROM_ISO8601_TIMESTAMP(
          JSON_EXTRACT_SCALAR(items, '$.check_in_at["$date"]')
        ),
        'Asia/Bangkok'
      )                                                          AS check_in_at
    , JSON_EXTRACT_SCALAR(items, '$.stop_point')                AS stop_point
    , CAST(JSON_EXTRACT(items, '$.items_dropped') AS ARRAY(VARCHAR)) AS items_dropped

  FROM "dw-ghn"."data_logistics_truck"."data_trip_co_dinh_inside"

  CROSS JOIN UNNEST(
    CAST(JSON_EXTRACT(partner_router, '$') AS ARRAY(JSON))
  ) AS t(items)

  WHERE updated_at_date >= CAST(DATE_ADD('day', -60, CURRENT_DATE) AS TIMESTAMP)
    AND updated_at_date <  CAST(CURRENT_DATE AS TIMESTAMP)
    AND JSON_EXTRACT(items, '$.items_dropped') IS NOT NULL
    AND CARDINALITY(CAST(JSON_EXTRACT(items, '$.items_dropped') AS ARRAY(VARCHAR))) > 0
)

, data_check_in AS (
  SELECT
      TRY(CAST(b.hub_code AS INT)) AS warehouse_id
    , data_trip_raw.check_in_at
    , item

  FROM data_trip_raw

  CROSS JOIN UNNEST(items_dropped) AS h(item)

  LEFT JOIN "dw-ghn"."data_logistics_truck"."data_partner_stoppoint_v2" b
    ON data_trip_raw.stop_point = b.code
)

, tg_don_hang_den_buu_cuc AS (
  SELECT
      ordercode
    , warehouseid
    , CASE
        WHEN CAST(b.check_in_at AS TIMESTAMP) IS NULL
          THEN createdtime
        ELSE CAST(b.check_in_at AS TIMESTAMP)
      END                                                        AS createdtime

  FROM nhan_kien a

  LEFT JOIN data_check_in b
    ON  a.warehouseid = b.warehouse_id
    AND a.packagecode = b.item

  UNION

  SELECT ordercode, warehouseid, createdtime
  FROM ra_kien_du
)

, transit_late AS (
  SELECT
      s.order_code
    , s.sla_time
    , s.status
    , s.client_id
    , s.pick_warehouse_id
    , s.deliver_warehouse_id
    , s.province_id
    , s.warehouse_name
    , s.deadline_network
    , s.deadline_lc
    , s.deli_province
    , s.externallane
    , MIN(CAST(a.createdtime AS TIMESTAMP)) AS received_time
    , MIN(CAST(b.createdtime AS TIMESTAMP)) AS pick_delivered_time

  FROM slatime_filtered AS s

  LEFT JOIN tg_don_hang_den_buu_cuc AS a
    ON  s.order_code           = a.ordercode
    AND s.deliver_warehouse_id = a.warehouseid

  LEFT JOIN xuat_kien AS b
    ON  s.order_code        = b.ordercode
    AND s.pick_warehouse_id = b.warehouseid

  GROUP BY
      s.order_code
    , s.sla_time
    , s.status
    , s.client_id
    , s.pick_warehouse_id
    , s.deliver_warehouse_id
    , s.province_id
    , s.warehouse_name
    , s.deadline_network
    , s.deadline_lc
    , s.deli_province
    , s.externallane
)

SELECT
    DATE_TRUNC('week', received_time)                            AS week_start
  , deli_province
  , externallane
  , SUM(CASE WHEN received_time < deadline_network THEN 1 ELSE 0 END) AS ontime_tc
  , SUM(CASE WHEN DATE(received_time) > DATE(sla_time) THEN 1 ELSE 0 END) AS da_tre
  , SUM(
      CASE
        WHEN DATE(received_time) = DATE(sla_time)
         AND province_id IN (201, 202)
         AND received_time > CAST(DATE(received_time) AS TIMESTAMP) + INTERVAL '8' HOUR
          THEN 1
        WHEN DATE(received_time) = DATE(sla_time)
         AND province_id NOT IN (201, 202)
         AND received_time > CAST(DATE(received_time) AS TIMESTAMP) + INTERVAL '9' HOUR
          THEN 1
        ELSE 0
      END
    )                                                            AS D0C2
  , SUM(
      CASE
        WHEN DATE(received_time) = DATE(sla_time)
         AND province_id IN (201, 202)
         AND received_time <= CAST(DATE(received_time) AS TIMESTAMP) + INTERVAL '8' HOUR
          THEN 1
        WHEN DATE(received_time) = DATE(sla_time)
         AND province_id NOT IN (201, 202)
         AND received_time <= CAST(DATE(received_time) AS TIMESTAMP) + INTERVAL '9' HOUR
          THEN 1
        ELSE 0
      END
    )                                                            AS D0C1
  , SUM(
      CASE
        WHEN DATE_ADD('day', 1, DATE(received_time)) = DATE(sla_time)
         AND province_id IN (201, 202)
         AND received_time > CAST(DATE(received_time) AS TIMESTAMP) + INTERVAL '8' HOUR
          THEN 1
        WHEN DATE_ADD('day', 1, DATE(received_time)) = DATE(sla_time)
         AND province_id NOT IN (201, 202)
         AND received_time > CAST(DATE(received_time) AS TIMESTAMP) + INTERVAL '9' HOUR
          THEN 1
        ELSE 0
      END
    )                                                            AS D1C2
  , SUM(
      CASE
        WHEN DATE_ADD('day', 1, DATE(received_time)) = DATE(sla_time)
         AND province_id IN (201, 202)
         AND received_time <= CAST(DATE(received_time) AS TIMESTAMP) + INTERVAL '8' HOUR
          THEN 1
        WHEN DATE_ADD('day', 1, DATE(received_time)) = DATE(sla_time)
         AND province_id NOT IN (201, 202)
         AND received_time <= CAST(DATE(received_time) AS TIMESTAMP) + INTERVAL '9' HOUR
          THEN 1
        ELSE 0
      END
    )                                                            AS D1C1
  , SUM(
      CASE
        WHEN DATE_ADD('day', 2, DATE(received_time)) = DATE(sla_time)
        THEN 1 ELSE 0
      END
    )                                                            AS D2
  , SUM(
      CASE
        WHEN DATE_ADD('day', 2, DATE(received_time)) < DATE(sla_time)
        THEN 1 ELSE 0
      END
    )                                                            AS D3
  , COUNT(order_code)                                            AS tong_don

FROM transit_late

WHERE 1 = 1
AND DATE(received_time) >= DATE '2026-05-18'
AND DATE(received_time) < CURRENT_DATE
GROUP BY
    DATE_TRUNC('week', received_time)
  , deli_province
  , externallane;
