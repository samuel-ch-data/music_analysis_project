WITH DF AS (
    SELECT
        PRIM_BILL_MTHD_CD
      , AT_BUY_CNT
      , AVG(OUT_PROD_RATE) AS OUT_PROD_AVG_RATE
    FROM (
        SELECT
            F1.VLD_END_DATE
          , F1.PRIM_BILL_MTHD_CD
          , F1.AT_BUY_CNT
          , F1.TARGET_PROD_CNT
          , F2.DT
          , F2.OUT_PROD_CNT
          , IF(F2.OUT_PROD_CNT IS NULL, 0, F2.OUT_PROD_CNT/CAST(F1.TARGET_PROD_CNT AS DOUBLE)) AS OUT_PROD_RATE
        FROM (
            SELECT
                DATE(T1.VLD_END_DATE AT TIME ZONE 'Asia/Seoul' + INTERVAL '1' DAY) AS VLD_END_DATE
              , T1.PRIM_BILL_MTHD_CD
              , CASE
                    WHEN T1.AT_BUY_CNT = 0              THEN '0'
                    WHEN T1.AT_BUY_CNT = 1              THEN '1'
                    WHEN T1.AT_BUY_CNT = 2              THEN '2'
                    WHEN T1.AT_BUY_CNT = 3              THEN '3'
                    WHEN T1.AT_BUY_CNT BETWEEN 4 AND 11 THEN '4-11'
                    WHEN T1.AT_BUY_CNT >= 12            THEN '12<'
                END AS AT_BUY_CNT
              , COUNT(DISTINCT T1.BUY_NO) AS TARGET_PROD_CNT
            FROM HADOOP_KENT.MELON_MA_STAT_PRODUCTION.F_PROD_USER_FXMT_DT  T1
            JOIN HADOOP_KENT.MELON_MA_STAT_PRODUCTION.D_PROD T2 ON (T1.PROD_ID = T2.PROD_ID)
            LEFT OUTER JOIN (
                SELECT
                    BUY_NO
                  , AUTO_BILL_STAUS_CODE
                FROM (
                    SELECT
                        BUY_NO
                      , FIRST_VALUE(AUTO_BILL_STAUS_CODE) OVER (PARTITION BY BUY_NO ORDER BY PROD_STAUS_SEQ DESC) AS AUTO_BILL_STAUS_CODE
                    FROM HADOOP_KENT.MELON_ODS_COMMERCE_PRODUCTION.SPA_PROD_STAT_TBH_RO
                ) T11
                WHERE AUTO_BILL_STAUS_CODE <> '1Q0100'
                GROUP BY
                    1, 2
                ) T4
            ON (T1.BUY_NO = T4.BUY_NO)
            WHERE T1.LOG_DATE BETWEEN CAST(DATE_FORMAT(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Seoul' - INTERVAL '60' DAY, '%Y%m%d') AS VARCHAR(8)) AND CAST(DATE_FORMAT(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Seoul' - INTERVAL '1' DAY, '%Y%m%d') AS VARCHAR(8))
              AND T1.PROD_STAT_CD NOT IN (3401, 3901, 2200, 2100, 3900, 3902, 3903) /*자결당일해지, 일지정지해제(자결성공), 일시정지 -> 제외*/
              AND T2.PROD_ATTR_CD NOT IN (10040, 10050) /*종량제외*/
              AND T2.PROD_SELL_PRT_CD = 60000 /*B2C*/
              AND T2.PROD_PRT_CD = 20000 
              AND T1.PF_YN = 1
              AND DATE(T1.VLD_STRT_DATE AT TIME ZONE 'Asia/Seoul') <= DATE(T1.VLD_END_DATE AT TIME ZONE 'Asia/Seoul')
              AND DATE(DT) = DATE(VLD_END_DATE AT TIME ZONE 'Asia/Seoul' - INTERVAL '1' DAY)
              AND T4.AUTO_BILL_STAUS_CODE IS NULL /*자발적해지 제외*/
            GROUP BY 1, 2, 3
            ) F1
        LEFT OUTER JOIN (
            SELECT
                DATE(T1.DT + INTERVAL '1' DAY) AS DT
              , T1.PRIM_BILL_MTHD_CD
              , CASE
                    WHEN T1.AT_BUY_CNT = 0              THEN '0'
                    WHEN T1.AT_BUY_CNT = 1              THEN '1'
                    WHEN T1.AT_BUY_CNT = 2              THEN '2'
                    WHEN T1.AT_BUY_CNT = 3              THEN '3'
                    WHEN T1.AT_BUY_CNT BETWEEN 4 AND 11 THEN '4-11'
                    WHEN T1.AT_BUY_CNT >= 12            THEN '12<'
                END AS AT_BUY_CNT
              , COUNT(DISTINCT T1.BUY_NO) AS OUT_PROD_CNT
            FROM HADOOP_KENT.MELON_MA_STAT_PRODUCTION.F_PROD_USER_FXMT_DT  T1
            JOIN HADOOP_KENT.MELON_MA_STAT_PRODUCTION.D_PROD T2 ON (T1.PROD_ID = T2.PROD_ID)
            WHERE T1.LOG_DATE BETWEEN CAST(DATE_FORMAT(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Seoul' - INTERVAL '60' DAY, '%Y%m%d') AS VARCHAR(8)) AND CAST(DATE_FORMAT(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Seoul' + INTERVAL '1' DAY, '%Y%m%d') AS VARCHAR(8))
              AND T2.PROD_ATTR_CD NOT IN (10040, 10050)
              AND T2.PROD_SELL_PRT_CD = 60000
              AND T1.PF_YN = 1
              AND T1.PROD_STAT_CD IN (3400, 3402) -- 자결실패
              AND T2.PROD_PRT_CD = 20000
            GROUP BY 1, 2, 3
            ) F2
        ON (F1.VLD_END_DATE = F2.DT AND F1.PRIM_BILL_MTHD_CD = F2.PRIM_BILL_MTHD_CD AND F1.AT_BUY_CNT = F2.AT_BUY_CNT)
        ) F3
    GROUP BY 1, 2
)
SELECT
    DF1.VLD_END_DATE AS DT
  , DF1.PRED_OUT_PROD_CNT AS PRED_FAIL_CNT
FROM (
    SELECT
        VLD_END_DATE
      , ROUND(SUM(PRED_OUT_PROD_CNT)) AS PRED_OUT_PROD_CNT
    FROM (
        SELECT
            F1.VLD_END_DATE
          , F1.PRIM_BILL_MTHD_CD
          , F1.AT_BUY_CNT
          , F1.TARGET_PROD_CNT
          , F2.OUT_PROD_AVG_RATE
          , F1.TARGET_PROD_CNT*F2.OUT_PROD_AVG_RATE AS PRED_OUT_PROD_CNT
        FROM (
            SELECT
                DATE(T1.VLD_END_DATE AT TIME ZONE 'Asia/Seoul' + INTERVAL '1' DAY) AS VLD_END_DATE
              , T1.PRIM_BILL_MTHD_CD
              , CASE
                    WHEN T1.AT_BUY_CNT = 0              THEN '0'
                    WHEN T1.AT_BUY_CNT = 1              THEN '1'
                    WHEN T1.AT_BUY_CNT = 2              THEN '2'
                    WHEN T1.AT_BUY_CNT = 3              THEN '3'
                    WHEN T1.AT_BUY_CNT BETWEEN 4 AND 11 THEN '4-11'
                    WHEN T1.AT_BUY_CNT >= 12            THEN '12<'
                END AS AT_BUY_CNT
              , COUNT(DISTINCT T1.BUY_NO) AS TARGET_PROD_CNT
            FROM HADOOP_KENT.MELON_MA_STAT_PRODUCTION.F_PROD_USER_FXMT_DT  T1
            JOIN HADOOP_KENT.MELON_MA_STAT_PRODUCTION.D_PROD T2 ON (T1.PROD_ID = T2.PROD_ID)
            LEFT OUTER JOIN (
                SELECT
                    BUY_NO
                  , AUTO_BILL_STAUS_CODE
                FROM (
                    SELECT
                        BUY_NO
                      , FIRST_VALUE(AUTO_BILL_STAUS_CODE) OVER (PARTITION BY BUY_NO ORDER BY PROD_STAUS_SEQ DESC) AS AUTO_BILL_STAUS_CODE
                    FROM HADOOP_KENT.MELON_ODS_COMMERCE_PRODUCTION.SPA_PROD_STAT_TBH_RO
                ) T11
                WHERE AUTO_BILL_STAUS_CODE <> '1Q0100'
                GROUP BY
                    1, 2
            ) T4
            ON (T1.BUY_NO = T4.BUY_NO)
            WHERE T1.LOG_DATE = CAST(DATE_FORMAT(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Seoul' - INTERVAL '1' DAY, '%Y%m%d') AS VARCHAR(8))
              AND T1.PROD_STAT_CD NOT IN (3401, 3901, 2200, 2100, 3900, 3902, 3903) /*자결당일해지, 일지정지해제(자결성공), 일시정지 -> 제외*/
              AND T2.PROD_ATTR_CD NOT IN (10040, 10050) /*종량제외*/
              AND T2.PROD_SELL_PRT_CD = 60000 /*B2C*/
              AND T1.PF_YN = 1
              AND DATE(T1.VLD_STRT_DATE AT TIME ZONE 'Asia/Seoul') <= DATE(T1.VLD_END_DATE AT TIME ZONE 'Asia/Seoul')
              AND T2.PROD_PRT_CD = 20000
              AND DATE(VLD_END_DATE AT TIME ZONE 'Asia/Seoul' + INTERVAL '1' DAY) BETWEEN DATE(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Seoul') - INTERVAL '31' DAY AND DATE(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Seoul') + INTERVAL '31' DAY
              AND T4.AUTO_BILL_STAUS_CODE IS NULL /*자발적해지 제외*/
            GROUP BY
                1, 2, 3
        ) F1
        LEFT OUTER JOIN DF F2
        ON (F1.PRIM_BILL_MTHD_CD = F2.PRIM_BILL_MTHD_CD AND F1.AT_BUY_CNT = F2.AT_BUY_CNT)
    ) FINAL
    GROUP BY 1
) DF1
WHERE DF1.VLD_END_DATE BETWEEN DATE(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Seoul') + INTERVAL '1' DAY AND DATE(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Seoul') + INTERVAL '31' DAY
ORDER BY DF1.VLD_END_DATE