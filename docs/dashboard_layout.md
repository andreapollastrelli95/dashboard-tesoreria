# Layout della dashboard

Canvas 1920 × 1080. Struttura fissa: intestazione con navigazione, filtri, banner di stato (solo pagina di sintesi), card KPI, grafici.

Palette come negli altri progetti (blu notte `#1B2A41`, blu `#2E5C8A`, azzurro `#9DB7D5`, verde petrolio `#3A8D8C`, ambra `#E0A100`), con una regola in più: il **rosso `#C0392B` è riservato agli alert e ai saldi negativi**, il verde `#1E8E5A` alle entrate. Linee di soglia sempre tratteggiate.

## Filtri
Periodo (anno / mese) · Sede · Banca. La data di riferimento non è un filtro ma un parametro di Power Query (`AsOfDate`), mostrato come testo.

Nota: il filtro Sede agisce su movimenti e scadenzari; i saldi bancari si filtrano con il filtro Banca (un conto di sede centrale paga anche fornitori delle filiali, quindi saldo e sede non coincidono).

## Pagina 1 - Sintesi CFO
| Visual | Tipo | Misure / campi |
|---|---|---|
| Banner stato | Card con sfondo condizionale | Treasury Status, Treasury Status Color, Active Alerts |
| 6 KPI | Card | Closing Cash, Net Cash Flow, Operating Cash Flow (vs PY), Available Liquidity, DSO, DPO |
| Cassa consuntivo + previsione | Linee | Asse Calendar[Date] (ultimi 6 mesi + 13 settimane); Cash Actual and Projected; linea costante Min Cash Threshold; marker su Projected Min Cash Date |
| Flussi mensili | Colonne in pila + linea | Mese; Amount per CashCategory[CashFlowSection]; linea Net Cash Flow |
| Alert | Tabella | AlertList[AlertName], Alert Current Value, Alert Threshold, Alert Icon (colore da Alert Color) |
| Liquidità per banca | Barre | BankAccount[BankName]; Closing Cash |
| Commento | Card / narrativa intelligente | Funding Need Message + testo |

## Pagina 2 - Rendiconto
| Visual | Tipo | Misure / campi |
|---|---|---|
| Rendiconto finanziario | Matrice | Righe CashFlowSection → CategoryName; colonne Year; Net Cash Flow; righe aggiuntive Opening Cash e Closing Cash (card allineate sopra e sotto) |
| Dal saldo iniziale al finale | Cascata | CategoryGroup; Net Cash Flow |
| OCF mensile | Colonne raggruppate | Mese; Operating Cash Flow; legenda Year |

## Pagina 3 - Posizione di cassa
| Visual | Tipo | Misure / campi |
|---|---|---|
| 6 KPI | Card | Daily Cash Position, Min Daily Cash, Avg Daily Cash, Days Below Threshold, Peak Credit Line Usage %, Liquidity Days |
| Saldo giornaliero | Linee (asse continuo) | Calendar[Date]; Daily Cash Position; media mobile 30 gg; soglia; area rossa sotto soglia (banda di errore / linea costante con riempimento) |
| Saldi per conto | Tabella | BankAccount; Closing Cash, Credit Lines, Available Liquidity, Peak Credit Line Usage % |
| Utilizzo fidi | Colonne + linea | Mese; Peak Credit Line Usage % e Credit Line Usage % a fine mese; soglia 70% |

## Pagina 4 - Crediti e debiti
| Visual | Tipo | Misure / campi |
|---|---|---|
| 6 KPI | Card | Outstanding Receivables, Overdue Receivables %, Overdue > 90 Days, DSO, Outstanding Payables, Bounced RiBa |
| Aging per sede | Barre in pila | Site; OpenAmountAtAsOf per AgingBucket |
| DSO / DPO | Linee | Fine mese; DSO, DPO; obiettivo DSO |
| Clienti con più scaduto | Tabella | Counterparty; Overdue Receivables, giorni max, Avg Payment Delay (days), Bounced RiBa (Top N 10) |
| Debiti per scadenza | Colonne | fascia di scadenza fornitori; Outstanding Payables |

Drill-through dal cliente a una pagina nascosta con l'elenco fatture aperte e lo storico pagamenti.

## Pagina 5 - Previsione 13 settimane
| Visual | Tipo | Misure / campi |
|---|---|---|
| 6 KPI | Card | Forecast Opening Cash, Forecast Inflows, Forecast Outflows, Projected Cash a fine orizzonte, Projected Min Cash 13W, Funding Need 13W |
| Settimane | Colonne raggruppate + linea su asse secondario | Calendar[WeekStart] (RelativeWeek 0-13); Forecast Inflows, Forecast Outflows; Projected Cash; soglia |
| Dettaglio | Matrice | CashCategory; mese; Forecast Net Flow |
| Ipotesi | Casella di testo | metodo di stima |
