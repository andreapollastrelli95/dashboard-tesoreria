/* =============================================================================
   Script 04 - caricamento DW (stg -> dw) e snapshot saldi giornalieri
   ============================================================================= */
USE TreasuryDW;
GO

CREATE OR ALTER PROCEDURE dw.usp_LoadTreasury
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        TRUNCATE TABLE dw.FactBankTransaction;
        DELETE FROM dw.FactCashForecast;
        DELETE FROM dw.FactBankBalanceDaily;
        DELETE FROM dw.FactARInvoice;      DBCC CHECKIDENT ('dw.FactARInvoice', RESEED, 0) WITH NO_INFOMSGS;
        DELETE FROM dw.FactAPInvoice;      DBCC CHECKIDENT ('dw.FactAPInvoice', RESEED, 0) WITH NO_INFOMSGS;
        DELETE FROM dw.DimBankAccount;     DBCC CHECKIDENT ('dw.DimBankAccount', RESEED, 0) WITH NO_INFOMSGS;
        DELETE FROM dw.DimCounterparty;    DBCC CHECKIDENT ('dw.DimCounterparty', RESEED, 0) WITH NO_INFOMSGS;
        DELETE FROM dw.DimCashCategory;    DBCC CHECKIDENT ('dw.DimCashCategory', RESEED, 0) WITH NO_INFOMSGS;
        DELETE FROM dw.DimSite;            DBCC CHECKIDENT ('dw.DimSite', RESEED, 0) WITH NO_INFOMSGS;

        /* ---------------- dimensioni ---------------- */
        INSERT INTO dw.DimSite (SiteCode, SiteName, Area, Headcount)
        SELECT SiteCode, SiteName, Area, TRY_CONVERT(SMALLINT, Headcount) FROM stg.Sites;

        INSERT INTO dw.DimBankAccount (BankAccountCode, AccountName, BankName, AccountType, SiteKey, CreditLine)
        SELECT b.BankAccountCode, b.AccountName, b.BankName, b.AccountType, s.SiteKey,
               ISNULL(TRY_CONVERT(DECIMAL(18,2), b.CreditLine), 0)
        FROM stg.BankAccounts b
        JOIN dw.DimSite s ON s.SiteCode = b.SiteCode;

        INSERT INTO dw.DimCounterparty (CounterpartyCode, CounterpartyName, CounterpartyType, HomeSiteCode,
                                        PaymentTerms, PaymentMethod, CustomerSegment)
        SELECT CounterpartyCode, CounterpartyName, CounterpartyType, NULLIF(SiteCode, N''),
               NULLIF(PaymentTerms, N''),
               CASE WHEN PaymentTerms LIKE N'RIBA%' THEN N'RiBa'
                    WHEN PaymentTerms LIKE N'BB%'   THEN N'Bonifico'
                    WHEN PaymentTerms = N'RD'       THEN N'Rimessa diretta' END,
               NULLIF(CustomerSegment, N'')
        FROM stg.Counterparties;

        SET IDENTITY_INSERT dw.DimCounterparty ON;
        INSERT INTO dw.DimCounterparty (CounterpartyKey, CounterpartyCode, CounterpartyName, CounterpartyType)
        VALUES (-1, N'N/D', N'Nessuna controparte (giroconti)', N'Interno');
        SET IDENTITY_INSERT dw.DimCounterparty OFF;

        INSERT INTO dw.DimCashCategory (CategoryCode, CategoryName, CashFlowSection, Direction, CategoryGroup, SectionSort)
        SELECT CategoryCode, CategoryName, CashFlowSection, Direction, CategoryGroup,
               CASE CashFlowSection WHEN N'Operativa' THEN 1 WHEN N'Investimento' THEN 2
                                    WHEN N'Finanziamento' THEN 3 ELSE 4 END
        FROM stg.CashFlowCategories;

        /* ---------------- movimenti bancari ---------------- */
        INSERT INTO dw.FactBankTransaction (TransactionID, DateKey, BankAccountKey, SiteKey, CashCategoryKey,
                                            CounterpartyKey, Amount, InflowAmount, OutflowAmount,
                                            Description, DocumentReference)
        SELECT  t.TransactionID,
                CONVERT(INT, CONVERT(CHAR(8), TRY_CONVERT(DATE, t.TransactionDate), 112)),
                b.BankAccountKey,
                s.SiteKey,
                c.CashCategoryKey,
                ISNULL(cp.CounterpartyKey, -1),
                v.Amount,
                CASE WHEN v.Amount > 0 THEN v.Amount ELSE 0 END,
                CASE WHEN v.Amount < 0 THEN -v.Amount ELSE 0 END,
                t.Description,
                NULLIF(t.DocumentReference, N'')
        FROM stg.BankTransactions t
        CROSS APPLY (SELECT TRY_CONVERT(DECIMAL(18,2), t.Amount) AS Amount) v
        JOIN dw.DimBankAccount  b  ON b.BankAccountCode  = t.BankAccountCode
        JOIN dw.DimSite         s  ON s.SiteCode         = t.SiteCode
        JOIN dw.DimCashCategory c  ON c.CategoryCode     = t.CategoryCode
        LEFT JOIN dw.DimCounterparty cp ON cp.CounterpartyCode = NULLIF(t.CounterpartyCode, N'');

        /* ---------------- scadenzari ---------------- */
        INSERT INTO dw.FactARInvoice (InvoiceNumber, InvoiceDateKey, SiteKey, CounterpartyKey, InvoiceDate, DueDate,
                                      PaymentDate, NetAmount, GrossAmount, AmountPaid, IsBounced)
        SELECT  a.InvoiceNumber,
                CONVERT(INT, CONVERT(CHAR(8), TRY_CONVERT(DATE, a.InvoiceDate), 112)),
                s.SiteKey, cp.CounterpartyKey,
                TRY_CONVERT(DATE, a.InvoiceDate), TRY_CONVERT(DATE, a.DueDate), TRY_CONVERT(DATE, NULLIF(a.PaymentDate, N'')),
                TRY_CONVERT(DECIMAL(18,2), a.NetAmount), TRY_CONVERT(DECIMAL(18,2), a.GrossAmount),
                TRY_CONVERT(DECIMAL(18,2), a.AmountPaid), TRY_CONVERT(BIT, a.IsBounced)
        FROM stg.ARInvoices a
        JOIN dw.DimSite s          ON s.SiteCode = a.SiteCode
        JOIN dw.DimCounterparty cp ON cp.CounterpartyCode = a.CounterpartyCode;

        INSERT INTO dw.FactAPInvoice (InvoiceNumber, InvoiceDateKey, SiteKey, CounterpartyKey, PurchaseType, InvoiceDate,
                                      DueDate, PaymentDate, NetAmount, GrossAmount, AmountPaid)
        SELECT  a.InvoiceNumber,
                CONVERT(INT, CONVERT(CHAR(8), TRY_CONVERT(DATE, a.InvoiceDate), 112)),
                s.SiteKey, cp.CounterpartyKey, a.PurchaseType,
                TRY_CONVERT(DATE, a.InvoiceDate), TRY_CONVERT(DATE, a.DueDate), TRY_CONVERT(DATE, NULLIF(a.PaymentDate, N'')),
                TRY_CONVERT(DECIMAL(18,2), a.NetAmount), TRY_CONVERT(DECIMAL(18,2), a.GrossAmount),
                TRY_CONVERT(DECIMAL(18,2), a.AmountPaid)
        FROM stg.APInvoices a
        JOIN dw.DimSite s          ON s.SiteCode = a.SiteCode
        JOIN dw.DimCounterparty cp ON cp.CounterpartyCode = a.CounterpartyCode;

        /* ---------------- snapshot saldi giornalieri ----------------
           saldo di apertura + somma cumulata dei movimenti, per ogni giorno di calendario
           e ogni conto (anche nei giorni senza movimenti: serve per la posizione giornaliera) */
        DECLARE @From DATE = (SELECT MIN(TRY_CONVERT(DATE, BalanceDate)) FROM stg.BankOpeningBalances);
        DECLARE @To   DATE = (SELECT MAX(d.[Date]) FROM dw.FactBankTransaction f JOIN dw.DimDate d ON d.DateKey = f.DateKey);

        ;WITH grid AS (
            SELECT d.DateKey, d.[Date], b.BankAccountKey, b.CreditLine, b.BankAccountCode
            FROM dw.DimDate d
            CROSS JOIN dw.DimBankAccount b
            WHERE d.[Date] BETWEEN @From AND @To
        ),
        mov AS (
            SELECT DateKey, BankAccountKey, SUM(Amount) AS Amount
            FROM dw.FactBankTransaction
            GROUP BY DateKey, BankAccountKey
        )
        INSERT INTO dw.FactBankBalanceDaily (DateKey, BankAccountKey, ClosingBalance, CreditLine)
        SELECT  g.DateKey, g.BankAccountKey,
                ISNULL(TRY_CONVERT(DECIMAL(18,2), ob.Balance), 0)
                  + SUM(ISNULL(m.Amount, 0)) OVER (PARTITION BY g.BankAccountKey ORDER BY g.[Date]
                                                   ROWS UNBOUNDED PRECEDING),
                g.CreditLine
        FROM grid g
        LEFT JOIN mov m ON m.DateKey = g.DateKey AND m.BankAccountKey = g.BankAccountKey
        LEFT JOIN stg.BankOpeningBalances ob ON ob.BankAccountCode = g.BankAccountCode;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

/* parametri di tesoreria usati dagli alert (modificabili dal CFO senza toccare il report) */
DELETE FROM dw.TreasuryParameter;
INSERT INTO dw.TreasuryParameter (ParameterName, ParameterValue, Note) VALUES
    (N'MinCashThreshold',      2500000, N'Liquidita'' minima di gruppo (euro)'),
    (N'CreditLineUsageAlert',       70, N'% utilizzo affidamenti oltre cui scatta l''alert'),
    (N'DSOTarget',                  90, N'Giorni'),
    (N'OverdueRatioAlert',          10, N'% scaduto su crediti aperti'),
    (N'LiquidityDaysMin',           30, N'Giorni di uscite coperti dalla cassa');
GO

EXEC dw.usp_LoadTreasury;
GO
