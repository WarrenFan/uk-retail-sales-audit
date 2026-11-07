/********************************************************************************
Project:     UK Online Retail Audit (2009-2011)
Script:      01_clean_and_reconciliation.sql
Author:      Warren Fan
Description: Classifies every raw record exactly once (duplicate, non-product,
             anomaly or clean), builds the clean sales view, and produces the
             control-totals reconciliation used in the README.

Design note: All cleaning rules live in ONE place (vw_classified). Every other
             view is derived from it, so the reconciliation balances by design.
********************************************************************************/

USE RetailAudit;
GO

/*==============================================================================
  1. Classification view: every raw row gets exactly one status
     CASE is evaluated top to bottom, so a row is assigned to the first rule
     it matches and can never be counted in two steps.
==============================================================================*/
CREATE OR ALTER VIEW dbo.vw_classified AS
WITH Base AS (
    SELECT
        Invoice,
        StockCode,
        Description,
        Quantity,
        InvoiceDate,
        CAST(Price AS DECIMAL(18, 4)) AS UnitPrice,   -- 4 dp: some prices have more than 2 decimals
        CustomerID,
        Country,
        ROW_NUMBER() OVER (
            PARTITION BY Invoice, StockCode, Description, Quantity,
                         InvoiceDate, Price, CustomerID, Country
            ORDER BY (SELECT NULL)
        ) AS row_num
    FROM dbo.online_retail
),
Detailed AS (
    SELECT
        *,
        CAST(Quantity * UnitPrice AS DECIMAL(18, 4)) AS LineTotal,
        CASE
            WHEN row_num > 1
                THEN 'Exact duplicate'
            WHEN StockCode NOT LIKE '[0-9][0-9][0-9][0-9][0-9]%'
                THEN 'Non-product code'
            WHEN UnitPrice <= 0
                THEN 'Zero or negative price'
            WHEN Invoice LIKE 'A%'
                THEN 'Bad-debt adjustment (A invoice)'
            WHEN Quantity = 0
                THEN 'Zero quantity'
            WHEN Invoice NOT LIKE 'C%' AND Quantity < 0
                THEN 'Negative quantity on non-C invoice'
            WHEN Invoice LIKE 'C%' AND Quantity > 0
                THEN 'Positive quantity on C invoice'
            ELSE 'Clean'
        END AS StatusDetail
    FROM Base
)
SELECT
    Invoice,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    UnitPrice,
    LineTotal,
    CustomerID,
    Country,
    StatusDetail,
    CASE
        WHEN StatusDetail = 'Exact duplicate'  THEN '1_Duplicate'
        WHEN StatusDetail = 'Non-product code' THEN '2_NonProduct'
        WHEN StatusDetail = 'Clean'            THEN '4_Clean'
        ELSE '3_Anomaly'
    END AS RecordStatus
FROM Detailed;
GO

/*==============================================================================
  2. Exploration queries (results go into Data_Quality_Log.md)
==============================================================================*/

-- 2a. Review every excluded non-product StockCode before accepting the rule.
--     If any of these look like real products, adjust the rule in section 1.
SELECT
    StockCode,
    COUNT(*)         AS row_count,
    MAX(Description) AS sample_description,
    SUM(LineTotal)   AS total_amount
FROM dbo.vw_classified
WHERE RecordStatus = '2_NonProduct'
GROUP BY StockCode
ORDER BY row_count DESC;

-- 2b. Breakdown of every exclusion reason (rows and value).
SELECT
    RecordStatus,
    StatusDetail,
    COUNT(*)       AS row_count,
    SUM(LineTotal) AS total_amount
FROM dbo.vw_classified
GROUP BY RecordStatus, StatusDetail
ORDER BY RecordStatus, row_count DESC;
GO

/*==============================================================================
  3. Production clean view (source for analysis and Power BI)
==============================================================================*/
CREATE OR ALTER VIEW dbo.vw_clean_retail AS
SELECT
    Invoice,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    UnitPrice,
    LineTotal,
    -- Missing IDs become GUEST_USER; strip the ".0" artifact from Excel import
    CASE
        WHEN NULLIF(LTRIM(RTRIM(CustomerID)), '') IS NULL
            THEN 'GUEST_USER'
        WHEN LTRIM(RTRIM(CustomerID)) LIKE '%.0'
            THEN LEFT(LTRIM(RTRIM(CustomerID)), LEN(LTRIM(RTRIM(CustomerID))) - 2)
        ELSE LTRIM(RTRIM(CustomerID))
    END AS CustomerID,
    Country,
    CASE WHEN Invoice LIKE 'C%' THEN 1 ELSE 0 END                       AS IsCancelled,
    CASE WHEN Invoice LIKE 'C%' THEN 'Cancellation' ELSE 'Sale' END     AS TransactionType
FROM dbo.vw_classified
WHERE RecordStatus = '4_Clean';
GO

/*==============================================================================
  4. Table A: control-totals reconciliation (cleaning steps)
     The step list is joined with LEFT JOIN so a step still appears with 0
     if no rows fall into it.
==============================================================================*/
CREATE OR ALTER VIEW dbo.vw_reconciliation AS
SELECT
    0                  AS StepOrder,
    'Raw data'         AS StepDescription,
    COUNT(*)           AS TotalRows,
    SUM(LineTotal)     AS TotalAmount
FROM dbo.vw_classified

UNION ALL

SELECT
    s.StepOrder,
    s.StepDescription,
    -COUNT(c.RecordStatus)          AS TotalRows,
    -COALESCE(SUM(c.LineTotal), 0)  AS TotalAmount
FROM (VALUES
        (1, '1_Duplicate',  '(-) Exact duplicates'),
        (2, '2_NonProduct', '(-) Non-product codes'),
        (3, '3_Anomaly',    '(-) Anomalies')
     ) AS s (StepOrder, RecordStatus, StepDescription)
LEFT JOIN dbo.vw_classified AS c
    ON c.RecordStatus = s.RecordStatus
GROUP BY s.StepOrder, s.StepDescription

UNION ALL

SELECT
    4                  AS StepOrder,
    '= Cleaned dataset',
    COUNT(*),
    SUM(LineTotal)
FROM dbo.vw_clean_retail;
GO

/*==============================================================================
  5. Table B: cleaned dataset breakdown (sales vs cancellations)
==============================================================================*/
CREATE OR ALTER VIEW dbo.vw_net_revenue_breakdown AS
SELECT
    CASE TransactionType WHEN 'Sale' THEN 1 ELSE 2 END AS SortOrder,
    TransactionType                                     AS LineType,
    COUNT(*)                                            AS TotalRows,
    SUM(LineTotal)                                      AS TotalAmount
FROM dbo.vw_clean_retail
GROUP BY TransactionType

UNION ALL

SELECT
    3,
    'Net revenue',
    COUNT(*),
    SUM(LineTotal)
FROM dbo.vw_clean_retail;
GO

/*==============================================================================
  6. Outputs and verification
==============================================================================*/

-- Table A and Table B for the README
SELECT * FROM dbo.vw_reconciliation        ORDER BY StepOrder;
SELECT * FROM dbo.vw_net_revenue_breakdown ORDER BY SortOrder;

-- Check 1: Raw minus all exclusions must equal the cleaned dataset (expect 0, 0)
SELECT
    SUM(CASE WHEN StepOrder < 4 THEN TotalRows   ELSE 0 END)
  - SUM(CASE WHEN StepOrder = 4 THEN TotalRows   ELSE 0 END) AS row_difference,
    SUM(CASE WHEN StepOrder < 4 THEN TotalAmount ELSE 0 END)
  - SUM(CASE WHEN StepOrder = 4 THEN TotalAmount ELSE 0 END) AS amount_difference
FROM dbo.vw_reconciliation;

-- Check 2: Cleaned dataset in Table A must equal net revenue in Table B (expect 0, 0)
SELECT
    a.TotalRows   - b.TotalRows   AS row_difference,
    a.TotalAmount - b.TotalAmount AS amount_difference
FROM dbo.vw_reconciliation        AS a
CROSS JOIN dbo.vw_net_revenue_breakdown AS b
WHERE a.StepOrder = 4
  AND b.LineType  = 'Net revenue';
GO