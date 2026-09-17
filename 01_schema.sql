-- =============================================================================
-- NIS2/ACN REGISTRO CENTRALIZZATO — Schema Relazionale
-- Progetto: PW Tema 2 - Privacy e Sicurezza Aziendale
-- Corso: Informatica per le Aziende Digitali (L-31)
-- RDBMS: PostgreSQL 15+ (sviluppato e testato su PostgreSQL 18)
-- Eseguire nell'ordine: 01 → 02 → 03 → 04 → 05
--
-- Standard di riferimento:
--   - Reg. di esecuzione (UE) 2024/2690, punto 12 (gestione degli attivi),
--     in particolare 12.3 (inventario) e 12.4 (proprietario dell'attivo)
--   - D.Lgs. 138/2024 (recepimento NIS2), artt. 23-25
--   - ACN Determinazione n. 164179 del 14 aprile 2025, agg. n. 379887 e
--     n. 379907 del 2025
-- =============================================================================

-- =============================================================================
-- PULIZIA SCHEMA (idempotente — rieseguibile su database esistente)
-- =============================================================================
DROP VIEW IF EXISTS
    vw_profilo_acn_contatti,
    vw_profilo_acn_dipendenze,
    vw_profilo_acn_servizi,
    vw_profilo_acn_asset
CASCADE;

DROP FUNCTION IF EXISTS
    fn_esporta_profilo_acn(TEXT),
    fn_csv_quote(TEXT),
    fn_storia_asset(INTEGER),
    fn_audit_asset(),
    fn_audit_servizio(),
    fn_update_timestamp(),
    fn_blocca_modifica_storico()
CASCADE;

DROP PROCEDURE IF EXISTS
    sp_cessa_asset(INTEGER, VARCHAR, TEXT),
    sp_subentra_responsabile(INTEGER, INTEGER, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR)
CASCADE;

DROP TABLE IF EXISTS
    servizio_responsabile,
    asset_responsabile,
    servizio_dipendenza,
    asset_dipendenza,
    asset_servizio,
    servizio_storico,
    asset_storico,
    responsabile,
    dipendenza,
    servizio,
    asset,
    fornitore,
    organizzazione,
    ruolo_organizzativo,
    tipo_dipendenza,
    tipo_servizio,
    tipo_soggetto,
    settore_nis2,
    livello_criticita,
    tipo_asset
CASCADE;

-- =============================================================================
-- SEZIONE 1: TABELLE DI LOOKUP / DOMINIO
-- =============================================================================

CREATE TABLE tipo_asset (
    id          SERIAL PRIMARY KEY,
    codice      VARCHAR(20)  NOT NULL,
    descrizione VARCHAR(150) NOT NULL,
    CONSTRAINT uk_tipo_asset_codice UNIQUE (codice)
);
COMMENT ON TABLE tipo_asset IS 'Tipologie di asset: HW, SW, DATO, RETE, CLOUD, FISICO, IOT';

CREATE TABLE livello_criticita (
    id          SERIAL PRIMARY KEY,
    codice      VARCHAR(20)  NOT NULL,
    etichetta   VARCHAR(50)  NOT NULL,
    livello     SMALLINT     NOT NULL CHECK (livello BETWEEN 1 AND 5),
    CONSTRAINT uk_livello_codice UNIQUE (codice),
    CONSTRAINT uk_livello_num   UNIQUE (livello)
);
COMMENT ON TABLE livello_criticita IS
    '1=BASSO, 2=MEDIO_BASSO, 3=MEDIO, 4=ALTO, 5=CRITICO. '
    'Due candidate key (id e livello): BCNF rispettata perche ogni determinante e candidate key.';

-- Allegato I = settori ad alta criticita; Allegato II = altri settori critici.
-- La classificazione essenziale/importante dipende dall'incrocio settore x dimensione
-- (D.Lgs. 138/2024, All. I-IV). Il CHECK include III e IV per PA e altri soggetti.
CREATE TABLE settore_nis2 (
    id          SERIAL PRIMARY KEY,
    codice      VARCHAR(30)  NOT NULL,
    descrizione VARCHAR(255) NOT NULL,
    allegato    VARCHAR(3)   NOT NULL CHECK (allegato IN ('I','II','III','IV')),
    CONSTRAINT uk_settore_codice UNIQUE (codice)
);
COMMENT ON TABLE settore_nis2 IS
    'Settori NIS2: Allegato I = settori ad alta criticita; '
    'Allegato II = altri settori critici; '
    'Allegato III = PA centrale; Allegato IV = altri soggetti (D.Lgs. 138/2024)';

CREATE TABLE tipo_soggetto (
    id          SERIAL PRIMARY KEY,
    codice      VARCHAR(20)  NOT NULL,
    descrizione VARCHAR(100) NOT NULL,
    CONSTRAINT uk_tipo_soggetto_codice UNIQUE (codice)
);
COMMENT ON TABLE tipo_soggetto IS
    'ESSENZIALE | IMPORTANTE — artt. 3 e 6 D.Lgs. 138/2024. '
    'La classificazione dipende dall''incrocio settore x dimensione aziendale: '
    'grandi imprese in Allegato I = essenziali; medie imprese in Allegato I = importanti.';

CREATE TABLE tipo_servizio (
    id          SERIAL PRIMARY KEY,
    codice      VARCHAR(30)  NOT NULL,
    descrizione VARCHAR(150) NOT NULL,
    CONSTRAINT uk_tipo_servizio_codice UNIQUE (codice)
);
COMMENT ON TABLE tipo_servizio IS 'Categorie funzionali di servizio erogato';

CREATE TABLE tipo_dipendenza (
    id          SERIAL PRIMARY KEY,
    codice      VARCHAR(30)  NOT NULL,
    descrizione VARCHAR(150) NOT NULL,
    CONSTRAINT uk_tipo_dipendenza_codice UNIQUE (codice)
);
COMMENT ON TABLE tipo_dipendenza IS
    'Tipologie dipendenza: CLOUD_IAAS, CLOUD_SAAS, FORNITURA_SW, '
    'FORNITURA_HW, CONNETTIVITA, CLOUD_BACKUP, ALTRO';

CREATE TABLE ruolo_organizzativo (
    id          SERIAL PRIMARY KEY,
    codice      VARCHAR(40)  NOT NULL,
    descrizione VARCHAR(150) NOT NULL,
    CONSTRAINT uk_ruolo_codice UNIQUE (codice)
);
COMMENT ON TABLE ruolo_organizzativo IS
    'Ruoli rilevanti NIS2: CISO, DPO, RSPP, RESP_ICT, REFERENTE_NIS2, AMM_SISTEMA, LEGALE';

-- =============================================================================
-- SEZIONE 2: ENTITÀ PRINCIPALI
-- =============================================================================

CREATE TABLE organizzazione (
    id                       SERIAL PRIMARY KEY,
    codice_fiscale           VARCHAR(16)   NOT NULL,
    denominazione            VARCHAR(255)  NOT NULL,
    id_settore_nis2          INTEGER       NOT NULL REFERENCES settore_nis2(id),
    id_tipo_soggetto         INTEGER       NOT NULL REFERENCES tipo_soggetto(id),
    -- dimensione separata da tipo_soggetto perche la classificazione
    -- essenziale/importante dipende da entrambi (settore x dimensione)
    dimensione               VARCHAR(10)   NOT NULL
        CHECK (dimensione IN ('MICRO','PICCOLA','MEDIA','GRANDE')),
    indirizzo                TEXT,
    comune                   VARCHAR(100),
    cap                      CHAR(5),
    paese                    CHAR(3)       NOT NULL DEFAULT 'ITA',
    codice_nace              VARCHAR(10),
    numero_dipendenti        INTEGER,
    fatturato_mln_eur        NUMERIC(12,2),
    data_registrazione_acn   DATE,
    -- UNIQUE: e la chiave logica usata come filtro di export ACN
    numero_registrazione_acn VARCHAR(50)   UNIQUE,
    data_inserimento         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    data_modifica            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    attiva                   BOOLEAN       NOT NULL DEFAULT TRUE,
    CONSTRAINT uk_org_cf UNIQUE (codice_fiscale)
);
COMMENT ON TABLE organizzazione IS 'Soggetti NIS2 registrati presso ACN';

CREATE TABLE responsabile (
    id                SERIAL PRIMARY KEY,
    id_organizzazione INTEGER      NOT NULL REFERENCES organizzazione(id) ON DELETE RESTRICT,
    nome              VARCHAR(100) NOT NULL,
    cognome           VARCHAR(100) NOT NULL,
    email             VARCHAR(255) NOT NULL,
    telefono          VARCHAR(50),
    id_ruolo          INTEGER      NOT NULL REFERENCES ruolo_organizzativo(id),
    data_inizio       DATE         NOT NULL,
    data_fine         DATE,
    data_inserimento  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    -- data_modifica aggiornata dal trigger trg_responsabile_timestamp (02_...)
    data_modifica     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    inserito_da       VARCHAR(100),
    -- UNIQUE su (id, id_organizzazione) per le FK composite nelle junction
    CONSTRAINT uk_responsabile_email UNIQUE (email),
    CONSTRAINT uk_resp_id_org UNIQUE (id, id_organizzazione),
    CONSTRAINT ck_responsabile_date CHECK (data_fine IS NULL OR data_fine > data_inizio)
);
COMMENT ON TABLE responsabile IS 'Responsabili/referenti organizzativi per NIS2';

-- Un solo responsabile attivo per ruolo per organizzazione
CREATE UNIQUE INDEX uk_responsabile_ruolo_attivo
    ON responsabile (id_organizzazione, id_ruolo)
    WHERE data_fine IS NULL;

CREATE TABLE asset (
    id                        SERIAL PRIMARY KEY,
    id_organizzazione         INTEGER      NOT NULL REFERENCES organizzazione(id) ON DELETE RESTRICT,
    codice_interno            VARCHAR(100) NOT NULL,
    nome                      VARCHAR(255) NOT NULL,
    descrizione               TEXT,
    id_tipo_asset             INTEGER      NOT NULL REFERENCES tipo_asset(id),
    id_livello_criticita      INTEGER      NOT NULL REFERENCES livello_criticita(id),
    produttore                VARCHAR(255),
    modello_versione          VARCHAR(255),
    ubicazione                VARCHAR(255),
    indirizzo_ip              INET,
    hostname                  VARCHAR(255),
    sistema_operativo         VARCHAR(100),
    data_acquisizione         DATE,
    data_fine_vita            DATE,
    in_produzione             BOOLEAN      NOT NULL DEFAULT TRUE,
    note_sicurezza            TEXT,
    -- Campi richiesti da Reg. (UE) 2024/2690, punto 12.3
    data_ultima_patch         DATE,
    stato_valutazione_rischio VARCHAR(30)
        CHECK (stato_valutazione_rischio IN
            ('NON_VALUTATO','IN_CORSO','VALUTATO','MITIGATO','ACCETTATO')),
    -- Versioning
    versione_record           INTEGER      NOT NULL DEFAULT 1,
    data_inserimento          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    data_modifica             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    inserito_da               VARCHAR(100),
    modificato_da             VARCHAR(100),
    -- UNIQUE composita per FK composite nelle junction (isolamento multi-tenant)
    CONSTRAINT uk_asset_codice   UNIQUE (id_organizzazione, codice_interno),
    CONSTRAINT uk_asset_id_org   UNIQUE (id, id_organizzazione),
    CONSTRAINT ck_asset_date     CHECK (data_fine_vita IS NULL OR data_fine_vita > data_acquisizione)
);
COMMENT ON TABLE asset IS
    'Inventario asset ICT (HW, SW, dati, rete, cloud) soggetti a NIS2. '
    'Schema conforme a Reg. (UE) 2024/2690, punto 12.3 (inventario) e 12.4 (proprietario).';

-- ON DELETE RESTRICT: cancellare un asset non deve distruggere il suo storico.
-- L'audit trail deve sopravvivere all'entita che monitora.
CREATE TABLE asset_storico (
    id                        SERIAL PRIMARY KEY,
    id_asset                  INTEGER      NOT NULL
        REFERENCES asset(id) ON DELETE RESTRICT,
    versione_record           INTEGER      NOT NULL,
    nome                      VARCHAR(255),
    descrizione               TEXT,
    id_tipo_asset             INTEGER      REFERENCES tipo_asset(id),
    id_livello_criticita      INTEGER      REFERENCES livello_criticita(id),
    produttore                VARCHAR(255),
    modello_versione          VARCHAR(255),
    ubicazione                VARCHAR(255),
    indirizzo_ip              INET,
    hostname                  VARCHAR(255),
    sistema_operativo         VARCHAR(100),
    in_produzione             BOOLEAN,
    note_sicurezza            TEXT,
    data_ultima_patch         DATE,
    stato_valutazione_rischio VARCHAR(30),
    data_modifica             TIMESTAMPTZ  NOT NULL,
    modificato_da             VARCHAR(100),
    motivo_modifica           TEXT,
    CONSTRAINT uk_asset_storico UNIQUE (id_asset, versione_record)
);
COMMENT ON TABLE asset_storico IS
    'Storico versioni asset — append-only. '
    'ON DELETE RESTRICT: lo storico sopravvive alla cessazione logica dell''asset. '
    'UPDATE e DELETE bloccati dal trigger fn_blocca_modifica_storico.';

CREATE TABLE servizio (
    id                      SERIAL PRIMARY KEY,
    id_organizzazione       INTEGER      NOT NULL REFERENCES organizzazione(id) ON DELETE RESTRICT,
    codice_interno          VARCHAR(100) NOT NULL,
    nome                    VARCHAR(255) NOT NULL,
    descrizione             TEXT,
    id_tipo_servizio        INTEGER      NOT NULL REFERENCES tipo_servizio(id),
    id_livello_criticita    INTEGER      NOT NULL REFERENCES livello_criticita(id),
    -- RTO/RPO in MINUTI: con le ore, RPO=0 non e distinguibile da RPO=59 min.
    -- Su impianti OT/SCADA in esercizio la differenza e un requisito reale.
    rto_minuti              INTEGER      CHECK (rto_minuti >= 0),
    rpo_minuti              INTEGER      CHECK (rpo_minuti >= 0),
    disponibilita_target    NUMERIC(6,3) CHECK (disponibilita_target BETWEEN 0 AND 100),
    dati_personali          BOOLEAN      NOT NULL DEFAULT FALSE,
    -- SEGRETO rimosso: appartiene alla classifica di segretezza statale
    -- (L. 124/2007), non applicabile a soggetti privati.
    classificazione_dati    VARCHAR(20)
        CHECK (classificazione_dati IN
            ('PUBBLICO','INTERNO','RISERVATO','CONFIDENZIALE','DATI_PARTICOLARI')),
    normative_applicabili   TEXT,
    utenti_stimati          INTEGER,
    data_avvio              DATE,
    attivo                  BOOLEAN      NOT NULL DEFAULT TRUE,
    versione_record         INTEGER      NOT NULL DEFAULT 1,
    data_inserimento        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    data_modifica           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    inserito_da             VARCHAR(100),
    modificato_da           VARCHAR(100),
    CONSTRAINT uk_servizio_codice UNIQUE (id_organizzazione, codice_interno),
    CONSTRAINT uk_servizio_id_org UNIQUE (id, id_organizzazione)
);
COMMENT ON TABLE servizio IS
    'Servizi digitali erogati soggetti a NIS2. '
    'rto_minuti/rpo_minuti in minuti (non ore) per granularita su SCADA (RPO=0 min). '
    'classificazione_dati: DATI_PARTICOLARI per dati art.9 GDPR (ex SEGRETO rimosso).';

CREATE TABLE servizio_storico (
    id                      SERIAL PRIMARY KEY,
    id_servizio             INTEGER      NOT NULL
        REFERENCES servizio(id) ON DELETE RESTRICT,
    versione_record         INTEGER      NOT NULL,
    nome                    VARCHAR(255),
    descrizione             TEXT,
    id_tipo_servizio        INTEGER      REFERENCES tipo_servizio(id),
    id_livello_criticita    INTEGER      REFERENCES livello_criticita(id),
    rto_minuti              INTEGER,
    rpo_minuti              INTEGER,
    disponibilita_target    NUMERIC(6,3),
    dati_personali          BOOLEAN,
    classificazione_dati    VARCHAR(20),
    normative_applicabili   TEXT,
    attivo                  BOOLEAN,
    data_modifica           TIMESTAMPTZ  NOT NULL,
    modificato_da           VARCHAR(100),
    motivo_modifica         TEXT,
    CONSTRAINT uk_servizio_storico UNIQUE (id_servizio, versione_record)
);
COMMENT ON TABLE servizio_storico IS
    'Storico versioni servizi — ON DELETE RESTRICT, UPDATE/DELETE bloccati dal trigger.';

CREATE TABLE fornitore (
    id                   SERIAL PRIMARY KEY,
    codice_interno       VARCHAR(100) NOT NULL,
    ragione_sociale      VARCHAR(255) NOT NULL,
    paese                CHAR(3)      NOT NULL DEFAULT 'ITA',
    codice_fiscale_piva  VARCHAR(50),
    sito_web             VARCHAR(255),
    email_sicurezza      VARCHAR(255),
    certificazioni       TEXT,
    note                 TEXT,
    data_inserimento     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    data_modifica        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT uk_fornitore_codice UNIQUE (codice_interno)
);
COMMENT ON TABLE fornitore IS
    'Fornitori terzi — supply chain NIS2 art. 21(2)(d), art. 24 D.Lgs. 138/2024, '
    'Reg. (UE) 2024/2690 punto 14';

CREATE TABLE dipendenza (
    id                      SERIAL PRIMARY KEY,
    codice_interno          VARCHAR(50)  NOT NULL,
    id_organizzazione       INTEGER      NOT NULL REFERENCES organizzazione(id) ON DELETE RESTRICT,
    id_fornitore            INTEGER      NOT NULL REFERENCES fornitore(id),
    id_tipo_dipendenza      INTEGER      NOT NULL REFERENCES tipo_dipendenza(id),
    denominazione_servizio  VARCHAR(255) NOT NULL,
    descrizione             TEXT,
    id_livello_criticita    INTEGER      NOT NULL REFERENCES livello_criticita(id),
    data_inizio             DATE         NOT NULL,
    data_scadenza           DATE,
    paesi_elaborazione_dati TEXT,
    contratto_numero        VARCHAR(100),
    dpa_firmato             BOOLEAN      NOT NULL DEFAULT FALSE,
    sla_disponibilita       NUMERIC(6,3),
    attiva                  BOOLEAN      NOT NULL DEFAULT TRUE,
    data_inserimento        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    -- data_modifica aggiornata dal trigger trg_dipendenza_timestamp (02_...)
    data_modifica           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT uk_dipendenza_codice UNIQUE (id_organizzazione, codice_interno),
    CONSTRAINT uk_dipendenza_id_org UNIQUE (id, id_organizzazione),
    CONSTRAINT ck_dipendenza_date   CHECK (data_scadenza IS NULL OR data_scadenza > data_inizio)
);
COMMENT ON TABLE dipendenza IS 'Dipendenze da fornitori terzi — supply chain NIS2 art. 21(2)(d)';

-- =============================================================================
-- SEZIONE 3: TABELLE DI RELAZIONE (JUNCTION TABLES)
-- FK composte (id + id_organizzazione) per prevenire cross-tenant data leak
-- =============================================================================

CREATE TABLE asset_servizio (
    id_asset        INTEGER     NOT NULL,
    id_asset_org    INTEGER     NOT NULL,
    id_servizio     INTEGER     NOT NULL,
    id_servizio_org INTEGER     NOT NULL,
    tipo_relazione  VARCHAR(30) NOT NULL DEFAULT 'SUPPORTA'
        CHECK (tipo_relazione IN ('SUPPORTA','EROGA','DIPENDE_DA','OSPITA')),
    note            TEXT,
    PRIMARY KEY (id_asset, id_servizio, tipo_relazione),
    FOREIGN KEY (id_asset,    id_asset_org)    REFERENCES asset(id,    id_organizzazione),
    FOREIGN KEY (id_servizio, id_servizio_org) REFERENCES servizio(id, id_organizzazione),
    CONSTRAINT ck_as_same_org CHECK (id_asset_org = id_servizio_org)
);
COMMENT ON TABLE asset_servizio IS
    'Asset che supportano/erogano servizi (N:M). '
    'FK composte + CHECK: asset e servizio devono appartenere alla stessa organizzazione.';

CREATE TABLE asset_dipendenza (
    id_asset          INTEGER NOT NULL,
    id_asset_org      INTEGER NOT NULL,
    id_dipendenza     INTEGER NOT NULL,
    id_dipendenza_org INTEGER NOT NULL,
    note              TEXT,
    PRIMARY KEY (id_asset, id_dipendenza),
    FOREIGN KEY (id_asset,      id_asset_org)      REFERENCES asset(id,      id_organizzazione),
    FOREIGN KEY (id_dipendenza, id_dipendenza_org) REFERENCES dipendenza(id, id_organizzazione),
    CONSTRAINT ck_ad_same_org CHECK (id_asset_org = id_dipendenza_org)
);
COMMENT ON TABLE asset_dipendenza IS
    'Asset che dipendono direttamente da fornitori terzi (N:M con controllo cross-tenant).';

CREATE TABLE servizio_dipendenza (
    id_servizio       INTEGER NOT NULL,
    id_servizio_org   INTEGER NOT NULL,
    id_dipendenza     INTEGER NOT NULL,
    id_dipendenza_org INTEGER NOT NULL,
    note              TEXT,
    PRIMARY KEY (id_servizio, id_dipendenza),
    FOREIGN KEY (id_servizio,  id_servizio_org)   REFERENCES servizio(id,   id_organizzazione),
    FOREIGN KEY (id_dipendenza,id_dipendenza_org) REFERENCES dipendenza(id, id_organizzazione),
    CONSTRAINT ck_sd_same_org CHECK (id_servizio_org = id_dipendenza_org)
);
COMMENT ON TABLE servizio_dipendenza IS
    'Servizi che dipendono da fornitori terzi (N:M con controllo cross-tenant).';

CREATE TABLE asset_responsabile (
    id                  SERIAL PRIMARY KEY,
    id_asset            INTEGER     NOT NULL,
    id_asset_org        INTEGER     NOT NULL,
    id_responsabile     INTEGER     NOT NULL,
    id_resp_org         INTEGER     NOT NULL,
    tipo_responsabilita VARCHAR(30) NOT NULL
        CHECK (tipo_responsabilita IN ('PROPRIETARIO','CUSTODE','AMMINISTRATORE','REFERENTE')),
    data_inizio         DATE        NOT NULL DEFAULT CURRENT_DATE,
    data_fine           DATE,
    FOREIGN KEY (id_asset,       id_asset_org) REFERENCES asset(id,        id_organizzazione),
    FOREIGN KEY (id_responsabile,id_resp_org)  REFERENCES responsabile(id, id_organizzazione),
    CONSTRAINT ck_ar_same_org CHECK (id_asset_org = id_resp_org),
    CONSTRAINT ck_asset_resp_date CHECK (data_fine IS NULL OR data_fine > data_inizio)
);
COMMENT ON TABLE asset_responsabile IS
    'Proprietario/custode dell''attivo — Reg. (UE) 2024/2690 punto 12.4. '
    'Validita temporale (data_inizio/data_fine) e controllo cross-tenant.';

CREATE UNIQUE INDEX uk_asset_resp_attivo
    ON asset_responsabile (id_asset, tipo_responsabilita)
    WHERE data_fine IS NULL;

CREATE TABLE servizio_responsabile (
    id                  SERIAL PRIMARY KEY,
    id_servizio         INTEGER     NOT NULL,
    id_servizio_org     INTEGER     NOT NULL,
    id_responsabile     INTEGER     NOT NULL,
    id_resp_org         INTEGER     NOT NULL,
    tipo_responsabilita VARCHAR(30) NOT NULL
        CHECK (tipo_responsabilita IN
            ('PROPRIETARIO','GESTORE','REFERENTE_SICUREZZA','APPROVATORE')),
    data_inizio         DATE        NOT NULL DEFAULT CURRENT_DATE,
    data_fine           DATE,
    FOREIGN KEY (id_servizio,    id_servizio_org) REFERENCES servizio(id,    id_organizzazione),
    FOREIGN KEY (id_responsabile,id_resp_org)     REFERENCES responsabile(id,id_organizzazione),
    CONSTRAINT ck_sr_same_org CHECK (id_servizio_org = id_resp_org),
    CONSTRAINT ck_servizio_resp_date CHECK (data_fine IS NULL OR data_fine > data_inizio)
);
COMMENT ON TABLE servizio_responsabile IS
    'Responsabilita sui servizi con validita temporale e controllo cross-tenant.';

CREATE UNIQUE INDEX uk_servizio_resp_attivo
    ON servizio_responsabile (id_servizio, tipo_responsabilita)
    WHERE data_fine IS NULL;

-- =============================================================================
-- SEZIONE 4: TRIGGER DI IMMUTABILITÀ DELLO STORICO
-- Impedisce UPDATE e DELETE sulle tabelle di audit anche all'owner del DB.
-- Nota: un superuser puo sempre rimuovere il trigger stesso — per tamper-evidence
-- completa occorre hash-chaining o WAL shipping a host separato (cfr. relazione).
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_blocca_modifica_storico()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION
        'AUDIT_TRAIL_IMMUTABLE: la tabella % e append-only. '
        'UPDATE e DELETE sono vietati per integrita del registro NIS2. '
        'Per vera tamper-evidence usare WAL shipping o hash-chaining.',
        TG_TABLE_NAME;
END; $$;
COMMENT ON FUNCTION fn_blocca_modifica_storico() IS
    'Blocca UPDATE e DELETE su asset_storico e servizio_storico.';

CREATE TRIGGER trg_blocca_asset_storico
    BEFORE UPDATE OR DELETE ON asset_storico
    FOR EACH ROW EXECUTE FUNCTION fn_blocca_modifica_storico();

CREATE TRIGGER trg_blocca_servizio_storico
    BEFORE UPDATE OR DELETE ON servizio_storico
    FOR EACH ROW EXECUTE FUNCTION fn_blocca_modifica_storico();

-- =============================================================================
-- SEZIONE 5: INDICI PER PERFORMANCE
-- =============================================================================

CREATE INDEX idx_asset_organizzazione     ON asset(id_organizzazione);
CREATE INDEX idx_asset_tipo               ON asset(id_tipo_asset);
CREATE INDEX idx_asset_criticita          ON asset(id_livello_criticita);
-- Un indice parziale WHERE in_produzione = TRUE indicizzerebbe ~100% delle righe
-- e non ridurrebbe la dimensione dell'indice: si indicizza il complemento, che
-- e il sottoinsieme raro e quello effettivamente interrogato per le dismissioni.
CREATE INDEX idx_asset_cessati            ON asset(in_produzione) WHERE NOT in_produzione;
-- Indice composito per la query di profilo ACN (filtro org + ordinamento criticita)
CREATE INDEX idx_asset_org_criticita      ON asset(id_organizzazione, id_livello_criticita)
    WHERE in_produzione;

CREATE INDEX idx_servizio_organizzazione  ON servizio(id_organizzazione);
CREATE INDEX idx_servizio_criticita       ON servizio(id_livello_criticita);
CREATE INDEX idx_servizio_attivo          ON servizio(attivo) WHERE attivo = TRUE;

CREATE INDEX idx_dipendenza_organizzazione ON dipendenza(id_organizzazione);
CREATE INDEX idx_dipendenza_fornitore      ON dipendenza(id_fornitore);
CREATE INDEX idx_dipendenza_attiva         ON dipendenza(attiva) WHERE attiva = TRUE;

CREATE INDEX idx_responsabile_org          ON responsabile(id_organizzazione);
CREATE INDEX idx_responsabile_ruolo        ON responsabile(id_ruolo);

CREATE INDEX idx_asset_storico_asset       ON asset_storico(id_asset);
CREATE INDEX idx_servizio_storico_serv     ON servizio_storico(id_servizio);
