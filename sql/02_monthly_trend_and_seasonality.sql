/********************************************************************************
Project:     UK Online Retail Audit (2009-2011)
Script:      02_monthly_trend_and_seasonality.sql
Author:      Warren Fan
Description: Analyzes monthly revenue trends, MoM/YoY growth rates, Q4 seasonal
             concentration, peak-to-trough ratios, and like-for-like YoY growth.
             Creates vw_monthly_sales for downstream reporting in Power BI.
********************************************************************************/

USE RetailAudit;
GO

-- ==============================================================================
-- 1. Create Production Monthly Sales View (for Power BI & Reporting)
-- ==============================================================================
CREATE OR ALTER VIEW dbo.vw_monthly_sales AS
SELECT 
    DATEFROMPARTS(YEAR(InvoiceDate), MONTH(InvoiceDate), 1) AS MonthStart,
    YEAR(InvoiceDate)                                      AS SalesYear,
    MONTH(InvoiceDate)                                     AS SalesMonth,
    SUM(LineTotal)                                         AS NetRevenue,
    COUNT(DISTINCT Invoice)                                AS OrderCount,
    COUNT(*)                                               AS LineItemCount,
    CAST(SUM(LineTotal) / NULLIF(COUNT(DISTINCT Invoice), 0) AS DECIMAL(18, 2)) AS AvgOrderValue
FROM dbo.vw_clean_retail
WHERE InvoiceDate < '2011-12-01' -- Exclude partial month December 2011
GROUP BY YEAR(InvoiceDate), MONTH(InvoiceDate);
GO

-- ==============================================================================
-- 2. Monthly Trend with MoM and YoY Growth Rates
-- ==============================================================================
SELECT 
    MonthStart,
    SalesYear,
    SalesMonth,
    NetRevenue,
    OrderCount,
    LineItemCount,
    AvgOrderValue,
    
    -- Prior Month & MoM Growth (%)
    LAG(NetRevenue, 1) OVER (ORDER BY MonthStart) AS PrevMonthRevenue,
    ROUND(
        (NetRevenue - LAG(NetRevenue, 1) OVER (ORDER BY MonthStart)) 
        / NULLIF(LAG(NetRevenue, 1) OVER (ORDER BY MonthStart), 0) * 100.0, 
        2
    ) AS MoM_Growth_Pct,
    
    -- Same Month Last Year & YoY Growth (%)
    LAG(NetRevenue, 12) OVER (ORDER BY MonthStart) AS PrevYearRevenue,
    ROUND(
        (NetRevenue - LAG(NetRevenue, 12) OVER (ORDER BY MonthStart)) 
        / NULLIF(LAG(NetRevenue, 12) OVER (ORDER BY MonthStart), 0) * 100.0, 
        2
    ) AS YoY_Growth_Pct
FROM dbo.vw_monthly_sales
ORDER BY MonthStart;
GO

-- ==============================================================================
-- 3. Seasonality Depth: 2010 Q4 Concentration & Peak-to-Trough Ratio
-- ==============================================================================
SELECT 
    SUM(NetRevenue) AS FullYear_2010_Revenue,
    SUM(CASE WHEN SalesMonth IN (10, 11, 12) THEN NetRevenue ELSE 0 END) AS Q4_Revenue,
    ROUND(
        SUM(CASE WHEN SalesMonth IN (10, 11, 12) THEN NetRevenue ELSE 0 END) 
        * 100.0 / NULLIF(SUM(NetRevenue), 0), 
        2
    ) AS Q4_Share_Pct,
    MAX(NetRevenue) AS Peak_Month_Revenue,
    MIN(NetRevenue) AS Trough_Month_Revenue,
    ROUND(MAX(NetRevenue) / NULLIF(MIN(NetRevenue), 0), 2) AS Peak_to_Trough_Ratio
FROM dbo.vw_monthly_sales
WHERE SalesYear = 2010;
GO

-- ==============================================================================
-- 4. Like-for-Like Annual Growth: 2010 vs 2011 (Jan - Nov YTD Comparison)
-- ==============================================================================
WITH YTD_Sales AS (
    SELECT 
        SalesYear,
        SUM(OrderCount)     AS TotalOrders,
        SUM(LineItemCount)  AS TotalItems,
        SUM(NetRevenue)     AS Jan_to_Nov_NetRevenue
    FROM dbo.vw_monthly_sales
    WHERE SalesMonth BETWEEN 1 AND 11
      AND SalesYear IN (2010, 2011)
    GROUP BY SalesYear
)
SELECT 
    SalesYear,
    TotalOrders,
    TotalItems,
    Jan_to_Nov_NetRevenue,
    ROUND(
        (Jan_to_Nov_NetRevenue - LAG(Jan_to_Nov_NetRevenue) OVER (ORDER BY SalesYear)) 
        * 100.0 / NULLIF(LAG(Jan_to_Nov_NetRevenue) OVER (ORDER BY SalesYear), 0), 
        2
    ) AS YTD_YoY_Growth_Pct
FROM YTD_Sales;
GO