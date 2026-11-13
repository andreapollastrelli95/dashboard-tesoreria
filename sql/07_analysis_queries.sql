/* =============================================================================
   Script 07 - query di analisi per la tesoreria
   ============================================================================= */
USE TreasuryDW;
GO

DECLARE @AsOf DATE = '2025-12-31';

/* 1. Rendiconto finanziario mensile con saldo di apertura e chiusura */
WITH cf AS (
    SELECT YearMonth, OperatingCashFlow, InvestingCashFlow, FinancingCashFlow, NetCashFlow
    FROM rpt.vw_CashFlowMonthly
),
bal AS (
    SELECT d.YearMonth, SUM(b.ClosingBalance) AS ClosingCash
    FROM dw.FactBankBalanceDaily b
    JOIN dw.DimDate d ON d.DateKey = b.DateKey
    WHERE d.[Date] = d.MonthEndDate
    GROUP BY d.YearMonth
)
SELECT  cf.YearMonth,
        LAG(bal.ClosingCash) OVER (ORDER BY cf.YearMonth) AS OpeningCash,
        cf.OperatingCashFlow, cf.InvestingCashFlow, cf.FinancingCashFlow, cf.NetCashFlow,
        bal.ClosingCash
FROM cf
JOIN bal ON bal.YearMonth = cf.YearMonth
ORDER BY cf.YearMonth;

/* 2. Posizione di cassa giornaliera di gruppo: minimo, massimo e media per mese */
SELECT  d.YearMonth,
        MIN(x.GroupCash) AS MinCash, MAX(x.GroupCash) AS MaxCash, AVG(x.GroupCash) AS AvgCash
FROM (
    SELECT DateKey, SUM(ClosingBalance) AS GroupCash
    FROM dw.FactBankBalanceDaily
    GROUP BY DateKey
) x
JOIN dw.DimDate d ON d.DateKey = x.DateKey
WHERE d.[Year] >= 2024
GROUP BY d.YearMonth
ORDER BY d.YearMonth;

/* 3. Scadenziario clienti alla data: aging per sede */
SELECT  s.SiteName,
        SUM(CASE WHEN a.DueDate >= @AsOf THEN a.GrossAmount ELSE 0 END)                                          AS NotDue,
        SUM(CASE WHEN DATEDIFF(DAY, a.DueDate, @AsOf) BETWEEN 1  AND 30  THEN a.GrossAmount ELSE 0 END)           AS Overdue_1_30,
        SUM(CASE WHEN DATEDIFF(DAY, a.DueDate, @AsOf) BETWEEN 31 AND 60  THEN a.GrossAmount ELSE 0 END)           AS Overdue_31_60,
        SUM(CASE WHEN DATEDIFF(DAY, a.DueDate, @AsOf) BETWEEN 61 AND 90  THEN a.GrossAmount ELSE 0 END)           AS Overdue_61_90,
        SUM(CASE WHEN DATEDIFF(DAY, a.DueDate, @AsOf) > 90               THEN a.GrossAmount ELSE 0 END)           AS Overdue_90plus,
        SUM(a.GrossAmount)                                                                                         AS TotalOpen,
        CAST(SUM(CASE WHEN a.DueDate < @AsOf THEN a.GrossAmount ELSE 0 END) * 100.0 / SUM(a.GrossAmount) AS DECIMAL(5,1)) AS OverduePct
FROM dw.FactARInvoice a
JOIN dw.DimSite s ON s.SiteKey = a.SiteKey
WHERE a.InvoiceDate <= @AsOf AND (a.PaymentDate IS NULL OR a.PaymentDate > @AsOf)
GROUP BY s.SiteName
ORDER BY TotalOpen DESC;

/* 4. DSO e DPO a fine mese (metodo semplice: saldo aperto / fatturato 90 gg x 90) */
WITH me AS (
    SELECT DISTINCT MonthEndDate AS D FROM dw.DimDate WHERE [Date] BETWEEN '2024-01-01' AND @AsOf
)
SELECT  me.D AS MonthEnd,
        ar.OpenAR, ar.Sales90,
        CAST(ar.OpenAR / NULLIF(ar.Sales90, 0) * 90 AS DECIMAL(6,1))     AS DSO,
        ap.OpenAP, ap.Purch90,
        CAST(ap.OpenAP / NULLIF(ap.Purch90, 0) * 90 AS DECIMAL(6,1))     AS DPO
FROM me
CROSS APPLY (
    SELECT SUM(CASE WHEN a.PaymentDate IS NULL OR a.PaymentDate > me.D THEN a.GrossAmount ELSE 0 END) AS OpenAR,
           SUM(CASE WHEN a.InvoiceDate > DATEADD(DAY, -90, me.D) THEN a.GrossAmount ELSE 0 END)     AS Sales90
    FROM dw.FactARInvoice a
    WHERE a.InvoiceDate <= me.D
) ar
CROSS APPLY (
    SELECT SUM(CASE WHEN p.PaymentDate IS NULL OR p.PaymentDate > me.D THEN p.GrossAmount ELSE 0 END) AS OpenAP,
           SUM(CASE WHEN p.InvoiceDate > DATEADD(DAY, -90, me.D) THEN p.GrossAmount ELSE 0 END)     AS Purch90
    FROM dw.FactAPInvoice p
    WHERE p.InvoiceDate <= me.D
) ap
ORDER BY me.D;

/* 5. Top 15 clienti per scaduto, con ritardo medio storico e insoluti */
SELECT TOP (15)
        cp.CounterpartyName, s.SiteName, cp.PaymentTerms,
        SUM(CASE WHEN a.PaymentDate IS NULL AND a.DueDate < @AsOf THEN a.GrossAmount ELSE 0 END) AS Overdue,
        MAX(CASE WHEN a.PaymentDate IS NULL AND a.DueDate < @AsOf THEN DATEDIFF(DAY, a.DueDate, @AsOf) END) AS OldestOverdueDays,
        AVG(CASE WHEN a.PaymentDate IS NOT NULL THEN CAST(a.PaymentDelayDays AS DECIMAL(9,1)) END)      AS AvgDelayDays,
        SUM(CAST(a.IsBounced AS INT))                                                                   AS BouncedRiBa
FROM dw.FactARInvoice a
JOIN dw.DimCounterparty cp ON cp.CounterpartyKey = a.CounterpartyKey
JOIN dw.DimSite s          ON s.SiteKey = a.SiteKey
GROUP BY cp.CounterpartyName, s.SiteName, cp.PaymentTerms
HAVING SUM(CASE WHEN a.PaymentDate IS NULL AND a.DueDate < @AsOf THEN a.GrossAmount ELSE 0 END) > 0
ORDER BY Overdue DESC;

/* 6. Utilizzo degli affidamenti: picco e media per conto, ultimi 12 mesi */
SELECT  b.AccountName, b.CreditLine,
        MIN(f.ClosingBalance)                                                              AS MinBalance,
        CAST(MAX(CASE WHEN f.ClosingBalance < 0 THEN -f.ClosingBalance ELSE 0 END) * 100.0
             / NULLIF(b.CreditLine, 0) AS DECIMAL(5,1))                                     AS PeakUsagePct,
        SUM(CASE WHEN f.ClosingBalance < 0 THEN 1 ELSE 0 END)                             AS DaysInOverdraft
FROM dw.FactBankBalanceDaily f
JOIN dw.DimBankAccount b ON b.BankAccountKey = f.BankAccountKey
JOIN dw.DimDate d        ON d.DateKey = f.DateKey
WHERE d.[Date] > DATEADD(MONTH, -12, @AsOf)
GROUP BY b.AccountName, b.CreditLine
ORDER BY PeakUsagePct DESC;

/* 7. Incidenza insoluti RiBa per sede e anno */
SELECT  s.SiteName, YEAR(a.InvoiceDate) AS [Year],
        COUNT(*) AS RiBaInvoices,
        SUM(CAST(a.IsBounced AS INT)) AS Bounced,
        CAST(SUM(CAST(a.IsBounced AS INT)) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS BouncedPct
FROM dw.FactARInvoice a
JOIN dw.DimSite s          ON s.SiteKey = a.SiteKey
JOIN dw.DimCounterparty cp ON cp.CounterpartyKey = a.CounterpartyKey
WHERE cp.PaymentMethod = N'RiBa' AND YEAR(a.InvoiceDate) >= 2024
GROUP BY s.SiteName, YEAR(a.InvoiceDate)
ORDER BY s.SiteName, [Year];

/* 8. Giorni di autonomia: cassa disponibile / uscite operative medie giornaliere (ultimi 90 gg) */
SELECT  CAST(
          (SELECT SUM(ClosingBalance) FROM dw.FactBankBalanceDaily b JOIN dw.DimDate d ON d.DateKey = b.DateKey WHERE d.[Date] = @AsOf)
        / ( (SELECT SUM(f.OutflowAmount) FROM dw.FactBankTransaction f
              JOIN dw.DimCashCategory c ON c.CashCategoryKey = f.CashCategoryKey
              JOIN dw.DimDate d ON d.DateKey = f.DateKey
             WHERE c.CashFlowSection = N'Operativa' AND d.[Date] > DATEADD(DAY, -90, @AsOf)) / 90.0 )
        AS DECIMAL(6,1)) AS LiquidityDays;
GO
