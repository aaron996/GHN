-- ============================================================
-- TẦNG 3: Sample đơn FD tại bưu cục/ngày spike + PoD URLs
-- Join v3 (FD metadata) với corev2 (pods array)
-- ============================================================
WITH fd_sample AS (
    SELECT
        v.order_code,
        v.deliverywarehouseid,
        v.deliverywh,
        v.toprovince,
        DATE(v.endpicktime)        AS pick_date,
        v.numdeliver,
        v.firstfaildeliverynote,
        v.secondfaildeliverynote,
        v.thirdfaildeliverynote,
        v.lastfaildeliverynote,
        v.allfailnote,
        v.startreturntime,
        -- Khoảng cách giữa pick và start return (giờ)
        DATE_DIFF('hour', v.endpicktime, v.startreturntime) AS hours_pick_to_return
    FROM "ghn-reporting".ka.dtm_ka_v3_createddate v
    WHERE
        v.createddate_partition BETWEEN DATE '2025-11-01' AND DATE '2026-05-31'
        AND v.endpicktime IS NOT NULL
        AND DATE(v.endpicktime) BETWEEN DATE '2026-05-01' AND DATE '2026-05-31'
        AND v.startreturntime IS NOT NULL
        AND v.clienttype IN ('SPE', 'SPB', 'TTSE', 'TTSB')
        AND v.deliverywarehouseid IN (/* wh_id flag */)
),

-- Join sang corev2 lấy pods
pods_raw AS (
    SELECT
        s.order_code,
        pod.order_status    AS pod_status,
        pod.reason          AS pod_reason,
        pod.time            AS pod_time,
        pod.lat             AS pod_lat,
        pod.lng             AS pod_lng,
        pod.is_correct      AS pod_is_correct,
        pod.urls            AS pod_urls
    FROM "ghn-reporting".online_core_corev2_shippingorder_createddate s
    CROSS JOIN UNNEST(s.pods) AS t(pod)
    WHERE
        s.createddate_partition BETWEEN DATE '2025-11-01' AND DATE '2026-05-31'
        AND s.order_code IN (SELECT order_code FROM fd_sample)
)

SELECT
    f.*,
    p.pod_status,
    p.pod_reason,
    p.pod_time,
    p.pod_lat,
    p.pod_lng,
    p.pod_is_correct,
    -- Flatten urls thành 1 string để dễ xem
    ARRAY_JOIN(p.pod_urls, ' | ')  AS pod_url_list
FROM fd_sample f
LEFT JOIN pods_raw p ON f.order_code = p.order_code
ORDER BY f.deliverywarehouseid, f.pick_date, f.order_code