WITH
  Details AS (
    SELECT
      C.orderdate,
      c.createddate,
      c.canceltime,
      C.ordercode,
      c.fromwardcode AS Ward_id,
      c.fromprovince AS Province,
      c.fromdistrict as District,
      w.ward_name as Ward,
      c.pickwh as Hub,
      c.currentstatus as currentstatus,
      c.clientcontactname,
      c.lastfailpicknote as lastfailpicknote,
      c.clienttype,
      c.clientid,
      c.fromregionshortname,
      c.numpick,
      c.weight,
      c.weightrdc,
 CASE
        WHEN C.PickWH LIKE '%Ahamove%' THEN 'Ahamove'
        WHEN C.PickWarehouseID IN (1297, 1327) THEN 'KHL'
        -- Giả định Subquery này trả về tập ID Kho tĩnh/hiện tại cho GXT
        WHEN C.PickWarehouseID IN (SELECT warehouse_id FROM "dw-ghn".datawarehouse.dim_warehouse WHERE department_name = 'Freight Operations Department' OR warehouse_name LIKE '%Kho Chuyển Tiếp %') THEN 'GXT'
        ELSE 'BC'
      end as TypeKH,
        CASE 
            WHEN endpicktime IS NOT NULL AND DATE(endpicktime) <= DATE(orderdate) THEN 'Ontime'
            
            WHEN numpick >= 3 
                AND thirdupdatedpickeduptime is not null 
                AND coalesce(lastfailpicknote,'') != 'Nhân viên gặp sự cố' 
                AND date(thirdupdatedpickeduptime) <= DATE(orderdate) 
              AND (currentstatus = 'cancel' AND date(canceltime) > DATE(orderdate) OR currentstatus != 'cancel') 
                THEN 'Ontime'
            
            WHEN numpick >= 2 
                AND secondupdatedpickeduptime is not null 
                AND coalesce(lastfailpicknote,'') != 'Nhân viên gặp sự cố' 
                AND date(secondupdatedpickeduptime) <= DATE(orderdate) 
                AND (currentstatus = 'cancel' AND date(canceltime) > DATE(orderdate) OR currentstatus != 'cancel') 
                THEN 'Ontime'
            
            WHEN numpick >= 1 
                AND firstupdatedpickeduptime  is not null 
                AND coalesce(firstfailpicknote,'') != 'Nhân viên gặp sự cố' 
                AND  date(firstupdatedpickeduptime) <= DATE(orderdate) 
                AND (currentstatus = 'cancel' AND date(canceltime) > DATE(orderdate) OR currentstatus != 'cancel') 
                THEN 'Ontime'
            when  currentstatus = 'cancel' AND date(canceltime) <= DATE(orderdate) then ''
            ELSE 'Late' 

      END AS IsOntime,
      CASE 
            WHEN endpicktime IS NOT NULL AND DATE(endpicktime) <= DATE(orderdate) THEN 'Done Ontime'
            when  currentstatus = 'cancel' AND date(canceltime) <= DATE(orderdate) then ''
            else 'Late'
      END AS PuDoneOntime,
            
      c.firstcreatedpickeduptime,
      c.firstupdatedpickeduptime,
      c.firstfailpicknote as firstfailpicknote,
      c.secondupdatedpickeduptime secondupdatedpickeduptime,
      c.thirdupdatedpickeduptime as thirdupdatedpickeduptime,
      endpicktime
    FROM "ghn-reporting"."ka"."dtm_ka_v3_createddate" C
    LEFT JOIN "dw-ghn"."datawarehouse"."dim_location_ward" W on c.fromwardcode = w.Ward_id
   -- LEFT join "ghn-reporting"."bd"."dtm_freight_Shopee_order_detail" F on c.ordercode = f.ordercode
    WHERE 
    C.clientid IN (18692)
      AND C.isexpecteddropoff = FALSE
      AND NOT C.channel = 'WH - Shopee'
     -- AND DATE(C.orderdate) BETWEEN date('2025-12-12') and date ('2025-12-15')
      --AND currentstatus = 'cancel' AND date(b.canceltime) < date(b.orderdate)) OR b.currentstatus != 'cancel' 
  )
  
SELECT
  date(D.orderdate),
  d.createddate,
  d.canceltime,
  D.ordercode,
  D.TypeKH,
  D.Province,
  D.District,
  D.Ward,
  D.fromregionshortname region,
  D.Hub,
  D.currentstatus,
  D.clientcontactname,
  D.clienttype,
  D.clientid,
  D.firstcreatedpickeduptime,
  D.firstupdatedpickeduptime,
  D.firstfailpicknote,
  D.endpicktime,
  D.secondupdatedpickeduptime,
  D.thirdupdatedpickeduptime,
  D.lastfailpicknote,
  D.IsOntime,
  d.PuDoneOntime,
  d.numpick,
  d.weight,
  d.weightrdc
FROM Details D
--INNER JOIN "gsheet-data_input_from_external"."default"."input_customer_shopee" GS
  --ON d.ordercode = GS.OrderCode
WHERE 
--d.ordercode = 'GYDFN4AU'
--d.clientcontactname in ('UNIQ by SimiGO')

--d.Hub = 'Bưu cục 148 Trâu Quỳ-Gia Lâm-HN'
--D.Province in ('Hà Nội')
--and D.District = 'Quận Bình Tân'
--and d.Ward in ('Phường Bình Hưng Hòa')
--and DATE(d.OrderTime) = CURRENT_DATE - INTERVAL '1' DAY
--and DATE(d.OrderTime) = date('2025-12-03')
d.Hub in ('Key Account Warehouse Ha Noi')
and DATE(d.orderdate) between date('2026-02-24') and date ('2026-02-26')
--and D.IsOntime = 'Late'
-- and DATE(d.orderdate) = date('2025-12-26')

--D.currentstatus in ('ready_to_pick','picking')
   --D.fromregionshortname = 'ĐCL'
  --and D.firstfailpicknote IS NOT NULL
  --AND D.firstfailpicknote != ''
  --AND D.firstfailpicknote NOT IN ('Nhân viên gặp sự cố')
--and DATE(d.OrderTime) BETWEEN CURRENT_DATE - INTERVAL '7' DAY AND CURRENT_DATE - INTERVAL '1' DAY


  
