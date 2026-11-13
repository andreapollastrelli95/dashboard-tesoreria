/* =============================================================================
   Script 06 - viste di reporting lette da Power BI
   ============================================================================= */
USE TreasuryDW;
GO

CREATE OR ALTER VIEW rpt.Calendar AS
SELECT DateKey, [Date], [Year], [Quarter], QuarterLabel, [Month], MonthName, MonthShort, YearMonth,
       YearMonthLabel, WeekOfYear, DayOfWeek, DayName, IsWorkingDay,
       DATEADD(DAY, 1 - DayOfWeek, [Date]) AS WeekStart      -- lunedi' della settimana
FROM dw.DimDate
WHERE [Date] BETWEEN '2023-07-01' AND '2026-06-30';           -- storico scadenzari + orizzonte previsione
GO

CREATE OR ALTER VIEW rpt.Site AS
SELECT SiteKey, SiteCode, SiteName, Area, Headcount FROM dw.DimSite;
GO

CREATE OR ALTER VIEW rpt.BankAccount AS
SELECT b.BankAccountKey, b.BankAccountCode, b.AccountName, b.BankName, b.AccountType, b.CreditLine,
       s.SiteName AS AccountSite
FROM dw.DimBankAccount b
JOIN dw.DimSite s ON s.SiteKey = b.SiteKey;
GO

CREATE OR ALTER VIEW rpt.Counterparty AS
SELECT CounterpartyKey, CounterpartyCode, CounterpartyName, CounterpartyType, HomeSiteCode,
       PaymentTerms, PaymentMethod, CustomerSegment
FROM dw.DimCounterparty;
GO

CREATE OR ALTER VIEW rpt.CashCategory AS
SELECT CashCategoryKey, CategoryCode, CategoryName, CashFlowSection, SectionSort, Direction, CategoryGroup
FROM dw.DimCashCategory;
GO

CREATE OR ALTER VIEW rpt.FactBankTransaction AS
SELECT TransactionID, DateKey, BankAccountKey, SiteKey, CashCategoryKey, CounterpartyKey,
       Amount, InflowAmount, OutflowAmount, Description, DocumentReference
FROM dw.FactBankTransaction;
GO

CREATE OR ALTER VIEW rpt.FactBankBalanceDaily AS
SELECT DateKey, BankAccountKey, ClosingBalance, CreditLine, AvailableFunds
FROM dw.FactBankBalanceDaily;
GO

CREATE OR ALTER VIEW rpt.FactARInvoice AS
SELECT ARInvoiceKey, InvoiceNumber, InvoiceDateKey, SiteKey, CounterpartyKey, InvoiceDate, DueDate,
       PaymentDate, NetAmount, GrossAmount, AmountPaid, IsBounced, PaymentDelayDays
FROM dw.FactARInvoice;
GO

CREATE OR ALTER VIEW rpt.FactAPInvoice AS
SELECT APInvoiceKey, InvoiceNumber, InvoiceDateKey, SiteKey, CounterpartyKey, PurchaseType, InvoiceDate,
       DueDate, PaymentDate, NetAmount, GrossAmount, AmountPaid
FROM dw.FactAPInvoice;
GO

CREATE OR ALTER VIEW rpt.FactCashForecast AS
SELECT f.AsOfDate, f.DateKey, f.CashCategoryKey, f.SourceType, f.Amount
FROM dw.FactCashForecast f
WHERE f.AsOfDate = (SELECT MAX(AsOfDate) FROM dw.FactCashForecast);   -- solo l'ultima previsione
GO

CREATE OR ALTER VIEW rpt.TreasuryParameter AS
SELECT ParameterName, ParameterValue FROM dw.TreasuryParameter;
GO

/* rendiconto finanziario mensile per sezione (vista di controllo / export) */
CREATE OR ALTER VIEW rpt.vw_CashFlowMonthly AS
SELECT  d.[Year], d.[Month], d.YearMonth,
        SUM(CASE WHEN c.CashFlowSection = N'Operativa'     THEN f.Amount ELSE 0 END) AS OperatingCashFlow,
        SUM(CASE WHEN c.CashFlowSection = N'Investimento'  THEN f.Amount ELSE 0 END) AS InvestingCashFlow,
        SUM(CASE WHEN c.CashFlowSection = N'Finanziamento' THEN f.Amount ELSE 0 END) AS FinancingCashFlow,
        SUM(CASE WHEN c.CashFlowSection <> N'Giroconto'    THEN f.Amount ELSE 0 END) AS NetCashFlow
FROM dw.FactBankTransaction f
JOIN dw.DimCashCategory c ON c.CashCategoryKey = f.CashCategoryKey
JOIN dw.DimDate d         ON d.DateKey = f.DateKey
GROUP BY d.[Year], d.[Month], d.YearMonth;
GO
