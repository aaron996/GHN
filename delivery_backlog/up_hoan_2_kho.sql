
--code lấy all đơn
SELECT
  ordercode
  ,case 
  when towardcode = '21903' and deliverywarehouseid = 1327 then 'Kho M14' 
  when towardcode = '22303' and deliverywarehouseid = 21965000 then 'Kho 3CE tiki'
  end AS "kho"
  ,clientid
  ,DATE(enddeliverytime) AS "enddeliverytime"
  ,DATE(lastdeliveredupdatedtime) AS "lastdeliveredupdatedtime"
  ,currentstatus AS Status
  ,numdeliver
  ,numreturn
  ,currentwh
FROM dtm_ka_v3_createddate
WHERE clientid = 224845
  AND numdeliver >= 1
  AND towardcode in ('21903','22303')
  AND returnwardcode in ('21903','22303')
  AND MONTH(orderdate) IN (7,8,9,10)
  and currentstatus not in ('returned','delivered')
  AND deliverywarehouseid in (1327,21965000)



-- Export data reverse cancel
SELECT 
  GS."OrderCode"
  ,clientid
  ,DATE(enddeliverytime) AS "enddeliverytime"
  ,DATE(lastdeliveredupdatedtime) AS "lastdeliveredupdatedtime"
  ,currentstatus AS Status
  ,numdeliver
  ,numreturn
  ,currentwh
FROM "gsheet-data_input_from_external"."default"."input_customer_shopee" GS
LEFT JOIN "ghn-reporting"."ka".dtm_ka_v3_createddate C
  ON GS."OrderCode" = C.ordercode
WHERE GS."OrderCode" IS NOT NULL
and c.clientid = 224845
AND C.numdeliver IS NOT NULL
and c.numdeliver >=1
