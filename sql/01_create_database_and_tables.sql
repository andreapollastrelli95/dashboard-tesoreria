/* =============================================================================
   Progetto : Cash Flow e Tesoreria
   Azienda  : Centralia Forniture S.p.A. - 4 sedi (dati simulati)
   Script   : 01 - database, schemi, tabelle
   Target   : SQL Server 2019 o successivo
   ============================================================================= */

IF DB_ID(N'TreasuryDW') IS NULL
    CREATE DATABASE TreasuryDW;
GO
USE TreasuryDW;
GO

IF SCHEMA_ID(N'stg') IS NULL EXEC (N'CREATE SCHEMA stg AUTHORIZATION dbo;');
IF SCHEMA_ID(N'dw')  IS NULL EXEC (N'CREATE SCHEMA dw  AUTHORIZATION dbo;');
IF SCHEMA_ID(N'rpt') IS NULL EXEC (N'CREATE SCHEMA rpt AUTHORIZATION dbo;');
GO

/* ------------------------------------------------------------------ STAGING */
DROP TABLE IF EXISTS stg.Sites;
CREATE TABLE stg.Sites (SiteCode NVARCHAR(5), SiteName NVARCHAR(100), Area NVARCHAR(20), Headcount NVARCHAR(10));

DROP TABLE IF EXISTS stg.BankAccounts;
CREATE TABLE stg.BankAccounts (BankAccountCode NVARCHAR(10), AccountName NVARCHAR(150), BankName NVARCHAR(100),
                               SiteCode NVARCHAR(5), AccountType NVARCHAR(100), CreditLine NVARCHAR(30));

DROP TABLE IF EXISTS stg.BankOpeningBalances;
CREATE TABLE stg.BankOpeningBalances (BankAccountCode NVARCHAR(10), BalanceDate NVARCHAR(20), Balance NVARCHAR(30));

DROP TABLE IF EXISTS stg.Counterparties;
CREATE TABLE stg.Counterparties (CounterpartyCode NVARCHAR(10), CounterpartyName NVARCHAR(200), CounterpartyType NVARCHAR(50),
                                 SiteCode NVARCHAR(5), PaymentTerms NVARCHAR(20), CustomerSegment NVARCHAR(50));

DROP TABLE IF EXISTS stg.CashFlowCategories;
CREATE TABLE stg.CashFlowCategories (CategoryCode NVARCHAR(10), CategoryName NVARCHAR(100), CashFlowSection NVARCHAR(30),
                                     Direction NVARCHAR(10), CategoryGroup NVARCHAR(50));

DROP TABLE IF EXISTS stg.ARInvoices;
CREATE TABLE stg.ARInvoices (InvoiceNumber NVARCHAR(30), SiteCode NVARCHAR(5), CounterpartyCode NVARCHAR(10),
                             InvoiceDate NVARCHAR(20), DueDate NVARCHAR(20), NetAmount NVARCHAR(30), GrossAmount NVARCHAR(30),
                             PaymentTerms NVARCHAR(20), PaymentDate NVARCHAR(20), AmountPaid NVARCHAR(30), IsBounced NVARCHAR(5));

DROP TABLE IF EXISTS stg.APInvoices;
CREATE TABLE stg.APInvoices (InvoiceNumber NVARCHAR(30), SiteCode NVARCHAR(5), CounterpartyCode NVARCHAR(10),
                             InvoiceDate NVARCHAR(20), DueDate NVARCHAR(20), NetAmount NVARCHAR(30), GrossAmount NVARCHAR(30),
                             PaymentTerms NVARCHAR(20), PurchaseType NVARCHAR(20), PaymentDate NVARCHAR(20), AmountPaid NVARCHAR(30));

DROP TABLE IF EXISTS stg.BankTransactions;
CREATE TABLE stg.BankTransactions (TransactionID NVARCHAR(20), TransactionDate NVARCHAR(20), ValueDate NVARCHAR(20),
                                   BankAccountCode NVARCHAR(10), SiteCode NVARCHAR(5), CategoryCode NVARCHAR(10),
                                   CounterpartyCode NVARCHAR(10), Amount NVARCHAR(30), Description NVARCHAR(250),
                                   DocumentReference NVARCHAR(30));
GO

/* ------------------------------------------------------------------ DW */
DROP TABLE IF EXISTS dw.FactCashForecast;
DROP TABLE IF EXISTS dw.FactBankBalanceDaily;
DROP TABLE IF EXISTS dw.FactBankTransaction;
DROP TABLE IF EXISTS dw.FactARInvoice;
DROP TABLE IF EXISTS dw.FactAPInvoice;
DROP TABLE IF EXISTS dw.RecurringCashItem;
DROP TABLE IF EXISTS dw.TreasuryParameter;
DROP TABLE IF EXISTS dw.DimBankAccount;
DROP TABLE IF EXISTS dw.DimCounterparty;
DROP TABLE IF EXISTS dw.DimCashCategory;
DROP TABLE IF EXISTS dw.DimSite;
DROP TABLE IF EXISTS dw.DimDate;
GO

CREATE TABLE dw.DimDate (
    DateKey INT NOT NULL CONSTRAINT PK_DimDate PRIMARY KEY, [Date] DATE NOT NULL, [Year] SMALLINT NOT NULL,
    [Quarter] TINYINT NOT NULL, QuarterLabel CHAR(2) NOT NULL, [Month] TINYINT NOT NULL, MonthName NVARCHAR(15) NOT NULL,
    MonthShort NVARCHAR(3) NOT NULL, YearMonth INT NOT NULL, YearMonthLabel NVARCHAR(10) NOT NULL,
    WeekOfYear TINYINT NOT NULL, DayOfWeek TINYINT NOT NULL, DayName NVARCHAR(10) NOT NULL,
    IsWeekend BIT NOT NULL, IsHoliday BIT NOT NULL, IsWorkingDay BIT NOT NULL,
    MonthStartDate DATE NOT NULL, MonthEndDate DATE NOT NULL
);

CREATE TABLE dw.DimSite (
    SiteKey     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimSite PRIMARY KEY,
    SiteCode    NVARCHAR(5)   NOT NULL CONSTRAINT UQ_DimSite UNIQUE,
    SiteName    NVARCHAR(100) NOT NULL,
    Area        NVARCHAR(20)  NOT NULL,
    Headcount   SMALLINT      NOT NULL
);

CREATE TABLE dw.DimBankAccount (
    BankAccountKey  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimBankAccount PRIMARY KEY,
    BankAccountCode NVARCHAR(10)  NOT NULL CONSTRAINT UQ_DimBankAccount UNIQUE,
    AccountName     NVARCHAR(150) NOT NULL,
    BankName        NVARCHAR(100) NOT NULL,
    AccountType     NVARCHAR(100) NOT NULL,
    SiteKey         INT           NOT NULL CONSTRAINT FK_DimBankAccount_Site REFERENCES dw.DimSite(SiteKey),
    CreditLine      DECIMAL(18,2) NOT NULL       -- affidamento di cassa
);

CREATE TABLE dw.DimCounterparty (
    CounterpartyKey   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimCounterparty PRIMARY KEY,
    CounterpartyCode  NVARCHAR(10)  NOT NULL CONSTRAINT UQ_DimCounterparty UNIQUE,
    CounterpartyName  NVARCHAR(200) NOT NULL,
    CounterpartyType  NVARCHAR(50)  NOT NULL,     -- Cliente, Fornitore merce, Fornitore servizi, Erario, ...
    HomeSiteCode      NVARCHAR(5)   NULL,
    PaymentTerms      NVARCHAR(20)  NULL,
    PaymentMethod     NVARCHAR(20)  NULL,         -- RiBa, Bonifico, Rimessa diretta
    CustomerSegment   NVARCHAR(50)  NULL
);

CREATE TABLE dw.DimCashCategory (
    CashCategoryKey INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimCashCategory PRIMARY KEY,
    CategoryCode    NVARCHAR(10)  NOT NULL CONSTRAINT UQ_DimCashCategory UNIQUE,
    CategoryName    NVARCHAR(100) NOT NULL,
    CashFlowSection NVARCHAR(30)  NOT NULL,       -- Operativa / Investimento / Finanziamento / Giroconto
    Direction       NVARCHAR(10)  NOT NULL,
    CategoryGroup   NVARCHAR(50)  NOT NULL,
    SectionSort     TINYINT       NOT NULL
);

-- grain: movimento di estratto conto
CREATE TABLE dw.FactBankTransaction (
    TransactionKey    BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FactBankTransaction PRIMARY KEY NONCLUSTERED,
    TransactionID     NVARCHAR(20)  NOT NULL,
    DateKey           INT           NOT NULL CONSTRAINT FK_FBT_Date        REFERENCES dw.DimDate(DateKey),
    BankAccountKey    INT           NOT NULL CONSTRAINT FK_FBT_BankAccount REFERENCES dw.DimBankAccount(BankAccountKey),
    SiteKey           INT           NOT NULL CONSTRAINT FK_FBT_Site        REFERENCES dw.DimSite(SiteKey),
    CashCategoryKey   INT           NOT NULL CONSTRAINT FK_FBT_Category    REFERENCES dw.DimCashCategory(CashCategoryKey),
    CounterpartyKey   INT           NOT NULL CONSTRAINT FK_FBT_Counterparty REFERENCES dw.DimCounterparty(CounterpartyKey),
    Amount            DECIMAL(18,2) NOT NULL,     -- + entrata, - uscita
    InflowAmount      DECIMAL(18,2) NOT NULL,     -- valorizzati in fase di caricamento
    OutflowAmount     DECIMAL(18,2) NOT NULL,     -- (niente colonne calcolate su tabelle columnstore)
    Description       NVARCHAR(250) NULL,
    DocumentReference NVARCHAR(30)  NULL
);

-- grain: fattura attiva (scadenza unica)
CREATE TABLE dw.FactARInvoice (
    ARInvoiceKey      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FactARInvoice PRIMARY KEY,
    InvoiceNumber     NVARCHAR(30)  NOT NULL CONSTRAINT UQ_FactARInvoice UNIQUE,
    InvoiceDateKey    INT           NOT NULL CONSTRAINT FK_FAR_Date REFERENCES dw.DimDate(DateKey),
    SiteKey           INT           NOT NULL CONSTRAINT FK_FAR_Site REFERENCES dw.DimSite(SiteKey),
    CounterpartyKey   INT           NOT NULL CONSTRAINT FK_FAR_Counterparty REFERENCES dw.DimCounterparty(CounterpartyKey),
    InvoiceDate       DATE          NOT NULL,
    DueDate           DATE          NOT NULL,
    PaymentDate       DATE          NULL,         -- NULL = aperta alla data di riferimento
    NetAmount         DECIMAL(18,2) NOT NULL,
    GrossAmount       DECIMAL(18,2) NOT NULL,     -- imponibile + IVA: e' l'importo che incassiamo
    AmountPaid        DECIMAL(18,2) NOT NULL,
    IsBounced         BIT           NOT NULL,     -- RiBa tornata insoluta almeno una volta
    PaymentDelayDays  AS (DATEDIFF(DAY, DueDate, PaymentDate))
);

CREATE TABLE dw.FactAPInvoice (
    APInvoiceKey      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FactAPInvoice PRIMARY KEY,
    InvoiceNumber     NVARCHAR(30)  NOT NULL CONSTRAINT UQ_FactAPInvoice UNIQUE,
    InvoiceDateKey    INT           NOT NULL CONSTRAINT FK_FAP_Date REFERENCES dw.DimDate(DateKey),
    SiteKey           INT           NOT NULL CONSTRAINT FK_FAP_Site REFERENCES dw.DimSite(SiteKey),
    CounterpartyKey   INT           NOT NULL CONSTRAINT FK_FAP_Counterparty REFERENCES dw.DimCounterparty(CounterpartyKey),
    PurchaseType      NVARCHAR(20)  NOT NULL,
    InvoiceDate       DATE          NOT NULL,
    DueDate           DATE          NOT NULL,
    PaymentDate       DATE          NULL,
    NetAmount         DECIMAL(18,2) NOT NULL,
    GrossAmount       DECIMAL(18,2) NOT NULL,
    AmountPaid        DECIMAL(18,2) NOT NULL
);

-- snapshot giornaliero dei saldi (tutti i giorni di calendario, saldo riportato nei festivi)
CREATE TABLE dw.FactBankBalanceDaily (
    DateKey          INT           NOT NULL CONSTRAINT FK_FBB_Date REFERENCES dw.DimDate(DateKey),
    BankAccountKey   INT           NOT NULL CONSTRAINT FK_FBB_BankAccount REFERENCES dw.DimBankAccount(BankAccountKey),
    ClosingBalance   DECIMAL(18,2) NOT NULL,
    CreditLine       DECIMAL(18,2) NOT NULL,
    AvailableFunds   AS (ClosingBalance + CreditLine),
    CONSTRAINT PK_FactBankBalanceDaily PRIMARY KEY (DateKey, BankAccountKey)
);

-- previsione di cassa a 13 settimane (creata dalla procedura dw.usp_BuildCashForecast)
CREATE TABLE dw.FactCashForecast (
    ForecastKey      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FactCashForecast PRIMARY KEY,
    AsOfDate         DATE          NOT NULL,
    DateKey          INT           NOT NULL CONSTRAINT FK_FCF_Date REFERENCES dw.DimDate(DateKey),
    CashCategoryKey  INT           NOT NULL CONSTRAINT FK_FCF_Category REFERENCES dw.DimCashCategory(CashCategoryKey),
    SourceType       NVARCHAR(20)  NOT NULL,      -- Scadenzario clienti / Scadenzario fornitori / Ricorrente
    Amount           DECIMAL(18,2) NOT NULL
);

-- uscite ricorrenti non presenti negli scadenzari (stipendi, F24, affitti, rate ...)
CREATE TABLE dw.RecurringCashItem (
    RecurringItemID  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_RecurringCashItem PRIMARY KEY,
    CategoryCode     NVARCHAR(10)  NOT NULL,
    Description      NVARCHAR(150) NOT NULL,
    DayOfMonth       TINYINT       NOT NULL,
    MonthsList       VARCHAR(40)   NOT NULL,      -- es. '1,2,3,4,5,6,7,8,9,10,11,12' oppure '1,4,7,10'
    Amount           DECIMAL(18,2) NOT NULL       -- negativo = uscita
);

-- parametri di tesoreria (soglie per gli alert)
CREATE TABLE dw.TreasuryParameter (
    ParameterName  NVARCHAR(50)  NOT NULL CONSTRAINT PK_TreasuryParameter PRIMARY KEY,
    ParameterValue DECIMAL(18,2) NOT NULL,
    Note           NVARCHAR(200) NULL
);
GO

CREATE CLUSTERED COLUMNSTORE INDEX CCI_FactBankTransaction ON dw.FactBankTransaction;
CREATE NONCLUSTERED INDEX IX_FactARInvoice_Dates ON dw.FactARInvoice (InvoiceDate, PaymentDate) INCLUDE (GrossAmount, DueDate, CounterpartyKey);
CREATE NONCLUSTERED INDEX IX_FactAPInvoice_Dates ON dw.FactAPInvoice (InvoiceDate, PaymentDate) INCLUDE (GrossAmount, DueDate, CounterpartyKey);
GO
