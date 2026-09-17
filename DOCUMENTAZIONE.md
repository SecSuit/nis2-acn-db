# DOCUMENTAZIONE TECNICA — Registro NIS2/ACN

**Project Work — Informatica per le Aziende Digitali (L-31)**
Tema n. 2: Privacy e Sicurezza Aziendale — Traccia PW 19

**Standard di riferimento**

- Regolamento di esecuzione (UE) 2024/2690 del 17 ottobre 2024 — punti 12.3
  (campi minimi dell'inventario), 12.4 (proprietario dell'attivo), 14 (supply chain)
- D.Lgs. 4 settembre 2024, n. 138 (recepimento NIS2) — artt. 3, 6, 23–25
- ACN, Determinazione n. 164179 del 14 aprile 2025, aggiornata dalle
  Determinazioni n. 379887 e n. 379907 del 2025
- Regolamento (UE) 2016/679 (GDPR) — artt. 9, 28, 44

---

## 1. Struttura del repository

| File | Contenuto |
|---|---|
| `01_schema.sql` | 20 tabelle, vincoli, FK composite multi-tenant, indici, trigger di immutabilita |
| `02_trigger_versioning.sql` | Trigger BEFORE UPDATE, trigger di timestamp, stored procedure, `fn_storia_asset` |
| `03_dati_test.sql` | Dataset simulato — 2 organizzazioni NIS2 essenziali |
| `04_query_acn.sql` | 6 query analitiche, 4 view CSV, `fn_csv_quote`, `fn_esporta_profilo_acn` |
| `05_deploy_test.sql` | Ruoli e privilegi, 17 test automatici, riepilogo del registro |
| `DOCUMENTAZIONE.md` | Questo file |
| `README.md` | Guida rapida di installazione |
| `ERD_nis2_ACN.mmd` | Sorgente Mermaid del diagramma ER (20 entita) |
| `ERD_nis2_ACN.png` | Render del diagramma ER, generato da mermaid.live |
| `LICENSE` | MIT |
| `.gitignore` | Esclude credenziali, export CSV con dati personali, dump |

Il diagramma ER e mantenuto come **sorgente testuale** e non come sola immagine:
il file `.mmd` e diffabile, quindi ogni modifica allo schema produce una
differenza leggibile nella cronologia Git, mentre il PNG e un artefatto
rigenerabile incollando il sorgente su <https://mermaid.live> ed esportando
l'immagine.

---

## 2. Deploy

### 2.1 Prerequisiti

- PostgreSQL 15+ (sviluppato su 18, verificato su 16). Nessuna estensione richiesta.
- psql CLI oppure pgAdmin 4.

### 2.2 Installazione

```bash
createdb -U postgres nis2_acn
psql -U postgres -d nis2_acn -f 01_schema.sql
psql -U postgres -d nis2_acn -f 02_trigger_versioning.sql
psql -U postgres -d nis2_acn -f 03_dati_test.sql
psql -U postgres -d nis2_acn -f 04_query_acn.sql
psql -U postgres -d nis2_acn -f 05_deploy_test.sql

# Password impostate fuori dal controllo di versione
psql -U postgres -d nis2_acn -c "ALTER ROLE nis2_app      PASSWORD '<password_sicura>';"
psql -U postgres -d nis2_acn -c "ALTER ROLE nis2_readonly PASSWORD '<password_readonly>';"
```

### 2.3 Idempotenza

`01_schema.sql` inizia con un blocco `DROP VIEW / FUNCTION / PROCEDURE / TABLE
IF EXISTS ... CASCADE`: l'intera sequenza puo essere rieseguita su un database
esistente senza errori, ricreando lo schema da zero. La proprieta e stata
verificata eseguendo due volte di seguito i cinque script sullo stesso database.

---

## 3. Struttura dello schema (20 tabelle in 4 zone)

| Zona | N. | Tabelle | Ruolo |
|---|---|---|---|
| Lookup / Dominio | 7 | `tipo_asset`, `livello_criticita`, `settore_nis2`, `tipo_soggetto`, `tipo_servizio`, `tipo_dipendenza`, `ruolo_organizzativo` | Valori controllati con `UNIQUE` su codice |
| Entita principali | 6 | `organizzazione`, `asset`, `servizio`, `fornitore`, `dipendenza`, `responsabile` | Core del profilo ACN |
| Junction N:M | 5 | `asset_servizio`, `asset_dipendenza`, `servizio_dipendenza`, `asset_responsabile`, `servizio_responsabile` | Relazioni con attributi propri e isolamento multi-tenant |
| Storico / Audit | 2 | `asset_storico`, `servizio_storico` | Snapshot append-only, `ON DELETE RESTRICT` |

### 3.1 Nota normativa — `settore_nis2.allegato`

| Allegato | Contenuto |
|---|---|
| I | Settori ad alta criticita (energia, trasporti, sanita, banche, infrastrutture digitali, acqua) |
| II | Altri settori critici (manifatturiero, ricerca, servizi postali, rifiuti) |
| III | Pubblica Amministrazione centrale |
| IV | Altri soggetti |

L'allegato **non** coincide con la classificazione essenziale/importante, che
dipende dall'**incrocio settore × dimensione aziendale**:

- grande impresa (≥ 250 dipendenti **oppure** fatturato > 50 M€ **e** totale di
  bilancio > 43 M€, ai sensi della Raccomandazione 2003/361/CE) in Allegato I →
  soggetto **essenziale**;
- media impresa nello stesso settore → soggetto **importante**;
- sono essenziali a prescindere dalla dimensione, tra gli altri, i soggetti
  critici ex Dir. (UE) 2022/2557, i prestatori di servizi fiduciari qualificati,
  i gestori di registri TLD e fornitori di servizi DNS, le PA centrali.

Per questo lo schema mantiene `dimensione` e `id_tipo_soggetto` come attributi
distinti: il secondo e la classificazione dichiarata e verificata da ACN, il
primo e il dato dimensionale che la giustifica.

---

## 4. Data dictionary — entita principali

### 4.1 `organizzazione`

| Campo | Tipo | Vincoli | Significato |
|---|---|---|---|
| `id` | SERIAL | PK | Chiave surrogata |
| `codice_fiscale` | VARCHAR(16) | UNIQUE NOT NULL | CF o P.IVA del soggetto |
| `denominazione` | VARCHAR(255) | NOT NULL | Ragione sociale |
| `id_settore_nis2` | INTEGER | FK | Allegato I–IV |
| `id_tipo_soggetto` | INTEGER | FK | ESSENZIALE / IMPORTANTE |
| `dimensione` | VARCHAR(10) | CHECK | MICRO / PICCOLA / MEDIA / GRANDE |
| `numero_dipendenti`, `fatturato_mln_eur` | INTEGER, NUMERIC | — | Dati dimensionali a supporto della classificazione |
| `numero_registrazione_acn` | VARCHAR(50) | **UNIQUE** | Chiave logica di export ACN: un profilo per codice |
| `attiva` | BOOLEAN | DEFAULT TRUE | Cessazione logica; le view filtrano `attiva = TRUE` |

### 4.2 `asset` — conforme al Reg. (UE) 2024/2690 punto 12.3

| Campo | Tipo | Vincoli | Riferimento normativo |
|---|---|---|---|
| `codice_interno` | VARCHAR(100) | UNIQUE per organizzazione | §12.3 *identifier* |
| `nome`, `descrizione` | VARCHAR, TEXT | NOT NULL / — | §12.3 *description* |
| `id_tipo_asset` | INTEGER | FK | §12.3 *type* — HW/SW/DATO/RETE/CLOUD/FISICO/IOT |
| `id_livello_criticita` | INTEGER | FK | §12.2 *classification* — scala 1–5 |
| `ubicazione` | VARCHAR(255) | — | §12.3 *location* |
| `indirizzo_ip` | INET | — | Tipo nativo PostgreSQL: validazione IPv4/IPv6 e operatori CIDR |
| `hostname`, `sistema_operativo` | VARCHAR | — | Identificazione tecnica |
| `data_ultima_patch` | DATE | — | **§12.3 *patch dates*** |
| `stato_valutazione_rischio` | VARCHAR(30) | CHECK 5 valori | **§12.3 *risk assessment status*** |
| `data_fine_vita` | DATE | CHECK > acquisizione | §12.3 *end of life* |
| `in_produzione` | BOOLEAN | NOT NULL | Cessazione logica |
| `versione_record` | INTEGER | NOT NULL DEFAULT 1 | Incrementato dal trigger di versioning |

Il *proprietario dell'attivo* richiesto dal punto **12.4** non e un campo di
`asset` ma una relazione temporale in `asset_responsabile`
(`tipo_responsabilita = 'PROPRIETARIO'`, `data_fine IS NULL`): questo consente di
ricostruire chi era responsabile di un asset a una data passata, cosa che un
semplice campo `owner` non permetterebbe.

### 4.3 `servizio`

| Campo | Tipo | Vincoli | Note |
|---|---|---|---|
| `rto_minuti` | INTEGER | CHECK ≥ 0 | Recovery Time Objective in **minuti** |
| `rpo_minuti` | INTEGER | CHECK ≥ 0 | Recovery Point Objective in **minuti**; 0 = nessuna perdita tollerata |
| `disponibilita_target` | NUMERIC(6,3) | CHECK 0–100 | Obiettivo interno di disponibilita |
| `dati_personali` | BOOLEAN | NOT NULL | Determina obblighi DPA e notifica violazioni |
| `classificazione_dati` | VARCHAR(20) | CHECK | PUBBLICO / INTERNO / RISERVATO / CONFIDENZIALE / DATI_PARTICOLARI |
| `versione_record` | INTEGER | NOT NULL DEFAULT 1 | Versioning automatico |

**Unita di misura.** RTO e RPO sono espressi in minuti e non in ore: con la
granularita oraria, `RPO = 0` non sarebbe distinguibile da `RPO = 59 minuti`.
Su impianti OT/SCADA in esercizio la differenza e un requisito operativo reale,
ed e il caso che il dataset usa come esempio (`SRV-SDS-001`: RTO 60 min, RPO 0 min).

**Classificazione.** Il valore `SEGRETO` e stato rimosso perche appartiene alla
classifica di segretezza statale (L. 124/2007), non applicabile a soggetti
privati. Al suo posto `DATI_PARTICOLARI` identifica i dati di cui all'art. 9
GDPR (sanitari, genetici, biometrici) e `CONFIDENZIALE` il livello aziendale
piu elevato.

### 4.4 `dipendenza` — supply chain

| Campo | Tipo | Note |
|---|---|---|
| `codice_interno` | VARCHAR(50) UNIQUE per org | Chiave logica stabile |
| `id_fornitore`, `id_tipo_dipendenza` | INTEGER FK | — |
| `paesi_elaborazione_dati` | TEXT | GDPR art. 44 — trasferimenti verso paesi terzi |
| `dpa_firmato` | BOOLEAN NOT NULL | GDPR art. 28 — anomalia se FALSE su criticita ≥ ALTO |
| `sla_disponibilita` | NUMERIC(6,3) | SLA contrattuale, confrontabile con RTO/RPO dei servizi dipendenti |

### 4.5 `responsabile`

| Campo | Tipo | Note |
|---|---|---|
| `email` | VARCHAR(255) UNIQUE NOT NULL | Chiave logica usata negli INSERT delle junction |
| `id_ruolo` | INTEGER FK | CISO, DPO, RSPP, RESP_ICT, REFERENTE_NIS2, AMM_SISTEMA, LEGALE |
| `data_inizio` / `data_fine` | DATE | `data_fine IS NULL` = incarico in corso (SCD di tipo 2 sull'incarico) |

---

## 5. Isolamento multi-tenant nelle junction table

Il registro ospita piu soggetti NIS2 nello stesso database. Senza vincoli
specifici nulla impedirebbe di collegare un asset dell'organizzazione A a un
servizio dell'organizzazione B — un data leak a livello di modello, oltre che un
errore di integrita.

La soluzione adottata e dichiarativa, senza codice applicativo:

1. ogni entita principale espone `UNIQUE (id, id_organizzazione)`
   (`uk_asset_id_org`, `uk_servizio_id_org`, `uk_dipendenza_id_org`, `uk_resp_id_org`);
2. ogni junction table porta l'organizzazione di **entrambi** i lati e dichiara
   due **FK composite**:

```sql
FOREIGN KEY (id_asset,    id_asset_org)    REFERENCES asset(id,    id_organizzazione),
FOREIGN KEY (id_servizio, id_servizio_org) REFERENCES servizio(id, id_organizzazione),
CONSTRAINT ck_as_same_org CHECK (id_asset_org = id_servizio_org)
```

Il `CHECK` blocca il collegamento fra organizzazioni diverse; le FK composite
impediscono di aggirarlo dichiarando un'organizzazione falsa, perche la coppia
(id, organizzazione) non esisterebbe nella tabella referenziata. Entrambi i
percorsi sono verificati dal Test 15.

---

## 6. Versioning e immutabilita dello storico

### 6.1 Pattern snapshot-on-write

```sql
SELECT set_config('app.motivo_modifica', 'Rivalutazione risk assessment Q3', false);

UPDATE asset
SET id_livello_criticita = (SELECT id FROM livello_criticita WHERE codice = 'CRITICO'),
    modificato_da = 'e.rossi@zagara-neuro.it'
WHERE codice_interno = 'AST-HW-001';
-- il trigger archivia automaticamente la versione precedente in asset_storico
```

Il trigger `BEFORE UPDATE ... WHEN (OLD.* IS DISTINCT FROM NEW.*)` si attiva solo
in caso di modifica reale, evitando righe fantasma da UPDATE ridondanti; il
motivo della modifica e letto dalla variabile di sessione (GUC)
`app.motivo_modifica`, mantenendo separati il dato (`note_sicurezza`) e il
metadato di audit (`motivo_modifica`).

Lo snapshot archivia **tutti** i campi dell'inventario, inclusi
`data_ultima_patch` e `stato_valutazione_rischio`: senza di essi non sarebbe
possibile dimostrare ad ACN lo stato di patching di un asset a una data passata,
che e l'uso concreto dell'audit trail in sede di ispezione (Test 13).

Alternative valutate e scartate: colonna JSON con lo storico incorporato (rompe
la 1NF e complica le query storiche) e flag `is_current` su tabella unica
(richiede UPDATE su righe esistenti e complica gli indici).

### 6.2 Tre livelli di protezione dell'audit trail

| Livello | Meccanismo | Test |
|---|---|---|
| 1 | `REVOKE UPDATE, DELETE ON asset_storico, servizio_storico FROM nis2_app` | — |
| 2 | Trigger `fn_blocca_modifica_storico()` BEFORE UPDATE OR DELETE — solleva `AUDIT_TRAIL_IMMUTABLE` anche per l'owner del database | 7a, 7b |
| 3 | `ON DELETE RESTRICT` sulle FK `asset_storico.id_asset` e `servizio_storico.id_servizio`: cancellare l'entita non ne distrugge la storia | 7c |

**Limitazione nota.** Un superuser PostgreSQL o il table owner possono rimuovere
i trigger e modificare lo storico. Per tamper-evidence completa servono
hash-chaining (SHA-256 della riga precedente) oppure WAL shipping verso un host
separato di sola lettura. Il limite e dichiarato esplicitamente e non aggirato.

> In PostgreSQL le tabelle create in futuro non concedono alcun privilegio per
> default: un `ALTER DEFAULT PRIVILEGES ... REVOKE` sarebbe un'istruzione priva
> di effetto, perche si puo revocare solo una GRANT di default mai definita.

---

## 7. Normalizzazione — verifica e trade-off

| Forma | Verifica nello schema | Trade-off deliberato |
|---|---|---|
| **1NF** | Tutti gli attributi contengono valori atomici | `normative_applicabili`, `certificazioni` e `paesi_elaborazione_dati` sono TEXT con separatore: la normalizzazione aggiungerebbe tre tabelle e due JOIN per ogni export, senza valore pratico per il profilo ACN |
| **2NF** | PK surrogata SERIAL sulle entita; nelle junction la PK composita e minimale e l'unico attributo non chiave (`note`) dipende dall'intera chiave | In `asset_servizio` `tipo_relazione` e parte della PK: lo stesso asset puo relazionarsi allo stesso servizio con ruoli diversi (SUPPORTA e OSPITA) |
| **3NF** | Nessuna dipendenza transitiva: le tabelle di lookup eliminano quelle che esisterebbero con valori testuali inline | `dimensione` non e derivata da `numero_dipendenti`: e il dato dichiarato e verificato da ACN, mantenuto esplicito per auditabilita |
| **BCNF** | `livello_criticita` ha due candidate key, `id` (PK) e `livello` (UNIQUE); `etichetta` dipende da entrambe. Poiche ogni determinante e una candidate key, la BCNF e rispettata | Nessuno |

### Denormalizzazioni consapevoli

- Le view `vw_profilo_acn_*` denormalizzano per l'output CSV senza alterare lo
  schema sottostante.
- Le tabelle `*_storico` replicano le colonne della tabella principale: e la
  condizione necessaria perche lo snapshot sia immutabile e autosufficiente.
- Le junction table replicano `id_organizzazione` di entrambi i lati: ridondanza
  introdotta di proposito per rendere dichiarativo il vincolo di isolamento
  multi-tenant (§5).

---

## 8. Strategia di indicizzazione

| Indice | Tipo | Condizione | Motivazione |
|---|---|---|---|
| `uk_responsabile_ruolo_attivo` | UNIQUE parziale | `WHERE data_fine IS NULL` | Un solo responsabile attivo per ruolo/organizzazione: vincolo di integrita dichiarativo, piu efficiente e auto-documentante di un trigger |
| `uk_asset_resp_attivo` | UNIQUE parziale | `WHERE data_fine IS NULL` | Un solo proprietario attivo per asset |
| `idx_asset_org_criticita` | B-Tree composito parziale | `WHERE in_produzione` | Copre il filtro per organizzazione e l'ordinamento per criticita della query di profilo ACN |
| `idx_asset_cessati` | B-Tree parziale | `WHERE NOT in_produzione` | Vedi nota seguente |
| `idx_servizio_attivo`, `idx_dipendenza_attiva` | B-Tree parziali | `WHERE ... = TRUE` | Filtri frequenti nelle view di export |

**Nota critica sugli indici parziali.** Un indice `WHERE in_produzione = TRUE`
indicizzerebbe circa il 100% delle righe della tabella `asset`, perche quasi
tutti gli asset censiti sono attivi: non ridurrebbe in modo significativo la
dimensione dell'indice ne migliorerebbe i piani di esecuzione. E stato quindi
sostituito con `idx_asset_cessati`, che indicizza il **complemento** — il
sottoinsieme raro, effettivamente selettivo, interrogato per le dismissioni. Un
indice parziale conviene quando la condizione seleziona una frazione ridotta
delle righe: e la condizione, non la sintassi, a determinare il beneficio.

---

## 9. View e funzioni per il profilo ACN

| View | Sezione ACN | Filtro |
|---|---|---|
| `vw_profilo_acn_asset` | 1 — Inventario asset (§12.3) | `in_produzione = TRUE AND o.attiva = TRUE` |
| `vw_profilo_acn_servizi` | 2 — Servizi erogati | `attivo = TRUE AND o.attiva = TRUE` |
| `vw_profilo_acn_dipendenze` | 3 — Dipendenze da terzi | `attiva = TRUE AND o.attiva = TRUE` |
| `vw_profilo_acn_contatti` | 4 — Punti di contatto | `data_fine IS NULL AND o.attiva = TRUE` |

Tutte le view filtrano anche `o.attiva = TRUE`: un soggetto cessato non deve
comparire nel profilo, coerentemente con il controllo di esistenza effettuato da
`fn_esporta_profilo_acn()`.

Le concatenazioni nome/cognome usano l'operatore `||` e non `CONCAT()`:
`CONCAT()` restituisce stringa vuota al posto di NULL, neutralizzando il
`COALESCE(..., 'N/D')` e producendo celle apparentemente vuote nel CSV.

| Funzione / Procedura | Tipo | Descrizione |
|---|---|---|
| `fn_csv_quote(text)` | FUNCTION IMMUTABLE | Quoting RFC 4180: raddoppia gli apici doppi interni e neutralizza la formula injection anteponendo un apice ai valori che iniziano con `=`, `+`, `@` |
| `fn_esporta_profilo_acn(codice_acn)` | FUNCTION STABLE | Profilo completo in 4 sezioni CSV conformi RFC 4180 |
| `fn_storia_asset(id_asset)` | FUNCTION STABLE | Cronologia completa (storico + versione corrente), inclusi i campi §12.3 |
| `sp_cessa_asset(id, utente, motivo)` | PROCEDURE | Cessazione logica con motivo tracciato |
| `sp_subentra_responsabile(...)` | PROCEDURE | Chiude l'incarico attivo e nomina il successore in un'unica transazione |
| `fn_audit_asset()`, `fn_audit_servizio()` | TRIGGER FUNCTION | Snapshot-on-write |
| `fn_blocca_modifica_storico()` | TRIGGER FUNCTION | Blocca UPDATE e DELETE sulle tabelle di storico |
| `fn_update_timestamp()` | TRIGGER FUNCTION | Aggiorna `data_modifica` su organizzazione, fornitore, dipendenza, responsabile |

### 9.1 Export CSV

```sql
-- Anteprima completa in un'unica chiamata
SELECT fn_esporta_profilo_acn('ACN-2024-00123');
```

```bash
# Export su file: COPY applica nativamente l'escaping RFC 4180
\COPY (SELECT * FROM vw_profilo_acn_asset WHERE "ID_ACN" = 'ACN-2024-00123')
  TO 'asset.csv' WITH (FORMAT csv, HEADER, QUOTE '"', FORCE_QUOTE *);
```

Entrambe le vie producono CSV conformi: `COPY` con `FORCE_QUOTE *` e la via
canonica per l'export su file, `fn_esporta_profilo_acn()` serve per l'anteprima
delle quattro sezioni in un'unica chiamata (utile da pgAdmin Query Tool). La
conformita e verificata dal Test 11, che introduce un valore contenente apici
doppi e virgole e ne controlla l'escaping.

---

## 10. Dataset simulato

| Entita | N. | Dettaglio |
|---|---|---|
| Organizzazioni NIS2 | 2 | Zagara Neuro Therapeutics (sanitario, Trapani) · Sole di Sicilia (energia, Palermo) |
| Asset in produzione | 18 | HW 5 · SW 4 · DATO 3 · RETE 2 · FISICO 2 · CLOUD 1 · IOT 1 |
| — per criticita | 18 | CRITICO 11 · ALTO 4 · MEDIO 1 · MEDIO-BASSO 1 · BASSO 1 |
| Servizi attivi | 7 | 4 Zagara (CCE, CUP, PACS, DR) + 3 Sole (SCADA, Billing, DR) |
| Fornitori | 8 | Tutti fittizi e anonimizzati |
| Dipendenze attive | 8 | 4 Zagara + 4 Sole |
| Responsabili in carica | 7 | 4 Zagara + 3 Sole |
| Relazioni asset-servizio | 14 | SUPPORTA / EROGA / OSPITA |
| Relazioni asset-dipendenza | 6 | Collegamento diretto asset-fornitore |
| Relazioni servizio-dipendenza | 9 | — |
| Relazioni asset-responsabile | 18 | 16 PROPRIETARIO + 2 REFERENTE |

### 10.1 Distribuzione di criticita e potere discriminante del filtro

La distribuzione copre tutti e cinque i livelli. Il filtro `livello >= 4`
usato dalla query "asset critici" seleziona **15 asset su 18**: e quindi un
filtro che discrimina realmente un sottoinsieme, non una condizione che
restituisce l'intero inventario. Il Test 17 verifica questa proprieta.

### 10.2 Anomalie deliberate

Il dataset contiene tre classi di anomalie **volute**, che dimostrano la capacita
del registro di rilevare gap di conformita (Query 6):

| Anomalia | N. | Riferimento violato |
|---|---|---|
| Asset privi di PROPRIETARIO (`AST-DATO-002`, `SDS-HW-002`) | 2 | Reg. (UE) 2024/2690 punto 12.4 |
| Dipendenza critica senza DPA (`DIP-ZNT-004`) | 1 | GDPR art. 28 + NIS2 art. 21(2)(d) |
| Asset ad alta criticita con valutazione del rischio non effettuata (`AST-CLOUD-001`, `SDS-FISICO-001`) | 2 | Reg. (UE) 2024/2690 punto 12.3 |

Il Test 16 asserisce il numero esatto di anomalie attese: una variazione non
intenzionale del dataset farebbe fallire la suite.

Una quarta dipendenza priva di DPA (`DIP-SDS-003`) ha criticita MEDIA e resta
sotto la soglia di segnalazione: e un esempio deliberato di *non* falso positivo.

**Disclaimer.** Tutti i dati — denominazioni, codici fiscali, contatti, numeri di
contratto, fornitori — sono completamente fittizi e generati a scopo didattico.

---

## 11. Test automatici (17 test, 21 asserzioni)

| N. | Test | Verifica |
|---|---|---|
| 1–3 | Conteggi entita | organizzazioni = 2, asset = 18, servizi = 7 |
| 4a–b | Trigger di versioning | `versione_record` e righe di storico crescono di esattamente 1 dopo l'UPDATE |
| 5 | `fn_storia_asset` | ≥ 2 versioni in cronologia |
| 6 | Indice unico parziale | `unique_violation` su secondo CISO attivo per la stessa organizzazione |
| 7a | Immutabilita storico — UPDATE | eccezione `AUDIT_TRAIL_IMMUTABLE` |
| 7b | Immutabilita storico — DELETE | eccezione `AUDIT_TRAIL_IMMUTABLE` |
| 7c | `ON DELETE RESTRICT` | cancellare un asset con storico e bloccato e lo storico resta integro |
| 8a–e | Junction table | 14 / 9 / 6 / 18 / 5 righe |
| 9a–d | View CSV | 18 asset, 7 servizi, 8 dipendenze, 7 contatti |
| 10a–e | `fn_esporta_profilo_acn` | tutte e 4 le sezioni presenti |
| 11a–b | **Conformita RFC 4180** | un valore contenente `"` e `,` viene esportato con apici raddoppiati e non spezza il record |
| 12a–b | `sp_cessa_asset` | `in_produzione = FALSE` e `data_fine_vita` valorizzata |
| 13a–b | **Completezza dello storico §12.3** | `data_ultima_patch` e `stato_valutazione_rischio` archiviati nello snapshot |
| 14 | **Copertura della view di export** | tutti i campi §12.3 presenti in `vw_profilo_acn_asset` |
| 15a–b | **Isolamento multi-tenant** | il CHECK blocca il collegamento cross-org; la FK composita blocca la falsificazione dell'organizzazione |
| 16a–b | **Rilevamento anomalie** | esattamente 2 asset senza proprietario e 1 dipendenza critica senza DPA |
| 17 | **Selettivita del filtro** | il filtro criticita ≥ ALTO seleziona un sottoinsieme proprio dell'inventario |

I test che modificano dati rileggono il valore originale dalla tabella e lo
ripristinano: nessun valore di ripristino e hardcodato, quindi la suite non puo
introdurre nel registro dati che non appartengono al dataset. Le asserzioni sono
formulate su **incrementi** e non su valori assoluti (Test 4), quindi
`05_deploy_test.sql` puo essere rieseguito da solo, senza ricreare lo schema.

### 11.1 Nota di portabilita fra versioni di PostgreSQL

Un DELETE bloccato da `ON DELETE RESTRICT` non produce lo stesso codice di errore
su tutte le versioni:

| Versione | SQLSTATE | Condizione PL/pgSQL |
|---|---|---|
| PostgreSQL ≤ 17 | 23503 | `foreign_key_violation` |
| PostgreSQL 18 | 23001 | `restrict_violation` |

PostgreSQL 18 distingue esplicitamente il vincolo RESTRICT dalla generica
violazione di chiave esterna. Inoltre, quando piu chiavi esterne referenziano la
stessa riga (per `asset` sono cinque), l'ordine di verifica non e garantito e il
codice restituito puo variare. Il Test 7c cattura quindi entrambe le condizioni:

```sql
EXCEPTION WHEN foreign_key_violation OR restrict_violation THEN
```

E un esempio concreto di come un test che passa su una versione possa fallire su
un'altra senza che il comportamento del sistema sia cambiato: il vincolo funziona
correttamente in entrambi i casi, cambia solo il modo in cui l'errore viene
classificato.

---

## 12. Ruoli database e sicurezza

| Ruolo | Privilegi | Uso |
|---|---|---|
| `nis2_app` | SELECT, INSERT, UPDATE su tutte le tabelle; **nessun** UPDATE/DELETE sullo storico | Applicazione web/API |
| `nis2_readonly` | SELECT su tutte le tabelle | Audit, reporting, export ACN |

- **Credenziali**: i ruoli sono creati con `PASSWORD NULL`; nessuna password e
  presente nel repository. Vanno impostate con `ALTER ROLE` dopo il deploy.
- **Trasporto e autenticazione**: si raccomanda `pg_hba.conf` con
  `scram-sha-256` e connessioni `hostssl`.
- **Dati personali**: `responsabile` contiene nome, cognome, email e telefono di
  persone fisiche; gli export CSV li replicano su file. Il `.gitignore` esclude
  i file `*.csv` dal repository. La base giuridica del trattamento e l'obbligo
  legale (art. 6.1.c GDPR) derivante dagli obblighi di comunicazione dei punti
  di contatto ex art. 23 D.Lgs. 138/2024.

### 12.1 Threat model sintetico

| Minaccia | Impatto | Controllo implementato |
|---|---|---|
| Modifica non autorizzata della storia di audit | Perdita di tamper-evidence in sede di ispezione ACN | REVOKE UPDATE/DELETE + trigger `fn_blocca_modifica_storico` + `ON DELETE RESTRICT` |
| Cross-tenant data leak fra organizzazioni | Violazione GDPR e segregazione NIS2 | FK composite `(id, id_organizzazione)` + CHECK sull'uguaglianza delle organizzazioni |
| Credenziali nel repository pubblico | Accesso non autorizzato al registro | `PASSWORD NULL` nel DDL, password fuori dal VCS, `.gitignore` |
| Cancellazione di un asset con la sua storia | Perdita permanente dell'audit trail | `ON DELETE RESTRICT` sulle FK dello storico |
| CSV malformato o formula injection nell'export | Profilo ACN corrotto o codice eseguito all'apertura in un foglio di calcolo | `fn_csv_quote()` + `COPY ... FORCE_QUOTE *`, verificati dal Test 11 |
| Esposizione del registro come mappa d'attacco | Il registro concentra IP, hostname, versioni OS e criticita di due soggetti essenziali | Least privilege, ruolo di sola lettura separato, TLS-only; evoluzione: Row-Level Security per organizzazione |

**Residuo dichiarato**: un superuser PostgreSQL puo rimuovere i trigger e
modificare lo storico. Mitigazioni non implementate in questa versione:
hash-chaining delle righe di audit, WAL shipping verso un host di sola lettura,
`pgaudit` per la tracciatura delle sessioni.

---

## 13. Limiti noti e sviluppi futuri

| Limite | Impatto | Evoluzione |
|---|---|---|
| Storico non hash-chained | Un superuser puo alterare l'audit trail | SHA-256 per riga con hash della precedente, oppure WAL shipping |
| Nessun modulo incidenti | L'art. 25 D.Lgs. 138/2024 (pre-notifica 24h, notifica 72h, relazione 30gg) non e coperto | Tabelle `incidente` e `notifica_acn` con scadenze calcolate |
| Nessuna Row-Level Security | L'isolamento e garantito a livello di integrita, non di visibilita | Policy RLS su `id_organizzazione` con `current_setting` |
| Nessuna validazione empirica delle performance | Le scelte di indicizzazione non sono misurate | Dataset sintetico da 100k asset + `EXPLAIN (ANALYZE, BUFFERS)` |
| Tabelle di storico non partizionate | Crescita lineare su volumi elevati | Partitioning per `data_modifica` |
| Nessuna interfaccia utente | Aggiornamento riservato a utenti SQL | API REST + frontend |
| Popolamento manuale | Dipende dall'inserimento umano | ETL da CMDB/SIEM o scanner di rete |
