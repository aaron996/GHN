WITH base AS (
    SELECT
        order_code,
        deliver_warehouse_id,
        client_id,
        CASE WHEN status like '%return%' THEN 1 ELSE 0 END AS is_fd
    FROM iceberg.clean.online_core_corev2_shippingorder_createddate
    WHERE
        dt > '2026-01-01'
        AND end_pick_time IS NOT NULL
        AND DATE(end_pick_time) BETWEEN DATE '2026-05-01' AND DATE '2026-05-31'
        AND deliver_warehouse_id IS NOT NULL
),
labeled AS (
    SELECT
        b.*,
        dw.warehouse_name AS deliverywh,
        CASE
            WHEN client_id IN (18692, 3892833)   THEN 'Shopee'
            WHEN client_id IN (3819710, 4447237) THEN 'TikTokShop'
            ELSE 'Khác'
        END AS client_label
    FROM base b
    LEFT JOIN "dw-ghn".datawarehouse.dim_warehouse dw
        ON b.deliver_warehouse_id = dw.warehouse_id
),
flagged_wh AS (
    SELECT *
    FROM labeled
    WHERE deliverywh IN (
        'Bưu Cục 73 Phó Cơ Điều-Phường Phước Hậu-Vĩnh Long',
        'Bưu Cục Thôn Chùa-Việt Yên-Bắc Giang',
        'Bưu Cục Tổ 1 TT Hương Sơn-Xã Phú Bình-Thái Nguyên',
        'Bưu Cục 992 Đường Huyện 35-Vĩnh Kim-Châu Thành-Tiền Giang',
        'Bưu Cục Quốc Lộ 50-Gò Công Tây-Tiền Giang',
        'Bưu Cục 77 Hoàng Quốc Việt-Mộc Châu-Sơn La',
        '(HYE) Mỹ Hào',
        'Bưu Cục Phố Mới-Thủy Nguyên-Hải Phòng',
        'Bưu Cục Khu Sơn Đông-Phường Nam Sơn-Bắc Ninh',
        'Bưu Cục Ngã Ba Khe-Văn Chấn-Yên Bái',
        'Bưu Cục 130 Trần Văn Lan-Q.Hải An-Hải Phòng',
        'Bưu Cục 83 Điện Biên Phủ-Xã Bum Tở-Lai Châu',
        'Bưu Cục 270 Phan Văn Mãng- Bến Lức-Long An',
        'Bưu Cục Cầu Thia-Nghĩa Lộ-Yên Bái',
        'Bưu Cục Gia Đông-Thuận Thành-Bắc Ninh',
        'Bưu Cục Chợ Ấp Đồn-Yên Trung-Yên Phong-Bắc Ninh',
        'Bưu Cục Cột 5-Hạ Long-Quảng Ninh',
        'Bưu cục Khu 4-Quan Hoá-Thanh Hoá',
        'Bưu Cục 102 Nguyễn Đăng Lành-Nam Sách-Hải Dương',
        'Bưu Cục An Dương 2-Hải Phòng'
    )
)
SELECT
    deliverywh,
    client_label,
    COUNT(*)      AS total_orders,
    SUM(is_fd)    AS fd_orders
FROM flagged_wh
--WHERE client_label IN ('Shopee', 'TikTokShop')
GROUP BY 1, 2
ORDER BY 1, 2
