// =============================================================================
//  Power Query (M) - Cash Flow e Tesoreria
//  Parametri: ServerName, DatabaseName, AsOfDate (data di riferimento report)
//  Le tabelle grandi arrivano dalle viste rpt con query folding; le trasformazioni
//  qui sotto sono quelle che ha senso fare lato report (etichette, fasce, flag).
// =============================================================================

// ---- Parametri ---------------------------------------------------------------
// ServerName   = "localhost"          meta [IsParameterQuery = true, Type = "Text"]
// DatabaseName = "TreasuryDW"         meta [IsParameterQuery = true, Type = "Text"]
// AsOfDate     = #date(2025, 12, 31)  meta [IsParameterQuery = true, Type = "Date"]


// ---- fnGetView ---------------------------------------------------------------
(ViewName as text) as table =>
let
    Source = Sql.Database(ServerName, DatabaseName),
    View   = Source{[Schema = "rpt", Item = ViewName]}[Data]
in
    View


// ---- fnAgingBucket: fascia di scaduto da giorni di ritardo -------------------
(DaysOverdue as nullable number) as text =>
    if DaysOverdue = null or DaysOverdue <= 0 then "0 - A scadere"
    else if DaysOverdue <= 30 then "1 - Scaduto 1-30 gg"
    else if DaysOverdue <= 60 then "2 - Scaduto 31-60 gg"
    else if DaysOverdue <= 90 then "3 - Scaduto 61-90 gg"
    else if DaysOverdue <= 180 then "4 - Scaduto 91-180 gg"
    else "5 - Scaduto oltre 180 gg"


// ---- Calendar ----------------------------------------------------------------
let
    Source    = fnGetView("Calendar"),
    Types     = Table.TransformColumnTypes(Source, {{"Date", type date}, {"WeekStart", type date},
                    {"Year", Int64.Type}, {"Month", Int64.Type}, {"YearMonth", Int64.Type}, {"IsWorkingDay", type logical}}),
    WeekLabel = Table.AddColumn(Types, "WeekLabel",
                    each "Sett. " & Date.ToText([WeekStart], "dd/MM"), type text),
    // periodo: storico o previsione rispetto alla data di riferimento
    Period    = Table.AddColumn(WeekLabel, "Period",
                    each if [Date] <= AsOfDate then "Consuntivo" else "Previsione", type text),
    // settimane relative (0 = settimana della data di riferimento) per il grafico a 13 settimane
    RelWeek   = Table.AddColumn(Period, "RelativeWeek",
                    each Number.RoundDown(Duration.Days([WeekStart] - Date.StartOfWeek(AsOfDate, Day.Monday)) / 7),
                    Int64.Type)
in
    RelWeek


// ---- Site / BankAccount / CashCategory ---------------------------------------
let Source = fnGetView("Site") in Source

let
    Source   = fnGetView("BankAccount"),
    Types    = Table.TransformColumnTypes(Source, {{"CreditLine", Currency.Type}}),
    // etichetta breve per i grafici: banca + ultime parole del tipo conto
    Short    = Table.AddColumn(Types, "AccountShortName",
                   each [BankName] & " (" & Text.Start([AccountType], 14) & ")", type text)
in
    Short

let
    Source = fnGetView("CashCategory"),
    // ordinamento delle sezioni del rendiconto
    Sort   = Table.TransformColumnTypes(Source, {{"SectionSort", Int64.Type}})
in
    Sort


// ---- Counterparty ------------------------------------------------------------
let
    Source  = fnGetView("Counterparty"),
    Clean   = Table.TransformColumns(Source, {{"CounterpartyName", Text.Trim, type text}}),
    Replace = Table.ReplaceValue(Clean, null, "n.a.", Replacer.ReplaceValue, {"PaymentTerms", "PaymentMethod", "CustomerSegment"})
in
    Replace


// ---- FactBankTransaction -----------------------------------------------------
let
    Source = fnGetView("FactBankTransaction"),
    Types  = Table.TransformColumnTypes(Source, {{"Amount", Currency.Type},
                 {"InflowAmount", Currency.Type}, {"OutflowAmount", Currency.Type}})
in
    Types


// ---- FactBankBalanceDaily ----------------------------------------------------
let
    Source = fnGetView("FactBankBalanceDaily"),
    Types  = Table.TransformColumnTypes(Source, {{"ClosingBalance", Currency.Type},
                 {"CreditLine", Currency.Type}, {"AvailableFunds", Currency.Type}})
in
    Types


// ---- FactARInvoice: aging alla data di riferimento ---------------------------
let
    Source      = fnGetView("FactARInvoice"),
    Types       = Table.TransformColumnTypes(Source, {{"InvoiceDate", type date}, {"DueDate", type date},
                      {"PaymentDate", type date}, {"GrossAmount", Currency.Type}, {"NetAmount", Currency.Type},
                      {"AmountPaid", Currency.Type}, {"IsBounced", type logical}}),
    IsOpen      = Table.AddColumn(Types, "IsOpenAtAsOf",
                      each [InvoiceDate] <= AsOfDate and ([PaymentDate] = null or [PaymentDate] > AsOfDate), type logical),
    Days        = Table.AddColumn(IsOpen, "DaysOverdueAtAsOf",
                      each if [IsOpenAtAsOf] then Duration.Days(AsOfDate - [DueDate]) else null, Int64.Type),
    Bucket      = Table.AddColumn(Days, "AgingBucket",
                      each if [IsOpenAtAsOf] then fnAgingBucket([DaysOverdueAtAsOf]) else null, type text),
    OpenAmount  = Table.AddColumn(Bucket, "OpenAmountAtAsOf",
                      each if [IsOpenAtAsOf] then [GrossAmount] else 0, Currency.Type)
in
    OpenAmount


// ---- FactAPInvoice -----------------------------------------------------------
let
    Source     = fnGetView("FactAPInvoice"),
    Types      = Table.TransformColumnTypes(Source, {{"InvoiceDate", type date}, {"DueDate", type date},
                     {"PaymentDate", type date}, {"GrossAmount", Currency.Type}, {"NetAmount", Currency.Type},
                     {"AmountPaid", Currency.Type}}),
    IsOpen     = Table.AddColumn(Types, "IsOpenAtAsOf",
                     each [InvoiceDate] <= AsOfDate and ([PaymentDate] = null or [PaymentDate] > AsOfDate), type logical),
    // pagamento anticipato / puntuale / in ritardo rispetto alla scadenza
    PayStatus  = Table.AddColumn(IsOpen, "PaymentTiming",
                     each if [PaymentDate] = null then "Aperta"
                          else if [PaymentDate] < [DueDate] then "Anticipata"
                          else if Duration.Days([PaymentDate] - [DueDate]) <= 5 then "Puntuale"
                          else "In ritardo", type text)
in
    PayStatus


// ---- FactCashForecast --------------------------------------------------------
let
    Source = fnGetView("FactCashForecast"),
    Types  = Table.TransformColumnTypes(Source, {{"AsOfDate", type date}, {"Amount", Currency.Type}})
in
    Types


// ---- TreasuryParameter: da righe a una sola riga con colonne (usata dalle misure)
let
    Source  = fnGetView("TreasuryParameter"),
    Types   = Table.TransformColumnTypes(Source, {{"ParameterValue", type number}}),
    Pivoted = Table.Pivot(Types, List.Distinct(Types[ParameterName]), "ParameterName", "ParameterValue")
in
    Pivoted
