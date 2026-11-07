/********************************************************************************
Project:     UK Online Retail Audit (2009-2011)
Script:      04_cancellation_and_returns_analysis.sql
Author:      Warren Fan
Description: In-depth cancellation and return root cause analysis:
             1. Overall business return rate benchmark.
             2. Returns by ABC product tier (linking Q3 and Q4).
             3. Product-level hotspots (Top 5 SKUs by lost value).
             4. Customer-level hotspots (Top 5 customers, excluding GUEST_USER).
             5. Geographic concentration of return losses by country.
********************************************************************************/

USE RetailAudit;
GO

-- ==============================================================================
-- 1. Overall Business Cancellation Benchmark (Q1 & Q4 Core Totals)
-- ==============================================================================
SELECT 
    CAST(SUM(CASE WHEN IsCancelled = 0 THEN LineTotal ELSE 0 END) AS DECIMAL(18, 2)) AS Overall_Gross_Revenue,
    CAST(SUM(CASE WHEN IsCancelled = 1 THEN ABS(LineTotal) ELSE 0 END) AS DECIMAL(18, 2)) AS Overall_Cancelled_Value,
    CAST(SUM(LineTotal) AS DECIMAL(18, 2)) AS Overall_Net_Revenue,
    ROUND(
        SUM(CASE WHEN IsCancelled = 1 THEN ABS(LineTotal) ELSE 0 END) * 100.0 
        / NULLIF(SUM(CASE WHEN IsCancelled = 0 THEN LineTotal ELSE 0 END), 0), 
        2
    ) AS Overall_Return_Rate_Pct
FROM dbo.vw_clean_retail;
GO

-- ==============================================================================
-- 2. Returns Breakdown by ABC Product Tier (Linking Q3 & Q4)
-- ==============================================================================
WITH ProductReturns AS (
    SELECT 
        StockCode,
        SUM(CASE WHEN IsCancelled = 0 THEN LineTotal ELSE 0 END) AS GrossRevenue,
        SUM(CASE WHEN IsCancelled = 1 THEN ABS(LineTotal) ELSE 0 END) AS CancelledValue
    FROM dbo.vw_clean_retail
    WHERE InvoiceDate < '2011-12-01'
    GROUP BY StockCode
)
SELECT 
    m.ABC_Tag,
    COUNT(DISTINCT m.StockCode) AS SKU_Count,
    CAST(SUM(r.GrossRevenue) AS DECIMAL(18, 2)) AS GrossRevenue,
    CAST(SUM(r.CancelledValue) AS DECIMAL(18, 2)) AS CancelledValue,
    ROUND(
        SUM(r.CancelledValue) * 100.0 / NULLIF(SUM(r.GrossRevenue), 0), 
        2
    ) AS ReturnRate_Pct,
    ROUND(
        SUM(r.CancelledValue) * 100.0 / SUM(SUM(r.CancelledValue)) OVER (), 
        2
    ) AS Pct_of_Total_Loss
FROM dbo.abc_xyz_results m
JOIN ProductReturns r ON m.StockCode = r.StockCode
GROUP BY m.ABC_Tag
ORDER BY m.ABC_Tag;
GO

-- ==============================================================================
-- 3. Product-Level Cancellation Hotspots (Top 5 SKUs by Lost Value)
-- ==============================================================================
SELECT TOP 5 
    StockCode,
    MAX(Description) AS Description,
    CAST(SUM(CASE WHEN IsCancelled = 0 THEN LineTotal ELSE 0 END) AS DECIMAL(18, 2)) AS GrossRevenue,
    CAST(SUM(CASE WHEN IsCancelled = 1 THEN ABS(LineTotal) ELSE 0 END) AS DECIMAL(18, 2)) AS CancelledValue,
    CAST(SUM(LineTotal) AS DECIMAL(18, 2)) AS NetRevenue,
    ROUND(
        SUM(CASE WHEN IsCancelled = 1 THEN ABS(LineTotal) ELSE 0 END) 
        / NULLIF(SUM(CASE WHEN IsCancelled = 0 THEN LineTotal ELSE 0 END), 0) * 100.0, 
        2
    ) AS ReturnRate_Pct
FROM dbo.vw_clean_retail
GROUP BY StockCode
ORDER BY SUM(CASE WHEN IsCancelled = 1 THEN ABS(LineTotal) ELSE 0 END) DESC;
GO

-- ==============================================================================
-- 4. Customer-Level Cancellation Hotspots (Top 5 Customers, Excluding GUEST_USER)
-- ==============================================================================
SELECT TOP 5 
    CustomerID,
    CAST(SUM(CASE WHEN IsCancelled = 0 THEN LineTotal ELSE 0 END) AS DECIMAL(18, 2)) AS GrossPurchases,
    CAST(SUM(CASE WHEN IsCancelled = 1 THEN ABS(LineTotal) ELSE 0 END) AS DECIMAL(18, 2)) AS CancelledValue,
    CAST(SUM(LineTotal) AS DECIMAL(18, 2)) AS NetPurchases,
    ROUND(
        SUM(CASE WHEN IsCancelled = 1 THEN ABS(LineTotal) ELSE 0 END) 
        / NULLIF(SUM(CASE WHEN IsCancelled = 0 THEN LineTotal ELSE 0 END), 0) * 100.0, 
        2
    ) AS ReturnRate_Pct
FROM dbo.vw_clean_retail
WHERE CustomerID <> 'GUEST_USER'
GROUP BY CustomerID
ORDER BY SUM(CASE WHEN IsCancelled = 1 THEN ABS(LineTotal) ELSE 0 END) DESC;
GO

-- ==============================================================================
-- 5. Geographic Concentration of Returns by Country (Top 5)
-- ==============================================================================
SELECT TOP 5 
    Country,
    CAST(SUM(CASE WHEN IsCancelled = 0 THEN LineTotal ELSE 0 END) AS DECIMAL(18, 2)) AS GrossRevenue,
    CAST(SUM(CASE WHEN IsCancelled = 1 THEN ABS(LineTotal) ELSE 0 END) AS DECIMAL(18, 2)) AS CancelledValue,
    ROUND(
        SUM(CASE WHEN IsCancelled = 1 THEN ABS(LineTotal) ELSE 0 END) 
        / NULLIF(SUM(CASE WHEN IsCancelled = 0 THEN LineTotal ELSE 0 END), 0) * 100.0, 
        2
    ) AS Country_ReturnRate_Pct,
    ROUND(
        SUM(CASE WHEN IsCancelled = 1 THEN ABS(LineTotal) ELSE 0 END) * 100.0 
        / SUM(SUM(CASE WHEN IsCancelled = 1 THEN ABS(LineTotal) ELSE 0 END)) OVER (), 
        2
    ) AS Pct_of_Total_Cancellations
FROM dbo.vw_clean_retail
GROUP BY Country
ORDER BY SUM(CASE WHEN IsCancelled = 1 THEN ABS(LineTotal) ELSE 0 END) DESC;
GO