------------------------------------------------------------ Query 1: Tổng quan tất cả chỉ số performance ------------------------------------------------------------

WITH
  Total_Table AS (
    SELECT
      month(C.orderdate) AS Time -- thay đổi sang Week/Month nếu cần
      ,COUNT(C.ordercode) AS Total_Volume
    FROM dtm_ka_v3_createddate C
    WHERE C.clientid IN (18692)
      AND DATE(C.orderdate) BETWEEN DATE('2025-08-01') AND DATE('2025-09-30')
    GROUP BY 1
  )
, Detail_Normal AS (
    SELECT
      month(C.orderdate) AS Time --thay đổi sang Week/Month
      ,COUNT(C.ordercode) AS Volume_Created
      ,SUM(
          CASE
          WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 0
            WHEN (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
              OR (HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 1
            ELSE 0
          END
          ) AS OntimeFirstPU
      ,SUM(
          CASE
          WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 0
            WHEN (HOUR(C.orderdate) < 18 AND DATE(C.endpicktime) <= DATE(C.orderdate)) 
              OR (HOUR(C.orderdate) >= 18 AND COALESCE(DATE(C.endpicktime), CURRENT_DATE) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 1
            ELSE 0 
          END
          ) AS OntimeSuccessPU
      ,SUM(
          CASE
            WHEN C.endpicktime IS NOT NULL THEN 1
            ELSE 0
          END
          ) AS PickupSuccess
    FROM dtm_ka_v3_createddate C
    WHERE C.clientid IN (18692)
      AND C.isexpecteddropoff = False
      AND NOT C.channel = 'WH - Shopee'
      AND DATE(C.orderdate) BETWEEN DATE('2025-08-01') AND DATE('2025-09-30')
    GROUP BY 1
  )
, Normal AS (
    SELECT
      Time
      ,ROUND((AVG(OntimeFirstPU)/AVG(Volume_Created)),4) AS "%OntimeFirstPU_Normal"
      ,ROUND((AVG(OntimeSuccessPU)/AVG(Volume_Created)),4) AS "%OntimeSuccessPU_Normal"
      ,ROUND((AVG(PickupSuccess)/AVG(Volume_Created)),4) AS "%PickupSuccess_Normal"
    FROM Detail_Normal
    GROUP BY 1
  )
, Detail_Sunday AS (
    SELECT
      month(C.orderdate) AS Time --thay đổi sang Week/Month
      ,COUNT(C.ordercode) AS Volume_Created
      ,SUM(
          CASE
          WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 0
            WHEN (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
              OR (HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 1
            ELSE 0
          END
          ) AS OntimeFirstPU
    FROM dtm_ka_v3_createddate C
    WHERE C.clientid IN (18692)
      AND C.isexpecteddropoff = False
      AND NOT C.channel = 'WH - Shopee'
      AND EXTRACT(DAY_OF_WEEK FROM C.orderdate) = 7
      AND DATE(C.orderdate) BETWEEN DATE('2025-08-01') AND DATE('2025-09-30')
    GROUP BY 1
  )
, Sunday AS (
    SELECT
      Time
      ,ROUND((AVG(OntimeFirstPU)/AVG(Volume_Created)),4) AS "%OntimeFirstPU_Sunday"
    FROM Detail_Sunday
    GROUP BY 1
  )
, event_days AS (
    SELECT
      CAST(date_column AS DATE) AS Date_SLA
    FROM 
      (VALUES 
    -- Double days
      '2024-10-10', '2024-10-11', '2024-10-12', '2024-11-11', '2024-11-12', '2024-11-13', '2024-12-12', '2024-12-13', '2024-12-14',
      '2025-01-15', '2025-01-16', '2025-01-17', '2025-02-02', '2025-02-03', '2025-02-04', '2025-03-03', '2025-03-04', '2025-03-05',
      '2025-04-04', '2025-04-05', '2025-04-06', '2025-05-05', '2025-05-06', '2025-05-07', '2025-06-06', '2025-06-07', '2025-06-08',
      '2025-07-07', '2025-07-08', '2025-07-09', '2025-08-08', '2025-08-09', '2025-08-10', '2025-09-09', '2025-09-10', '2025-09-11',
      '2025-10-10', '2025-10-11', '2025-10-12', '2025-11-11', '2025-11-12', '2025-11-13', '2025-12-12', '2025-12-13', '2025-12-14',
      
    -- Holidays
      '2025-01-01', '2025-01-25', '2025-01-26', '2025-01-27', '2025-01-28', '2025-01-29', '2025-01-30', '2025-01-31', '2025-02-01',
      '2025-02-02', '2025-04-07', '2025-04-30', '2025-05-01', '2025-09-01', '2025-09-02'
      ) AS t(date_column) -- Thêm hoặc chỉnh sửa ngày cần extend
  )
, Penalty_Raw AS (
    SELECT
      month(C.orderdate) AS Time --thay đổi sang Week/Month
      ,COUNT(C.ordercode) AS Volume_Created
      ,SUM
        (
        CASE
          WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 0
          WHEN ((HOUR(C.orderdate) >= 18 AND DATE(C.orderdate) = DATE(E.Date_SLA) AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '2' DAY)))
            OR ((HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)))
            OR ((HOUR(C.orderdate) < 18 AND DATE(C.orderdate) = DATE(E.Date_SLA) AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)))
            OR (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
          THEN 1
          ELSE 0
        END
        ) AS OntimeFirstPU
    FROM dtm_ka_v3_createddate C
    LEFT JOIN event_days AS E
      ON DATE(C.orderdate) = DATE(E.Date_SLA)
    WHERE C.clientid IN (18692)
      AND C.isexpecteddropoff = False
      AND NOT C.channel = 'WH - Shopee'
      AND DATE(C.orderdate) BETWEEN DATE('2025-08-01') AND DATE('2025-09-30')
      AND NOT (C.currentstatus = 'cancel' AND DATE(C.canceltime) <= DATE(C.orderdate))
    GROUP BY 1
  )
, Penalty_Pivot AS (
    SELECT
      Time
      ,ROUND((AVG(OntimeFirstPU)/AVG(Volume_Created)),4) AS "%OntimeFirstPU_Penalty"
    FROM Penalty_Raw
    GROUP BY 1
  )
  SELECT
    N.Time
    ,T.Total_Volume
    ,"%OntimeFirstPU_Normal"
    ,"%OntimeFirstPU_Penalty"
    ,"%OntimeSuccessPU_Normal"
    ,"%PickupSuccess_Normal"
    ,"%OntimeFirstPU_Sunday"
  FROM Normal AS N
  JOIN Total_Table AS T
    ON N."Time" = T."Time"
  JOIN Penalty_Pivot AS P
    ON N."Time" = P."Time"
  LEFT JOIN Sunday AS S
    ON N."Time" = S."Time"
  ORDER BY 1 ASC
------------------------------------------------------------ Query 2: Tất cả chỉ số performance của từng vùng ------------------------------------------------------------
WITH
  Normal_Total AS (
    SELECT
      month(C.orderdate) AS Time --thay đổi sang Week/Month
      ,COUNT(C.ordercode) AS Total_Volume
    FROM dtm_ka_v3_createddate AS C
    WHERE C.clientid IN (18692)
      AND C.isexpecteddropoff = False
      AND NOT C.channel = 'WH - Shopee'
      AND DATE(C.orderdate) BETWEEN DATE('2025-08-01') AND DATE('2025-09-30')
    GROUP BY 1
  )
, Normal_Details AS (
    SELECT
      month(C.orderdate) AS Time --thay đổi sang Week/Month
      ,C.fromregionshortname AS Region
      ,COUNT(C.ordercode) AS Volume_Created
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 0
            WHEN (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
              OR (HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 1
            ELSE 0
          END
          ) AS OntimeFirstPU
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 1
            WHEN (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
              OR (HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 0
            ELSE 1
          END
          ) AS LateFirstPU
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 0
            WHEN (HOUR(C.orderdate) < 18 AND DATE(C.endpicktime) <= DATE(C.orderdate)) 
              OR (HOUR(C.orderdate) >= 18 AND COALESCE(DATE(C.endpicktime), CURRENT_DATE) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 1
            ELSE 0 
          END
          ) AS OntimeSuccessPU
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 1
            WHEN (HOUR(C.orderdate) < 18 AND DATE(C.endpicktime) <= DATE(C.orderdate)) 
              OR (HOUR(C.orderdate) >= 18 AND COALESCE(DATE(C.endpicktime), CURRENT_DATE) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 0
            ELSE 1
          END
          ) AS LateSuccessPU
      FROM dtm_ka_v3_createddate AS C
      WHERE C.clientid IN (18692)
        AND C.isexpecteddropoff = False
        AND NOT C.channel = 'WH - Shopee'
        AND DATE(C.orderdate) BETWEEN DATE('2025-08-01') AND DATE('2025-09-30')
      GROUP BY 1,2
  )
, Sunday_Details AS (
    SELECT
      month(C.orderdate) AS Time --thay đổi sang Week/Month
      ,C.fromregionshortname AS Region
      ,COUNT(C.ordercode) AS Volume_Created
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 0
            WHEN (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
              OR (HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 1
            ELSE 0
          END
          ) AS OntimeFirstPU
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 1
            WHEN (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
              OR (HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 0
            ELSE 1
          END
          ) AS LateFirstPU
    FROM dtm_ka_v3_createddate C
    WHERE C.clientid IN (18692)
      AND C.isexpecteddropoff = False
      AND NOT C.channel = 'WH - Shopee'
      AND EXTRACT(DAY_OF_WEEK FROM C.orderdate) = 7
      AND DATE(C.orderdate) BETWEEN DATE('2025-08-01') AND DATE('2025-09-30')
    GROUP BY 1,2
  )
  SELECT
    ND.Time
    ,ND.Region
    ,ND.Volume_Created
    ,ROUND((AVG(ND.OntimeFirstPU)/AVG(ND.Volume_Created)),4) AS "%Ontime1stPU_Normal"
    ,AVG(ND.LateFirstPU)/AVG(NT.Total_Volume) AS "%1stContribute_Normal"
    ,ROUND((AVG(ND.OntimeSuccessPU)/AVG(ND.Volume_Created)),4) AS "%OntimeSuccessPU_Normal"
    ,AVG(ND.LateSuccessPU)/AVG(NT.Total_Volume) AS "%SuccessContribute_Normal"
    ,ROUND((AVG(SD.OntimeFirstPU)/AVG(SD.Volume_Created)),4) AS "%Ontime1stPU_Sunday"
    ,AVG(SD.LateFirstPU)/AVG(NT.Total_Volume) AS "%1stContribute_Sunday"
  FROM Normal_Details AS ND
  JOIN Normal_Total AS NT
    ON ND.Time = NT.Time
  LEFT JOIN Sunday_Details AS SD
    ON ND.Time = SD.Time AND ND.Region = SD.Region
  GROUP BY 1,2,3
  ORDER BY 2 ASC
---------------------------------------------------------------Province-------------------------------------------------------------------------------------
WITH
  Normal_Total AS (
    SELECT
      month(C.orderdate) AS Time --thay đổi sang Week/Month
      ,COUNT(C.ordercode) AS Total_Volume
    FROM dtm_ka_v3_createddate AS C
    WHERE C.clientid IN (18692)
      AND C.isexpecteddropoff = False
      AND NOT C.channel = 'WH - Shopee'
      AND DATE(C.orderdate) BETWEEN DATE('2025-08-01') AND DATE('2025-09-30')
    GROUP BY 1
  )
, Normal_Details AS (
    SELECT
      month(C.orderdate) AS Time --thay đổi sang Week/Month
      ,C.fromregionshortname AS Region
      ,C.fromprovince as Province
      ,COUNT(C.ordercode) AS Volume_Created
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 0
            WHEN (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
              OR (HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 1
            ELSE 0
          END
          ) AS OntimeFirstPU
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 1
            WHEN (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
              OR (HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 0
            ELSE 1
          END
          ) AS LateFirstPU
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 0
            WHEN (HOUR(C.orderdate) < 18 AND DATE(C.endpicktime) <= DATE(C.orderdate)) 
              OR (HOUR(C.orderdate) >= 18 AND COALESCE(DATE(C.endpicktime), CURRENT_DATE) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 1
            ELSE 0 
          END
          ) AS OntimeSuccessPU
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 1
            WHEN (HOUR(C.orderdate) < 18 AND DATE(C.endpicktime) <= DATE(C.orderdate)) 
              OR (HOUR(C.orderdate) >= 18 AND COALESCE(DATE(C.endpicktime), CURRENT_DATE) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 0
            ELSE 1
          END
          ) AS LateSuccessPU
      FROM dtm_ka_v3_createddate AS C
      WHERE C.clientid IN (18692)
        AND C.isexpecteddropoff = False
        AND NOT C.channel = 'WH - Shopee'
        AND DATE(C.orderdate) BETWEEN DATE('2025-08-01') AND DATE('2025-09-30')
      GROUP BY 1,2,3
  )
, Sunday_Details AS (
    SELECT
      month(C.orderdate) AS Time --thay đổi sang Week/Month
      ,C.fromregionshortname AS Region
      ,C.fromprovince as Province
      ,COUNT(C.ordercode) AS Volume_Created
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 0
            WHEN (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
              OR (HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 1
            ELSE 0
          END
          ) AS OntimeFirstPU
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 1
            WHEN (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
              OR (HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 0
            ELSE 1
          END
          ) AS LateFirstPU
    FROM dtm_ka_v3_createddate C
    WHERE C.clientid IN (18692)
      AND C.isexpecteddropoff = False
      AND NOT C.channel = 'WH - Shopee'
      AND EXTRACT(DAY_OF_WEEK FROM C.orderdate) = 7
      AND DATE(C.orderdate) BETWEEN DATE('2025-08-01') AND DATE('2025-09-30')
    GROUP BY 1,2,3
  )
  SELECT
    ND.Time
    ,ND.Region
    ,ND.Province
    ,ND.Volume_Created
    ,ROUND((AVG(ND.OntimeFirstPU)/AVG(ND.Volume_Created)),4) AS "%Ontime1stPU_Normal"
    ,AVG(ND.LateFirstPU)/AVG(NT.Total_Volume) AS "%1stContribute_Normal"
    ,ROUND((AVG(ND.OntimeSuccessPU)/AVG(ND.Volume_Created)),4) AS "%OntimeSuccessPU_Normal"
    ,AVG(ND.LateSuccessPU)/AVG(NT.Total_Volume) AS "%SuccessContribute_Normal"
    ,ROUND((AVG(SD.OntimeFirstPU)/AVG(SD.Volume_Created)),4) AS "%Ontime1stPU_Sunday"
    ,AVG(SD.LateFirstPU)/AVG(NT.Total_Volume) AS "%1stContribute_Sunday"
  FROM Normal_Details AS ND
  JOIN Normal_Total AS NT
    ON ND.Time = NT.Time
  LEFT JOIN Sunday_Details AS SD
    ON ND.Time = SD.Time AND ND.Region = SD.Region AND ND.Province = SD.Province
  GROUP BY 1,2,3,4
  ORDER BY 2 ASC
---------------------------------------------------------------Sunday District Monthly-------------------------------------------------------------------------------------
WITH
  Normal_Total AS (
    SELECT
      month(C.orderdate) AS Time --thay đổi sang Week/Month
      ,COUNT(C.ordercode) AS Total_Volume
    FROM dtm_ka_v3_createddate AS C
    WHERE C.clientid IN (18692)
      AND C.isexpecteddropoff = False
      AND NOT C.channel = 'WH - Shopee'
      AND DATE(C.orderdate) BETWEEN DATE('2025-08-01') AND DATE('2025-09-30')
    GROUP BY 1
  )
, Normal_Details AS (
    SELECT
      month(C.orderdate) AS Time --thay đổi sang Week/Month
      --,C.fromregionshortname AS Region
      ,C.fromprovince as Province
      ,C.fromdistrict as District
      ,COUNT(C.ordercode) AS Volume_Created
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 0
            WHEN (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
              OR (HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 1
            ELSE 0
          END
          ) AS OntimeFirstPU
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 1
            WHEN (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
              OR (HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 0
            ELSE 1
          END
          ) AS LateFirstPU
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 0
            WHEN (HOUR(C.orderdate) < 18 AND DATE(C.endpicktime) <= DATE(C.orderdate)) 
              OR (HOUR(C.orderdate) >= 18 AND COALESCE(DATE(C.endpicktime), CURRENT_DATE) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 1
            ELSE 0 
          END
          ) AS OntimeSuccessPU
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 1
            WHEN (HOUR(C.orderdate) < 18 AND DATE(C.endpicktime) <= DATE(C.orderdate)) 
              OR (HOUR(C.orderdate) >= 18 AND COALESCE(DATE(C.endpicktime), CURRENT_DATE) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 0
            ELSE 1
          END
          ) AS LateSuccessPU
      FROM dtm_ka_v3_createddate AS C
      WHERE C.clientid IN (18692)
        AND C.isexpecteddropoff = False
        AND NOT C.channel = 'WH - Shopee'
        AND DATE(C.orderdate) BETWEEN DATE('2025-08-01') AND DATE('2025-09-30')
      GROUP BY 1,2,3
  )
, Sunday_Details AS (
    SELECT
      month(C.orderdate) AS Time --thay đổi sang Week/Month
      --,C.fromregionshortname AS Region
      ,C.fromprovince as Province
      ,C.fromdistrict as District
      ,COUNT(C.ordercode) AS Volume_Created
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 0
            WHEN (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
              OR (HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 1
            ELSE 0
          END
          ) AS OntimeFirstPU
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 1
            WHEN (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
              OR (HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 0
            ELSE 1
          END
          ) AS LateFirstPU
    FROM dtm_ka_v3_createddate C
    WHERE C.clientid IN (18692)
      AND C.isexpecteddropoff = False
      AND NOT C.channel = 'WH - Shopee'
      AND EXTRACT(DAY_OF_WEEK FROM C.orderdate) = 7
      AND DATE(C.orderdate) BETWEEN DATE('2025-08-01') AND DATE('2025-09-30')
    GROUP BY 1,2,3
  )
  SELECT
    ND.Time
   -- ,ND.Region
    ,ND.Province
    ,ND.District
    ,sum(ND.Volume_Created) as "Total vol"
    ,sum(nd.OntimeFirstPU) as "Ontime1stPU"
    ,sum(nd.OntimeSuccessPU) as "OntimeSuccessPU_Normal"
    ,sum(sd.Volume_Created) as "Total Sunday vol"
    ,sum(sd.OntimeFirstPU) as "Ontime1stPU_Sunday"
    
    --,ROUND((AVG(ND.OntimeFirstPU)/AVG(ND.Volume_Created)),4) AS "%Ontime1stPU_Normal"
    --,AVG(ND.LateFirstPU)/AVG(NT.Total_Volume) AS "%1stContribute_Normal"
    --,ROUND((AVG(ND.OntimeSuccessPU)/AVG(ND.Volume_Created)),4) AS "%OntimeSuccessPU_Normal"
    --,AVG(ND.LateSuccessPU)/AVG(NT.Total_Volume) AS "%SuccessContribute_Normal"
    --,ROUND((AVG(SD.OntimeFirstPU)/AVG(SD.Volume_Created)),4) AS "%Ontime1stPU_Sunday"
    --,AVG(SD.LateFirstPU)/AVG(SD.Volume_Created) AS "%1stContributetotal_Sunday"
    --,AVG(SD.LateFirstPU)/sum(SD.LateFirstPU) AS "%1stContributelate_Sunday"
  FROM Normal_Details AS ND
  JOIN Normal_Total AS NT
    ON ND.Time = NT.Time
  LEFT JOIN Sunday_Details AS SD
    ON ND.Time = SD.Time 
    --AND ND.Region = SD.Region 
    AND ND.Province = SD.Province
    AND ND.District = SD.District
  GROUP BY 1,2,3
  --ORDER BY 2 ASC
-----------------------------------------------------------------Sunday district Weekly------------------------------------------------------------------------
WITH
  Normal_Total AS (
    SELECT
      week(C.orderdate) AS Time --thay đổi sang Week/Month
      ,COUNT(C.ordercode) AS Total_Volume
    FROM dtm_ka_v3_createddate AS C
    WHERE C.clientid IN (18692)
      AND C.isexpecteddropoff = False
      AND NOT C.channel = 'WH - Shopee'
      AND DATE(C.orderdate) BETWEEN DATE('2025-08-01') AND DATE('2025-09-30')
    GROUP BY 1
  )
, Normal_Details AS (
    SELECT
      week(C.orderdate) AS Time --thay đổi sang Week/Month
      --,C.fromregionshortname AS Region
      ,C.fromprovince as Province
      ,C.fromdistrict as District
      ,COUNT(C.ordercode) AS Volume_Created
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 0
            WHEN (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
              OR (HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 1
            ELSE 0
          END
          ) AS OntimeFirstPU
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 1
            WHEN (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
              OR (HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 0
            ELSE 1
          END
          ) AS LateFirstPU
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 0
            WHEN (HOUR(C.orderdate) < 18 AND DATE(C.endpicktime) <= DATE(C.orderdate)) 
              OR (HOUR(C.orderdate) >= 18 AND COALESCE(DATE(C.endpicktime), CURRENT_DATE) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 1
            ELSE 0 
          END
          ) AS OntimeSuccessPU
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 1
            WHEN (HOUR(C.orderdate) < 18 AND DATE(C.endpicktime) <= DATE(C.orderdate)) 
              OR (HOUR(C.orderdate) >= 18 AND COALESCE(DATE(C.endpicktime), CURRENT_DATE) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 0
            ELSE 1
          END
          ) AS LateSuccessPU
      FROM dtm_ka_v3_createddate AS C
      WHERE C.clientid IN (18692)
        AND C.isexpecteddropoff = False
        AND NOT C.channel = 'WH - Shopee'
        AND DATE(C.orderdate) BETWEEN DATE('2025-08-01') AND DATE('2025-09-30')
      GROUP BY 1,2,3
  )
, Sunday_Details AS (
    SELECT
      week(C.orderdate) AS Time --thay đổi sang Week/Month
      --,C.fromregionshortname AS Region
      ,C.fromprovince as Province
      ,C.fromdistrict as District
      ,COUNT(C.ordercode) AS Volume_Created
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 0
            WHEN (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
              OR (HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 1
            ELSE 0
          END
          ) AS OntimeFirstPU
      ,SUM(
          CASE
            WHEN (firstfailpicknote = 'Nhân viên gặp sự cố' AND DATE(firstupdatedpickeduptime) != DATE(secondcreatedpickeduptime) AND DATE(firstupdatedpickeduptime) >= DATE(C.orderdate)) THEN 1
            WHEN (HOUR(C.orderdate) < 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate))
              OR (HOUR(C.orderdate) >= 18 AND DATE(COALESCE(C.firstupdatedpickeduptime, C.endpicktime, CURRENT_DATE)) <= DATE(C.orderdate + INTERVAL '1' DAY)) THEN 0
            ELSE 1
          END
          ) AS LateFirstPU
    FROM dtm_ka_v3_createddate C
    WHERE C.clientid IN (18692)
      AND C.isexpecteddropoff = False
      AND NOT C.channel = 'WH - Shopee'
      AND EXTRACT(DAY_OF_WEEK FROM C.orderdate) = 7
      AND DATE(C.orderdate) BETWEEN DATE('2025-08-01') AND DATE('2025-09-30')
    GROUP BY 1,2,3
  )
  SELECT
    ND.Time
   -- ,ND.Region
    ,ND.Province
    ,ND.District
    ,sum(ND.Volume_Created) as "Total vol"
    ,sum(nd.OntimeFirstPU) as "Ontime1stPU"
    ,sum(nd.OntimeSuccessPU) as "OntimeSuccessPU_Normal"
    ,sum(sd.Volume_Created) as "Total Sunday vol"
    ,sum(sd.OntimeFirstPU) as "Ontime1stPU_Sunday"
    
    --,ROUND((AVG(ND.OntimeFirstPU)/AVG(ND.Volume_Created)),4) AS "%Ontime1stPU_Normal"
    --,AVG(ND.LateFirstPU)/AVG(NT.Total_Volume) AS "%1stContribute_Normal"
    --,ROUND((AVG(ND.OntimeSuccessPU)/AVG(ND.Volume_Created)),4) AS "%OntimeSuccessPU_Normal"
    --,AVG(ND.LateSuccessPU)/AVG(NT.Total_Volume) AS "%SuccessContribute_Normal"
    --,ROUND((AVG(SD.OntimeFirstPU)/AVG(SD.Volume_Created)),4) AS "%Ontime1stPU_Sunday"
    --,AVG(SD.LateFirstPU)/AVG(SD.Volume_Created) AS "%1stContributetotal_Sunday"
    --,AVG(SD.LateFirstPU)/sum(SD.LateFirstPU) AS "%1stContributelate_Sunday"
  FROM Normal_Details AS ND
  JOIN Normal_Total AS NT
    ON ND.Time = NT.Time
  LEFT JOIN Sunday_Details AS SD
    ON ND.Time = SD.Time 
    --AND ND.Region = SD.Region 
    AND ND.Province = SD.Province
    AND ND.District = SD.District
  GROUP BY 1,2,3
  --ORDER BY 2 ASC
-----------------------------------------------------------------------------------------------------------------------------------------------------
