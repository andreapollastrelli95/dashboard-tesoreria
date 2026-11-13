# Data dictionary

## Tabelle dei fatti

### dw.FactBankTransaction - movimenti di estratto conto
| Colonna | Descrizione |
|---|---|
| TransactionID | identificativo movimento (MOV0000001) |
| DateKey | data operazione |
| BankAccountKey | conto su cui è registrato il movimento |
| SiteKey | sede a cui si riferisce l'operazione (può essere diversa dalla sede del conto: i fornitori delle filiali si pagano dalla sede centrale) |
| CashCategoryKey | categoria di cassa → sezione del rendiconto |
| CounterpartyKey | cliente, fornitore, erario, banca... (-1 per i giroconti) |
| Amount | importo con segno (+ entrata, - uscita) |
| InflowAmount / OutflowAmount | importo separato in entrata e uscita (sempre positivo) |
| Description | causale |
| DocumentReference | numero fattura collegata (incassi, pagamenti, insoluti) |

### dw.FactBankBalanceDaily - snapshot saldi
Un record per ogni giorno di calendario e ogni conto, dal 31/12/2023 (saldo di apertura) alla data di riferimento.

| Colonna | Descrizione |
|---|---|
| ClosingBalance | saldo contabile a fine giornata |
| CreditLine | affidamento di cassa del conto |
| AvailableFunds | ClosingBalance + CreditLine |

### dw.FactARInvoice / dw.FactAPInvoice - scadenzari
| Colonna | Descrizione |
|---|---|
| InvoiceNumber | numero fattura (attive: SEDE/ANNO/NUMERO, passive: FPANNO/NUMERO) |
| InvoiceDate, DueDate | data fattura e scadenza |
| PaymentDate | data incasso/pagamento; vuota se la fattura era aperta alla data di riferimento |
| NetAmount, GrossAmount | imponibile e totale documento (IVA 22%) |
| AmountPaid | importo incassato/pagato |
| IsBounced | (solo attive) RiBa tornata insoluta almeno una volta |
| PaymentDelayDays | (solo attive) giorni di ritardo rispetto alla scadenza |
| PurchaseType | (solo passive) Merce / Servizi |

### dw.FactCashForecast - previsione
| Colonna | Descrizione |
|---|---|
| AsOfDate | data di riferimento della previsione (si possono conservare più versioni) |
| DateKey | data prevista del movimento |
| SourceType | Scadenzario clienti / Scadenzario fornitori / Stima nuove vendite / Stima nuovi acquisti / Ricorrente |
| Amount | importo previsto con segno |

## Dimensioni

| Tabella | Contenuto |
|---|---|
| DimDate | calendario con giorni lavorativi e festività italiane |
| DimSite | 4 sedi con area e organico |
| DimBankAccount | 7 conti: banca, tipo conto, sede, affidamento |
| DimCounterparty | clienti (con termini e metodo di pagamento, segmento), fornitori merce e servizi, controparti istituzionali |
| DimCashCategory | 20 categorie di cassa con sezione del rendiconto (Operativa, Investimento, Finanziamento, Giroconto) |

## Tabelle di supporto

| Tabella | Contenuto |
|---|---|
| dw.TreasuryParameter | soglie degli alert: MinCashThreshold, CreditLineUsageAlert, DSOTarget, OverdueRatioAlert, LiquidityDaysMin |
| dw.RecurringCashItem | uscite ricorrenti usate dalla previsione, ricalcolate a ogni esecuzione |

## Categorie di cassa

| Codice | Categoria | Sezione |
|---|---|---|
| IN01 | Incassi da clienti | Operativa |
| IN02 | Insoluti RiBa | Operativa |
| IN03 | Altri incassi | Operativa |
| OU01 | Pagamenti fornitori merce | Operativa |
| OU02 | Pagamenti fornitori servizi | Operativa |
| OU03 | Stipendi netti | Operativa |
| OU04 | F24 contributi e ritenute | Operativa |
| OU05 | F24 IVA | Operativa |
| OU06 | F24 imposte dirette (IRES/IRAP) | Operativa |
| OU07 | Affitti | Operativa |
| OU08 | Utenze | Operativa |
| OU09 | Commissioni e spese bancarie | Operativa |
| IV01 | Investimenti (capex) | Investimento |
| FI01 | Erogazione finanziamenti | Finanziamento |
| FI02 | Rimborso quota capitale mutui | Finanziamento |
| FI03 | Interessi passivi | Finanziamento |
| FI04 | Canoni leasing | Finanziamento |
| FI05 | Dividendi distribuiti | Finanziamento |
| TR01 / TR02 | Giroconto in entrata / in uscita | Giroconto (escluso dai flussi) |

Scelta di classificazione: interessi passivi e canoni di leasing sono nella gestione finanziaria, come avviene di solito nel rendiconto gestionale (l'OIC 10 lascia la scelta per gli interessi).
