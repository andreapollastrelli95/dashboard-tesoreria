/* =============================================================================
   Script 03 - caricamento CSV in staging (BULK INSERT)
   Prima di eseguire: impostare @DataPath con la cartella "data" del repository.
   Nota: il percorso deve essere visibile dal servizio SQL Server, non dal client.
   FORMAT = 'CSV' richiede SQL Server 2017 o successivo.
   ============================================================================= */
USE TreasuryDW;
GO
SET NOCOUNT ON;

DECLARE @DataPath NVARCHAR(400) = N'C:\Projects\dashboard-tesoreria\data\';   -- <-- modificare
DECLARE @sql NVARCHAR(MAX);

DECLARE @files TABLE (TableName SYSNAME, FileName NVARCHAR(200));
INSERT INTO @files VALUES
    (N'stg.Sites',               N'sites.csv'),
    (N'stg.BankAccounts',        N'bank_accounts.csv'),
    (N'stg.BankOpeningBalances', N'bank_opening_balances.csv'),
    (N'stg.Counterparties',      N'counterparties.csv'),
    (N'stg.CashFlowCategories',  N'cash_flow_categories.csv'),
    (N'stg.ARInvoices',          N'ar_invoices.csv'),
    (N'stg.APInvoices',          N'ap_invoices.csv'),
    (N'stg.BankTransactions',    N'bank_transactions.csv');

DECLARE @t SYSNAME, @f NVARCHAR(200);
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT TableName, FileName FROM @files;
OPEN cur;
FETCH NEXT FROM cur INTO @t, @f;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'TRUNCATE TABLE ' + @t + N';
    BULK INSERT ' + @t + N'
    FROM ''' + @DataPath + @f + N'''
    WITH (FORMAT = ''CSV'', FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'',
          CODEPAGE = ''65001'', FIELDQUOTE = ''"'', TABLOCK);';
    EXEC sys.sp_executesql @sql;
    PRINT CONCAT(@t, N' caricata');
    FETCH NEXT FROM cur INTO @t, @f;
END;
CLOSE cur;
DEALLOCATE cur;

-- conteggio righe caricate
SELECT 'stg.BankTransactions' AS TableName, COUNT(*) AS RowsLoaded FROM stg.BankTransactions
UNION ALL SELECT 'stg.ARInvoices',     COUNT(*) FROM stg.ARInvoices
UNION ALL SELECT 'stg.APInvoices',     COUNT(*) FROM stg.APInvoices
UNION ALL SELECT 'stg.Counterparties', COUNT(*) FROM stg.Counterparties
UNION ALL SELECT 'stg.BankAccounts',   COUNT(*) FROM stg.BankAccounts;
GO
