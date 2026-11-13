# -----------------------------------------------------------------------------
# Esporta le tabelle del modello Power BI in CSV (cartella data/model).
# Replica la logica degli script SQL 04-06 (schema dw, previsione a 13 settimane,
# viste rpt) per poter usare il report anche senza SQL Server.
# -----------------------------------------------------------------------------
import os
import numpy as np
import pandas as pd
from dateutil.easter import easter

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")
OUT = os.path.join(BASE, "model")
os.makedirs(OUT, exist_ok=True)

AS_OF = pd.Timestamp("2025-12-31")
HORIZON = 91
END = AS_OF + pd.Timedelta(days=HORIZON)
MESI = ["Gennaio", "Febbraio", "Marzo", "Aprile", "Maggio", "Giugno", "Luglio", "Agosto",
        "Settembre", "Ottobre", "Novembre", "Dicembre"]
GIORNI = ["Lunedì", "Martedì", "Mercoledì", "Giovedì", "Venerdì", "Sabato", "Domenica"]


def key(s):
    return s.dt.strftime("%Y%m%d").astype(int)


def save(df, name):
    df.to_csv(os.path.join(OUT, name), index=False, date_format="%Y-%m-%d")


# ---------------------------------------------------------------- calendario
d = pd.DataFrame({"Date": pd.date_range("2023-07-01", "2026-06-30")})
d["DateKey"] = key(d.Date)
d["Year"] = d.Date.dt.year
d["Quarter"] = d.Date.dt.quarter
d["QuarterLabel"] = "T" + d.Quarter.astype(str)
d["Month"] = d.Date.dt.month
d["MonthName"] = d.Month.map(lambda m: MESI[m - 1])
d["MonthShort"] = d.MonthName.str[:3]
d["YearMonth"] = d.Year * 100 + d.Month
d["YearMonthLabel"] = d.MonthShort + " " + d.Year.astype(str)
d["WeekOfYear"] = d.Date.dt.isocalendar().week.astype(int)
d["DayOfWeek"] = d.Date.dt.weekday + 1
d["DayName"] = d.Date.dt.weekday.map(lambda i: GIORNI[i])
fixed = {(1, 1), (1, 6), (4, 25), (5, 1), (6, 2), (8, 15), (11, 1), (12, 8), (12, 25), (12, 26)}
pasquetta = {pd.Timestamp(easter(y)) + pd.Timedelta(days=1) for y in range(2023, 2027)}
d["IsWorkingDay"] = (d.DayOfWeek <= 5) & ~d.Date.map(lambda x: (x.month, x.day) in fixed or x in pasquetta)
d["WeekStart"] = d.Date - pd.to_timedelta(d.DayOfWeek - 1, unit="D")
d["WeekLabel"] = "Sett. " + d.WeekStart.dt.strftime("%d/%m")
d["Period"] = np.where(d.Date <= AS_OF, "Consuntivo", "Previsione")
d["RelativeWeek"] = ((d.WeekStart - (AS_OF - pd.Timedelta(days=AS_OF.weekday()))).dt.days // 7)
save(d, "calendar.csv")
work_days = d[d.IsWorkingDay].Date.values


def next_workday(x):
    x = np.datetime64(x)
    return pd.Timestamp(work_days[np.searchsorted(work_days, x)])


# ---------------------------------------------------------------- dimensioni
sites = pd.read_csv(os.path.join(BASE, "sites.csv"))
sites.insert(0, "SiteKey", range(1, len(sites) + 1))
save(sites, "site.csv")
site_key = sites.set_index("SiteCode").SiteKey

banks = pd.read_csv(os.path.join(BASE, "bank_accounts.csv"))
banks.insert(0, "BankAccountKey", range(1, len(banks) + 1))
banks["AccountSite"] = banks.SiteCode.map(sites.set_index("SiteCode").SiteName)
banks["AccountShortName"] = banks.BankName + " (" + banks.AccountType.str[:14] + ")"
save(banks[["BankAccountKey", "BankAccountCode", "AccountName", "BankName", "AccountType", "CreditLine",
            "AccountSite", "AccountShortName"]], "bank_account.csv")
bank_key = banks.set_index("BankAccountCode").BankAccountKey

cp = pd.read_csv(os.path.join(BASE, "counterparties.csv"))
cp.insert(0, "CounterpartyKey", range(1, len(cp) + 1))
cp["PaymentMethod"] = np.select([cp.PaymentTerms.str.startswith("RIBA", na=False), cp.PaymentTerms.str.startswith("BB", na=False),
                                 cp.PaymentTerms.eq("RD")], ["RiBa", "Bonifico", "Rimessa diretta"], "n.a.")
cp["PaymentTerms"] = cp.PaymentTerms.fillna("n.a.")
cp["CustomerSegment"] = cp.CustomerSegment.fillna("n.a.")
cp = cp.rename(columns={"SiteCode": "HomeSiteCode"})
cp = pd.concat([pd.DataFrame([{"CounterpartyKey": -1, "CounterpartyCode": "N/D",
                               "CounterpartyName": "Nessuna controparte (giroconti)", "CounterpartyType": "Interno",
                               "HomeSiteCode": None, "PaymentTerms": "n.a.", "PaymentMethod": "n.a.",
                               "CustomerSegment": "n.a."}]), cp], ignore_index=True)
save(cp[["CounterpartyKey", "CounterpartyCode", "CounterpartyName", "CounterpartyType", "HomeSiteCode",
         "PaymentTerms", "PaymentMethod", "CustomerSegment"]], "counterparty.csv")
cp_key = cp.set_index("CounterpartyCode").CounterpartyKey

cat = pd.read_csv(os.path.join(BASE, "cash_flow_categories.csv"))
cat.insert(0, "CashCategoryKey", range(1, len(cat) + 1))
cat["SectionSort"] = cat.CashFlowSection.map({"Operativa": 1, "Investimento": 2, "Finanziamento": 3}).fillna(4).astype(int)
save(cat[["CashCategoryKey", "CategoryCode", "CategoryName", "CashFlowSection", "SectionSort", "Direction",
          "CategoryGroup"]], "cash_category.csv")
cat_key = cat.set_index("CategoryCode").CashCategoryKey

# ---------------------------------------------------------------- movimenti
t = pd.read_csv(os.path.join(BASE, "bank_transactions.csv"), parse_dates=["TransactionDate"])
f = pd.DataFrame({
    "TransactionID": t.TransactionID,
    "DateKey": key(t.TransactionDate),
    "BankAccountKey": t.BankAccountCode.map(bank_key),
    "SiteKey": t.SiteCode.map(site_key),
    "CashCategoryKey": t.CategoryCode.map(cat_key),
    "CounterpartyKey": t.CounterpartyCode.map(cp_key).fillna(-1).astype(int),
    "Amount": t.Amount,
    "InflowAmount": t.Amount.clip(lower=0),
    "OutflowAmount": (-t.Amount).clip(lower=0),
    "Description": t.Description,
    "DocumentReference": t.DocumentReference,
})
save(f, "fact_bank_transaction.csv")

# ------------------------------------------------------- saldi giornalieri
ob = pd.read_csv(os.path.join(BASE, "bank_opening_balances.csv")).set_index("BankAccountCode").Balance
days = pd.date_range(pd.read_csv(os.path.join(BASE, "bank_opening_balances.csv")).BalanceDate.min(), t.TransactionDate.max())
mov = t.pivot_table(index="TransactionDate", columns="BankAccountCode", values="Amount", aggfunc="sum")
bal = mov.reindex(days).reindex(columns=ob.index).fillna(0).cumsum() + ob
bd = bal.stack().rename("ClosingBalance").reset_index()
bd.columns = ["Date", "BankAccountCode", "ClosingBalance"]
bd["DateKey"] = key(bd.Date)
bd["BankAccountKey"] = bd.BankAccountCode.map(bank_key)
bd["CreditLine"] = bd.BankAccountCode.map(banks.set_index("BankAccountCode").CreditLine)
bd["AvailableFunds"] = bd.ClosingBalance + bd.CreditLine
save(bd[["DateKey", "BankAccountKey", "ClosingBalance", "CreditLine", "AvailableFunds"]], "fact_bank_balance_daily.csv")

# --------------------------------------------------------------- scadenzari
ar = pd.read_csv(os.path.join(BASE, "ar_invoices.csv"), parse_dates=["InvoiceDate", "DueDate", "PaymentDate"])
ap = pd.read_csv(os.path.join(BASE, "ap_invoices.csv"), parse_dates=["InvoiceDate", "DueDate", "PaymentDate"])


def bucket(g):
    return np.select([g <= 0, g <= 30, g <= 60, g <= 90, g <= 180],
                     ["0 - A scadere", "1 - Scaduto 1-30 gg", "2 - Scaduto 31-60 gg", "3 - Scaduto 61-90 gg",
                      "4 - Scaduto 91-180 gg"], "5 - Scaduto oltre 180 gg")


def invoices(df, kind):
    o = pd.DataFrame({
        ("ARInvoiceKey" if kind == "AR" else "APInvoiceKey"): range(1, len(df) + 1),
        "InvoiceNumber": df.InvoiceNumber,
        "InvoiceDateKey": key(df.InvoiceDate),
        "SiteKey": df.SiteCode.map(site_key),
        "CounterpartyKey": df.CounterpartyCode.map(cp_key),
    })
    if kind == "AP":
        o["PurchaseType"] = df.PurchaseType
    o["InvoiceDate"], o["DueDate"], o["PaymentDate"] = df.InvoiceDate, df.DueDate, df.PaymentDate
    o["NetAmount"], o["GrossAmount"], o["AmountPaid"] = df.NetAmount, df.GrossAmount, df.AmountPaid
    if kind == "AR":
        o["IsBounced"] = df.IsBounced.astype(bool)
        o["PaymentDelayDays"] = (df.PaymentDate - df.DueDate).dt.days
    is_open = (df.InvoiceDate <= AS_OF) & (df.PaymentDate.isna() | (df.PaymentDate > AS_OF))
    o["IsOpenAtAsOf"] = is_open
    if kind == "AR":
        over = (AS_OF - df.DueDate).dt.days
        o["DaysOverdueAtAsOf"] = over.where(is_open)
        o["AgingBucket"] = pd.Series(bucket(over), index=df.index).where(is_open)
        o["OpenAmountAtAsOf"] = df.GrossAmount.where(is_open, 0)
    else:
        o["PaymentTiming"] = np.select([df.PaymentDate.isna(), df.PaymentDate < df.DueDate,
                                        (df.PaymentDate - df.DueDate).dt.days <= 5],
                                       ["Aperta", "Anticipata", "Puntuale"], "In ritardo")
    return o


save(invoices(ar, "AR"), "fact_ar_invoice.csv")
save(invoices(ap, "AP"), "fact_ap_invoice.csv")

# ---------------------------------------------------- previsione 13 settimane
fc = []

paid = ar[ar.PaymentDate.notna() & (ar.PaymentDate > AS_OF - pd.DateOffset(months=12))].copy()
paid["dl"] = (paid.PaymentDate - paid.DueDate).dt.days.clip(lower=0)
delay, delay_all = paid.groupby("CounterpartyCode").dl.mean(), paid.dl.mean()
oa = ar[ar.PaymentDate.isna() & (ar.InvoiceDate <= AS_OF)].copy()
oa["exp"] = oa.DueDate + pd.to_timedelta(oa.CounterpartyCode.map(delay).fillna(delay_all).round(), unit="D")
oa = oa[(AS_OF - oa.DueDate).dt.days <= 180]
oa["exp"] = oa.exp.where(oa.exp > AS_OF, AS_OF + pd.Timedelta(days=14))
oa = oa[oa.exp <= END]
fc.append(pd.DataFrame({"d": oa.exp.map(next_workday), "code": "IN01", "src": "Scadenzario clienti", "amt": oa.GrossAmount}))

op = ap[ap.PaymentDate.isna() & (ap.InvoiceDate <= AS_OF)].copy()
op["pay"] = op.DueDate.map(lambda x: AS_OF + pd.Timedelta(days=5) if x <= AS_OF
                           else (pd.Timestamp(x.year, x.month, 10) if x.day <= 10 else x + pd.offsets.MonthEnd(0)))
op = op[op.pay <= END]
fc.append(pd.DataFrame({"d": op.pay.map(next_workday), "code": np.where(op.PurchaseType == "Merce", "OU01", "OU02"),
                        "src": "Scadenzario fornitori", "amt": -op.GrossAmount}))

ly0, ly1 = AS_OF - pd.DateOffset(years=1), END - pd.DateOffset(years=1)


def growth(df):
    cur = df[(df.InvoiceDate > ly0) & (df.InvoiceDate <= AS_OF)].GrossAmount.sum()
    prev = df[(df.InvoiceDate > AS_OF - pd.DateOffset(years=2)) & (df.InvoiceDate <= ly0)].GrossAmount.sum()
    return cur / prev if prev else 1


na = ar[(ar.InvoiceDate > ly0) & (ar.InvoiceDate <= ly1) & (ar.PaymentDate <= ly1)]
fc.append(pd.DataFrame({"d": (na.PaymentDate + pd.DateOffset(years=1)).map(next_workday), "code": "IN01",
                        "src": "Stima nuove vendite", "amt": na.GrossAmount * growth(ar)}))
npur = ap[(ap.InvoiceDate > ly0) & (ap.InvoiceDate <= ly1) & (ap.PaymentDate <= ly1)]
fc.append(pd.DataFrame({"d": (npur.PaymentDate + pd.DateOffset(years=1)).map(next_workday),
                        "code": np.where(npur.PurchaseType == "Merce", "OU01", "OU02"),
                        "src": "Stima nuovi acquisti", "amt": -npur.GrossAmount * growth(ap)}))

h = t[t.TransactionDate > AS_OF - pd.DateOffset(months=6)].copy()
h["ym"] = h.TransactionDate.dt.year * 100 + h.TransactionDate.dt.month
mon = h.groupby(["CategoryCode", "ym"]).Amount.sum().reset_index()


def mavg(code, skip=()):
    x = mon[(mon.CategoryCode == code) & ~(mon.ym % 100).isin(skip)]
    return x.Amount.mean()


def hsum(code, desc=None, lo=None, hi=None):
    x = h[h.CategoryCode == code]
    if desc:
        x = x[x.Description.str.contains(desc)]
    if lo is not None:
        x = x[x.TransactionDate >= lo]
    if hi is not None:
        x = x[x.TransactionDate < hi]
    return x.Amount.sum()


eom = AS_OF + pd.offsets.MonthEnd(0)
ou07 = h[h.CategoryCode == "OU07"]
recurring = [
    ("OU03", 27, range(1, 13), mavg("OU03", (7, 12))),
    ("OU04", 16, range(1, 13), mavg("OU04", (1, 8))),
    ("OU05", 16, range(1, 13), h[(h.CategoryCode == "OU05") & h.TransactionDate.dt.day.between(15, 18)].Amount.mean()),
    ("OU07", 5, (1, 4, 7, 10), ou07[ou07.TransactionDate >= ou07.TransactionDate.max() - pd.Timedelta(days=10)].Amount.sum()),
    ("OU08", 20, (2, 4, 6, 8, 10, 12), mavg("OU08")),
    ("FI04", 1, range(1, 13), mavg("FI04")),
    ("OU09", 31, (3, 6, 9, 12), hsum("OU09", lo=eom - pd.Timedelta(days=3))),
    ("FI03", 31, (3, 6, 9, 12), hsum("FI03", "c/c", lo=eom - pd.Timedelta(days=3))),
    ("FI02", 30, (3, 6, 9, 12), hsum("FI02", "UniCredit", lo=AS_OF - pd.Timedelta(days=95), hi=AS_OF - pd.Timedelta(days=85))),
    ("FI03", 30, (3, 6, 9, 12), hsum("FI03", "UniCredit", lo=AS_OF - pd.Timedelta(days=95), hi=AS_OF - pd.Timedelta(days=85))),
]
rows = []
for code, day, months, amt in recurring:
    if pd.isna(amt):
        continue
    for x in pd.date_range(AS_OF + pd.Timedelta(days=1), END):
        if x.month in months and x.day == min(day, x.days_in_month):
            rows.append((next_workday(x), code, "Ricorrente", amt))
fc.append(pd.DataFrame(rows, columns=["d", "code", "src", "amt"]))

fc = pd.concat(fc)
fc = fc.groupby(["d", "code", "src"], as_index=False).amt.sum()
fc = fc[fc.d <= END + pd.Timedelta(days=10)]
out = pd.DataFrame({"AsOfDate": AS_OF, "DateKey": key(fc.d), "CashCategoryKey": fc.code.map(cat_key),
                    "SourceType": fc.src, "Amount": fc.amt.round(2)})
save(out, "fact_cash_forecast.csv")

# ---------------------------------------------------- parametri e lista alert
pd.DataFrame([{"MinCashThreshold": 2500000, "CreditLineUsageAlert": 70, "DSOTarget": 90,
               "OverdueRatioAlert": 10, "LiquidityDaysMin": 30}]).to_csv(os.path.join(OUT, "treasury_parameter.csv"), index=False)
pd.DataFrame({"AlertID": range(1, 7),
              "AlertName": ["Liquidità sotto soglia", "Previsione sotto soglia", "Utilizzo affidamenti",
                            "DSO oltre obiettivo", "Scaduto clienti elevato", "Giorni di autonomia"],
              "Rule": ["Cassa di gruppo < soglia minima", "Minimo previsto 13 settimane < soglia",
                       "Utilizzo fidi > % parametro", "DSO > giorni obiettivo",
                       "Scaduto / crediti aperti > % parametro", "Cassa / uscite medie giornaliere < giorni minimi"]}) \
    .to_csv(os.path.join(OUT, "alert_list.csv"), index=False)

proj = bal.sum(axis=1)[AS_OF] + out.groupby("DateKey").Amount.sum().reindex(key(pd.Series(pd.date_range(AS_OF + pd.Timedelta(days=1), END))), fill_value=0).cumsum()
print("cassa al", AS_OF.date(), round(bal.sum(axis=1)[AS_OF]), "| minimo previsto", round(proj.min()), "il", proj.idxmin())
