/* =============================================================================
   Script 05 - previsione di cassa a 13 settimane
   Fonti:
     1. scadenzario clienti aperto  -> data incasso attesa = scadenza + ritardo medio
                                       storico del cliente (ultimi 12 mesi)
     2. scadenzario fornitori aperto -> date dei "pay run" aziendali (10 e fine mese)
     2b. fatture non ancora emesse  -> stesso periodo anno precedente x crescita
     3. uscite ricorrenti           -> stimate dalla media degli ultimi mesi
   I crediti scaduti da oltre 180 giorni NON entrano in previsione (prudenza:
   sono da gestire come posizioni in contenzioso / svalutazione).
   ============================================================================= */
USE TreasuryDW;
GO

CREATE OR ALTER PROCEDURE dw.usp_BuildCashForecast
    @AsOfDate     DATE = NULL,
    @HorizonDays  INT  = 91
AS
BEGIN
    SET NOCOUNT ON;

    IF @AsOfDate IS NULL
        SELECT @AsOfDate = MAX(d.[Date])
        FROM dw.FactBankTransaction f JOIN dw.DimDate d ON d.DateKey = f.DateKey;

    DECLARE @End DATE = DATEADD(DAY, @HorizonDays, @AsOfDate);

    DELETE FROM dw.FactCashForecast WHERE AsOfDate = @AsOfDate;

    /* primo giorno lavorativo >= data (per spostare scadenze che cadono nel weekend) */
    DROP TABLE IF EXISTS #NextWorkDay;
    SELECT d.[Date],
           (SELECT MIN(w.[Date]) FROM dw.DimDate w WHERE w.[Date] >= d.[Date] AND w.IsWorkingDay = 1) AS WorkDate
    INTO #NextWorkDay
    FROM dw.DimDate d
    WHERE d.[Date] BETWEEN @AsOfDate AND DATEADD(DAY, 10, @End);

    /* ---------------------------------------------------------- 1. clienti */
    ;WITH cust_delay AS (
        SELECT CounterpartyKey,
               AVG(CAST(CASE WHEN PaymentDelayDays < 0 THEN 0 ELSE PaymentDelayDays END AS DECIMAL(9,2))) AS AvgDelay
        FROM dw.FactARInvoice
        WHERE PaymentDate IS NOT NULL
          AND PaymentDate > DATEADD(MONTH, -12, @AsOfDate)
        GROUP BY CounterpartyKey
    ),
    overall AS (
        SELECT AVG(CAST(CASE WHEN PaymentDelayDays < 0 THEN 0 ELSE PaymentDelayDays END AS DECIMAL(9,2))) AS AvgDelay
        FROM dw.FactARInvoice
        WHERE PaymentDate IS NOT NULL AND PaymentDate > DATEADD(MONTH, -12, @AsOfDate)
    ),
    exp_ar AS (
        SELECT  a.GrossAmount,
                DATEADD(DAY, CAST(ROUND(ISNULL(dl.AvgDelay, o.AvgDelay), 0) AS INT), a.DueDate) AS ExpDate,
                DATEDIFF(DAY, a.DueDate, @AsOfDate) AS DaysOverdue
        FROM dw.FactARInvoice a
        LEFT JOIN cust_delay dl ON dl.CounterpartyKey = a.CounterpartyKey
        CROSS JOIN overall o
        WHERE a.PaymentDate IS NULL
          AND a.InvoiceDate <= @AsOfDate
    )
    INSERT INTO dw.FactCashForecast (AsOfDate, DateKey, CashCategoryKey, SourceType, Amount)
    SELECT  @AsOfDate,
            CONVERT(INT, CONVERT(CHAR(8), nw.WorkDate, 112)),
            (SELECT CashCategoryKey FROM dw.DimCashCategory WHERE CategoryCode = N'IN01'),
            N'Scadenzario clienti',
            SUM(e.GrossAmount)
    FROM exp_ar e
    CROSS APPLY (SELECT CASE WHEN e.ExpDate <= @AsOfDate THEN DATEADD(DAY, 14, @AsOfDate) ELSE e.ExpDate END AS d) x
    JOIN #NextWorkDay nw ON nw.[Date] = x.d
    WHERE e.DaysOverdue <= 180
      AND x.d <= @End
    GROUP BY nw.WorkDate;

    /* ---------------------------------------------------------- 2. fornitori */
    ;WITH exp_ap AS (
        SELECT  ap.GrossAmount, ap.PurchaseType,
                CASE WHEN ap.DueDate <= @AsOfDate THEN DATEADD(DAY, 5, @AsOfDate)
                     WHEN DAY(ap.DueDate) <= 10   THEN DATEFROMPARTS(YEAR(ap.DueDate), MONTH(ap.DueDate), 10)
                     ELSE EOMONTH(ap.DueDate) END AS PayDate
        FROM dw.FactAPInvoice ap
        WHERE ap.PaymentDate IS NULL
          AND ap.InvoiceDate <= @AsOfDate
    )
    INSERT INTO dw.FactCashForecast (AsOfDate, DateKey, CashCategoryKey, SourceType, Amount)
    SELECT  @AsOfDate,
            CONVERT(INT, CONVERT(CHAR(8), nw.WorkDate, 112)),
            c.CashCategoryKey,
            N'Scadenzario fornitori',
            -SUM(e.GrossAmount)
    FROM exp_ap e
    JOIN #NextWorkDay nw ON nw.[Date] = e.PayDate
    JOIN dw.DimCashCategory c ON c.CategoryCode = CASE WHEN e.PurchaseType = N'Merce' THEN N'OU01' ELSE N'OU02' END
    WHERE e.PayDate <= @End
    GROUP BY nw.WorkDate, c.CashCategoryKey;

    /* ---------------------------------------------------------- 2b. fatture non ancora emesse
       Gli scadenzari contengono solo fatture gia' emesse: senza una stima delle vendite
       e degli acquisti dei prossimi tre mesi la previsione sottostima soprattutto gli
       incassi a breve (rimesse dirette, bonifici a 30 gg). Uso lo stesso periodo
       dell'anno precedente: fatture emesse E pagate dentro la finestra, spostate di un
       anno e moltiplicate per la crescita degli ultimi 12 mesi. */
    DECLARE @LY0 DATE = DATEADD(YEAR, -1, @AsOfDate),
            @LY1 DATE = DATEADD(YEAR, -1, @End);

    DECLARE @GrowthAR DECIMAL(9,4) =
        ISNULL((SELECT SUM(GrossAmount) FROM dw.FactARInvoice WHERE InvoiceDate >  @LY0 AND InvoiceDate <= @AsOfDate)
             / NULLIF((SELECT SUM(GrossAmount) FROM dw.FactARInvoice
                       WHERE InvoiceDate > DATEADD(YEAR, -2, @AsOfDate) AND InvoiceDate <= @LY0), 0), 1);
    DECLARE @GrowthAP DECIMAL(9,4) =
        ISNULL((SELECT SUM(GrossAmount) FROM dw.FactAPInvoice WHERE InvoiceDate >  @LY0 AND InvoiceDate <= @AsOfDate)
             / NULLIF((SELECT SUM(GrossAmount) FROM dw.FactAPInvoice
                       WHERE InvoiceDate > DATEADD(YEAR, -2, @AsOfDate) AND InvoiceDate <= @LY0), 0), 1);

    INSERT INTO dw.FactCashForecast (AsOfDate, DateKey, CashCategoryKey, SourceType, Amount)
    SELECT  @AsOfDate,
            CONVERT(INT, CONVERT(CHAR(8), nw.WorkDate, 112)),
            (SELECT CashCategoryKey FROM dw.DimCashCategory WHERE CategoryCode = N'IN01'),
            N'Stima nuove vendite',
            SUM(a.GrossAmount) * @GrowthAR
    FROM dw.FactARInvoice a
    JOIN #NextWorkDay nw ON nw.[Date] = DATEADD(YEAR, 1, a.PaymentDate)
    WHERE a.InvoiceDate > @LY0 AND a.InvoiceDate <= @LY1
      AND a.PaymentDate <= @LY1
    GROUP BY nw.WorkDate;

    INSERT INTO dw.FactCashForecast (AsOfDate, DateKey, CashCategoryKey, SourceType, Amount)
    SELECT  @AsOfDate,
            CONVERT(INT, CONVERT(CHAR(8), nw.WorkDate, 112)),
            c.CashCategoryKey,
            N'Stima nuovi acquisti',
            -SUM(p.GrossAmount) * @GrowthAP
    FROM dw.FactAPInvoice p
    JOIN #NextWorkDay nw ON nw.[Date] = DATEADD(YEAR, 1, p.PaymentDate)
    JOIN dw.DimCashCategory c ON c.CategoryCode = CASE WHEN p.PurchaseType = N'Merce' THEN N'OU01' ELSE N'OU02' END
    WHERE p.InvoiceDate > @LY0 AND p.InvoiceDate <= @LY1
      AND p.PaymentDate <= @LY1
    GROUP BY nw.WorkDate, c.CashCategoryKey;

    /* ---------------------------------------------------------- 3. ricorrenti
       importi ricalcolati a ogni esecuzione dallo storico recente */
    DELETE FROM dw.RecurringCashItem;

    ;WITH hist AS (
        SELECT c.CategoryCode, d.[Date], d.YearMonth, f.Amount
        FROM dw.FactBankTransaction f
        JOIN dw.DimCashCategory c ON c.CashCategoryKey = f.CashCategoryKey
        JOIN dw.DimDate d         ON d.DateKey = f.DateKey
        WHERE d.[Date] > DATEADD(MONTH, -6, @AsOfDate)
    ),
    monthly AS (
        SELECT CategoryCode, YearMonth, SUM(Amount) AS Amount
        FROM hist
        GROUP BY CategoryCode, YearMonth
    )
    INSERT INTO dw.RecurringCashItem (CategoryCode, Description, DayOfMonth, MonthsList, Amount)
    SELECT N'OU03', N'Stipendi netti (media ultimi mesi esclusa 13esima)', 27, '1,2,3,4,5,6,7,8,9,10,11,12',
           (SELECT AVG(Amount) FROM monthly WHERE CategoryCode = N'OU03' AND YearMonth % 100 NOT IN (7, 12))
    UNION ALL
    SELECT N'OU04', N'F24 contributi e ritenute', 16, '1,2,3,4,5,6,7,8,9,10,11,12',
           (SELECT AVG(Amount) FROM monthly WHERE CategoryCode = N'OU04' AND YearMonth % 100 NOT IN (1, 8))
    UNION ALL
    SELECT N'OU05', N'F24 IVA mensile', 16, '1,2,3,4,5,6,7,8,9,10,11,12',
           (SELECT AVG(Amount) FROM hist WHERE CategoryCode = N'OU05' AND DAY([Date]) BETWEEN 15 AND 18)
    UNION ALL
    SELECT N'OU07', N'Canoni di locazione trimestrali', 5, '1,4,7,10',
           (SELECT SUM(Amount) FROM hist WHERE CategoryCode = N'OU07'
             AND [Date] >= (SELECT DATEADD(DAY, -10, MAX([Date])) FROM hist WHERE CategoryCode = N'OU07'))
    UNION ALL
    SELECT N'OU08', N'Utenze (bimestrali)', 20, '2,4,6,8,10,12',
           (SELECT AVG(Amount) FROM monthly WHERE CategoryCode = N'OU08')
    UNION ALL
    SELECT N'FI04', N'Canoni leasing', 1, '1,2,3,4,5,6,7,8,9,10,11,12',
           (SELECT AVG(Amount) FROM monthly WHERE CategoryCode = N'FI04')
    UNION ALL
    SELECT N'OU09', N'Competenze e spese bancarie', 31, '3,6,9,12',
           (SELECT SUM(Amount) FROM hist WHERE CategoryCode IN (N'OU09') AND MONTH([Date]) = MONTH(@AsOfDate)
             AND [Date] >= DATEADD(DAY, -3, EOMONTH(@AsOfDate)))
    UNION ALL
    SELECT N'FI03', N'Interessi passivi c/c', 31, '3,6,9,12',
           (SELECT SUM(Amount) FROM hist WHERE CategoryCode = N'FI03' AND Description LIKE N'%c/c%'
             AND [Date] >= DATEADD(DAY, -3, EOMONTH(@AsOfDate)))
    UNION ALL
    SELECT N'FI02', N'Finanziamento UniCredit - quota capitale', 30, '3,6,9,12',
           (SELECT SUM(Amount) FROM hist WHERE CategoryCode = N'FI02' AND Description LIKE N'%UniCredit%'
             AND [Date] >= DATEADD(DAY, -95, @AsOfDate) AND [Date] < DATEADD(DAY, -85, @AsOfDate))
    UNION ALL
    SELECT N'FI03', N'Finanziamento UniCredit - quota interessi', 30, '3,6,9,12',
           (SELECT SUM(Amount) FROM hist WHERE CategoryCode = N'FI03' AND Description LIKE N'%UniCredit%'
             AND [Date] >= DATEADD(DAY, -95, @AsOfDate) AND [Date] < DATEADD(DAY, -85, @AsOfDate));

    ;WITH days AS (
        SELECT d.[Date], d.[Month], DAY(d.[Date]) AS DayNum, DAY(EOMONTH(d.[Date])) AS LastDay
        FROM dw.DimDate d
        WHERE d.[Date] > @AsOfDate AND d.[Date] <= @End
    )
    INSERT INTO dw.FactCashForecast (AsOfDate, DateKey, CashCategoryKey, SourceType, Amount)
    SELECT  @AsOfDate,
            CONVERT(INT, CONVERT(CHAR(8), nw.WorkDate, 112)),
            c.CashCategoryKey,
            N'Ricorrente',
            r.Amount
    FROM dw.RecurringCashItem r
    JOIN dw.DimCashCategory c ON c.CategoryCode = r.CategoryCode
    JOIN days dd ON dd.DayNum = CASE WHEN r.DayOfMonth > dd.LastDay THEN dd.LastDay ELSE r.DayOfMonth END
                AND dd.[Month] IN (SELECT TRY_CONVERT(INT, value) FROM STRING_SPLIT(r.MonthsList, ','))
    JOIN #NextWorkDay nw ON nw.[Date] = dd.[Date]
    WHERE r.Amount IS NOT NULL;

    /* riepilogo settimanale con saldo progressivo (stesso calcolo della pagina Forecast) */
    DECLARE @Opening DECIMAL(18,2) =
        (SELECT SUM(b.ClosingBalance) FROM dw.FactBankBalanceDaily b
         JOIN dw.DimDate d ON d.DateKey = b.DateKey WHERE d.[Date] = @AsOfDate);

    SELECT  DATEADD(DAY, 1 - d.DayOfWeek, d.[Date])                     AS WeekStart,
            SUM(CASE WHEN f.Amount > 0 THEN f.Amount ELSE 0 END)        AS Inflows,
            SUM(CASE WHEN f.Amount < 0 THEN f.Amount ELSE 0 END)        AS Outflows,
            SUM(f.Amount)                                               AS NetFlow,
            @Opening + SUM(SUM(f.Amount)) OVER (ORDER BY DATEADD(DAY, 1 - d.DayOfWeek, d.[Date])
                                                ROWS UNBOUNDED PRECEDING) AS ProjectedClosingCash
    FROM dw.FactCashForecast f
    JOIN dw.DimDate d ON d.DateKey = f.DateKey
    WHERE f.AsOfDate = @AsOfDate
    GROUP BY DATEADD(DAY, 1 - d.DayOfWeek, d.[Date])
    ORDER BY WeekStart;
END;
GO

EXEC dw.usp_BuildCashForecast;
GO
