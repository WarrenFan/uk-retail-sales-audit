/********************************************************************************
Project:     UK Online Retail Audit (2009-2011)
Script:      03_abc_xyz_matrix.sql
Author:      Warren Fan
Description: Calculates the ABC-XYZ inventory optimization matrix:
             1. ABC classification based on Pareto revenue contribution (80/15/5).
             2. XYZ classification based on demand volatility (CV), with zeros
                padded only from each SKU's first active selling month onwards.
             3. Identifies new SKUs (< 6 months history) as category 'N'.
             4. Materializes SKU-level results into dbo.abc_xyz_results.
********************************************************************************/

USE RetailAudit;
GO

-- ==============================================================================
-- 1. Base Aggregation View: Monthly Product Quantity and Revenue
-- ==============================================================================
CREATE OR ALTER VIEW dbo.vw_product_monthly_qty AS
SELECT 
    StockCode,
    MAX(Description) AS Description,
    YEAR(InvoiceDate) AS SalesYear,
    MONTH(InvoiceDate) AS SalesMonth,
    SUM(CASE WHEN Quantity > 0 THEN Quantity ELSE 0 END) AS MonthlyQty,
    SUM(LineTotal) AS MonthlyRevenue
FROM dbo.vw_clean_retail
WHERE InvoiceDate < '2011-12-01'
GROUP BY StockCode, YEAR(InvoiceDate), MONTH(InvoiceDate);
GO

-- ==============================================================================
-- 2. Materialize SKU-level ABC-XYZ Results into Physical Table
-- ==============================================================================
DROP TABLE IF EXISTS dbo.abc_xyz_results;
GO

WITH ProductTotals AS (
    -- Exclude SKUs with net zero or negative lifetime revenue
    SELECT 
        StockCode,
        MAX(Description) AS Description,
        SUM(MonthlyRevenue) AS TotalRevenue,
        MIN(SalesYear * 12 + SalesMonth) AS FirstActiveMonthIndex
    FROM dbo.vw_product_monthly_qty
    GROUP BY StockCode
    HAVING SUM(MonthlyRevenue) > 0
),
CumulativeABC AS (
    -- Calculate strict cumulative revenue percentage once
    SELECT 
        StockCode,
        Description,
        TotalRevenue,
        FirstActiveMonthIndex,
        ROUND(
            SUM(TotalRevenue) OVER (
                ORDER BY TotalRevenue DESC, StockCode
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) * 100.0 / SUM(TotalRevenue) OVER (), 
            2
        ) AS CumRevenuePct
    FROM ProductTotals
),
RankedABC AS (
    -- Assign ABC tags cleanly without repeating the window expression
    SELECT 
        StockCode,
        Description,
        TotalRevenue,
        FirstActiveMonthIndex,
        CumRevenuePct,
        CASE 
            WHEN CumRevenuePct <= 80.0 THEN 'A'
            WHEN CumRevenuePct <= 95.0 THEN 'B'
            ELSE 'C'
        END AS ABC_Tag
    FROM CumulativeABC
),
AllCalendarMonths AS (
    SELECT DISTINCT 
        SalesYear, 
        SalesMonth,
        (SalesYear * 12 + SalesMonth) AS MonthIndex
    FROM dbo.vw_monthly_sales
),
ProductActiveGrid AS (
    -- Pad zeros only from SKU's first active selling month onwards
    SELECT 
        p.StockCode,
        m.SalesYear,
        m.SalesMonth
    FROM RankedABC p
    CROSS JOIN AllCalendarMonths m
    WHERE m.MonthIndex >= p.FirstActiveMonthIndex
),
PaddedSales AS (
    SELECT 
        g.StockCode,
        COALESCE(s.MonthlyQty, 0) AS Qty
    FROM ProductActiveGrid g
    LEFT JOIN dbo.vw_product_monthly_qty s
        ON g.StockCode = s.StockCode 
       AND g.SalesYear = s.SalesYear 
       AND g.SalesMonth = s.SalesMonth
),
XYZ_Stats AS (
    SELECT 
        StockCode,
        COUNT(*) AS MonthsObserved,
        AVG(Qty * 1.0) AS MeanMonthlyQty,
        STDEV(Qty) AS StdevMonthlyQty,
        CASE 
            WHEN AVG(Qty * 1.0) = 0 THEN 999.00
            ELSE ROUND(STDEV(Qty) / AVG(Qty * 1.0), 2)
        END AS CV
    FROM PaddedSales
    GROUP BY StockCode
),
XYZ_Tagged AS (
    SELECT 
        s.StockCode,
        s.MonthsObserved,
        s.MeanMonthlyQty,
        s.CV,
        CASE 
            WHEN s.MonthsObserved < 6 THEN 'N' -- New items with < 6 months observation
            WHEN s.CV < 0.5 THEN 'X'
            WHEN s.CV <= 1.0 THEN 'Y'
            ELSE 'Z'
        END AS XYZ_Tag
    FROM XYZ_Stats s
)
-- Persist master classifications into physical table
SELECT 
    a.StockCode,
    a.Description,
    a.TotalRevenue,
    a.CumRevenuePct,
    a.ABC_Tag,
    x.MonthsObserved,
    x.MeanMonthlyQty,
    x.CV,
    x.XYZ_Tag,
    CONCAT(a.ABC_Tag, x.XYZ_Tag) AS Matrix_Segment
INTO dbo.abc_xyz_results
FROM RankedABC a
JOIN XYZ_Tagged x ON a.StockCode = x.StockCode;
GO

-- ==============================================================================
-- 3. Matrix Summary Output
-- ==============================================================================
SELECT 
    Matrix_Segment,
    COUNT(*) AS SKU_Count,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(10, 2)) AS SKU_Share_Pct,
    CAST(SUM(TotalRevenue) AS DECIMAL(18, 2)) AS Segment_Revenue,
    CAST(SUM(TotalRevenue) * 100.0 / SUM(SUM(TotalRevenue)) OVER () AS DECIMAL(10, 2)) AS Revenue_Share_Pct
FROM dbo.abc_xyz_results
GROUP BY Matrix_Segment
ORDER BY Matrix_Segment;
GO