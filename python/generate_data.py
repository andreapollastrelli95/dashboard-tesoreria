# -----------------------------------------------------------------------------
# Generazione dataset simulato - Centralia Forniture S.p.A.
# Progetto: Cash Flow e Tesoreria (azienda multisede)
#
# Distributore di materiale elettrico e termoidraulico con 4 sedi
# (Milano sede centrale, Bologna, Roma, Napoli). Periodo movimenti bancari:
# 01/01/2024 - 31/12/2025. Data di riferimento per scaduto e previsioni: 31/12/2025.
#
# File prodotti:
#   sites, bank_accounts, counterparties, cash_flow_categories
#   ar_invoices (fatture attive con data incasso), ap_invoices (fatture passive)
#   bank_transactions (estratti conto), bank_opening_balances
#
# La logica segue il ciclo reale: fattura -> scadenza (RiBa / bonifico) ->
# incasso o pagamento in banca. IVA, F24, stipendi, mutui ecc. sono derivati.
# -----------------------------------------------------------------------------
import os
from datetime import date, timedelta
import calendar

import numpy as np
import pandas as pd

rng = np.random.default_rng(42)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")
os.makedirs(OUT, exist_ok=True)

AS_OF = date(2025, 12, 31)
BANK_START = date(2024, 1, 1)
INV_START = date(2023, 7, 1)        # fatture dal 2° semestre 2023 = crediti/debiti di apertura
VAT = 0.22

HOLIDAYS = {(1, 1), (1, 6), (4, 25), (5, 1), (6, 2), (8, 15), (11, 1), (12, 8), (12, 25), (12, 26),
            (4, 1, 2024), (4, 21, 2025)}  # Pasquetta 2024 e 2025


def is_bank_day(d):
    return d.weekday() < 5 and (d.month, d.day) not in HOLIDAYS and (d.month, d.day, d.year) not in HOLIDAYS


def next_bank_day(d):
    while not is_bank_day(d):
        d += timedelta(days=1)
    return d


def eom(d):
    return date(d.year, d.month, calendar.monthrange(d.year, d.month)[1])


def add_months_eom(d, months):
    m = d.month - 1 + months
    y = d.year + m // 12
    m = m % 12 + 1
    return date(y, m, calendar.monthrange(y, m)[1])


# ------------------------------------------------------------------ sedi e banche
sites = pd.DataFrame([
    ("MI", "Milano - Sede centrale", "Nord", 52, 1.00),
    ("BO", "Bologna", "Nord", 34, 0.78),
    ("RM", "Roma", "Centro", 31, 0.70),
    ("NA", "Napoli", "Sud", 23, 0.52),
], columns=["SiteCode", "SiteName", "Area", "Headcount", "SalesWeight"])

bank_accounts = pd.DataFrame([
    # code, banca, sede, tipo, fido (affidamento di cassa), saldo iniziale
    ("BK01", "Intesa Sanpaolo", "MI", "Conto corrente ordinario", 1_500_000, 1_180_000),
    ("BK02", "UniCredit",       "MI", "Conto corrente ordinario", 1_000_000,   640_000),
    ("BK03", "Banco BPM",       "MI", "Conto anticipi / RiBa",      800_000,   210_000),
    ("BK04", "BPER Banca",      "BO", "Conto corrente ordinario",   500_000,   420_000),
    ("BK05", "BNL",             "RM", "Conto corrente ordinario",   400_000,   365_000),
    ("BK06", "Credem",          "NA", "Conto corrente ordinario",   300_000,   185_000),
    ("BK07", "Banca Sella",     "MI", "Conto deposito vincolabile",       0,   400_000),
], columns=["BankAccountCode", "BankName", "SiteCode", "AccountType", "CreditLine", "OpeningBalance"])
bank_accounts["AccountName"] = bank_accounts.BankName + " - " + bank_accounts.AccountType
site_bank = {"MI": "BK01", "BO": "BK04", "RM": "BK05", "NA": "BK06"}

categories = pd.DataFrame([
    # code, nome, sezione rendiconto, direzione, gruppo
    ("IN01", "Incassi da clienti",                 "Operativa",      "Entrata", "Incassi commerciali"),
    ("IN02", "Insoluti RiBa",                      "Operativa",      "Uscita",  "Incassi commerciali"),
    ("IN03", "Altri incassi",                      "Operativa",      "Entrata", "Altri"),
    ("OU01", "Pagamenti fornitori merce",          "Operativa",      "Uscita",  "Fornitori"),
    ("OU02", "Pagamenti fornitori servizi",        "Operativa",      "Uscita",  "Fornitori"),
    ("OU03", "Stipendi netti",                     "Operativa",      "Uscita",  "Personale"),
    ("OU04", "F24 contributi e ritenute",          "Operativa",      "Uscita",  "Personale"),
    ("OU05", "F24 IVA",                            "Operativa",      "Uscita",  "Imposte"),
    ("OU06", "F24 imposte dirette (IRES/IRAP)",    "Operativa",      "Uscita",  "Imposte"),
    ("OU07", "Affitti",                            "Operativa",      "Uscita",  "Costi di struttura"),
    ("OU08", "Utenze",                             "Operativa",      "Uscita",  "Costi di struttura"),
    ("OU09", "Commissioni e spese bancarie",       "Operativa",      "Uscita",  "Oneri bancari"),
    ("IV01", "Investimenti (capex)",               "Investimento",   "Uscita",  "Investimenti"),
    ("FI01", "Erogazione finanziamenti",           "Finanziamento",  "Entrata", "Debito bancario"),
    ("FI02", "Rimborso quota capitale mutui",      "Finanziamento",  "Uscita",  "Debito bancario"),
    ("FI03", "Interessi passivi",                  "Finanziamento",  "Uscita",  "Debito bancario"),
    ("FI04", "Canoni leasing",                     "Finanziamento",  "Uscita",  "Leasing"),
    ("FI05", "Dividendi distribuiti",              "Finanziamento",  "Uscita",  "Soci"),
    ("TR01", "Giroconto in entrata",               "Giroconto",      "Entrata", "Giroconti"),
    ("TR02", "Giroconto in uscita",                "Giroconto",      "Uscita",  "Giroconti"),
], columns=["CategoryCode", "CategoryName", "CashFlowSection", "Direction", "CategoryGroup"])

# ------------------------------------------------------------------ controparti
pfx = ["Elettro", "Termo", "Idro", "Impianti", "Edil", "Clima", "Tecno", "Global", "Energia", "Casa"]
sfx = ["Service", "Sistemi", "Impianti", "Group", "Installazioni", "Tecnica", "Progetti", "Lavori", "& Figli", "Nord",
       "Sud", "Centro", "Italia", "Solar", "Point"]
forms = ["S.r.l.", "S.r.l.", "S.n.c.", "S.p.A.", "S.a.s.", "di Rossi Mario", "S.r.l.s."]
used = set()


def uname(a, b):
    while True:
        n = f"{rng.choice(a)} {rng.choice(b)} {rng.choice(forms)}"
        if n not in used:
            used.add(n)
            return n


cust_rows = []
cid = 0
for _, s in sites.iterrows():
    n = int(170 * s.SalesWeight)
    for i in range(n):
        cid += 1
        terms = rng.choice(["RIBA60FM", "RIBA90FM", "RIBA120FM", "BB30DF", "BB60DF", "RD"],
                           p=[.32, .30, .08, .12, .13, .05])
        # profilo di pagamento: 0 puntuale, 1 ritardo lieve, 2 ritardo forte, 3 problematico
        prof = rng.choice([0, 1, 2, 3], p=[.62, .25, .10, .03])
        if s.SiteCode == "NA":
            prof = rng.choice([0, 1, 2, 3], p=[.45, .32, .17, .06])
        cust_rows.append((f"CL{cid:05d}", uname(pfx, sfx), "Cliente", s.SiteCode, terms, int(prof),
                          rng.choice(["Installatore", "Impresa edile", "Rivenditore", "Industria"], p=[.48, .22, .18, .12])))
custs = pd.DataFrame(cust_rows, columns=["CounterpartyCode", "CounterpartyName", "CounterpartyType", "SiteCode",
                                         "PaymentTerms", "PaymentProfile", "CustomerSegment"])

sup_goods = ["ABB S.p.A.", "Schneider Electric S.p.A.", "BTicino S.p.A.", "Vimar S.p.A.", "Gewiss S.p.A.",
             "Prysmian Cavi e Sistemi Italia S.r.l.", "Legrand Italia S.p.A.", "Siemens S.p.A.", "Ariston S.p.A.",
             "Baxi S.p.A.", "Daikin Air Conditioning Italy S.p.A.", "Grundfos Pompe Italia S.r.l.", "Caleffi S.p.A.",
             "Giacomini S.p.A.", "Valsir S.p.A.", "Geberit Marketing e Distribuzione S.r.l.", "Philips Lighting Italy S.p.A.",
             "Disano Illuminazione S.p.A.", "Finder S.p.A.", "Hager Bocchiotti S.p.A."]
sup_serv = ["Studio Commercialista Bianchi", "Arcese Trasporti S.p.A.", "BRT S.p.A.", "Enel Energia S.p.A.",
            "A2A Energia S.p.A.", "TIM S.p.A.", "Vodafone Italia S.p.A.", "Securitas Italia S.r.l.",
            "Pulizie Industriali Emilia S.r.l.", "Zucchetti S.p.A.", "Manpower S.r.l.", "Assicurazioni Generali S.p.A.",
            "Studio Legale Moretti", "Officina Mezzi Pesanti Rossi S.r.l.", "Kuehne+Nagel S.r.l.", "Q8 Italia S.p.A."]
sup_rows = []
for i, n in enumerate(sup_goods):
    sup_rows.append((f"FO{i+1:04d}", n, "Fornitore merce", "MI", rng.choice(["BB90FM", "BB120FM", "BB60FM", "RIBA90FM"], p=[.4, .25, .2, .15]), 0, ""))
for i, n in enumerate(sup_serv):
    sup_rows.append((f"FS{i+1:04d}", n, "Fornitore servizi", rng.choice(sites.SiteCode), rng.choice(["BB30DF", "BB60DF", "RD", "BB30FM"]), 0, ""))
others = [("AL0001", "Erario - Agenzia delle Entrate", "Erario"), ("AL0002", "INPS / Enti previdenziali", "Enti"),
          ("AL0003", "Dipendenti", "Personale"), ("AL0004", "Immobiliare Lombarda S.r.l.", "Locatore"),
          ("AL0005", "Fondo Immobiliare Emilia", "Locatore"), ("AL0006", "Gestioni Immobiliari Capitolina S.r.l.", "Locatore"),
          ("AL0007", "Partenope Real Estate S.r.l.", "Locatore"), ("AL0008", "Intesa Sanpaolo - finanziamenti", "Banca"),
          ("AL0009", "UniCredit - finanziamenti", "Banca"), ("AL0010", "BNP Paribas Leasing Solutions", "Leasing"),
          ("AL0011", "Soci", "Soci"), ("AL0012", "Banca (spese e commissioni)", "Banca")]
for c, n, t in others:
    sup_rows.append((c, n, t, "MI", "", 0, ""))
counterparties = pd.concat([custs, pd.DataFrame(sup_rows, columns=custs.columns)], ignore_index=True)

# ------------------------------------------------------------------ fatture attive
season = {1: .85, 2: .95, 3: 1.08, 4: 1.05, 5: 1.12, 6: 1.10, 7: 1.08, 8: .55, 9: 1.06, 10: 1.10, 11: 1.03, 12: .90}
growth = {2023: 0.96, 2024: 1.0, 2025: 1.07}
delay_par = {0: (0, 3), 1: (12, 8), 2: (38, 15), 3: (95, 40)}

cust_by_site = {s: custs[custs.SiteCode == s].reset_index(drop=True) for s in sites.SiteCode}
cust_w = {}
for s, df in cust_by_site.items():
    w = rng.lognormal(0, 1.0, len(df))
    cust_w[s] = w / w.sum()


def due_date(inv_date, terms):
    if terms.startswith("RIBA"):
        days = int(terms[4:-2])
        return add_months_eom(inv_date, days // 30)
    if terms.startswith("BB") and terms.endswith("FM"):
        return add_months_eom(inv_date, int(terms[2:-2]) // 30)
    if terms.startswith("BB"):
        return inv_date + timedelta(days=int(terms[2:-2]))
    return inv_date  # RD rimessa diretta


ar = []
n_inv = {}
d = INV_START
while d <= AS_OF:
    if is_bank_day(d):
        for _, s in sites.iterrows():
            k = rng.poisson(13.5 * s.SalesWeight * season[d.month] * growth[d.year])
            if k == 0:
                continue
            idx = rng.choice(len(cust_by_site[s.SiteCode]), k, p=cust_w[s.SiteCode])
            for j in idx:
                c = cust_by_site[s.SiteCode].iloc[j]
                n_inv[(d.year, s.SiteCode)] = n_inv.get((d.year, s.SiteCode), 0) + 1
                net = round(float(rng.lognormal(7.75, 0.95)), 2)
                gross = round(net * (1 + VAT), 2)
                dd = next_bank_day(due_date(d, c.PaymentTerms))
                mu, sd = delay_par[c.PaymentProfile]
                delay = max(0, int(rng.normal(mu, sd))) if c.PaymentProfile else 0
                riba = c.PaymentTerms.startswith("RIBA")
                if riba and c.PaymentProfile == 0:
                    delay = 0
                pay = next_bank_day(dd + timedelta(days=delay))
                unpaid_forever = c.PaymentProfile == 3 and rng.random() < 0.35
                bounced = riba and rng.random() < (0.012 if c.PaymentProfile < 2 else 0.08)
                ar.append([f"{s.SiteCode}/{d.year}/{n_inv[(d.year, s.SiteCode)]:05d}", s.SiteCode, c.CounterpartyCode,
                           d, dd, net, gross, c.PaymentTerms, pay, unpaid_forever, bounced])
    d += timedelta(days=1)
ar = pd.DataFrame(ar, columns=["InvoiceNumber", "SiteCode", "CounterpartyCode", "InvoiceDate", "DueDate",
                               "NetAmount", "GrossAmount", "PaymentTerms", "PayPlan", "NeverPaid", "Bounced"])

# ------------------------------------------------------------------ fatture passive
ap = []
goods = counterparties[counterparties.CounterpartyType == "Fornitore merce"].reset_index(drop=True)
serv = counterparties[counterparties.CounterpartyType == "Fornitore servizi"].reset_index(drop=True)
gw = rng.lognormal(0, 0.8, len(goods)); gw /= gw.sum()
napn = 0
d = INV_START
while d <= AS_OF:
    if is_bank_day(d):
        k = rng.poisson(6.7 * season[d.month] * growth[d.year])
        for j in rng.choice(len(goods), k, p=gw):
            sp = goods.iloc[j]
            napn += 1
            net = round(float(rng.lognormal(9.35, 0.7)), 2)
            ap.append([f"FP{d.year}/{napn:06d}", sp.CounterpartyCode, rng.choice(sites.SiteCode, p=[.45, .22, .2, .13]),
                       d, next_bank_day(due_date(d, sp.PaymentTerms)), net, round(net * (1 + VAT), 2), sp.PaymentTerms, "Merce"])
        for _ in range(rng.poisson(2.2)):
            sp = serv.iloc[rng.integers(len(serv))]
            napn += 1
            net = round(float(rng.lognormal(6.6, 0.8)), 2)
            ap.append([f"FP{d.year}/{napn:06d}", sp.CounterpartyCode, sp.SiteCode,
                       d, next_bank_day(due_date(d, sp.PaymentTerms)), net, round(net * (1 + VAT), 2), sp.PaymentTerms, "Servizi"])
    d += timedelta(days=1)
ap = pd.DataFrame(ap, columns=["InvoiceNumber", "CounterpartyCode", "SiteCode", "InvoiceDate", "DueDate",
                               "NetAmount", "GrossAmount", "PaymentTerms", "PurchaseType"])

# pagamenti fornitori: bonifici raggruppati il 10 e a fine mese (prima data utile >= scadenza);
# nei mesi di tensione di cassa (luglio, agosto, dicembre) parte dei pagamenti slitta di 10-25 giorni
def pay_run(due):
    if due.day <= 10:
        t = date(due.year, due.month, 10)
    else:
        t = eom(due)
    return next_bank_day(t)


apPayPlan = []
for r in ap.itertuples():
    p = pay_run(r.DueDate)
    if p.month in (7, 8, 12) and rng.random() < 0.30:
        p = next_bank_day(p + timedelta(days=int(rng.integers(10, 26))))
    if r.PurchaseType == "Merce" and rng.random() < 0.04:
        p = next_bank_day(p + timedelta(days=int(rng.integers(15, 45))))   # contestazioni
    apPayPlan.append(p)
ap["PayPlan"] = apPayPlan

# ------------------------------------------------------------------ movimenti bancari
tx = []


def add(d, bank, site, cat, cp, amount, desc, ref=""):
    if BANK_START <= d <= AS_OF:
        tx.append((d, bank, site, cat, cp, round(float(amount), 2), desc, ref))


# incassi clienti (RiBa salvo buon fine sul conto RiBa per MI, sul conto di sede per le altre)
for r in ar.itertuples():
    if r.NeverPaid:
        continue
    bank = "BK03" if (r.SiteCode == "MI" and r.PaymentTerms.startswith("RIBA")) else site_bank[r.SiteCode]
    pay = r.PayPlan
    if r.Bounced:
        add(r.DueDate, bank, r.SiteCode, "IN01", r.CounterpartyCode, r.GrossAmount, "Accredito RiBa s.b.f.", r.InvoiceNumber)
        bd = next_bank_day(r.DueDate + timedelta(days=int(rng.integers(8, 15))))
        add(bd, bank, r.SiteCode, "IN02", r.CounterpartyCode, -r.GrossAmount, "Insoluto RiBa", r.InvoiceNumber)
        add(next_bank_day(bd + timedelta(days=9)), bank, r.SiteCode, "OU09", "AL0012", -round(rng.uniform(6, 12), 2), "Spese insoluto", r.InvoiceNumber)
        pay = next_bank_day(bd + timedelta(days=int(rng.integers(20, 60))))
        ar.loc[r.Index, "PayPlan"] = pay
        add(pay, site_bank[r.SiteCode], r.SiteCode, "IN01", r.CounterpartyCode, r.GrossAmount, "Bonifico a saldo insoluto", r.InvoiceNumber)
    else:
        desc = "Accredito RiBa s.b.f." if r.PaymentTerms.startswith("RIBA") else "Bonifico da cliente"
        add(pay, bank, r.SiteCode, "IN01", r.CounterpartyCode, r.GrossAmount, desc, r.InvoiceNumber)

# pagamenti fornitori (dalla sede centrale, Intesa 60% / UniCredit 40%)
for r in ap.itertuples():
    bank = "BK01" if rng.random() < 0.6 else "BK02"
    if r.PurchaseType == "Servizi" and r.SiteCode != "MI":
        bank = site_bank[r.SiteCode]
    add(r.PayPlan, bank, r.SiteCode if bank not in ("BK01", "BK02") else "MI",
        "OU01" if r.PurchaseType == "Merce" else "OU02", r.CounterpartyCode, -r.GrossAmount,
        "Bonifico fornitore", r.InvoiceNumber)

# personale: costo aziendale medio, netti il 27, F24 il 16 del mese dopo
avg_gross = {"MI": 3150, "BO": 2900, "RM": 2850, "NA": 2700}   # retribuzione lorda mensile media
months = pd.period_range("2023-12", "2025-12", freq="M")
for m in months:
    y, mo = m.year, m.month
    inc = 1.0 if y < 2025 else 1.028       # rinnovo CCNL commercio
    for s in sites.itertuples():
        hc = s.Headcount + (2 if (y == 2025 and s.SiteCode == "BO") else 0)
        gross = hc * avg_gross[s.SiteCode] * inc * rng.normal(1, 0.01)
        mult = 1.0
        if mo == 7: mult = 2.0     # 14esima
        if mo == 12: mult = 2.0    # 13esima
        net = gross * mult * 0.69
        pay_d = next_bank_day(date(y, mo, 27))
        add(pay_d, "BK01", s.SiteCode, "OU03", "AL0003", -net, f"Stipendi {m.strftime('%m/%Y')} - {s.SiteName}")
        # F24 del mese successivo: ritenute IRPEF + contributi dipendente + contributi azienda
        f24 = gross * mult * (0.31 + 0.30)
        f24_d = next_bank_day(date(y + (mo == 12), mo % 12 + 1, 16))
        add(f24_d, "BK01", s.SiteCode, "OU04", "AL0002", -f24, f"F24 contributi e ritenute {m.strftime('%m/%Y')} - {s.SiteCode}")

# IVA mensile: liquidazione del mese precedente, versamento il 16
ar["YM"] = ar.InvoiceDate.map(lambda x: (x.year, x.month))
ap["YM"] = ap.InvoiceDate.map(lambda x: (x.year, x.month))
iva_deb = (ar.groupby("YM").GrossAmount.sum() - ar.groupby("YM").NetAmount.sum())
iva_cred = (ap.groupby("YM").GrossAmount.sum() - ap.groupby("YM").NetAmount.sum())
credit_carry = 0.0
for ym in sorted(iva_deb.index):
    y, mo = ym
    bal = iva_deb.get(ym, 0) - iva_cred.get(ym, 0) - credit_carry
    if bal > 0:
        add(next_bank_day(date(y + (mo == 12), mo % 12 + 1, 16)), "BK01", "MI", "OU05", "AL0001", -bal, f"F24 IVA {mo:02d}/{y}")
        credit_carry = 0
    else:
        credit_carry = -bal
# acconto IVA dicembre (27/12)
for y in (2024, 2025):
    add(next_bank_day(date(y, 12, 27)), "BK01", "MI", "OU05", "AL0001", -round(rng.uniform(230000, 280000), 2), f"F24 acconto IVA {y}")

# imposte dirette: saldo + primo acconto a giugno, secondo acconto a novembre
for y, (giu, nov) in {2024: (520_000, 410_000), 2025: (585_000, 450_000)}.items():
    add(next_bank_day(date(y, 6, 30)), "BK01", "MI", "OU06", "AL0001", -giu, f"F24 saldo e I acconto IRES/IRAP {y}")
    add(next_bank_day(date(y, 11, 30)), "BK01", "MI", "OU06", "AL0001", -nov, f"F24 II acconto IRES/IRAP {y}")

# affitti trimestrali anticipati, utenze bimestrali, leasing mensile, commissioni trimestrali
rent = {"MI": ("AL0004", 96_000), "BO": ("AL0005", 61_000), "RM": ("AL0006", 58_000), "NA": ("AL0007", 39_000)}
for y in (2024, 2025):
    for q in (1, 4, 7, 10):
        for s, (cp, amt) in rent.items():
            add(next_bank_day(date(y, q, 5)), site_bank[s], s, "OU07", cp, -amt * (1.012 if y == 2025 else 1), f"Canone locazione {q//3+1}T {y}")
    for mo in range(1, 13):
        for s in sites.SiteCode:
            if mo % 2 == 0:
                add(next_bank_day(date(y, mo, 20)), site_bank[s], s, "OU08", "FS0004", -rng.uniform(5500, 9500) * sites.set_index("SiteCode").SalesWeight[s],
                    "Addebito SDD utenze")
        add(next_bank_day(date(y, mo, 1)), "BK02", "MI", "FI04", "AL0010", -18_450 if y == 2024 else -22_900, f"Canone leasing automezzi {mo:02d}/{y}")
    for q in (3, 6, 9, 12):
        for b in ("BK01", "BK02", "BK03", "BK04", "BK05", "BK06"):
            add(eom(date(y, q, 1)), b, bank_accounts.set_index("BankAccountCode").SiteCode[b], "OU09", "AL0012",
                -rng.uniform(450, 1900), "Competenze e spese trimestrali")
            add(eom(date(y, q, 1)), b, bank_accounts.set_index("BankAccountCode").SiteCode[b], "FI03", "AL0012",
                -rng.uniform(800, 6500), "Interessi passivi c/c")

# mutui: rata semestrale (Intesa, residuo 2,4 M) + nuovo finanziamento UniCredit 2 M a marzo 2025
for y in (2024, 2025):
    for mo in (6, 12):
        add(next_bank_day(date(y, mo, 30 if mo == 6 else 31)), "BK01", "MI", "FI02", "AL0008", -300_000, "Mutuo chirografario - quota capitale")
        add(next_bank_day(date(y, mo, 30 if mo == 6 else 31)), "BK01", "MI", "FI03", "AL0008", -round(48_000 * (1.1 if y == 2024 else 0.92), 2), "Mutuo chirografario - quota interessi")
add(next_bank_day(date(2025, 3, 14)), "BK02", "MI", "FI01", "AL0009", 2_000_000, "Erogazione finanziamento 60 mesi - nuovo magazzino Bologna")
for mo in (6, 9, 12):
    add(next_bank_day(date(2025, mo, 30 if mo != 12 else 31)), "BK02", "MI", "FI02", "AL0009", -100_000, "Finanziamento UniCredit - quota capitale")
    add(next_bank_day(date(2025, mo, 30 if mo != 12 else 31)), "BK02", "MI", "FI03", "AL0009", -round(25_000 - mo * 400, 2), "Finanziamento UniCredit - quota interessi")

# capex: scaffalature e carrelli nuovo magazzino Bologna (2025), furgoni, IT
capex = [(date(2024, 2, 20), "BK01", "MI", -86_000, "Server e licenze ERP"),
         (date(2024, 9, 12), "BK02", "MI", -64_500, "Acquisto carrelli elevatori"),
         (date(2025, 4, 10), "BK02", "BO", -720_000, "Scaffalature e impianti magazzino Bologna - SAL 1"),
         (date(2025, 6, 18), "BK02", "BO", -540_000, "Scaffalature e impianti magazzino Bologna - SAL 2"),
         (date(2025, 9, 25), "BK04", "BO", -185_000, "Impianto fotovoltaico Bologna"),
         (date(2025, 11, 6), "BK01", "MI", -48_000, "Rinnovo hardware sedi")]
for d_, b, s, a, desc in capex:
    add(next_bank_day(d_), b, s, "IV01", "AL0011" if False else "FS0010", a, desc)

# dividendi
add(next_bank_day(date(2024, 5, 28)), "BK01", "MI", "FI05", "AL0011", -600_000, "Distribuzione utile 2023")
add(next_bank_day(date(2025, 5, 28)), "BK01", "MI", "FI05", "AL0011", -750_000, "Distribuzione utile 2024")

# altri incassi (rimborsi assicurativi, contributi GSE, vendita cespiti)
for d_, b, s, a, desc in [(date(2024, 4, 15), "BK01", "MI", 18_400, "Rimborso sinistro"),
                          (date(2024, 10, 3), "BK02", "MI", 22_000, "Vendita automezzo usato"),
                          (date(2025, 7, 22), "BK04", "BO", 31_500, "Credito d'imposta beni strumentali - compensazione")]:
    add(next_bank_day(d_), b, s, "IN03", "AL0012", a, desc)

tx = pd.DataFrame(tx, columns=["TransactionDate", "BankAccountCode", "SiteCode", "CategoryCode", "CounterpartyCode",
                               "Amount", "Description", "DocumentReference"])

# giroconti: ogni venerdi' le sedi trasferiscono alla sede centrale l'eccedenza oltre 250k,
# e il conto RiBa (BK03) viene azzerato su Intesa; la sede centrale copre le sedi in rosso
bal = bank_accounts.set_index("BankAccountCode").OpeningBalance.astype(float).to_dict()
tx = tx.sort_values("TransactionDate").reset_index(drop=True)
daily = tx.groupby(["TransactionDate", "BankAccountCode"]).Amount.sum()
gc = []
d = BANK_START
while d <= AS_OF:
    for b in bal:
        bal[b] += daily.get((d, b), 0.0)
    if d.weekday() == 4 and is_bank_day(d):
        for b, s in (("BK04", "BO"), ("BK05", "RM"), ("BK06", "NA"), ("BK03", "MI")):
            target = 250_000 if b != "BK03" else 50_000
            amt = round(bal[b] - target, -3)
            if abs(amt) >= 20_000:
                src, dst = (b, "BK01") if amt > 0 else ("BK01", b)
                a = abs(amt)
                gc.append((d, src, s if src == b else "MI", "TR02", "", -a, "Giroconto a " + dst, ""))
                gc.append((d, dst, "MI" if dst == "BK01" else s, "TR01", "", a, "Giroconto da " + src, ""))
                bal[src] -= a; bal[dst] += a
    # bilanciamento giornaliero tra i due conti principali della sede
    if is_bank_day(d):
        if bal["BK02"] < -150_000:
            a = round(-bal["BK02"] + 50_000, -3)
            gc += [(d, "BK01", "MI", "TR02", "", -a, "Giroconto a BK02", ""), (d, "BK02", "MI", "TR01", "", a, "Giroconto da BK01", "")]
            bal["BK01"] -= a; bal["BK02"] += a
        if bal["BK01"] < -400_000 and bal["BK07"] > 0:
            a = min(bal["BK07"], round(-bal["BK01"], -3))
            gc += [(d, "BK07", "MI", "TR02", "", -a, "Svincolo deposito", ""), (d, "BK01", "MI", "TR01", "", a, "Giroconto da deposito", "")]
            bal["BK07"] -= a; bal["BK01"] += a
    d += timedelta(days=1)
tx = pd.concat([tx, pd.DataFrame(gc, columns=tx.columns)], ignore_index=True)
tx = tx.sort_values(["TransactionDate", "BankAccountCode", "Amount"]).reset_index(drop=True)
tx["ValueDate"] = tx.TransactionDate
tx.insert(0, "TransactionID", [f"MOV{i:07d}" for i in range(1, len(tx) + 1)])

# ------------------------------------------------------------------ stato fatture alla data di riferimento
ar["PaymentDate"] = ar.apply(lambda r: None if (r.NeverPaid or r.PayPlan > AS_OF) else r.PayPlan, axis=1)
ar["AmountPaid"] = np.where(ar.PaymentDate.isna(), 0.0, ar.GrossAmount)
ar["IsBounced"] = ar.Bounced.astype(int)
ap["PaymentDate"] = ap.PayPlan.where(ap.PayPlan <= AS_OF, None)
ap["AmountPaid"] = np.where(ap.PaymentDate.isna(), 0.0, ap.GrossAmount)

ar_out = ar[["InvoiceNumber", "SiteCode", "CounterpartyCode", "InvoiceDate", "DueDate", "NetAmount", "GrossAmount",
             "PaymentTerms", "PaymentDate", "AmountPaid", "IsBounced"]]
ap_out = ap[["InvoiceNumber", "SiteCode", "CounterpartyCode", "InvoiceDate", "DueDate", "NetAmount", "GrossAmount",
             "PaymentTerms", "PurchaseType", "PaymentDate", "AmountPaid"]]

bank_open = bank_accounts[["BankAccountCode"]].assign(BalanceDate="2023-12-31", Balance=bank_accounts.OpeningBalance)

sites.drop(columns="SalesWeight").to_csv(os.path.join(OUT, "sites.csv"), index=False)
bank_accounts[["BankAccountCode", "AccountName", "BankName", "SiteCode", "AccountType", "CreditLine"]].to_csv(
    os.path.join(OUT, "bank_accounts.csv"), index=False)
bank_open.to_csv(os.path.join(OUT, "bank_opening_balances.csv"), index=False)
counterparties.drop(columns="PaymentProfile").to_csv(os.path.join(OUT, "counterparties.csv"), index=False)
categories.to_csv(os.path.join(OUT, "cash_flow_categories.csv"), index=False)
ar_out.to_csv(os.path.join(OUT, "ar_invoices.csv"), index=False)
ap_out.to_csv(os.path.join(OUT, "ap_invoices.csv"), index=False)
tx[["TransactionID", "TransactionDate", "ValueDate", "BankAccountCode", "SiteCode", "CategoryCode", "CounterpartyCode",
    "Amount", "Description", "DocumentReference"]].to_csv(os.path.join(OUT, "bank_transactions.csv"), index=False)

print("fatture attive", len(ar_out), " passive", len(ap_out), " movimenti", len(tx))
t = tx.copy(); t["y"] = pd.to_datetime(t.TransactionDate).dt.year
print(t.merge(categories, on="CategoryCode").pivot_table(index="CashFlowSection", columns="y", values="Amount", aggfunc="sum").round(0))
print("saldo finale", round(bank_accounts.OpeningBalance.sum() + tx.Amount.sum()), {k: round(v) for k, v in bal.items()})
