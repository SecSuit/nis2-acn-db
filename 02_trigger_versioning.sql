-- =============================================================================
-- NIS2/ACN — Trigger e Stored Procedure per Versioning / Storico
-- =============================================================================
-- NOTA sul motivo_modifica:
-- Prima di ogni UPDATE che richiede tracciatura del motivo, impostare:
--   SELECT set_config('app.motivo_modifica', 'Descrizione motivo', false);
-- Il trigger legge automaticamente questo valore.
-- Se non impostato, viene usato il default 'Aggiornamento record'.
-- =============================================================================

-- =============================================================================
-- TRIGGER: asset → asset_storico
-- Prima di ogni UPDATE significativo archivia la versione corrente nello storico.
-- Lo snapshot include TUTTI i campi dell'inventario richiesti dal
-- Reg. (UE) 2024/2690 punto 12.3, compresi data_ultima_patch e
-- stato_valutazione_rischio: senza di essi non sarebbe possibile ricostruire
-- lo stato di patching di un asset a una data passata durante un'ispezione ACN.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_audit_asset()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO asset_storico (
        id_asset,                  versione_record,
        nome,                      descrizione,
        id_tipo_asset,             id_livello_criticita,
        produttore,                modello_versione,
        ubicazione,                indirizzo_ip,
        hostname,                  sistema_operativo,
        in_produzione,             note_sicurezza,
        data_ultima_patch,         stato_valutazione_rischio,
        data_modifica,             modificato_da,
        motivo_modifica
    ) VALUES (
        OLD.id,                    OLD.versione_record,
        OLD.nome,                  OLD.descrizione,
        OLD.id_tipo_asset,         OLD.id_livello_criticita,
        OLD.produttore,            OLD.modello_versione,
        OLD.ubicazione,            OLD.indirizzo_ip,
        OLD.hostname,              OLD.sistema_operativo,
        OLD.in_produzione,         OLD.note_sicurezza,
        OLD.data_ultima_patch,     OLD.stato_valutazione_rischio,
        OLD.data_modifica,         OLD.modificato_da,
        -- Legge il motivo dalla variabile di sessione (GUC)
        COALESCE(
            current_setting('app.motivo_modifica', true),
            'Aggiornamento record'
        )
    );

    -- Incrementa versione e aggiorna timestamp sulla riga nuova
    NEW.versione_record := OLD.versione_record + 1;
    NEW.data_modifica   := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_asset_versioning
    BEFORE UPDATE ON asset
    FOR EACH ROW
    WHEN (OLD.* IS DISTINCT FROM NEW.*)   -- esegue solo se c'e una modifica reale
    EXECUTE FUNCTION fn_audit_asset();

COMMENT ON FUNCTION fn_audit_asset() IS
    'Archivia la versione precedente di asset in asset_storico prima di ogni UPDATE '
    'significativo, inclusi i campi Reg. (UE) 2024/2690 punto 12.3 '
    '(data_ultima_patch, stato_valutazione_rischio).';

-- =============================================================================
-- TRIGGER: servizio → servizio_storico
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_audit_servizio()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO servizio_storico (
        id_servizio,          versione_record,
        nome,                 descrizione,
        id_tipo_servizio,     id_livello_criticita,
        rto_minuti,           rpo_minuti,
        disponibilita_target, dati_personali,
        classificazione_dati, normative_applicabili,
        attivo,
        data_modifica,        modificato_da,
        motivo_modifica
    ) VALUES (
        OLD.id,                          OLD.versione_record,
        OLD.nome,                        OLD.descrizione,
        OLD.id_tipo_servizio,            OLD.id_livello_criticita,
        OLD.rto_minuti,                  OLD.rpo_minuti,
        OLD.disponibilita_target,        OLD.dati_personali,
        OLD.classificazione_dati,        OLD.normative_applicabili,
        OLD.attivo,
        OLD.data_modifica,               OLD.modificato_da,
        COALESCE(
            current_setting('app.motivo_modifica', true),
            'Aggiornamento record'
        )
    );

    NEW.versione_record := OLD.versione_record + 1;
    NEW.data_modifica   := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_servizio_versioning
    BEFORE UPDATE ON servizio
    FOR EACH ROW
    WHEN (OLD.* IS DISTINCT FROM NEW.*)
    EXECUTE FUNCTION fn_audit_servizio();

COMMENT ON FUNCTION fn_audit_servizio() IS
    'Archivia la versione precedente di servizio in servizio_storico prima di ogni UPDATE significativo';

-- =============================================================================
-- TRIGGER: aggiornamento automatico di data_modifica
-- Applicato a TUTTE le entita che espongono la colonna data_modifica ma non
-- hanno versioning completo: organizzazione, fornitore, dipendenza, responsabile.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_update_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.data_modifica := NOW();
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION fn_update_timestamp() IS
    'Aggiorna data_modifica a NOW() su ogni UPDATE delle entita senza versioning completo';

CREATE TRIGGER trg_org_timestamp
    BEFORE UPDATE ON organizzazione
    FOR EACH ROW EXECUTE FUNCTION fn_update_timestamp();

CREATE TRIGGER trg_fornitore_timestamp
    BEFORE UPDATE ON fornitore
    FOR EACH ROW EXECUTE FUNCTION fn_update_timestamp();

CREATE TRIGGER trg_dipendenza_timestamp
    BEFORE UPDATE ON dipendenza
    FOR EACH ROW EXECUTE FUNCTION fn_update_timestamp();

CREATE TRIGGER trg_responsabile_timestamp
    BEFORE UPDATE ON responsabile
    FOR EACH ROW EXECUTE FUNCTION fn_update_timestamp();

-- =============================================================================
-- STORED PROCEDURE: cessazione asset con storico
-- =============================================================================

CREATE OR REPLACE PROCEDURE sp_cessa_asset(
    p_id_asset      INTEGER,
    p_modificato_da VARCHAR(100),
    p_motivo        TEXT DEFAULT 'Dismissione asset'
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM asset WHERE id = p_id_asset) THEN
        RAISE EXCEPTION 'Asset con id % non trovato', p_id_asset;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM asset WHERE id = p_id_asset AND in_produzione = TRUE) THEN
        RAISE EXCEPTION 'Asset % e gia cessato', p_id_asset;
    END IF;

    -- Imposta il motivo per il trigger di versioning
    PERFORM set_config('app.motivo_modifica', p_motivo, false);

    UPDATE asset
    SET
        in_produzione  = FALSE,
        data_fine_vita = CURRENT_DATE,
        modificato_da  = p_modificato_da
    WHERE id = p_id_asset;

    RAISE NOTICE 'Asset % cessato correttamente (motivo: %).', p_id_asset, p_motivo;
END;
$$;

COMMENT ON PROCEDURE sp_cessa_asset IS
    'Cessa un asset: in_produzione=FALSE, data_fine_vita=oggi, motivo tracciato dal trigger';

-- =============================================================================
-- STORED PROCEDURE: subentra responsabile
-- Chiude l'incarico attivo e apre il nuovo nello stesso blocco transazionale
-- =============================================================================

CREATE OR REPLACE PROCEDURE sp_subentra_responsabile(
    p_id_organizzazione INTEGER,
    p_id_ruolo          INTEGER,
    p_nome              VARCHAR(100),
    p_cognome           VARCHAR(100),
    p_email             VARCHAR(255),
    p_telefono          VARCHAR(50),
    p_inserito_da       VARCHAR(100)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_nuovo INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM ruolo_organizzativo WHERE id = p_id_ruolo) THEN
        RAISE EXCEPTION 'Ruolo con id % non trovato', p_id_ruolo;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM organizzazione WHERE id = p_id_organizzazione) THEN
        RAISE EXCEPTION 'Organizzazione con id % non trovata', p_id_organizzazione;
    END IF;

    -- Chiude il responsabile attivo per quel ruolo (se esiste)
    UPDATE responsabile
    SET data_fine = CURRENT_DATE
    WHERE id_organizzazione = p_id_organizzazione
      AND id_ruolo          = p_id_ruolo
      AND data_fine IS NULL;

    -- Inserisce il successore
    INSERT INTO responsabile (
        id_organizzazione, nome, cognome, email, telefono,
        id_ruolo, data_inizio, inserito_da
    ) VALUES (
        p_id_organizzazione, p_nome, p_cognome, p_email, p_telefono,
        p_id_ruolo, CURRENT_DATE, p_inserito_da
    ) RETURNING id INTO v_id_nuovo;

    RAISE NOTICE 'Nuovo responsabile inserito con id % per ruolo %.', v_id_nuovo, p_id_ruolo;
END;
$$;

COMMENT ON PROCEDURE sp_subentra_responsabile IS
    'Chiude il responsabile attivo per quel ruolo e ne nomina uno nuovo atomicamente';

-- =============================================================================
-- FUNZIONE: storia completa di un asset (storico + versione corrente)
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_storia_asset(p_id_asset INTEGER)
RETURNS TABLE (
    versione                  INTEGER,
    nome                      VARCHAR,
    criticita                 VARCHAR,
    in_produzione             BOOLEAN,
    data_ultima_patch         DATE,
    stato_valutazione_rischio VARCHAR,
    data_modifica             TIMESTAMPTZ,
    modificato_da             VARCHAR,
    motivo_modifica           TEXT
)
LANGUAGE sql
STABLE
AS $$
    -- Versioni archiviate
    SELECT
        s.versione_record,
        s.nome,
        lc.etichetta,
        s.in_produzione,
        s.data_ultima_patch,
        s.stato_valutazione_rischio,
        s.data_modifica,
        s.modificato_da,
        s.motivo_modifica
    FROM asset_storico s
    JOIN livello_criticita lc ON lc.id = s.id_livello_criticita
    WHERE s.id_asset = p_id_asset

    UNION ALL

    -- Versione corrente
    SELECT
        a.versione_record,
        a.nome,
        lc.etichetta,
        a.in_produzione,
        a.data_ultima_patch,
        a.stato_valutazione_rischio,
        a.data_modifica,
        a.modificato_da,
        'Versione corrente'
    FROM asset a
    JOIN livello_criticita lc ON lc.id = a.id_livello_criticita
    WHERE a.id = p_id_asset

    ORDER BY 1;
$$;

COMMENT ON FUNCTION fn_storia_asset(INTEGER) IS
    'Cronologia completa di tutte le versioni di un asset, inclusi i campi '
    'Reg. (UE) 2024/2690 punto 12.3 — usata per dimostrare ad ACN lo stato '
    'del registro a una qualsiasi data passata.';

-- =============================================================================
-- NOTA SICUREZZA STORICO
-- Le tabelle asset_storico e servizio_storico sono protette da tre livelli:
--   1. REVOKE UPDATE, DELETE FROM nis2_app          (05_deploy_test.sql)
--   2. Trigger fn_blocca_modifica_storico() BEFORE UPDATE OR DELETE (01_schema.sql)
--   3. ON DELETE RESTRICT sulla FK id_asset / id_servizio            (01_schema.sql)
--
-- LIMITAZIONE NOTA: un superuser PostgreSQL o il table owner possono rimuovere
-- i trigger e modificare lo storico. Per tamper-evidence completa e necessario
-- hash-chaining (SHA-256 della riga precedente) oppure WAL shipping verso un
-- host separato di sola lettura.
-- =============================================================================
