/* =============================================================================
   Script 08 - controlli e quadrature
   ============================================================================= */
USE TreasuryDW;
GO

/* 1. Giroconti: devono sommare a zero, ogni giorno */
SELECT d.[Date], SUM(f.Amount) AS Imbalance
FROM dw.FactBankTransaction f
JOIN dw.DimCashCategory c ON c.CashCategoryKey = f.CashCategoryKey
JOIN dw.DimDate d         ON d.DateKey = f.DateKey
WHERE c.CashFlowSection = N'Giroconto'
GROUP BY d.[Date]
HAVING SUM(f.Amount) <> 0;

/* 2. Saldo finale snapshot = saldo iniziale + movimenti */
SELECT  b.BankAccountCode,
        TRY_CONVERT(DECIMAL(18,2), ob.Balance) + ISNULL(m.Mov, 0) AS ExpectedClosing,
        s.ClosingBalance                                          AS SnapshotClosing
FROM dw.DimBankAccount b
JOIN stg.BankOpeningBalances ob ON ob.BankAccountCode = b.BankAccountCode
OUTER APPLY (SELECT SUM(Amount) AS Mov FROM dw.FactBankTransaction f WHERE f.BankAccountKey = b.BankAccountKey) m
JOIN dw.FactBankBalanceDaily s ON s.BankAccountKey = b.BankAccountKey
                              AND s.DateKey = (SELECT MAX(DateKey) FROM dw.FactBankBalanceDaily)
WHERE TRY_CONVERT(DECIMAL(18,2), ob.Balance) + ISNULL(m.Mov, 0) <> s.ClosingBalance;

/* 3. Fatture clienti risultate incassate ma senza movimento bancario collegato */
SELECT TOP (50) a.InvoiceNumber, a.PaymentDate, a.GrossAmount
FROM dw.FactARInvoice a
WHERE a.PaymentDate >= '2024-01-01'
  AND NOT EXISTS (SELECT 1 FROM dw.FactBankTransaction t
                  JOIN dw.DimCashCategory c ON c.CashCategoryKey = t.CashCategoryKey
                  WHERE t.DocumentReference = a.InvoiceNumber AND c.CategoryCode = N'IN01');

/* 4. Quadratura incassi: somma movimenti IN01 + IN02 = fatture incassate nel periodo */
SELECT
    (SELECT SUM(t.Amount) FROM dw.FactBankTransaction t JOIN dw.DimCashCategory c ON c.CashCategoryKey = t.CashCategoryKey
      WHERE c.CategoryCode IN (N'IN01', N'IN02'))                                     AS BankCustomerReceipts,
    (SELECT SUM(GrossAmount) FROM dw.FactARInvoice WHERE PaymentDate BETWEEN '2024-01-01' AND '2025-12-31') AS InvoicesCollected;
-- piccola differenza attesa: insoluti accreditati nel 2025 e riaddebitati dopo la data di riferimento

/* 5. Date incoerenti */
SELECT COUNT(*) AS BadDates FROM dw.FactARInvoice WHERE DueDate < InvoiceDate OR PaymentDate < InvoiceDate;
SELECT COUNT(*) AS BadDates FROM dw.FactAPInvoice WHERE DueDate < InvoiceDate OR PaymentDate < InvoiceDate;

/* 6. Movimenti con categoria non coerente con il segno */
SELECT c.CategoryCode, c.Direction, COUNT(*) AS Rows_
FROM dw.FactBankTransaction f
JOIN dw.DimCashCategory c ON c.CashCategoryKey = f.CashCategoryKey
WHERE (c.Direction = N'Entrata' AND f.Amount < 0) OR (c.Direction = N'Uscita' AND f.Amount > 0)
GROUP BY c.CategoryCode, c.Direction;

/* 7. Saldi oltre l'affidamento (sconfinamenti) */
SELECT d.[Date], b.AccountName, f.ClosingBalance, b.CreditLine
FROM dw.FactBankBalanceDaily f
JOIN dw.DimBankAccount b ON b.BankAccountKey = f.BankAccountKey
JOIN dw.DimDate d        ON d.DateKey = f.DateKey
WHERE f.ClosingBalance < -b.CreditLine;
GO
