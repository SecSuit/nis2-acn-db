-- =============================================================================
-- NIS2/ACN — Dati di Test
-- Scenario: 2 soggetti NIS2 essenziali
--   1. Zagara Neuro Therapeutics S.r.l. (Trapani) — settore sanitario
--   2. Sole di Sicilia S.p.A. (Palermo) — settore energia rinnovabile
--
-- NOTE DI PROGETTAZIONE DEL DATASET
--   - rto_minuti / rpo_minuti sono espressi in MINUTI (non ore): permette
--     granularita sub-oraria per sistemi OT/SCADA (RTO 4h = 240 min; RPO = 0 min).
--   - La distribuzione di criticita copre tutti e 5 i livelli (CRITICO..BASSO)
--     cosi che il filtro "asset critici" (livello >= 4) discrimini realmente
--     un sottoinsieme (15 su 18) invece di restituire l'intero inventario.
--   - Due anomalie di conformita sono DELIBERATE e servono a dimostrare la
--     capacita di rilevamento del registro (Query 6):
--       * 2 asset privi di PROPRIETARIO   -> Reg. (UE) 2024/2690 punto 12.4
--       * 2 dipendenze prive di DPA, di cui 1 ad alta criticita -> GDPR art. 28
--
-- Standard di riferimento:
--   Reg. (UE) 2024/2690 punti 12.3 (inventario) e 12.4 (proprietario)
--   ACN Determinazione n. 164179 del 14 aprile 2025
--
-- DISCLAIMER: tutti i dati (organizzazioni, codici fiscali, contatti, contratti,
-- fornitori) sono completamente fittizi e generati a scopo didattico.
-- =============================================================================

-- =============================================================================
-- LOOKUP TABLES
-- =============================================================================

INSERT INTO tipo_asset (codice, descrizione) VALUES
    ('HW',    'Hardware — Server, workstation, dispositivi fisici'),
    ('SW',    'Software — Applicazioni, sistemi operativi, middleware'),
    ('DATO',  'Dataset — Banche dati, archivi, repository documentali'),
    ('RETE',  'Infrastruttura di rete — Switch, router, firewall, VPN'),
    ('CLOUD', 'Servizio cloud — IaaS, PaaS, SaaS in outsourcing'),
    ('FISICO','Asset fisico — Datacenter, sale server, UPS, HVAC'),
    ('IOT',   'Dispositivo IoT/OT — Sensori, attuatori, SCADA, PLC');

INSERT INTO livello_criticita (codice, etichetta, livello) VALUES
    ('BASSO',       'Basso',       1),
    ('MEDIO_BASSO', 'Medio-Basso', 2),
    ('MEDIO',       'Medio',       3),
    ('ALTO',        'Alto',        4),
    ('CRITICO',     'Critico',     5);

-- Allegato I = settori ad alta criticita (non sinonimo di "essenziale").
-- La classificazione essenziale/importante dipende da settore x dimensione.
INSERT INTO settore_nis2 (codice, descrizione, allegato) VALUES
    ('SANITARIO',      'Settore sanitario (ospedali, ASL, laboratori)',               'I'),
    ('ENERGIA_ELETTR', 'Energia elettrica — produzione, trasmissione, distribuzione', 'I'),
    ('ENERGIA_GAS',    'Gas naturale — trasporto, distribuzione, stoccaggio',         'I'),
    ('INFR_DIGITALE',  'Infrastrutture digitali (DNS, IXP, CDN, Cloud)',              'I'),
    ('BANCARIO',       'Settore bancario e finanziario',                              'I'),
    ('PA_CENTRALE',    'Pubblica Amministrazione centrale',                           'III'),
    ('MANIFATTURIERO', 'Settore manifatturiero (macchinari, automotive)',             'II'),
    ('RICERCA',        'Istituti di ricerca',                                         'II');

INSERT INTO tipo_soggetto (codice, descrizione) VALUES
    ('ESSENZIALE', 'Soggetto Essenziale — art. 6 co. 1 D.Lgs. 138/2024'),
    ('IMPORTANTE', 'Soggetto Importante — art. 6 co. 2 D.Lgs. 138/2024');

INSERT INTO tipo_servizio (codice, descrizione) VALUES
    ('CARTELLA_CLIN',    'Cartella clinica elettronica (CCE)'),
    ('PRENOTAZIONE',     'Prenotazione e accettazione pazienti (CUP)'),
    ('NEUROIMAGING',     'Gestione immagini diagnostiche neurologiche (PACS)'),
    ('SUPERVISIONE_RETE','Supervisione e controllo rete elettrica SCADA'),
    ('BILLING_ENERGIA',  'Fatturazione e gestione clienti energia'),
    ('BACKUP_DR',        'Backup e Disaster Recovery'),
    ('POSTA_ELETTR',     'Servizio di posta elettronica aziendale');

INSERT INTO tipo_dipendenza (codice, descrizione) VALUES
    ('CLOUD_IAAS',   'Cloud IaaS — Infrastruttura as a Service'),
    ('CLOUD_SAAS',   'Cloud SaaS — Software as a Service'),
    ('FORNITURA_SW', 'Fornitura e manutenzione software'),
    ('FORNITURA_HW', 'Fornitura e manutenzione hardware'),
    ('CONNETTIVITA', 'Connettivita Internet / WAN'),
    ('CLOUD_BACKUP', 'Backup e archiviazione cloud'),
    ('ALTRO',        'Altra tipologia di dipendenza da terzi');

INSERT INTO ruolo_organizzativo (codice, descrizione) VALUES
    ('CISO',           'Chief Information Security Officer'),
    ('DPO',            'Data Protection Officer (GDPR)'),
    ('RSPP',           'Responsabile Servizio Prevenzione e Protezione'),
    ('RESP_ICT',       'Responsabile ICT / CIO'),
    ('REFERENTE_NIS2', 'Referente NIS2 (punto di contatto ACN — art. 23 D.Lgs. 138/2024)'),
    ('AMM_SISTEMA',    'Amministratore di Sistema'),
    ('LEGALE',         'Responsabile Affari Legali e Compliance');

-- =============================================================================
-- ORGANIZZAZIONI
-- Entrambe grandi imprese (>= 250 dip.) operanti in Allegato I -> ESSENZIALE.
-- Soglia grande impresa = >= 250 dip. OPPURE (fatturato > 50 M€ E bilancio > 43 M€)
-- ai sensi della Raccomandazione 2003/361/CE richiamata dall'art. 3 D.Lgs. 138/2024.
-- =============================================================================

INSERT INTO organizzazione (
    codice_fiscale, denominazione,
    id_settore_nis2, id_tipo_soggetto,
    dimensione, indirizzo, comune, cap, paese,
    codice_nace, numero_dipendenti, fatturato_mln_eur,
    data_registrazione_acn, numero_registrazione_acn
) VALUES
(
    '04521367890',
    'Zagara Neuro Therapeutics S.r.l.',
    (SELECT id FROM settore_nis2  WHERE codice = 'SANITARIO'),
    (SELECT id FROM tipo_soggetto WHERE codice = 'ESSENZIALE'),
    'GRANDE', 'Piazza Roberto Sica, 23', 'Trapani', '91100', 'ITA',
    '86.22', 850, 72.5,
    '2024-10-01', 'ACN-2024-00123'
),
(
    '06789012340',
    'Sole di Sicilia S.p.A.',
    (SELECT id FROM settore_nis2  WHERE codice = 'ENERGIA_ELETTR'),
    (SELECT id FROM tipo_soggetto WHERE codice = 'ESSENZIALE'),
    'GRANDE', 'Pedro Adamovic, 10', 'Palermo', '90141', 'ITA',
    '35.11', 310, 88.0,
    '2024-10-15', 'ACN-2024-00187'
);

-- =============================================================================
-- RESPONSABILI
-- =============================================================================

INSERT INTO responsabile
    (id_organizzazione, nome, cognome, email, telefono, id_ruolo, data_inizio, inserito_da)
VALUES
-- Zagara Neuro Therapeutics
(
    (SELECT id FROM organizzazione WHERE codice_fiscale = '04521367890'),
    'Elena','Rossi','e.rossi@zagara-neuro.it','+39 0923 123123',
    (SELECT id FROM ruolo_organizzativo WHERE codice = 'CISO'),
    '2023-01-15','admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale = '04521367890'),
    'Sofia','Bianchi','s.bianchi@zagara-neuro.it','+39 0923 123124',
    (SELECT id FROM ruolo_organizzativo WHERE codice = 'DPO'),
    '2022-05-01','admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale = '04521367890'),
    'Claire','Sterling','c.sterling@zagara-neuro.it','+39 0923 123125',
    (SELECT id FROM ruolo_organizzativo WHERE codice = 'RESP_ICT'),
    '2021-03-01','admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale = '04521367890'),
    'Sarah','Jenkins','s.jenkins@zagara-neuro.it','+39 0923 123126',
    (SELECT id FROM ruolo_organizzativo WHERE codice = 'REFERENTE_NIS2'),
    '2024-09-01','admin'
),
-- Sole di Sicilia
(
    (SELECT id FROM organizzazione WHERE codice_fiscale = '06789012340'),
    'Martina','Benitez','m.benitez@soledisicilia.it','+39 091 123123',
    (SELECT id FROM ruolo_organizzativo WHERE codice = 'CISO'),
    '2022-06-01','admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale = '06789012340'),
    'Chloe','Bennet','c.bennet@soledisicilia.it','+39 091 123124',
    (SELECT id FROM ruolo_organizzativo WHERE codice = 'DPO'),
    '2023-02-01','admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale = '06789012340'),
    'Isabella','Cavallero','i.cavallero@soledisicilia.it','+39 091 123125',
    (SELECT id FROM ruolo_organizzativo WHERE codice = 'REFERENTE_NIS2'),
    '2024-10-01','admin'
);

-- =============================================================================
-- FORNITORI (dati fittizi a scopo didattico)
-- =============================================================================

INSERT INTO fornitore
    (codice_interno, ragione_sociale, paese, codice_fiscale_piva,
     sito_web, email_sicurezza, certificazioni)
VALUES
('FRN-001','Fornitore Cloud A (SaaS)','IRL',NULL,
 'https://example-cloud-a.com','security@example-cloud-a.com',
 'ISO27001, SOC2 Type II, CSA STAR Level 2'),
('FRN-002','Fornitore Cloud B (IaaS)','LUX',NULL,
 'https://example-cloud-b.com','security@example-cloud-b.com',
 'ISO27001, ISO27017, SOC2 Type II'),
('FRN-003','Fornitore Backup Cloud IT','ITA',NULL,
 'https://example-backup.it','security@example-backup.it',
 'ISO27001, ISO22301'),
('FRN-004','Fornitore HIS Clinico','FRA',NULL,
 'https://example-his.com','security@example-his.com',
 'ISO27001, CE Medico'),
('FRN-005','Fornitore Connettivita IT','ITA',NULL,
 'https://example-telco.it','security@example-telco.it',
 'ISO27001, ISO22301'),
('FRN-006','Fornitore SCADA OT','FRA',NULL,
 'https://example-scada.com','cybersecurity@example-scada.com',
 'ISO27001, IEC62443'),
('FRN-007','Fornitore Backup Replication','CHE',NULL,
 'https://example-backup-ch.com','security@example-backup-ch.com',
 'SOC2 Type II'),
('FRN-008','Fornitore Billing CRM','ITA',NULL,
 'https://example-billing.it','csirt@example-billing.it',
 'ISO27001, ISO9001');

-- =============================================================================
-- ASSET — Zagara Neuro Therapeutics (11 asset)
-- Tipi: HW x3, RETE x1, SW x3, CLOUD x1, DATO x2, FISICO x1
-- =============================================================================

INSERT INTO asset (
    id_organizzazione, codice_interno, nome, descrizione,
    id_tipo_asset, id_livello_criticita,
    produttore, modello_versione, ubicazione, indirizzo_ip,
    hostname, sistema_operativo, data_acquisizione,
    data_ultima_patch, stato_valutazione_rischio,
    in_produzione, inserito_da
) VALUES
(
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    'AST-HW-001','Server HIS Neurologico',
    'Server fisico che ospita il sistema HIS per la gestione pazienti neurologici',
    (SELECT id FROM tipo_asset       WHERE codice='HW'),
    (SELECT id FROM livello_criticita WHERE codice='CRITICO'),
    'Produttore Server A','Modello Rack 2U Gen10','DC Zagara - Rack A1',
    '10.0.1.10','srv-his-01','VMware ESXi 8.0','2022-06-01',
    '2026-03-15','VALUTATO',TRUE,'admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    'AST-HW-002','Server Database Pazienti',
    'PostgreSQL primario per dati clinici e cartelle pazienti neurologici',
    (SELECT id FROM tipo_asset       WHERE codice='HW'),
    (SELECT id FROM livello_criticita WHERE codice='CRITICO'),
    'Produttore Server B','Modello Rack 2U','DC Zagara - Rack A2',
    '10.0.1.11','srv-db-01','RHEL 9.2','2022-06-01',
    '2026-04-01','VALUTATO',TRUE,'admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    'AST-RETE-001','Firewall Perimetrale',
    'Firewall cluster HA per protezione perimetro di rete',
    (SELECT id FROM tipo_asset       WHERE codice='RETE'),
    (SELECT id FROM livello_criticita WHERE codice='CRITICO'),
    'Produttore Firewall','FW Enterprise HA','DC Zagara - Rack B1',
    '10.0.0.1','fw-perimetro-01','Hardened OS 7.4','2023-03-15',
    '2026-05-10','MITIGATO',TRUE,'admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    'AST-SW-001','HIS — Sistema Informativo Neurologico',
    'Sistema informativo ospedaliero specializzato per neurologia',
    (SELECT id FROM tipo_asset       WHERE codice='SW'),
    (SELECT id FROM livello_criticita WHERE codice='CRITICO'),
    'Fornitore HIS Clinico','HIS v8.2','In-house (srv-his-01)',
    NULL,NULL,NULL,'2022-09-01',
    '2026-01-20','VALUTATO',TRUE,'admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    'AST-SW-002','PACS — Sistema Neuroimaging',
    'Sistema PACS per gestione immagini MRI e PET neurologiche',
    (SELECT id FROM tipo_asset       WHERE codice='SW'),
    (SELECT id FROM livello_criticita WHERE codice='ALTO'),
    'Produttore PACS','PACS v23.1','In-house (srv-his-01)',
    NULL,NULL,NULL,'2021-04-01',
    '2026-02-01','VALUTATO',TRUE,'admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    'AST-SW-003','Active Directory',
    'Servizio di autenticazione e gestione identita aziendale',
    (SELECT id FROM tipo_asset       WHERE codice='SW'),
    (SELECT id FROM livello_criticita WHERE codice='CRITICO'),
    'Produttore Directory','AD DS 2022','DC Zagara - VM',
    '10.0.1.5','srv-ad-01','Windows Server 2022','2020-01-01',
    '2026-04-15','VALUTATO',TRUE,'admin'
),(
    -- prefisso coerente con il tipo: asset CLOUD -> codice AST-CLOUD-xxx
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    'AST-CLOUD-001','Suite Produttivita Cloud (SaaS)',
    'Posta, collaboration e produttivita cloud per 850 utenti',
    (SELECT id FROM tipo_asset       WHERE codice='CLOUD'),
    (SELECT id FROM livello_criticita WHERE codice='ALTO'),
    'Fornitore Cloud A','SaaS Enterprise','Cloud EU datacenter',
    NULL,NULL,NULL,'2021-01-01',
    NULL,'NON_VALUTATO',TRUE,'admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    'AST-DATO-001','Archivio Dati Clinici Neurologici',
    'Dataset cartelle cliniche pazienti neurologici — dati particolari art.9 GDPR',
    (SELECT id FROM tipo_asset       WHERE codice='DATO'),
    (SELECT id FROM livello_criticita WHERE codice='CRITICO'),
    NULL,NULL,'srv-db-01 / Backup Cloud',
    NULL,NULL,NULL,'2012-01-01',
    NULL,'IN_CORSO',TRUE,'admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    'AST-FISICO-001','Datacenter Principale Trapani',
    'Sala server principale con UPS, HVAC ridondato, accesso biometrico',
    (SELECT id FROM tipo_asset       WHERE codice='FISICO'),
    (SELECT id FROM livello_criticita WHERE codice='CRITICO'),
    NULL,NULL,'Piazza Roberto Sica, 23 - Piano -1',
    NULL,NULL,NULL,'2019-01-01',
    NULL,'VALUTATO',TRUE,'admin'
),(
    -- asset a criticita MEDIA: il filtro livello >= 4 deve escluderlo
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    'AST-HW-003','Workstation Ambulatorio Neurologia',
    'Postazioni clinico-amministrative ambulatorio (pool 12 workstation)',
    (SELECT id FROM tipo_asset       WHERE codice='HW'),
    (SELECT id FROM livello_criticita WHERE codice='MEDIO'),
    'Produttore Client','Desktop Business G3','Ambulatorio - Piano 1',
    '10.0.2.0','ws-amb-pool','Windows 11 Enterprise','2023-09-01',
    '2026-05-02','VALUTATO',TRUE,'admin'
),(
    -- ANOMALIA DELIBERATA: nessun PROPRIETARIO assegnato (Reg. 2024/2690 §12.4)
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    'AST-DATO-002','Repository Documentale Procedure',
    'Archivio procedure operative e istruzioni di lavoro — senza owner assegnato',
    (SELECT id FROM tipo_asset       WHERE codice='DATO'),
    (SELECT id FROM livello_criticita WHERE codice='BASSO'),
    NULL,NULL,'File server interno',
    NULL,NULL,NULL,'2020-03-01',
    NULL,'NON_VALUTATO',TRUE,'admin'
);

-- =============================================================================
-- ASSET — Sole di Sicilia (7 asset)
-- Tipi: HW x2, RETE x1, IOT x1, SW x1, DATO x1, FISICO x1
-- =============================================================================

INSERT INTO asset (
    id_organizzazione, codice_interno, nome, descrizione,
    id_tipo_asset, id_livello_criticita,
    produttore, modello_versione, ubicazione, indirizzo_ip,
    hostname, sistema_operativo, data_acquisizione,
    data_ultima_patch, stato_valutazione_rischio,
    in_produzione, inserito_da
) VALUES
(
    (SELECT id FROM organizzazione WHERE codice_fiscale='06789012340'),
    'SDS-HW-001','SCADA Server Impianti Fotovoltaici',
    'Server che ospita il sistema SCADA per il monitoraggio degli impianti solari',
    (SELECT id FROM tipo_asset       WHERE codice='HW'),
    (SELECT id FROM livello_criticita WHERE codice='CRITICO'),
    'Produttore Server OT','SCADA Server v4','DC Palermo - Rack OT-1',
    '192.168.10.5','scada-srv-01','Windows Server 2019','2020-06-01',
    '2026-01-10','VALUTATO',TRUE,'admin'
),(
    -- tipo RETE (firewall di demarcazione OT/IT): prefisso allineato al tipo
    (SELECT id FROM organizzazione WHERE codice_fiscale='06789012340'),
    'SDS-RETE-001','Firewall OT/IT Demarcation',
    'Segmentazione e protezione rete OT (impianti) da rete IT aziendale',
    (SELECT id FROM tipo_asset       WHERE codice='RETE'),
    (SELECT id FROM livello_criticita WHERE codice='CRITICO'),
    'Produttore Security OT','Guardian v4','DC Palermo - Rack DMZ',
    '192.168.1.1','fw-ot-01','Hardened Linux','2021-09-01',
    '2026-03-20','MITIGATO',TRUE,'admin'
),(
    -- tipo IOT (piattaforma SCADA/OT — classificazione IEC 62443)
    (SELECT id FROM organizzazione WHERE codice_fiscale='06789012340'),
    'SDS-IOT-001','SCADA — Gestione Impianti Rinnovabili',
    'Piattaforma SCADA per monitoraggio e controllo impianti fotovoltaici ed eolici',
    (SELECT id FROM tipo_asset       WHERE codice='IOT'),
    (SELECT id FROM livello_criticita WHERE codice='CRITICO'),
    'Fornitore SCADA OT','EcoControl Power v9.0','In-house (scada-srv-01)',
    NULL,NULL,NULL,'2020-06-01',
    '2025-12-01','VALUTATO',TRUE,'admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale='06789012340'),
    'SDS-SW-001','Sistema Billing e CRM Clienti',
    'Gestione contratti, consumi e fatturazione clienti energia rinnovabile',
    (SELECT id FROM tipo_asset       WHERE codice='SW'),
    (SELECT id FROM livello_criticita WHERE codice='ALTO'),
    'Fornitore Billing CRM','BillingX v3.2','Cloud IaaS EU-West',
    NULL,NULL,NULL,'2019-03-01',
    '2026-02-14','VALUTATO',TRUE,'admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale='06789012340'),
    'SDS-DATO-001','Database Produzione Energetica',
    'Time-series dati produzione fotovoltaica ed eolica, 45 impianti attivi',
    (SELECT id FROM tipo_asset       WHERE codice='DATO'),
    (SELECT id FROM livello_criticita WHERE codice='ALTO'),
    NULL,NULL,'Cloud Storage EU-West (bucket cifrato)',
    NULL,NULL,NULL,'2021-01-01',
    NULL,'IN_CORSO',TRUE,'admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale='06789012340'),
    'SDS-FISICO-001','Impianto Fotovoltaico Serra Palermo Nord',
    'Impianto FV da 18 MW con inverter smart e sistema di accumulo',
    (SELECT id FROM tipo_asset       WHERE codice='FISICO'),
    (SELECT id FROM livello_criticita WHERE codice='CRITICO'),
    NULL,NULL,'Pedro Adamovic, 10 - Contrada Serra',
    NULL,NULL,NULL,'2018-06-01',
    NULL,'NON_VALUTATO',TRUE,'admin'
),(
    -- ANOMALIA DELIBERATA: nessun PROPRIETARIO assegnato (Reg. 2024/2690 §12.4)
    (SELECT id FROM organizzazione WHERE codice_fiscale='06789012340'),
    'SDS-HW-002','Workstation Ufficio Tecnico',
    'Postazioni ufficio tecnico e progettazione impianti — senza owner assegnato',
    (SELECT id FROM tipo_asset       WHERE codice='HW'),
    (SELECT id FROM livello_criticita WHERE codice='MEDIO_BASSO'),
    'Produttore Client','Desktop Business G3','Sede Palermo - Piano 2',
    '192.168.20.0','ws-tec-pool','Windows 11 Enterprise','2022-02-01',
    '2026-04-28','VALUTATO',TRUE,'admin'
);

-- =============================================================================
-- SERVIZI — Zagara Neuro Therapeutics (4 servizi)
-- rto_minuti / rpo_minuti in MINUTI
-- =============================================================================

INSERT INTO servizio (
    id_organizzazione, codice_interno, nome, descrizione,
    id_tipo_servizio, id_livello_criticita,
    rto_minuti, rpo_minuti, disponibilita_target,
    dati_personali, classificazione_dati, normative_applicabili,
    data_avvio, inserito_da
) VALUES
(
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    'SRV-ZNT-001','Cartella Clinica Neurologica',
    'Accesso e gestione CCE pazienti neurologici ricoverati e ambulatoriali',
    (SELECT id FROM tipo_servizio    WHERE codice='CARTELLA_CLIN'),
    (SELECT id FROM livello_criticita WHERE codice='CRITICO'),
    240,60,99.9,TRUE,'DATI_PARTICOLARI','NIS2, GDPR art.9, D.Lgs.138/2024',
    '2012-01-01','admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    'SRV-ZNT-002','CUP — Prenotazione Neurologica',
    'Prenotazione visite neurologiche ed esami diagnostici tramite portale web',
    (SELECT id FROM tipo_servizio    WHERE codice='PRENOTAZIONE'),
    (SELECT id FROM livello_criticita WHERE codice='ALTO'),
    480,240,99.5,TRUE,'RISERVATO','NIS2, GDPR',
    '2018-04-01','admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    'SRV-ZNT-003','PACS — Neuroimaging Diagnostico',
    'Gestione e distribuzione immagini MRI e PET per diagnosi neurologica',
    (SELECT id FROM tipo_servizio    WHERE codice='NEUROIMAGING'),
    (SELECT id FROM livello_criticita WHERE codice='ALTO'),
    360,120,99.5,TRUE,'DATI_PARTICOLARI','NIS2, GDPR art.9',
    '2021-04-01','admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    'SRV-ZNT-004','Backup e Disaster Recovery',
    'Backup giornaliero dati clinici su cloud con replica offsite',
    (SELECT id FROM tipo_servizio    WHERE codice='BACKUP_DR'),
    (SELECT id FROM livello_criticita WHERE codice='CRITICO'),
    1440,240,99.0,FALSE,'RISERVATO','NIS2, ISO27001',
    '2022-01-01','admin'
);

-- =============================================================================
-- SERVIZI — Sole di Sicilia (3 servizi)
-- SCADA: RPO = 0 minuti — zero perdita dati su impianti in esercizio
-- =============================================================================

INSERT INTO servizio (
    id_organizzazione, codice_interno, nome, descrizione,
    id_tipo_servizio, id_livello_criticita,
    rto_minuti, rpo_minuti, disponibilita_target,
    dati_personali, classificazione_dati, normative_applicabili,
    data_avvio, inserito_da
) VALUES
(
    (SELECT id FROM organizzazione WHERE codice_fiscale='06789012340'),
    'SRV-SDS-001','Supervisione Impianti Fotovoltaici SCADA',
    'Monitoraggio e controllo real-time impianti fotovoltaici ed eolici',
    (SELECT id FROM tipo_servizio    WHERE codice='SUPERVISIONE_RETE'),
    (SELECT id FROM livello_criticita WHERE codice='CRITICO'),
    60,0,99.99,FALSE,'RISERVATO','NIS2, D.Lgs.138/2024, IEC62443',
    '2020-06-01','admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale='06789012340'),
    'SRV-SDS-002','Portale Clienti e Billing Energia',
    'Gestione contratti energia rinnovabile e fatturazione clienti finali',
    (SELECT id FROM tipo_servizio    WHERE codice='BILLING_ENERGIA'),
    (SELECT id FROM livello_criticita WHERE codice='ALTO'),
    480,240,99.5,TRUE,'RISERVATO','NIS2, GDPR',
    '2019-03-01','admin'
),(
    (SELECT id FROM organizzazione WHERE codice_fiscale='06789012340'),
    'SRV-SDS-003','Backup e DR Sistemi IT',
    'Backup giornaliero infrastruttura IT con replica su cloud',
    (SELECT id FROM tipo_servizio    WHERE codice='BACKUP_DR'),
    (SELECT id FROM livello_criticita WHERE codice='MEDIO'),
    2880,1440,99.0,FALSE,'INTERNO','NIS2, ISO27001',
    '2023-01-01','admin'
);

-- =============================================================================
-- DIPENDENZE DA FORNITORI (8)
-- Due dipendenze prive di DPA: DIP-ZNT-004 (ALTO -> anomalia critica rilevata
-- da Query 6) e DIP-SDS-003 (MEDIO -> segnalata ma sotto soglia)
-- =============================================================================

INSERT INTO dipendenza (
    codice_interno, id_organizzazione, id_fornitore, id_tipo_dipendenza,
    denominazione_servizio, descrizione, id_livello_criticita,
    data_inizio, data_scadenza, paesi_elaborazione_dati,
    contratto_numero, dpa_firmato, sla_disponibilita
) VALUES
(
    'DIP-ZNT-001',
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    (SELECT id FROM fornitore WHERE codice_interno='FRN-001'),
    (SELECT id FROM tipo_dipendenza WHERE codice='CLOUD_SAAS'),
    'Suite SaaS Enterprise','Posta elettronica, collaboration e produttivita per 850 utenti',
    (SELECT id FROM livello_criticita WHERE codice='ALTO'),
    '2021-01-01','2026-12-31','EU (Irlanda, Paesi Bassi)',
    'CONT-ENT-2021-ZNT',TRUE,99.9
),(
    'DIP-ZNT-002',
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    (SELECT id FROM fornitore WHERE codice_interno='FRN-003'),
    (SELECT id FROM tipo_dipendenza WHERE codice='CLOUD_BACKUP'),
    'Backup Cloud Object Storage','Backup giornaliero dati clinici — DC IT',
    (SELECT id FROM livello_criticita WHERE codice='CRITICO'),
    '2022-01-01','2026-12-31','ITA (Arezzo, Roma)',
    'CONT-BCK-2022-ZNT',TRUE,99.9
),(
    'DIP-ZNT-003',
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    (SELECT id FROM fornitore WHERE codice_interno='FRN-004'),
    (SELECT id FROM tipo_dipendenza WHERE codice='FORNITURA_SW'),
    'HIS Clinico — Licenze e Manutenzione','Supporto H24 sistema HIS neurologico',
    (SELECT id FROM livello_criticita WHERE codice='CRITICO'),
    '2022-09-01','2027-08-31','ITA (on-premise)',
    'CONT-HIS-2022-ZNT',TRUE,NULL
),(
    -- ANOMALIA DELIBERATA: DPA mancante su dipendenza ad alta criticita
    'DIP-ZNT-004',
    (SELECT id FROM organizzazione WHERE codice_fiscale='04521367890'),
    (SELECT id FROM fornitore WHERE codice_interno='FRN-005'),
    (SELECT id FROM tipo_dipendenza WHERE codice='CONNETTIVITA'),
    'Connettivita Fibra + MPLS','Accesso Internet e collegamento sedi distaccate',
    (SELECT id FROM livello_criticita WHERE codice='ALTO'),
    '2023-01-01','2026-12-31','ITA',
    'CONT-CONN-2023-ZNT',FALSE,99.9
),(
    'DIP-SDS-001',
    (SELECT id FROM organizzazione WHERE codice_fiscale='06789012340'),
    (SELECT id FROM fornitore WHERE codice_interno='FRN-002'),
    (SELECT id FROM tipo_dipendenza WHERE codice='CLOUD_IAAS'),
    'Cloud IaaS EU-West','Hosting sistema Billing e storage dati produzione energetica',
    (SELECT id FROM livello_criticita WHERE codice='ALTO'),
    '2019-03-01','2027-02-28','IRL (Dublino)',
    'CONT-IAAS-SDS-2019',TRUE,99.99
),(
    'DIP-SDS-002',
    (SELECT id FROM organizzazione WHERE codice_fiscale='06789012340'),
    (SELECT id FROM fornitore WHERE codice_interno='FRN-006'),
    (SELECT id FROM tipo_dipendenza WHERE codice='FORNITURA_SW'),
    'SCADA OT — Manutenzione H24','Supporto e aggiornamenti piattaforma SCADA impianti rinnovabili',
    (SELECT id FROM livello_criticita WHERE codice='CRITICO'),
    '2020-06-01','2026-05-31','FRA + ITA (on-site)',
    'CONT-SCADA-SDS-001',TRUE,NULL
),(
    -- DPA mancante su dipendenza a criticita MEDIA: sotto la soglia di anomalia critica
    'DIP-SDS-003',
    (SELECT id FROM organizzazione WHERE codice_fiscale='06789012340'),
    (SELECT id FROM fornitore WHERE codice_interno='FRN-007'),
    (SELECT id FROM tipo_dipendenza WHERE codice='CLOUD_BACKUP'),
    'Backup & Replication Cloud','Backup infrastruttura IT + replica offsite',
    (SELECT id FROM livello_criticita WHERE codice='MEDIO'),
    '2023-01-01','2026-12-31','ITA (DC Arezzo)',
    'CONT-BCK-SDS-2023',FALSE,99.5
),(
    'DIP-SDS-004',
    (SELECT id FROM organizzazione WHERE codice_fiscale='06789012340'),
    (SELECT id FROM fornitore WHERE codice_interno='FRN-008'),
    (SELECT id FROM tipo_dipendenza WHERE codice='CLOUD_SAAS'),
    'Billing CRM — Gestione Clienti Energia','Piattaforma SaaS per contratti e fatturazione',
    (SELECT id FROM livello_criticita WHERE codice='ALTO'),
    '2019-03-01','2027-02-28','ITA (Roma)',
    'CONT-CRM-SDS-2019',TRUE,99.5
);

-- =============================================================================
-- JUNCTION: ASSET <-> SERVIZI (14 relazioni, N:M con controllo cross-tenant)
-- Il join include id_organizzazione: codice_interno e unico solo per organizzazione
-- =============================================================================

INSERT INTO asset_servizio (id_asset, id_asset_org, id_servizio, id_servizio_org, tipo_relazione)
SELECT a.id, a.id_organizzazione, s.id, s.id_organizzazione, rel.tipo
FROM (VALUES
    ('AST-HW-001',    'SRV-ZNT-001', 'SUPPORTA'),
    ('AST-HW-002',    'SRV-ZNT-001', 'SUPPORTA'),
    ('AST-SW-001',    'SRV-ZNT-001', 'EROGA'),
    ('AST-RETE-001',  'SRV-ZNT-001', 'SUPPORTA'),
    ('AST-HW-001',    'SRV-ZNT-002', 'SUPPORTA'),
    ('AST-SW-001',    'SRV-ZNT-002', 'EROGA'),
    ('AST-SW-002',    'SRV-ZNT-003', 'EROGA'),
    ('AST-HW-002',    'SRV-ZNT-003', 'SUPPORTA'),
    ('AST-FISICO-001','SRV-ZNT-004', 'OSPITA'),
    ('SDS-HW-001',    'SRV-SDS-001', 'SUPPORTA'),
    ('SDS-IOT-001',   'SRV-SDS-001', 'EROGA'),
    ('SDS-RETE-001',  'SRV-SDS-001', 'SUPPORTA'),
    ('SDS-SW-001',    'SRV-SDS-002', 'EROGA'),
    ('SDS-DATO-001',  'SRV-SDS-002', 'SUPPORTA')
) AS rel(cod_asset, cod_servizio, tipo)
JOIN asset    a ON a.codice_interno = rel.cod_asset
JOIN servizio s ON s.codice_interno = rel.cod_servizio
                AND s.id_organizzazione = a.id_organizzazione;

-- =============================================================================
-- JUNCTION: SERVIZI <-> DIPENDENZE (9 relazioni)
-- =============================================================================

INSERT INTO servizio_dipendenza (id_servizio, id_servizio_org, id_dipendenza, id_dipendenza_org)
SELECT s.id, s.id_organizzazione, d.id, d.id_organizzazione
FROM (VALUES
    ('SRV-ZNT-001', 'DIP-ZNT-002'),
    ('SRV-ZNT-001', 'DIP-ZNT-003'),
    ('SRV-ZNT-002', 'DIP-ZNT-001'),
    ('SRV-ZNT-003', 'DIP-ZNT-003'),
    ('SRV-ZNT-004', 'DIP-ZNT-002'),
    ('SRV-SDS-001', 'DIP-SDS-002'),
    ('SRV-SDS-002', 'DIP-SDS-001'),
    ('SRV-SDS-002', 'DIP-SDS-004'),
    ('SRV-SDS-003', 'DIP-SDS-003')
) AS rel(cod_servizio, cod_dip)
JOIN servizio   s ON s.codice_interno = rel.cod_servizio
JOIN dipendenza d ON d.codice_interno = rel.cod_dip
                  AND d.id_organizzazione = s.id_organizzazione;

-- =============================================================================
-- JUNCTION: ASSET <-> DIPENDENZE (6 relazioni)
-- =============================================================================

INSERT INTO asset_dipendenza (id_asset, id_asset_org, id_dipendenza, id_dipendenza_org)
SELECT a.id, a.id_organizzazione, d.id, d.id_organizzazione
FROM (VALUES
    ('AST-HW-001',    'DIP-ZNT-003'),  -- Server HIS: manutenzione fornitore HIS
    ('AST-HW-002',    'DIP-ZNT-002'),  -- Server DB: backup cloud
    ('AST-CLOUD-001', 'DIP-ZNT-001'),  -- Suite SaaS: fornitore cloud A
    ('AST-RETE-001',  'DIP-ZNT-004'),  -- Firewall: connettivita
    ('SDS-HW-001',    'DIP-SDS-002'),  -- SCADA server: fornitore OT
    ('SDS-IOT-001',   'DIP-SDS-002')   -- SCADA SW: fornitore OT
) AS rel(cod_asset, cod_dip)
JOIN asset      a ON a.codice_interno = rel.cod_asset
JOIN dipendenza d ON d.codice_interno = rel.cod_dip
                  AND d.id_organizzazione = a.id_organizzazione;

-- =============================================================================
-- JUNCTION: ASSET <-> RESPONSABILI — Reg. (UE) 2024/2690 punto 12.4
-- 16 PROPRIETARIO + 2 REFERENTE = 18 righe.
-- AST-DATO-002 e SDS-HW-002 restano DELIBERATAMENTE senza proprietario.
-- =============================================================================

INSERT INTO asset_responsabile
    (id_asset, id_asset_org, id_responsabile, id_resp_org, tipo_responsabilita, data_inizio)
SELECT a.id, a.id_organizzazione, r.id, r.id_organizzazione, rel.tipo, rel.data_inizio::DATE
FROM (VALUES
    -- Zagara — proprietari
    ('AST-HW-001',    'c.sterling@zagara-neuro.it',  'PROPRIETARIO', '2022-06-01'),
    ('AST-HW-002',    'c.sterling@zagara-neuro.it',  'PROPRIETARIO', '2022-06-01'),
    ('AST-HW-003',    'c.sterling@zagara-neuro.it',  'PROPRIETARIO', '2023-09-01'),
    ('AST-RETE-001',  'e.rossi@zagara-neuro.it',     'PROPRIETARIO', '2023-03-15'),
    ('AST-SW-001',    'c.sterling@zagara-neuro.it',  'PROPRIETARIO', '2022-09-01'),
    ('AST-SW-002',    'c.sterling@zagara-neuro.it',  'PROPRIETARIO', '2021-04-01'),
    ('AST-SW-003',    'c.sterling@zagara-neuro.it',  'PROPRIETARIO', '2020-01-01'),
    ('AST-CLOUD-001', 'c.sterling@zagara-neuro.it',  'PROPRIETARIO', '2021-01-01'),
    ('AST-DATO-001',  's.bianchi@zagara-neuro.it',   'PROPRIETARIO', '2012-01-01'),
    ('AST-FISICO-001','e.rossi@zagara-neuro.it',     'PROPRIETARIO', '2019-01-01'),
    -- Zagara — referente sicurezza su asset critico
    ('AST-HW-001',    'e.rossi@zagara-neuro.it',     'REFERENTE',    '2022-06-01'),
    -- Sole di Sicilia — proprietari
    ('SDS-HW-001',    'm.benitez@soledisicilia.it',  'PROPRIETARIO', '2020-06-01'),
    ('SDS-RETE-001',  'm.benitez@soledisicilia.it',  'PROPRIETARIO', '2021-09-01'),
    ('SDS-IOT-001',   'm.benitez@soledisicilia.it',  'PROPRIETARIO', '2020-06-01'),
    ('SDS-SW-001',    'i.cavallero@soledisicilia.it','PROPRIETARIO', '2019-03-01'),
    ('SDS-DATO-001',  'i.cavallero@soledisicilia.it','PROPRIETARIO', '2021-01-01'),
    ('SDS-FISICO-001','m.benitez@soledisicilia.it',  'PROPRIETARIO', '2018-06-01'),
    -- Sole di Sicilia — referente
    ('SDS-IOT-001',   'i.cavallero@soledisicilia.it','REFERENTE',    '2020-06-01')
) AS rel(cod_asset, email_resp, tipo, data_inizio)
JOIN asset        a ON a.codice_interno = rel.cod_asset
JOIN responsabile r ON r.email          = rel.email_resp
                    AND r.id_organizzazione = a.id_organizzazione;

-- =============================================================================
-- JUNCTION: SERVIZI <-> RESPONSABILI (5 relazioni)
-- =============================================================================

INSERT INTO servizio_responsabile
    (id_servizio, id_servizio_org, id_responsabile, id_resp_org, tipo_responsabilita, data_inizio)
SELECT s.id, s.id_organizzazione, r.id, r.id_organizzazione, rel.tipo, rel.data_inizio::DATE
FROM (VALUES
    ('SRV-ZNT-001', 'c.sterling@zagara-neuro.it',  'PROPRIETARIO',        '2022-09-01'),
    ('SRV-ZNT-001', 'e.rossi@zagara-neuro.it',     'REFERENTE_SICUREZZA', '2022-09-01'),
    ('SRV-ZNT-002', 'c.sterling@zagara-neuro.it',  'PROPRIETARIO',        '2018-04-01'),
    ('SRV-SDS-001', 'm.benitez@soledisicilia.it',  'PROPRIETARIO',        '2020-06-01'),
    ('SRV-SDS-002', 'i.cavallero@soledisicilia.it','PROPRIETARIO',        '2019-03-01')
) AS rel(cod_servizio, email_resp, tipo, data_inizio)
JOIN servizio     s ON s.codice_interno = rel.cod_servizio
JOIN responsabile r ON r.email          = rel.email_resp
                    AND r.id_organizzazione = s.id_organizzazione;
