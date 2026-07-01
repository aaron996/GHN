-- =============================================================================
-- PHÂN TÍCH TỒN ĐỌNG GIAO HÀNG (PENDING BACKLOG) TẠI CÁC BƯU CỤC TRỌNG ĐIỂM
-- KHU VỰC: LONG AN, BÌNH PHƯỚC, ĐỒNG NAI
-- =============================================================================

WITH base AS (
    SELECT
        so.order_code,
        so.created_date,
        so.client_id,
        so.status,
        so.current_warehouse_id,
        so.deliver_warehouse_id,
        so.to_ward_code,
        so.to_ward_id_v2,
        so.end_pick_time,

        CASE
            WHEN so.client_id = 18692   THEN 'SPE'
            WHEN so.client_id = 3892833 THEN 'SPB'
            WHEN so.client_id = 3819710 THEN 'TTSE'
            WHEN so.client_id = 4447237 THEN 'TTSB'
            WHEN so.client_id NOT IN (
                18692, 3892833, 3819710, 4447237,
                2781603, 2590595, 224845, 9794, 1367
            ) THEN 'SME'
            ELSE 'OTHER_EXCLUDED'
        END AS client_group

    FROM iceberg.clean.online_core_corev2_shippingorder_createddate so

    WHERE 1 = 1
        AND so.dt >= DATE_FORMAT(CURRENT_DATE - INTERVAL '7' DAY, '%Y-%m-%d')
        AND so.current_warehouse_id = so.deliver_warehouse_id
        AND so.status NOT IN ('delivered', 'returned', 'return', 'lost', 'scrap')
        AND (
            so.client_id IN (18692, 3892833, 3819710, 4447237)
            OR so.client_id NOT IN (
                2781603, 2590595, 224845, 9794, 1367,
                18692, 3892833, 3819710, 4447237
            )
        )
),

warehouse_dim AS (
    SELECT warehouse_id, MAX(warehouse_name) AS warehouse_name
    FROM iceberg.dwh.dim_warehouse
    GROUP BY warehouse_id
),

ward_dim AS (
    SELECT
        CAST(ward_id AS VARCHAR) AS ward_id,
        MAX(province_name)       AS province_name,
        MAX(district_name)       AS district_name,
        MAX(ward_name)           AS ward_name
    FROM "dw-ghn".datawarehouse.dim_location_ward
    GROUP BY CAST(ward_id AS VARCHAR)
),

-- ── inbounddeliveryhubtime: logic 3 tầng ──────────────────────────────────

last_receive AS (
    SELECT order_code, action_time AS ibh_from_receive
    FROM (
        SELECT
            iph.order_code,
            iph.action_time,
            ROW_NUMBER() OVER (
                PARTITION BY iph.order_code
                ORDER BY iph.action_time DESC
            ) AS rn
        FROM iceberg.clean.inside_package_history iph
        INNER JOIN base b
            ON  iph.order_code                   = b.order_code
            AND CAST(iph.warehouse_id AS BIGINT) = b.deliver_warehouse_id
        WHERE
            iph.dt          >= DATE_FORMAT(CURRENT_DATE - INTERVAL '7' DAY, '%Y-%m-%d')
            AND iph.action_name = 'RECEIVE_PACKAGE'
    ) sub
    WHERE rn = 1
),

last_unpack AS (
    SELECT order_code, action_time AS ibh_from_unpack
    FROM (
        SELECT
            iph.order_code,
            iph.action_time,
            ROW_NUMBER() OVER (
                PARTITION BY iph.order_code
                ORDER BY iph.action_time DESC
            ) AS rn
        FROM iceberg.clean.inside_package_history iph
        INNER JOIN base b
            ON  iph.order_code                   = b.order_code
            AND CAST(iph.warehouse_id AS BIGINT) = b.deliver_warehouse_id
        WHERE
            iph.dt             >= DATE_FORMAT(CURRENT_DATE - INTERVAL '7' DAY, '%Y-%m-%d')
            AND iph.action_category = 'unpack'
    ) sub
    WHERE rn = 1
),

-- ── join tất cả ────────────────────────────────────────────────────────────

joined AS (
    SELECT
        b.order_code    AS ordercode,
        CAST(b.created_date AS DATE) AS created_date,
        b.client_id     AS clientid,
        b.client_group,
        b.status        AS currentstatus,
        wh.warehouse_name AS currentwh,
        wh.warehouse_name AS deliverywh,
        to_loc.province_name AS toprovince,
        to_loc.district_name AS todistrict,
        COALESCE(
            CAST(b.to_ward_code AS VARCHAR),
            CAST(b.to_ward_id_v2 AS VARCHAR)
        ) AS towardcode,
        to_loc.ward_name AS ward_name,

        -- inbounddeliveryhubtime: 3-tier fallback
        COALESCE(
            lr.ibh_from_receive,
            lu.ibh_from_unpack,
            b.end_pick_time
        ) AS inbounddeliveryhubtime,

        CASE
            WHEN lr.ibh_from_receive IS NOT NULL THEN 'receive_package'
            WHEN lu.ibh_from_unpack  IS NOT NULL THEN 'unpack'
            WHEN b.end_pick_time     IS NOT NULL THEN 'end_pick_time'
            ELSE NULL
        END AS ibh_source,

        -- pending gap tính từ inbounddeliveryhubtime
        CASE
            WHEN COALESCE(lr.ibh_from_receive, lu.ibh_from_unpack, b.end_pick_time) IS NOT NULL
            THEN DATE_DIFF(
                'hour',
                COALESCE(lr.ibh_from_receive, lu.ibh_from_unpack, b.end_pick_time),
                CAST(CURRENT_TIMESTAMP AS TIMESTAMP)
            )
            ELSE NULL
        END AS pending_hours,

        CASE
            WHEN COALESCE(lr.ibh_from_receive, lu.ibh_from_unpack, b.end_pick_time) IS NOT NULL
            THEN DATE_DIFF(
                'day',
                COALESCE(lr.ibh_from_receive, lu.ibh_from_unpack, b.end_pick_time),
                CAST(CURRENT_TIMESTAMP AS TIMESTAMP)
            )
            ELSE NULL
        END AS pending_days,

        ROW_NUMBER() OVER (
            PARTITION BY b.order_code
            ORDER BY b.created_date DESC
        ) AS rn

    FROM base b

    LEFT JOIN warehouse_dim wh
        ON b.current_warehouse_id = wh.warehouse_id

    LEFT JOIN ward_dim to_loc
        ON COALESCE(
            CAST(b.to_ward_code AS VARCHAR),
            CAST(b.to_ward_id_v2 AS VARCHAR)
        ) = to_loc.ward_id

    LEFT JOIN last_receive lr ON b.order_code = lr.order_code
    LEFT JOIN last_unpack  lu ON b.order_code = lu.order_code

    WHERE b.client_group <> 'OTHER_EXCLUDED'

        AND to_loc.province_name IN (
            'Long An', 'Bình Phước', 'Đồng Nai',
            'Binh Phuoc', 'Dong Nai'
        )

        AND wh.warehouse_name IN (
            'Bưu Cục 1070 Quốc Lộ 51-TP. Biên Hòa-Đồng Nai',
            'Bưu Cục 55/3B Trần Quốc Toản-Phường Trấn Biên-Đồng Nai',
            'Bưu Cục Quốc Lộ 1A-Bắc Sơn-Trảng Bom-Đồng Nai',
            'Bưu Cục 79A Hưng Đạo Vương-Biên Hòa-Đồng Nai',
            'Bưu Cục 270 Phan Văn Mãng- Bến Lức-Long An',
            'Bưu Cục Agtex Long Bình-Biên Hoà-Đồng Nai',
            'Bưu Cục 76/540 KP8-Hố Nai-TP Biên Hòa-Đồng Nai',
            'Bưu Cục Tân Đồng-Đồng Xoài-Bình Phước',
            'Bưu Cục Ấp Cầu Xây-Xã Thủ Thừa-Long An',
            'Bưu Cục Phước Thiền-Nhơn Trạch-Đồng Nai',
            'Bưu Cục KDC Hóa An-Biên Hòa-Đồng Nai',
            'Bưu Cục Đường Hùng Vương-Xã Phước An-Đồng Nai'
        )
)

SELECT
    ordercode,
    created_date,
    clientid,
    client_group,
    currentstatus,
    currentwh,
    deliverywh,
    toprovince,
    todistrict,
    towardcode,
    ward_name,
    inbounddeliveryhubtime,
    ibh_source,
    pending_hours,
    pending_days

FROM joined
WHERE rn = 1

ORDER BY
    toprovince,
    todistrict,
    currentwh,
    currentstatus,
    pending_days  DESC,
    pending_hours DESC;
