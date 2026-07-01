-- =============================================================================
-- PHÂN TÍCH HIỆU SUẤT GIAO HÀNG VÀ BÁO CÁO BACKLOG - TIKTOKSHOP EXPRESS (TTS)
-- HẠT DỮ LIỆU (GRAIN): NGÀY BÁO CÁO (REPORT_DATE), TỈNH GIAO (TOPROVINCE)
-- =============================================================================

WITH delivered AS
  (SELECT CAST(enddeliveredtime AS DATE) AS report_date,
          toprovince,
          CAST(NULL AS VARCHAR) AS tuoibacklog,
          CAST(SUM(ontimeenddelivery) AS DOUBLE) / NULLIF(SUM(delivered), 0) AS metrics,
          'DELIVERED' AS metric_type
   FROM iceberg.freight_core.tts_express_order_detail
   WHERE createddate >= CURRENT_DATE - INTERVAL '30' DAY
     AND CAST(enddeliveredtime AS DATE) = CURRENT_DATE - INTERVAL '1' DAY
   GROUP BY 1,
            2),
     created AS
  (SELECT createddate AS report_date,
          toprovince,
          CAST(NULL AS VARCHAR) AS tuoibacklog,
          COUNT(DISTINCT ordercode) AS metrics,
          'CREATED' AS metric_type
   FROM iceberg.freight_core.tts_express_order_detail
   WHERE createddate >= CURRENT_DATE - INTERVAL '30' DAY
     AND createddate < CURRENT_DATE
     AND currentstatus != 'cancel'
   GROUP BY 1,
            2),
     backlog AS
  (SELECT CURRENT_DATE - INTERVAL '1' DAY AS report_date,
          tinhhientai AS toprovince,
          tuoibacklog,
          COUNT(DISTINCT madh) AS metrics,
          'BACKLOG' AS metric_type
   FROM "ghn-reporting"."ka"."Dtm_KA_Backlog"
   WHERE ordertype = 'Express'
     AND tuoibacklog IS NOT NULL
   GROUP BY 1,
            2,
            3)
SELECT *
FROM delivered
UNION ALL
SELECT *
FROM created
UNION ALL
SELECT *
FROM backlog
ORDER BY report_date DESC,
         toprovince,
         metric_type,
         tuoibacklog;
