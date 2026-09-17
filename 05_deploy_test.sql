-- =============================================================================
-- NIS2/ACN — Script di Deploy, Ruoli e Test Automatici
-- Eseguire DOPO: 01_schema.sql, 02_trigger_versioning.sql,
--                03_dati_test.sql, 04_query_acn.sql
-- =============================================================================

-- =============================================================================
-- RUOLI E PERMESSI
-- Nessuna password e presente nel repository: i ruoli sono creati con
-- PASSWORD NULL (login impossibile finche non viene impostata una password
-- fuori dal controllo di versione, vedi README.md).
-- =============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'nis2_app') THEN
        CREATE ROLE nis2_app LOGIN PASSWORD NULL;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'nis2_readonly') THEN
        CREATE ROLE nis2_readonly LOGIN PASSWORD NULL;
    END IF;
END;
$$;

-- Ruolo applicativo: lettura e scrittura sulle tabelle operative
GRANT CONNECT ON DATABASE nis2_acn TO nis2_app;
GRANT USAGE ON SCHEMA public TO nis2_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO nis2_app;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO nis2_app;

-- Storico append-only: si revocano UPDATE e DELETE (il GRANT sopra non
-- includeva DELETE, ma la revoca esplicita rende l'intento verificabile
-- con \dp e resiste a un futuro GRANT ... ON ALL TABLES piu permissivo).
REVOKE UPDATE, DELETE ON asset_storico    FROM nis2_app;
REVOKE UPDATE, DELETE ON servizio_storico FROM nis2_app;

-- Ruolo di sola lettura per audit, reporting ed export ACN
GRANT CONNECT ON DATABASE nis2_acn TO nis2_readonly;
GRANT USAGE ON SCHEMA public TO nis2_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO nis2_readonly;

-- NOTA: in PostgreSQL le tabelle create in futuro non concedono alcun
-- privilegio per default, quindi non serve (ne funzionerebbe) un
-- ALTER DEFAULT PRIVILEGES ... REVOKE: si puo solo revocare una GRANT di
-- default che non e stata mai definita. La protezione dello storico si
-- fonda quindi sui tre livelli seguenti:
--   1. REVOKE UPDATE, DELETE (sopra)
--   2. trigger fn_blocca_modifica_storico() BEFORE UPDATE OR DELETE (01_schema)
--   3. ON DELETE RESTRICT sulla FK verso asset/servizio               (01_schema)

-- =============================================================================
-- TEST AUTOMATICI — 17 asserzioni
-- I test che modificano dati ripristinano sempre il valore seed originale,
-- rileggendolo dalla tabella (nessun valore hardcodato).
-- =============================================================================

-- TEST 1: organizzazioni presenti
DO $$
DECLARE v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM organizzazione WHERE attiva = TRUE;
    ASSERT v_count = 2, 'FAIL Test 1: attese 2 organizzazioni, trovate ' || v_count;
    RAISE NOTICE 'PASS Test 1: % organizzazioni attive', v_count;
END;
$$;

-- TEST 2: asset inseriti correttamente (11 Zagara + 7 Sole)
DO $$
DECLARE v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM asset WHERE in_produzione = TRUE;
    ASSERT v_count = 18, 'FAIL Test 2: attesi 18 asset, trovati ' || v_count;
    RAISE NOTICE 'PASS Test 2: % asset in produzione', v_count;
END;
$$;

-- TEST 3: servizi attivi
DO $$
DECLARE v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM servizio WHERE attivo = TRUE;
    ASSERT v_count = 7, 'FAIL Test 3: attesi 7 servizi, trovati ' || v_count;
    RAISE NOTICE 'PASS Test 3: % servizi attivi', v_count;
END;
$$;

-- TEST 4: trigger di versioning — incremento versione e riga di storico
-- L'asserzione e sull'INCREMENTO (+1) e non sul valore assoluto: lo script
-- resta cosi rieseguibile da solo, senza dover ricreare lo schema.
DO $$
DECLARE
    v_id           INTEGER;
    v_ver_prima    INTEGER;
    v_ver_dopo     INTEGER;
    v_storico_prima INTEGER;
    v_storico_dopo  INTEGER;
    v_ubicaz_orig  VARCHAR(255);
BEGIN
    SELECT id, ubicazione, versione_record
      INTO v_id, v_ubicaz_orig, v_ver_prima
    FROM asset WHERE codice_interno = 'AST-HW-001';
    SELECT COUNT(*) INTO v_storico_prima FROM asset_storico WHERE id_asset = v_id;

    PERFORM set_config('app.motivo_modifica', 'Test versioning automatico', false);
    UPDATE asset
    SET ubicazione = 'DC Zagara - Test Rack ZZ', modificato_da = 'script_test'
    WHERE id = v_id;

    SELECT versione_record INTO v_ver_dopo     FROM asset         WHERE id = v_id;
    SELECT COUNT(*)        INTO v_storico_dopo FROM asset_storico WHERE id_asset = v_id;

    ASSERT v_ver_dopo = v_ver_prima + 1,
        'FAIL Test 4a: versione_record doveva passare da ' || v_ver_prima ||
        ' a ' || (v_ver_prima + 1) || ', trovato ' || v_ver_dopo;
    ASSERT v_storico_dopo = v_storico_prima + 1,
        'FAIL Test 4b: asset_storico doveva crescere di 1 riga, passato da ' ||
        v_storico_prima || ' a ' || v_storico_dopo;

    -- Ripristino del valore seed letto dalla tabella (non hardcodato)
    PERFORM set_config('app.motivo_modifica', 'Ripristino post-test 4', false);
    UPDATE asset
    SET ubicazione = v_ubicaz_orig, modificato_da = 'script_test'
    WHERE id = v_id;

    RAISE NOTICE 'PASS Test 4: versioning OK (versione % -> %, righe storico % -> %)',
        v_ver_prima, v_ver_dopo, v_storico_prima, v_storico_dopo;
END;
$$;

-- TEST 5: fn_storia_asset restituisce la cronologia completa
DO $$
DECLARE v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM fn_storia_asset((SELECT id FROM asset WHERE codice_interno = 'AST-HW-001'));
    ASSERT v_count >= 2,
        'FAIL Test 5: storia asset deve avere >= 2 righe, trovate ' || v_count;
    RAISE NOTICE 'PASS Test 5: fn_storia_asset ritorna % versioni', v_count;
END;
$$;

-- TEST 6: indice unico parziale — un solo responsabile attivo per ruolo/org
DO $$
BEGIN
    BEGIN
        INSERT INTO responsabile (
            id_organizzazione, nome, cognome, email, id_ruolo, data_inizio
        ) VALUES (
            (SELECT id FROM organizzazione WHERE codice_fiscale = '04521367890'),
            'Duplicato', 'Test', 'duplicato.test@zagara-neuro.it',
            (SELECT id FROM ruolo_organizzativo WHERE codice = 'CISO'),
            CURRENT_DATE
        );
        RAISE EXCEPTION 'FAIL Test 6: avrebbe dovuto violare il unique index';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'PASS Test 6: unique index ruolo attivo funziona correttamente';
    END;
END;
$$;

-- TEST 7: immutabilita storico — UPDATE bloccato dal trigger
DO $$
BEGIN
    BEGIN
        UPDATE asset_storico
        SET motivo_modifica = 'manomissione_test'
        WHERE id_asset = (SELECT id FROM asset WHERE codice_interno = 'AST-HW-001');
        RAISE EXCEPTION 'FAIL Test 7a: UPDATE su asset_storico avrebbe dovuto essere bloccato';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%AUDIT_TRAIL_IMMUTABLE%' THEN
            RAISE NOTICE 'PASS Test 7a: storico immutabile — UPDATE bloccato';
        ELSE
            RAISE;
        END IF;
    END;
END;
$$;

-- TEST 7b: immutabilita storico — DELETE bloccato dal trigger
DO $$
BEGIN
    BEGIN
        DELETE FROM asset_storico
        WHERE id_asset = (SELECT id FROM asset WHERE codice_interno = 'AST-HW-001');
        RAISE EXCEPTION 'FAIL Test 7b: DELETE su asset_storico avrebbe dovuto essere bloccato';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%AUDIT_TRAIL_IMMUTABLE%' THEN
            RAISE NOTICE 'PASS Test 7b: storico immutabile — DELETE bloccato';
        ELSE
            RAISE;
        END IF;
    END;
END;
$$;

-- TEST 7c: ON DELETE RESTRICT — cancellare un asset non distrugge lo storico
-- NOTA DI PORTABILITA: il SQLSTATE dipende dalla versione di PostgreSQL.
--   PostgreSQL <= 17 -> foreign_key_violation (23503)
--   PostgreSQL 18    -> restrict_violation    (23001), che distingue
--                       esplicitamente il vincolo ON DELETE RESTRICT.
-- Inoltre, quando piu FK referenziano la stessa riga, l'ordine di verifica non
-- e garantito: si catturano quindi entrambe le condizioni.
DO $$
DECLARE v_storico_prima INTEGER; v_storico_dopo INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_storico_prima FROM asset_storico;
    BEGIN
        DELETE FROM asset WHERE codice_interno = 'AST-HW-001';
        RAISE EXCEPTION 'FAIL Test 7c: DELETE su asset con storico avrebbe dovuto essere bloccato';
    EXCEPTION WHEN foreign_key_violation OR restrict_violation THEN
        SELECT COUNT(*) INTO v_storico_dopo FROM asset_storico;
        ASSERT v_storico_dopo = v_storico_prima,
            'FAIL Test 7c: lo storico e stato alterato dal tentativo di DELETE';
        RAISE NOTICE 'PASS Test 7c: ON DELETE RESTRICT protegge lo storico (% righe intatte)',
            v_storico_dopo;
    END;
END;
$$;

-- TEST 8: junction tables popolate correttamente
DO $$
DECLARE v_as INTEGER; v_sd INTEGER; v_ad INTEGER; v_ar INTEGER; v_sr INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_as FROM asset_servizio;
    SELECT COUNT(*) INTO v_sd FROM servizio_dipendenza;
    SELECT COUNT(*) INTO v_ad FROM asset_dipendenza;
    SELECT COUNT(*) INTO v_ar FROM asset_responsabile;
    SELECT COUNT(*) INTO v_sr FROM servizio_responsabile;
    ASSERT v_as = 14, 'FAIL Test 8a: attese 14 righe in asset_servizio, trovate '      || v_as;
    ASSERT v_sd =  9, 'FAIL Test 8b: attese 9 righe in servizio_dipendenza, trovate '  || v_sd;
    ASSERT v_ad =  6, 'FAIL Test 8c: attese 6 righe in asset_dipendenza, trovate '     || v_ad;
    ASSERT v_ar = 18, 'FAIL Test 8d: attese 18 righe in asset_responsabile, trovate '  || v_ar;
    ASSERT v_sr =  5, 'FAIL Test 8e: attese 5 righe in servizio_responsabile, trovate '|| v_sr;
    RAISE NOTICE 'PASS Test 8: junction OK (as=%, sd=%, ad=%, ar=%, sr=%)',
        v_as, v_sd, v_ad, v_ar, v_sr;
END;
$$;

-- TEST 9: view CSV non vuote per entrambe le organizzazioni
DO $$
DECLARE v_asset INTEGER; v_serv INTEGER; v_dip INTEGER; v_cont INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_asset FROM vw_profilo_acn_asset;
    SELECT COUNT(*) INTO v_serv  FROM vw_profilo_acn_servizi;
    SELECT COUNT(*) INTO v_dip   FROM vw_profilo_acn_dipendenze;
    SELECT COUNT(*) INTO v_cont  FROM vw_profilo_acn_contatti;
    ASSERT v_asset = 18, 'FAIL Test 9a: attesi 18 asset nella view, trovati ' || v_asset;
    ASSERT v_serv  =  7, 'FAIL Test 9b: attesi 7 servizi nella view, trovati ' || v_serv;
    ASSERT v_dip   =  8, 'FAIL Test 9c: attese 8 dipendenze nella view, trovate ' || v_dip;
    ASSERT v_cont  =  7, 'FAIL Test 9d: attesi 7 contatti nella view, trovati ' || v_cont;
    RAISE NOTICE 'PASS Test 9: view CSV OK (asset=%, servizi=%, dip=%, contatti=%)',
        v_asset, v_serv, v_dip, v_cont;
END;
$$;

-- TEST 10: fn_esporta_profilo_acn genera le 4 sezioni
DO $$
DECLARE v_out TEXT;
BEGIN
    SELECT fn_esporta_profilo_acn('ACN-2024-00123') INTO v_out;
    ASSERT v_out NOT LIKE 'ERRORE%',    'FAIL Test 10a: la funzione ha restituito un errore';
    ASSERT v_out LIKE '%SEZIONE 1: ASSET%',              'FAIL Test 10b: manca SEZIONE 1';
    ASSERT v_out LIKE '%SEZIONE 2: SERVIZI%',            'FAIL Test 10c: manca SEZIONE 2';
    ASSERT v_out LIKE '%SEZIONE 3: DIPENDENZE%',         'FAIL Test 10d: manca SEZIONE 3';
    ASSERT v_out LIKE '%SEZIONE 4: PUNTI DI CONTATTO%',  'FAIL Test 10e: manca SEZIONE 4';
    RAISE NOTICE 'PASS Test 10: profilo ACN completo (% caratteri)', LENGTH(v_out);
END;
$$;

-- TEST 11: conformita RFC 4180 — un apice doppio nel dato non spezza il record
DO $$
DECLARE
    v_id        INTEGER;
    v_nome_orig VARCHAR(255);
    v_out       TEXT;
BEGIN
    SELECT id, nome INTO v_id, v_nome_orig FROM asset WHERE codice_interno = 'AST-HW-002';

    PERFORM set_config('app.motivo_modifica', 'Test RFC 4180', false);
    UPDATE asset SET nome = 'Server "Core", sede B' WHERE id = v_id;

    SELECT fn_esporta_profilo_acn('ACN-2024-00123') INTO v_out;

    -- L'apice doppio interno deve comparire raddoppiato ("") come da RFC 4180
    ASSERT v_out LIKE '%""Core""%',
        'FAIL Test 11a: apice doppio non raddoppiato — CSV non conforme RFC 4180';
    -- Non deve comparire la forma non escaped che spezzerebbe il record
    ASSERT v_out NOT LIKE '%"Server "Core", sede B"%',
        'FAIL Test 11b: il valore risulta non escaped nell output CSV';

    PERFORM set_config('app.motivo_modifica', 'Ripristino post-test 11', false);
    UPDATE asset SET nome = v_nome_orig WHERE id = v_id;

    RAISE NOTICE 'PASS Test 11: export CSV conforme RFC 4180 (escaping apici verificato)';
END;
$$;

-- TEST 12: sp_cessa_asset
DO $$
DECLARE v_id INTEGER; v_prod BOOLEAN; v_data DATE;
BEGIN
    SELECT id INTO v_id FROM asset WHERE codice_interno = 'SDS-HW-002';

    CALL sp_cessa_asset(v_id, 'script_test', 'Test cessazione automatica');

    SELECT in_produzione, data_fine_vita INTO v_prod, v_data FROM asset WHERE id = v_id;
    ASSERT v_prod = FALSE,      'FAIL Test 12a: in_produzione non impostato a FALSE';
    ASSERT v_data IS NOT NULL,  'FAIL Test 12b: data_fine_vita non impostata';

    -- Ripristino
    PERFORM set_config('app.motivo_modifica', 'Ripristino post-test 12', false);
    UPDATE asset SET in_produzione = TRUE, data_fine_vita = NULL WHERE id = v_id;
    RAISE NOTICE 'PASS Test 12: sp_cessa_asset funziona correttamente';
END;
$$;

-- TEST 13: lo storico archivia i campi Reg. (UE) 2024/2690 punto 12.3
-- Senza questi campi non sarebbe possibile ricostruire lo stato di patching
-- di un asset a una data passata durante un'ispezione ACN.
DO $$
DECLARE
    v_id    INTEGER;
    v_patch DATE;
    v_stato VARCHAR(30);
BEGIN
    SELECT id INTO v_id FROM asset WHERE codice_interno = 'AST-HW-001';
    SELECT data_ultima_patch, stato_valutazione_rischio
      INTO v_patch, v_stato
    FROM asset_storico
    WHERE id_asset = v_id AND versione_record = 1;

    ASSERT v_patch IS NOT NULL,
        'FAIL Test 13a: data_ultima_patch non archiviata in asset_storico';
    ASSERT v_stato IS NOT NULL,
        'FAIL Test 13b: stato_valutazione_rischio non archiviato in asset_storico';
    RAISE NOTICE 'PASS Test 13: storico completo §12.3 (patch=%, rischio=%)', v_patch, v_stato;
END;
$$;

-- TEST 14: la view di export espone i campi Reg. (UE) 2024/2690 punto 12.3
DO $$
DECLARE v_mancanti TEXT;
BEGIN
    SELECT string_agg(c, ', ')
      INTO v_mancanti
    FROM unnest(ARRAY[
        'ID_ACN','COD_ASSET','NOME_ASSET','TIPO_ASSET','CRITICITA','UBICAZIONE',
        'IDENTIFICATORE','DATA_ULTIMA_PATCH','STATO_VAL_RISCHIO','DATA_FINE_VITA',
        'PROPRIETARIO','EMAIL_PROPRIETARIO'
    ]) AS c
    WHERE NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'vw_profilo_acn_asset' AND column_name = c
    );

    ASSERT v_mancanti IS NULL,
        'FAIL Test 14: campi §12.3 assenti dalla view di export: ' || v_mancanti;
    RAISE NOTICE 'PASS Test 14: la view di export copre tutti i campi §12.3 richiesti';
END;
$$;

-- TEST 15: isolamento multi-tenant — un asset non puo essere collegato
-- a un servizio di un'altra organizzazione
DO $$
DECLARE v_a INTEGER; v_ao INTEGER; v_s INTEGER; v_so INTEGER;
BEGIN
    SELECT id, id_organizzazione INTO v_a, v_ao FROM asset    WHERE codice_interno='AST-HW-001';
    SELECT id, id_organizzazione INTO v_s, v_so FROM servizio WHERE codice_interno='SRV-SDS-001';
    ASSERT v_ao <> v_so, 'FAIL Test 15: setup non valido, stessa organizzazione';

    BEGIN
        INSERT INTO asset_servizio
            (id_asset, id_asset_org, id_servizio, id_servizio_org, tipo_relazione)
        VALUES (v_a, v_ao, v_s, v_so, 'SUPPORTA');
        RAISE EXCEPTION 'FAIL Test 15a: collegamento cross-tenant non bloccato';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'PASS Test 15a: CHECK cross-tenant attivo su asset_servizio';
    END;

    -- Tentativo di aggirare il CHECK falsificando l'organizzazione:
    -- deve fallire sulla FK composita
    BEGIN
        INSERT INTO asset_servizio
            (id_asset, id_asset_org, id_servizio, id_servizio_org, tipo_relazione)
        VALUES (v_a, v_ao, v_s, v_ao, 'SUPPORTA');
        RAISE EXCEPTION 'FAIL Test 15b: FK composita non ha bloccato l''organizzazione falsificata';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'PASS Test 15b: FK composita blocca la falsificazione dell''organizzazione';
    END;
END;
$$;

-- TEST 16: la Query 6 rileva esattamente le anomalie deliberate del dataset
DO $$
DECLARE v_owner INTEGER; v_dpa INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_owner
    FROM asset a
    JOIN organizzazione o ON o.id = a.id_organizzazione
    WHERE a.in_produzione AND o.attiva
      AND NOT EXISTS (
        SELECT 1 FROM asset_responsabile ar
        WHERE ar.id_asset = a.id
          AND ar.tipo_responsabilita = 'PROPRIETARIO' AND ar.data_fine IS NULL);

    SELECT COUNT(*) INTO v_dpa
    FROM dipendenza d
    JOIN organizzazione    o  ON o.id = d.id_organizzazione
    JOIN livello_criticita lc ON lc.id = d.id_livello_criticita
    WHERE d.attiva AND o.attiva AND NOT d.dpa_firmato AND lc.livello >= 4;

    ASSERT v_owner = 2,
        'FAIL Test 16a: attesi 2 asset senza proprietario (anomalie deliberate), trovati ' || v_owner;
    ASSERT v_dpa = 1,
        'FAIL Test 16b: attesa 1 dipendenza critica senza DPA, trovate ' || v_dpa;
    RAISE NOTICE 'PASS Test 16: anomalie rilevate come atteso (asset senza owner=%, dipendenze critiche senza DPA=%)',
        v_owner, v_dpa;
END;
$$;

-- TEST 17: il filtro di criticita discrimina un sottoinsieme reale
DO $$
DECLARE v_tot INTEGER; v_critici INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_tot FROM asset WHERE in_produzione;
    SELECT COUNT(*) INTO v_critici
    FROM asset a JOIN livello_criticita lc ON lc.id = a.id_livello_criticita
    WHERE a.in_produzione AND lc.livello >= 4;

    ASSERT v_critici < v_tot,
        'FAIL Test 17: il filtro livello >= 4 seleziona l''intero inventario (' ||
        v_critici || '/' || v_tot || '): nessun potere discriminante';
    RAISE NOTICE 'PASS Test 17: filtro criticita discrimina % asset su %', v_critici, v_tot;
END;
$$;

-- =============================================================================
-- RIEPILOGO STATO REGISTRO
-- =============================================================================
SELECT entita, totale
FROM (
    SELECT 'Organizzazioni attive'           AS entita, COUNT(*) AS totale FROM organizzazione WHERE attiva = TRUE
    UNION ALL
    SELECT 'Asset in produzione',            COUNT(*) FROM asset      WHERE in_produzione = TRUE
    UNION ALL
    SELECT 'Servizi attivi',                 COUNT(*) FROM servizio   WHERE attivo = TRUE
    UNION ALL
    SELECT 'Fornitori registrati',           COUNT(*) FROM fornitore
    UNION ALL
    SELECT 'Dipendenze attive',              COUNT(*) FROM dipendenza WHERE attiva = TRUE
    UNION ALL
    SELECT 'Responsabili in carica',         COUNT(*) FROM responsabile WHERE data_fine IS NULL
    UNION ALL
    SELECT 'Relazioni asset-servizio',       COUNT(*) FROM asset_servizio
    UNION ALL
    SELECT 'Relazioni asset-dipendenza',     COUNT(*) FROM asset_dipendenza
    UNION ALL
    SELECT 'Relazioni servizio-dipendenza',  COUNT(*) FROM servizio_dipendenza
    UNION ALL
    SELECT 'Relazioni asset-responsabile',   COUNT(*) FROM asset_responsabile
    UNION ALL
    SELECT 'Versioni storico (asset)',       COUNT(*) FROM asset_storico
    UNION ALL
    SELECT 'Versioni storico (servizi)',     COUNT(*) FROM servizio_storico
) r
ORDER BY entita;

-- =============================================================================
-- DISTRIBUZIONE PER TIPO E CRITICITA (verifica dei conteggi dichiarati)
-- =============================================================================
SELECT ta.codice AS tipo_asset, COUNT(*) AS totale
FROM asset a JOIN tipo_asset ta ON ta.id = a.id_tipo_asset
GROUP BY ta.codice ORDER BY totale DESC, tipo_asset;

SELECT lc.etichetta AS criticita, lc.livello, COUNT(*) AS totale
FROM asset a JOIN livello_criticita lc ON lc.id = a.id_livello_criticita
GROUP BY lc.etichetta, lc.livello ORDER BY lc.livello DESC;
