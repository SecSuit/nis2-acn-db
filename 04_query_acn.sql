-- =============================================================================
-- NIS2/ACN — Query per la Generazione dei Profili ACN e Output CSV
--
-- Tutte le view filtrano o.attiva = TRUE: un soggetto cessato non deve comparire
-- nel profilo ACN, coerentemente con il controllo di esistenza effettuato da
-- fn_esporta_profilo_acn().
-- Tutte le concatenazioni di nome/cognome usano l'operatore || (NULL-propagating)
-- e non CONCAT(), che restituisce '' al posto di NULL e neutralizzerebbe COALESCE.
-- =============================================================================

-- =============================================================================
-- QUERY 1: Asset critici per organizzazione (livello >= 4 = ALTO o CRITICO)
-- Include i campi dell'inventario richiesti dal Reg. (UE) 2024/2690 punto 12.3
-- =============================================================================

SELECT
    o.numero_registrazione_acn                        AS codice_acn,
    o.denominazione                                   AS organizzazione,
    a.codice_interno                                  AS codice_asset,
    a.nome                                            AS nome_asset,
    ta.codice                                         AS tipo_asset,
    lc.etichetta                                      AS criticita,
    a.produttore,
    a.modello_versione,
    a.ubicazione,
    COALESCE(a.hostname, a.indirizzo_ip::TEXT, 'N/D') AS identificatore_rete,
    COALESCE(a.data_ultima_patch::TEXT, 'N/D')        AS data_ultima_patch,
    COALESCE(a.stato_valutazione_rischio, 'NON_VALUTATO') AS stato_valutazione_rischio,
    COALESCE(r.cognome || ' ' || r.nome, 'N/D')       AS proprietario,
    COALESCE(r.email, 'N/D')                          AS email_proprietario
FROM asset a
JOIN organizzazione    o  ON o.id = a.id_organizzazione
JOIN tipo_asset        ta ON ta.id = a.id_tipo_asset
JOIN livello_criticita lc ON lc.id = a.id_livello_criticita
LEFT JOIN asset_responsabile ar ON ar.id_asset = a.id
    AND ar.tipo_responsabilita = 'PROPRIETARIO' AND ar.data_fine IS NULL
LEFT JOIN responsabile r ON r.id = ar.id_responsabile
WHERE a.in_produzione = TRUE
  AND o.attiva = TRUE
  AND lc.livello >= 4
ORDER BY o.id, lc.livello DESC, a.codice_interno;

-- =============================================================================
-- QUERY 2: Servizi erogati con RTO/RPO in minuti e responsabili
-- =============================================================================

SELECT
    o.numero_registrazione_acn                    AS codice_acn,
    o.denominazione                               AS organizzazione,
    s.codice_interno                              AS codice_servizio,
    s.nome                                        AS nome_servizio,
    ts.descrizione                                AS tipo_servizio,
    lc.etichetta                                  AS criticita,
    s.rto_minuti,
    s.rpo_minuti,
    s.disponibilita_target                        AS sla_percent,
    s.dati_personali,
    s.classificazione_dati,
    s.normative_applicabili,
    COALESCE(rp.cognome || ' ' || rp.nome, 'N/D') AS proprietario,
    COALESCE(rp.email, 'N/D')                     AS email_proprietario,
    COALESCE(rs.cognome || ' ' || rs.nome, 'N/D') AS referente_sicurezza,
    COALESCE(rs.email, 'N/D')                     AS email_sicurezza
FROM servizio s
JOIN organizzazione    o  ON o.id = s.id_organizzazione
JOIN tipo_servizio     ts ON ts.id = s.id_tipo_servizio
JOIN livello_criticita lc ON lc.id = s.id_livello_criticita
LEFT JOIN servizio_responsabile srp ON srp.id_servizio = s.id
    AND srp.tipo_responsabilita = 'PROPRIETARIO' AND srp.data_fine IS NULL
LEFT JOIN responsabile rp ON rp.id = srp.id_responsabile
LEFT JOIN servizio_responsabile srs ON srs.id_servizio = s.id
    AND srs.tipo_responsabilita = 'REFERENTE_SICUREZZA' AND srs.data_fine IS NULL
LEFT JOIN responsabile rs ON rs.id = srs.id_responsabile
WHERE s.attivo = TRUE
  AND o.attiva = TRUE
ORDER BY o.id, lc.livello DESC, s.codice_interno;

-- =============================================================================
-- QUERY 3: Dipendenze da terze parti con DPA e paesi di elaborazione dati
-- =============================================================================

SELECT
    o.numero_registrazione_acn                       AS codice_acn,
    o.denominazione                                  AS organizzazione,
    d.codice_interno                                 AS codice_dipendenza,
    f.ragione_sociale                                AS fornitore,
    f.paese                                          AS paese_fornitore,
    td.codice                                        AS tipo_dipendenza,
    d.denominazione_servizio,
    lc.etichetta                                     AS criticita,
    d.data_inizio,
    COALESCE(d.data_scadenza::TEXT, 'Indeterminato') AS data_scadenza,
    COALESCE(d.paesi_elaborazione_dati, 'N/D')       AS paesi_dati,
    CASE WHEN d.dpa_firmato THEN 'SI' ELSE 'NO' END  AS dpa_firmato,
    COALESCE(d.sla_disponibilita::TEXT, 'N/D')       AS sla_fornitore,
    COALESCE(d.contratto_numero, 'N/D')              AS contratto,
    COALESCE(f.certificazioni, 'N/D')                AS cert_fornitore,
    COALESCE(f.email_sicurezza, 'N/D')               AS email_sicurezza_fornitore
FROM dipendenza d
JOIN organizzazione    o  ON o.id = d.id_organizzazione
JOIN fornitore         f  ON f.id = d.id_fornitore
JOIN tipo_dipendenza   td ON td.id = d.id_tipo_dipendenza
JOIN livello_criticita lc ON lc.id = d.id_livello_criticita
WHERE d.attiva = TRUE
  AND o.attiva = TRUE
ORDER BY o.id, lc.livello DESC, f.ragione_sociale;

-- =============================================================================
-- QUERY 4: Punti di contatto per organizzazione
-- =============================================================================

SELECT
    o.numero_registrazione_acn  AS codice_acn,
    o.denominazione             AS organizzazione,
    o.codice_fiscale,
    ro.codice                   AS ruolo,
    ro.descrizione              AS ruolo_descrizione,
    r.cognome,
    r.nome,
    r.email,
    COALESCE(r.telefono, 'N/D') AS telefono,
    r.data_inizio               AS in_carica_dal
FROM responsabile r
JOIN organizzazione      o  ON o.id = r.id_organizzazione
JOIN ruolo_organizzativo ro ON ro.id = r.id_ruolo
WHERE r.data_fine IS NULL
  AND o.attiva = TRUE
ORDER BY o.id, ro.codice;

-- =============================================================================
-- QUERY 5: Mappa servizi -> asset -> dipendenze (vista d'insieme)
-- Le due LEFT JOIN indipendenti producono un prodotto cartesiano parziale:
-- STRING_AGG(DISTINCT ...) lo neutralizza a livello di risultato.
-- =============================================================================

SELECT
    o.denominazione                               AS organizzazione,
    s.codice_interno                              AS codice_servizio,
    s.nome                                        AS servizio,
    lc.etichetta                                  AS criticita,
    STRING_AGG(DISTINCT a.nome, ' | ')            AS asset_di_supporto,
    STRING_AGG(DISTINCT f.ragione_sociale, ' | ') AS fornitori_dipendenza
FROM servizio s
JOIN organizzazione    o  ON o.id = s.id_organizzazione
JOIN livello_criticita lc ON lc.id = s.id_livello_criticita
LEFT JOIN asset_servizio   aserv ON aserv.id_servizio = s.id
LEFT JOIN asset            a     ON a.id = aserv.id_asset AND a.in_produzione = TRUE
LEFT JOIN servizio_dipendenza sd ON sd.id_servizio = s.id
LEFT JOIN dipendenza          d  ON d.id = sd.id_dipendenza AND d.attiva = TRUE
LEFT JOIN fornitore           f  ON f.id = d.id_fornitore
WHERE s.attivo = TRUE
  AND o.attiva = TRUE
GROUP BY o.denominazione, s.codice_interno, s.nome, lc.etichetta
ORDER BY o.denominazione, s.codice_interno;

-- =============================================================================
-- QUERY 6: Controlli di qualita — anomalie di conformita nel registro
-- Sul dataset simulato rileva 3 anomalie deliberate:
--   2 x ASSET_SENZA_PROPRIETARIO      (Reg. (UE) 2024/2690 punto 12.4)
--   1 x DIPENDENZA_CRITICA_SENZA_DPA  (GDPR art. 28 + NIS2 art. 21(2)(d))
-- =============================================================================

SELECT 'ASSET_SENZA_PROPRIETARIO'      AS anomalia,
       a.codice_interno                AS riferimento,
       a.nome                          AS descrizione,
       o.denominazione                 AS organizzazione
FROM asset a
JOIN organizzazione o ON o.id = a.id_organizzazione
WHERE a.in_produzione = TRUE
  AND o.attiva = TRUE
  AND NOT EXISTS (
    SELECT 1 FROM asset_responsabile ar
    WHERE ar.id_asset = a.id
      AND ar.tipo_responsabilita = 'PROPRIETARIO'
      AND ar.data_fine IS NULL
  )

UNION ALL

SELECT 'SERVIZIO_SENZA_RTO',
       s.codice_interno, s.nome, o.denominazione
FROM servizio s
JOIN organizzazione o ON o.id = s.id_organizzazione
WHERE s.attivo = TRUE AND o.attiva = TRUE AND s.rto_minuti IS NULL

UNION ALL

SELECT 'DIPENDENZA_CRITICA_SENZA_DPA',
       d.codice_interno, d.denominazione_servizio, o.denominazione
FROM dipendenza d
JOIN organizzazione    o  ON o.id = d.id_organizzazione
JOIN livello_criticita lc ON lc.id = d.id_livello_criticita
WHERE d.attiva = TRUE AND o.attiva = TRUE
  AND d.dpa_firmato = FALSE AND lc.livello >= 4

UNION ALL

SELECT 'ASSET_SENZA_VALUTAZIONE_RISCHIO',
       a.codice_interno, a.nome, o.denominazione
FROM asset a
JOIN organizzazione    o  ON o.id = a.id_organizzazione
JOIN livello_criticita lc ON lc.id = a.id_livello_criticita
WHERE a.in_produzione = TRUE AND o.attiva = TRUE
  AND lc.livello >= 4
  AND COALESCE(a.stato_valutazione_rischio,'NON_VALUTATO') = 'NON_VALUTATO'

ORDER BY 1, 4, 2;

-- =============================================================================
-- FUNZIONE DI UTILITA: quoting CSV conforme RFC 4180
-- - racchiude sempre il valore tra apici doppi
-- - raddoppia gli apici doppi interni ("" ) come prescritto dalla RFC
-- - neutralizza la formula injection anteponendo un apice singolo ai valori che
--   iniziano con = + @ (un '-' iniziale e lasciato intatto: e un numero negativo)
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_csv_quote(p_val TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT '"' ||
           replace(
               CASE WHEN left(COALESCE(p_val,''), 1) IN ('=','+','@')
                    THEN '''' || COALESCE(p_val,'')
                    ELSE COALESCE(p_val,'')
               END,
               '"', '""'
           ) || '"';
$$;

COMMENT ON FUNCTION fn_csv_quote(TEXT) IS
    'Quoting CSV RFC 4180: apici doppi raddoppiati, protezione formula injection';

-- =============================================================================
-- VIEW: vw_profilo_acn_asset — Sezione 1 del profilo ACN
-- Espone tutti i campi minimi dell'inventario ex Reg. (UE) 2024/2690 punto 12.3:
-- identificatore, proprietario, descrizione, ubicazione, tipo, classificazione,
-- data ultima patch, stato valutazione rischio, fine vita.
-- =============================================================================

CREATE OR REPLACE VIEW vw_profilo_acn_asset AS
SELECT
    o.numero_registrazione_acn                              AS "ID_ACN",
    o.denominazione                                         AS "ORGANIZZAZIONE",
    o.codice_fiscale                                        AS "CF_PIVA",
    sn.descrizione                                          AS "SETTORE_NIS2",
    ts.codice                                               AS "TIPO_SOGGETTO",
    a.codice_interno                                        AS "COD_ASSET",
    a.nome                                                  AS "NOME_ASSET",
    ta.codice                                               AS "TIPO_ASSET",
    lc.etichetta                                            AS "CRITICITA",
    lc.livello                                              AS "LIVELLO_NUM",
    COALESCE(a.produttore,      'N/D')                      AS "PRODUTTORE",
    COALESCE(a.modello_versione,'N/D')                      AS "MODELLO_VERSIONE",
    COALESCE(a.ubicazione,      'N/D')                      AS "UBICAZIONE",
    COALESCE(a.hostname, a.indirizzo_ip::TEXT, 'N/D')       AS "IDENTIFICATORE",
    CASE WHEN a.in_produzione THEN 'SI' ELSE 'NO' END       AS "IN_PRODUZIONE",
    COALESCE(TO_CHAR(a.data_ultima_patch,'YYYY-MM-DD'),'N/D') AS "DATA_ULTIMA_PATCH",
    COALESCE(a.stato_valutazione_rischio,'NON_VALUTATO')    AS "STATO_VAL_RISCHIO",
    COALESCE(TO_CHAR(a.data_fine_vita,'YYYY-MM-DD'),'N/D')  AS "DATA_FINE_VITA",
    COALESCE(r.cognome || ' ' || r.nome, 'N/D')             AS "PROPRIETARIO",
    COALESCE(r.email, 'N/D')                                AS "EMAIL_PROPRIETARIO",
    TO_CHAR(a.data_modifica, 'YYYY-MM-DD')                  AS "DATA_AGGIORNAMENTO",
    a.versione_record                                       AS "VERSIONE"
FROM asset a
JOIN organizzazione    o  ON o.id = a.id_organizzazione
JOIN settore_nis2      sn ON sn.id = o.id_settore_nis2
JOIN tipo_soggetto     ts ON ts.id = o.id_tipo_soggetto
JOIN tipo_asset        ta ON ta.id = a.id_tipo_asset
JOIN livello_criticita lc ON lc.id = a.id_livello_criticita
LEFT JOIN asset_responsabile ar ON ar.id_asset = a.id
    AND ar.tipo_responsabilita = 'PROPRIETARIO' AND ar.data_fine IS NULL
LEFT JOIN responsabile r ON r.id = ar.id_responsabile
WHERE a.in_produzione = TRUE
  AND o.attiva = TRUE;

COMMENT ON VIEW vw_profilo_acn_asset IS
    'Sezione 1 profilo ACN — inventario asset ex Reg. (UE) 2024/2690 punto 12.3. '
    'Export: \COPY (SELECT * FROM vw_profilo_acn_asset WHERE "ID_ACN"=''ACN-2024-00123'') '
    'TO ''asset.csv'' WITH (FORMAT csv, HEADER, QUOTE ''"'', FORCE_QUOTE *);';

-- =============================================================================
-- VIEW: vw_profilo_acn_servizi — Sezione 2
-- =============================================================================

CREATE OR REPLACE VIEW vw_profilo_acn_servizi AS
SELECT
    o.numero_registrazione_acn                         AS "ID_ACN",
    o.denominazione                                    AS "ORGANIZZAZIONE",
    s.codice_interno                                   AS "COD_SERVIZIO",
    s.nome                                             AS "NOME_SERVIZIO",
    ts.descrizione                                     AS "TIPO_SERVIZIO",
    lc.etichetta                                       AS "CRITICITA",
    COALESCE(s.rto_minuti::TEXT, 'N/D')                AS "RTO_MINUTI",
    COALESCE(s.rpo_minuti::TEXT, 'N/D')                AS "RPO_MINUTI",
    COALESCE(s.disponibilita_target::TEXT, 'N/D')      AS "SLA_PERCENT",
    CASE WHEN s.dati_personali THEN 'SI' ELSE 'NO' END AS "DATI_PERSONALI",
    COALESCE(s.classificazione_dati, 'N/D')            AS "CLASS_DATI",
    COALESCE(s.normative_applicabili, 'N/D')           AS "NORMATIVE",
    COALESCE(rp.cognome || ' ' || rp.nome, 'N/D')      AS "PROPRIETARIO",
    COALESCE(rp.email, 'N/D')                          AS "EMAIL_PROPRIETARIO",
    TO_CHAR(s.data_modifica, 'YYYY-MM-DD')             AS "DATA_AGGIORNAMENTO"
FROM servizio s
JOIN organizzazione    o  ON o.id = s.id_organizzazione
JOIN tipo_servizio     ts ON ts.id = s.id_tipo_servizio
JOIN livello_criticita lc ON lc.id = s.id_livello_criticita
LEFT JOIN servizio_responsabile srp ON srp.id_servizio = s.id
    AND srp.tipo_responsabilita = 'PROPRIETARIO' AND srp.data_fine IS NULL
LEFT JOIN responsabile rp ON rp.id = srp.id_responsabile
WHERE s.attivo = TRUE
  AND o.attiva = TRUE;

COMMENT ON VIEW vw_profilo_acn_servizi IS
    'Sezione 2 profilo ACN — servizi erogati con RTO/RPO in minuti';

-- =============================================================================
-- VIEW: vw_profilo_acn_dipendenze — Sezione 3
-- =============================================================================

CREATE OR REPLACE VIEW vw_profilo_acn_dipendenze AS
SELECT
    o.numero_registrazione_acn                              AS "ID_ACN",
    o.denominazione                                         AS "ORGANIZZAZIONE",
    d.codice_interno                                        AS "COD_DIPENDENZA",
    f.ragione_sociale                                       AS "FORNITORE",
    f.paese                                                 AS "PAESE_FORNITORE",
    td.codice                                               AS "TIPO_DIPENDENZA",
    d.denominazione_servizio                                AS "SERVIZIO_FORNITORE",
    lc.etichetta                                            AS "CRITICITA",
    TO_CHAR(d.data_inizio, 'YYYY-MM-DD')                    AS "DATA_INIZIO",
    COALESCE(TO_CHAR(d.data_scadenza,'YYYY-MM-DD'),'Indeterminato') AS "DATA_SCADENZA",
    COALESCE(d.paesi_elaborazione_dati, 'N/D')              AS "PAESI_DATO",
    CASE WHEN d.dpa_firmato THEN 'SI' ELSE 'NO' END         AS "DPA_FIRMATO",
    COALESCE(d.sla_disponibilita::TEXT, 'N/D')              AS "SLA_FORNITORE",
    COALESCE(d.contratto_numero, 'N/D')                     AS "N_CONTRATTO",
    COALESCE(f.certificazioni, 'N/D')                       AS "CERT_FORNITORE",
    COALESCE(f.email_sicurezza, 'N/D')                      AS "EMAIL_SICUREZZA_FORNITORE"
FROM dipendenza d
JOIN organizzazione    o  ON o.id = d.id_organizzazione
JOIN fornitore         f  ON f.id = d.id_fornitore
JOIN tipo_dipendenza   td ON td.id = d.id_tipo_dipendenza
JOIN livello_criticita lc ON lc.id = d.id_livello_criticita
WHERE d.attiva = TRUE
  AND o.attiva = TRUE;

COMMENT ON VIEW vw_profilo_acn_dipendenze IS
    'Sezione 3 profilo ACN — supply chain, Reg. (UE) 2024/2690 punto 14';

-- =============================================================================
-- VIEW: vw_profilo_acn_contatti — Sezione 4
-- =============================================================================

CREATE OR REPLACE VIEW vw_profilo_acn_contatti AS
SELECT
    o.numero_registrazione_acn           AS "ID_ACN",
    o.denominazione                      AS "ORGANIZZAZIONE",
    o.codice_fiscale                     AS "CF_PIVA",
    sn.descrizione                       AS "SETTORE",
    ts.codice                            AS "TIPO_SOGGETTO",
    ro.codice                            AS "RUOLO",
    ro.descrizione                       AS "RUOLO_DESCRIZIONE",
    r.cognome                            AS "COGNOME",
    r.nome                               AS "NOME",
    r.email                              AS "EMAIL",
    COALESCE(r.telefono, 'N/D')          AS "TELEFONO",
    TO_CHAR(r.data_inizio, 'YYYY-MM-DD') AS "IN_CARICA_DAL"
FROM responsabile r
JOIN organizzazione      o  ON o.id = r.id_organizzazione
JOIN settore_nis2        sn ON sn.id = o.id_settore_nis2
JOIN tipo_soggetto       ts ON ts.id = o.id_tipo_soggetto
JOIN ruolo_organizzativo ro ON ro.id = r.id_ruolo
WHERE r.data_fine IS NULL
  AND o.attiva = TRUE;

COMMENT ON VIEW vw_profilo_acn_contatti IS
    'Sezione 4 profilo ACN — punti di contatto ex art. 23 D.Lgs. 138/2024';

-- =============================================================================
-- FUNZIONE: fn_esporta_profilo_acn
-- Genera il profilo ACN completo (4 sezioni) come testo CSV conforme RFC 4180.
-- Ogni campo passa da fn_csv_quote(): gli apici doppi interni sono raddoppiati,
-- quindi un valore come  Server "Core", sede B  non spezza il record.
-- Utilizzo: SELECT fn_esporta_profilo_acn('ACN-2024-00123');
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_esporta_profilo_acn(p_codice_acn TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_out  TEXT := '';
    v_riga TEXT;
    v_sep  TEXT := ',';
    v_nl   TEXT := E'\n';
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM organizzazione
        WHERE numero_registrazione_acn = p_codice_acn AND attiva = TRUE
    ) THEN
        RETURN 'ERRORE: Nessuna organizzazione attiva trovata con codice ACN ' || p_codice_acn;
    END IF;

    -- -------------------------------------------------------------------------
    -- INTESTAZIONE
    -- -------------------------------------------------------------------------
    v_out := v_out
          || '=== PROFILO ACN - REGISTRO NIS2 ===' || v_nl
          || 'Codice ACN: ' || p_codice_acn || v_nl
          || 'Generato il: ' || TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS') || v_nl
          || 'Formato: CSV RFC 4180' || v_nl
          || v_nl;

    -- -------------------------------------------------------------------------
    -- SEZIONE 1 — ASSET (Reg. (UE) 2024/2690 punto 12.3)
    -- -------------------------------------------------------------------------
    v_out := v_out || '--- SEZIONE 1: ASSET ---' || v_nl;
    v_out := v_out
          || fn_csv_quote('ID_ACN')             || v_sep
          || fn_csv_quote('ORGANIZZAZIONE')     || v_sep
          || fn_csv_quote('COD_ASSET')          || v_sep
          || fn_csv_quote('NOME_ASSET')         || v_sep
          || fn_csv_quote('TIPO_ASSET')         || v_sep
          || fn_csv_quote('CRITICITA')          || v_sep
          || fn_csv_quote('PRODUTTORE')         || v_sep
          || fn_csv_quote('MODELLO_VERSIONE')   || v_sep
          || fn_csv_quote('UBICAZIONE')         || v_sep
          || fn_csv_quote('IDENTIFICATORE')     || v_sep
          || fn_csv_quote('IN_PRODUZIONE')      || v_sep
          || fn_csv_quote('DATA_ULTIMA_PATCH')  || v_sep
          || fn_csv_quote('STATO_VAL_RISCHIO')  || v_sep
          || fn_csv_quote('DATA_FINE_VITA')     || v_sep
          || fn_csv_quote('PROPRIETARIO')       || v_sep
          || fn_csv_quote('EMAIL_PROPRIETARIO') || v_sep
          || fn_csv_quote('DATA_AGGIORNAMENTO') || v_sep
          || fn_csv_quote('VERSIONE')           || v_nl;

    FOR v_riga IN
        SELECT
            fn_csv_quote("ID_ACN")             || v_sep ||
            fn_csv_quote("ORGANIZZAZIONE")     || v_sep ||
            fn_csv_quote("COD_ASSET")          || v_sep ||
            fn_csv_quote("NOME_ASSET")         || v_sep ||
            fn_csv_quote("TIPO_ASSET")         || v_sep ||
            fn_csv_quote("CRITICITA")          || v_sep ||
            fn_csv_quote("PRODUTTORE")         || v_sep ||
            fn_csv_quote("MODELLO_VERSIONE")   || v_sep ||
            fn_csv_quote("UBICAZIONE")         || v_sep ||
            fn_csv_quote("IDENTIFICATORE")     || v_sep ||
            fn_csv_quote("IN_PRODUZIONE")      || v_sep ||
            fn_csv_quote("DATA_ULTIMA_PATCH")  || v_sep ||
            fn_csv_quote("STATO_VAL_RISCHIO")  || v_sep ||
            fn_csv_quote("DATA_FINE_VITA")     || v_sep ||
            fn_csv_quote("PROPRIETARIO")       || v_sep ||
            fn_csv_quote("EMAIL_PROPRIETARIO") || v_sep ||
            fn_csv_quote("DATA_AGGIORNAMENTO") || v_sep ||
            fn_csv_quote("VERSIONE"::TEXT)
        FROM vw_profilo_acn_asset
        WHERE "ID_ACN" = p_codice_acn
        ORDER BY "LIVELLO_NUM" DESC, "COD_ASSET"
    LOOP
        v_out := v_out || v_riga || v_nl;
    END LOOP;

    -- -------------------------------------------------------------------------
    -- SEZIONE 2 — SERVIZI
    -- -------------------------------------------------------------------------
    v_out := v_out || v_nl || '--- SEZIONE 2: SERVIZI ---' || v_nl;
    v_out := v_out
          || fn_csv_quote('ID_ACN')             || v_sep
          || fn_csv_quote('ORGANIZZAZIONE')     || v_sep
          || fn_csv_quote('COD_SERVIZIO')       || v_sep
          || fn_csv_quote('NOME_SERVIZIO')      || v_sep
          || fn_csv_quote('TIPO_SERVIZIO')      || v_sep
          || fn_csv_quote('CRITICITA')          || v_sep
          || fn_csv_quote('RTO_MINUTI')         || v_sep
          || fn_csv_quote('RPO_MINUTI')         || v_sep
          || fn_csv_quote('SLA_PERCENT')        || v_sep
          || fn_csv_quote('DATI_PERSONALI')     || v_sep
          || fn_csv_quote('CLASS_DATI')         || v_sep
          || fn_csv_quote('NORMATIVE')          || v_sep
          || fn_csv_quote('PROPRIETARIO')       || v_sep
          || fn_csv_quote('EMAIL_PROPRIETARIO') || v_sep
          || fn_csv_quote('DATA_AGGIORNAMENTO') || v_nl;

    FOR v_riga IN
        SELECT
            fn_csv_quote("ID_ACN")             || v_sep ||
            fn_csv_quote("ORGANIZZAZIONE")     || v_sep ||
            fn_csv_quote("COD_SERVIZIO")       || v_sep ||
            fn_csv_quote("NOME_SERVIZIO")      || v_sep ||
            fn_csv_quote("TIPO_SERVIZIO")      || v_sep ||
            fn_csv_quote("CRITICITA")          || v_sep ||
            fn_csv_quote("RTO_MINUTI")         || v_sep ||
            fn_csv_quote("RPO_MINUTI")         || v_sep ||
            fn_csv_quote("SLA_PERCENT")        || v_sep ||
            fn_csv_quote("DATI_PERSONALI")     || v_sep ||
            fn_csv_quote("CLASS_DATI")         || v_sep ||
            fn_csv_quote("NORMATIVE")          || v_sep ||
            fn_csv_quote("PROPRIETARIO")       || v_sep ||
            fn_csv_quote("EMAIL_PROPRIETARIO") || v_sep ||
            fn_csv_quote("DATA_AGGIORNAMENTO")
        FROM vw_profilo_acn_servizi
        WHERE "ID_ACN" = p_codice_acn
        ORDER BY "COD_SERVIZIO"
    LOOP
        v_out := v_out || v_riga || v_nl;
    END LOOP;

    -- -------------------------------------------------------------------------
    -- SEZIONE 3 — DIPENDENZE DA TERZI
    -- -------------------------------------------------------------------------
    v_out := v_out || v_nl || '--- SEZIONE 3: DIPENDENZE DA TERZI ---' || v_nl;
    v_out := v_out
          || fn_csv_quote('ID_ACN')                    || v_sep
          || fn_csv_quote('ORGANIZZAZIONE')            || v_sep
          || fn_csv_quote('COD_DIPENDENZA')            || v_sep
          || fn_csv_quote('FORNITORE')                 || v_sep
          || fn_csv_quote('PAESE_FORNITORE')           || v_sep
          || fn_csv_quote('TIPO_DIPENDENZA')           || v_sep
          || fn_csv_quote('SERVIZIO_FORNITORE')        || v_sep
          || fn_csv_quote('CRITICITA')                 || v_sep
          || fn_csv_quote('DATA_INIZIO')               || v_sep
          || fn_csv_quote('DATA_SCADENZA')             || v_sep
          || fn_csv_quote('PAESI_DATO')                || v_sep
          || fn_csv_quote('DPA_FIRMATO')               || v_sep
          || fn_csv_quote('SLA_FORNITORE')             || v_sep
          || fn_csv_quote('N_CONTRATTO')               || v_sep
          || fn_csv_quote('CERT_FORNITORE')            || v_sep
          || fn_csv_quote('EMAIL_SICUREZZA_FORNITORE') || v_nl;

    FOR v_riga IN
        SELECT
            fn_csv_quote("ID_ACN")                    || v_sep ||
            fn_csv_quote("ORGANIZZAZIONE")            || v_sep ||
            fn_csv_quote("COD_DIPENDENZA")            || v_sep ||
            fn_csv_quote("FORNITORE")                 || v_sep ||
            fn_csv_quote("PAESE_FORNITORE")           || v_sep ||
            fn_csv_quote("TIPO_DIPENDENZA")           || v_sep ||
            fn_csv_quote("SERVIZIO_FORNITORE")        || v_sep ||
            fn_csv_quote("CRITICITA")                 || v_sep ||
            fn_csv_quote("DATA_INIZIO")               || v_sep ||
            fn_csv_quote("DATA_SCADENZA")             || v_sep ||
            fn_csv_quote("PAESI_DATO")                || v_sep ||
            fn_csv_quote("DPA_FIRMATO")               || v_sep ||
            fn_csv_quote("SLA_FORNITORE")             || v_sep ||
            fn_csv_quote("N_CONTRATTO")               || v_sep ||
            fn_csv_quote("CERT_FORNITORE")            || v_sep ||
            fn_csv_quote("EMAIL_SICUREZZA_FORNITORE")
        FROM vw_profilo_acn_dipendenze
        WHERE "ID_ACN" = p_codice_acn
        ORDER BY "COD_DIPENDENZA"
    LOOP
        v_out := v_out || v_riga || v_nl;
    END LOOP;

    -- -------------------------------------------------------------------------
    -- SEZIONE 4 — PUNTI DI CONTATTO
    -- -------------------------------------------------------------------------
    v_out := v_out || v_nl || '--- SEZIONE 4: PUNTI DI CONTATTO ---' || v_nl;
    v_out := v_out
          || fn_csv_quote('ID_ACN')            || v_sep
          || fn_csv_quote('ORGANIZZAZIONE')    || v_sep
          || fn_csv_quote('CF_PIVA')           || v_sep
          || fn_csv_quote('SETTORE')           || v_sep
          || fn_csv_quote('TIPO_SOGGETTO')     || v_sep
          || fn_csv_quote('RUOLO')             || v_sep
          || fn_csv_quote('RUOLO_DESCRIZIONE') || v_sep
          || fn_csv_quote('COGNOME')           || v_sep
          || fn_csv_quote('NOME')              || v_sep
          || fn_csv_quote('EMAIL')             || v_sep
          || fn_csv_quote('TELEFONO')          || v_sep
          || fn_csv_quote('IN_CARICA_DAL')     || v_nl;

    FOR v_riga IN
        SELECT
            fn_csv_quote("ID_ACN")            || v_sep ||
            fn_csv_quote("ORGANIZZAZIONE")    || v_sep ||
            fn_csv_quote("CF_PIVA")           || v_sep ||
            fn_csv_quote("SETTORE")           || v_sep ||
            fn_csv_quote("TIPO_SOGGETTO")     || v_sep ||
            fn_csv_quote("RUOLO")             || v_sep ||
            fn_csv_quote("RUOLO_DESCRIZIONE") || v_sep ||
            fn_csv_quote("COGNOME")           || v_sep ||
            fn_csv_quote("NOME")              || v_sep ||
            fn_csv_quote("EMAIL")             || v_sep ||
            fn_csv_quote("TELEFONO")          || v_sep ||
            fn_csv_quote("IN_CARICA_DAL")
        FROM vw_profilo_acn_contatti
        WHERE "ID_ACN" = p_codice_acn
        ORDER BY "RUOLO"
    LOOP
        v_out := v_out || v_riga || v_nl;
    END LOOP;

    RETURN v_out;
END;
$$;

COMMENT ON FUNCTION fn_esporta_profilo_acn(TEXT) IS
    'Profilo ACN completo (asset+servizi+dipendenze+contatti) come CSV RFC 4180 '
    'in 4 sezioni; ogni campo e quotato da fn_csv_quote()';

-- =============================================================================
-- ESPORTAZIONE SU FILE (da psql CLI)
-- Il comando COPY e la via canonica per l'export su file: applica l'escaping
-- RFC 4180 nativamente. fn_esporta_profilo_acn() serve per l'anteprima
-- completa in un'unica chiamata (es. da pgAdmin Query Tool).
-- =============================================================================

-- SELECT fn_esporta_profilo_acn('ACN-2024-00123');
--
-- \COPY (SELECT * FROM vw_profilo_acn_asset      WHERE "ID_ACN"='ACN-2024-00123') TO 'asset.csv'      WITH (FORMAT csv, HEADER, QUOTE '"', FORCE_QUOTE *);
-- \COPY (SELECT * FROM vw_profilo_acn_servizi    WHERE "ID_ACN"='ACN-2024-00123') TO 'servizi.csv'    WITH (FORMAT csv, HEADER, QUOTE '"', FORCE_QUOTE *);
-- \COPY (SELECT * FROM vw_profilo_acn_dipendenze WHERE "ID_ACN"='ACN-2024-00123') TO 'dipendenze.csv' WITH (FORMAT csv, HEADER, QUOTE '"', FORCE_QUOTE *);
-- \COPY (SELECT * FROM vw_profilo_acn_contatti   WHERE "ID_ACN"='ACN-2024-00123') TO 'contatti.csv'   WITH (FORMAT csv, HEADER, QUOTE '"', FORCE_QUOTE *);
