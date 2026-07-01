SELECT
    date(c.orderdate),
    --c.fromdistrict,
    
    -- ĐOẠN LOGIC BẠN CẦN SỬA --
    CASE 
        WHEN (
            CASE 
                WHEN c.clientid = 3892833 THEN i.weight_api -- Nếu là Bulky thì dùng weight_api
                ELSE c.weight                               -- Các sàn khác dùng weight gốc
            END
        ) >= 15 THEN '>=15'
        ELSE '<15' 
    END AS "weight range",
    c.fromprovince,

    CASE
        WHEN c.clientid = 18692 THEN '1. SPE'
        WHEN c.clientid = 2781603 THEN '2. SPX'
        WHEN c.clientid = 9794 THEN '3. LZD'
        WHEN c.clientid IN (2590595, 1367) THEN '4. Tiki'
        WHEN c.clientid IN (224845) THEN '5. Reverse'
        WHEN c.clientid = 3892833 THEN '6.Bulky'
    END AS "Sàn",
    COUNT(C.ordercode) AS Total_Volume

FROM "ghn-reporting"."ka"."dtm_ka_v3_createddate" C
LEFT JOIN "iceberg"."freight_core"."shopee_order_detail_v4" I
    ON c."OrderCode" = I."OrderCode"
    -- LƯU Ý QUAN TRỌNG: Phải để điều kiện lọc partition của bảng I ở đây để tránh mất data bảng C
    AND I.createddate_partition >= date '2025-01-01' 

WHERE 
    DATE(C.orderdate) BETWEEN current_date - interval '14' day and current_date - interval '1' day
    --and C.clientid IN (9794)

--month(c.orderdate) in (12)
--and C.clientcontactname in ('AChoice-VN-HCMC','Hanoi','HCM Warehouse')
    --DATE(C.orderdate) BETWEEN date ('2026-01-20') and date ('202https://data-query.ghn.vn/api/v1/sqllab/export/YVt1G1fLn/6-02-11')
    --and currentstatus = ''
    --and c.toprovince = 'Hà Nội'
    -- AND c.clientid = 3892833 -- Bỏ comment nếu muốn test riêng Bulky

GROUP BY 1, 2, 3,4
ORDER BY 1 DESC
