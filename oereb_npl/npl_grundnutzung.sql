/*
 * Die korrekte Reihenfolge der Queries ist zwingend. 
 * 
 * Es wird versucht möglichst rasch die Daten in den Tabellen zu speichern. So
 * können die Queries gekapselt werden und/oder in nachvollziehbareren 
 * Teilschritten durchgeführt werden. Alternativ kann man (fast) alles in einer sehr
 * langen CTE umbauen.
 * 
 * Es wird versucht wenn immer möglich die Original-TID (resp. der PK aus der 
 * Quelltabelle) in der Zieltabelle beizubehalten. Damit bleiben Beziehungen
 * 'bestehen' und sind einfacher zu behandeln.
 */


/*
 * Die Eigentumsbeschränkungen können als erstes persistiert werden. Der Umbau der anderen Objekte erfolgt anschliessend.
 * Verschiedene Herausforderungen / Spezialitäten müssen behandelt werden:
 * 
 * (1) basket und dataset müssen eruiert und als FK gespeichert werden. Beide werden
 * werden in einer Subquery ermittelt. Dies ist möglich, da bereits die zuständigen Stellen
 * vorhanden sein müssen. Die zuständigen Stellen werden mitexportiert und teilen sich daher
 * das gleiche Dataset wie die übrigen Daten (im Gegensatz dazu die Gesetze).
 * 
 * (2) Die Grundnutzung wird nicht flächendeckend in den ÖREB-Kataster überführt, d.h. es
 * gibt Grundnutzungen, die nicht Bestandteil des Katasters sind. Dieser Filter ist eine
 * einfache WHERE-Clause.
 * 
 * (3) Die Attribute 'publiziertab' und 'rechtsstatus' sind im kantonalen Modell nicht in
 * der Typ-Klasse vorhanden, sondern werden hier ebenfalls von der Geometrie-Klasse 
 * verwendet. Der Join führt dazu, dass ein unschönes Distinct notwendig wird.
 * 
 * (4) Momentan geht man von der Annahme aus, dass bei den diesen Eigentumsbeschränkungen
 * die Gemeinde die zuständige Stelle ist. Falls das nicht mehr zutrifft, muss man die
 * zuständigen Stellen eventuell in einem nachgelagerten Schritt abhandeln.
 * 
 * (5) Exportiert werden alle zuständigen Stellen, die vorgängig importiert wurden.
 * 
 * (6) Ein Artcode kann mehrfach vorkommen. Das sollte soweit richtig sein. Jedoch aufpassen, dass
 * bei den nachfolgenden Queries nicht fälschlicherweise angenommen wird, dass der Artcode unique ist.
 * Ausnahme: Bei den Symbolen ist diese Annahme materiell richtig (solange eine kantonale aggregierte
 * Form präsentiert wird).
 */

INSERT INTO 
    agi_oereb_npl_staging.transferstruktur_eigentumsbeschraenkung
    (
        t_id,
        t_basket,
        t_datasetname,
        aussage_de,
        thema,
        subthema,
        artcode,
        artcodeliste,
        rechtsstatus,
        publiziertab,
        zustaendigestelle
    )
    SELECT
        DISTINCT ON (typ_grundnutzung.t_ili_tid)
        typ_grundnutzung.t_id,
        basket_dataset.basket_t_id,
        basket_dataset.datasetname,
        typ_grundnutzung.bezeichnung AS aussage_de,
        'Nutzungsplanung' AS thema,
        'NutzungsplanungGrundnutzung' AS subthema,
        substring(typ_grundnutzung.typ_kt FROM 1 FOR 4) AS artcode,
        'urn:fdc:ilismeta.interlis.ch:2017:NP_Typ_Kanton_Grundnutzung' AS artcodeliste,      /* TODO: woher stammt die artcodeliste?' */
        CASE 
            WHEN grundnutzung.rechtsstatus IS NULL THEN 'inKraft' /* TODO: tbd */
            ELSE grundnutzung.rechtsstatus
        END AS rechtsstatus,
        grundnutzung.publiziertab, /* TODO: tbd */
        amt.t_id AS zustaendigestelle
    FROM
        arp_npl.nutzungsplanung_typ_grundnutzung AS typ_grundnutzung
        LEFT JOIN agi_oereb_npl_staging.vorschriften_amt AS amt
        ON typ_grundnutzung.t_datasetname = RIGHT(amt.t_ili_tid, 4)
        LEFT JOIN arp_npl.nutzungsplanung_grundnutzung AS grundnutzung
        ON typ_grundnutzung.t_id = grundnutzung.typ_grundnutzung,
        (
            SELECT
                basket.t_id AS basket_t_id,
                dataset.datasetname AS datasetname               
            FROM
                agi_oereb_npl_staging.t_ili2db_dataset AS dataset
                LEFT JOIN agi_oereb_npl_staging.t_ili2db_basket AS basket
                ON basket.dataset = dataset.t_id
            WHERE
                dataset.datasetname = 'ch.so.arp.nutzungsplanung' 
        ) AS basket_dataset
    WHERE
        typ_kt NOT IN 
        (
            'N180_Verkehrszone_Strasse',
            'N181_Verkehrszone_Bahnareal',
            'N182_Verkehrszone_Flugplatzareal',
            'N189_weitere_Verkehrszonen',
            'N210_Landwirtschaftszone',
            'N320_Gewaesser',
            'N329_weitere_Zonen_fuer_Gewaesser_und_ihre_Ufer',
            'N420_Verkehrsflaeche_Strasse', 
            'N421_Verkehrsflaeche_Bahnareal', 
            'N422_Verkehrsflaeche_Flugplatzareal', 
            'N429_weitere_Verkehrsflaechen', 
            'N430_Reservezone_Wohnzone_Mischzone_Kernzone_Zentrumszone',
            'N431_Reservezone_Arbeiten',
            'N432_Reservezone_OeBA',
            'N439_Reservezone',
            'N440_Wald'
        )
;

/*
 * Es werden die Dokumente der ersten Hierarchie-Ebene abgehandelt, d.h.
 * "HinweisWeitere" wird in einem weiteren Schritt bearbeitet. Um die Dokumente
 * zu kopieren, muss auch die n-m-Zwischentabelle bearbeitet werden, wegen der
 * Foreign Keys Constraints. Bemerkungen:
 * 
 * (1) Das Abfüllen der zuständigen Stellen muss ggf. nochmals überarbeit
 * werden. Kommt darauf an, ob das hier reicht. In den Ausgangsdaten müssen
 * die Attribute Abkuerzung und Rechtsvorschrift zwingend gesetzt sein, sonst
 * kann nicht korrekt umgebaut werden. 
 * 
 * (2) Relativ mühsam ist der Umstand, dass bereits Daten in der Dokumenten-
 * Tabelle vorhanden sind (die kantonalen Gesetze). Deren Primary Keys hat
 * man nicht im Griff und so kann es vorkommen, dass es zu einer Kollision
 * mit den zu kopierenden Daten kommt. Abhilfe schafft beim Erstellen des
 * Staging-Schemas der Parameter --idSeqMin. Damit kann der Startwert der
 * Sequenz gesetzt werden, um solche Kollisionen mit grösster Wahrscheinlichkeit
 * zu verhindern.
 * 
 * (3) Die t_ili_tid kann nicht einfach so aus der Quelltabelle übernommen werden,
 * da sie keine valide OID ist (die gemäss Modell verlangt wird). Gemäss Kommentar
 * sollte sie zudem wie eine Domain aufgebaut sein. Der Einfachheit halber (Referenzen
 * gibt es ja in der DB darauf nicht, sondern auf den PK) mache ich aus der UUID eine
 * valide OID mittels Substring, Replace und Concat.
 * 
 * (4) Es gibt Objekte (Typen), die in den Kataster aufgenommen werden müssen (gemäss
 * Excelliste) aber keine Dokumente zugewiesen haben. -> Datenfehler. Aus diesem Grund
 * wird eine Where-Clause verwendet (dokument.t_id IS NOT NULL).
 */


WITH basket_dataset AS 
(
    SELECT
        basket.t_id AS basket_t_id,
        dataset.datasetname AS datasetname               
    FROM
        agi_oereb_npl_staging.t_ili2db_dataset AS dataset
        LEFT JOIN agi_oereb_npl_staging.t_ili2db_basket AS basket
        ON basket.dataset = dataset.t_id
    WHERE
        dataset.datasetname = 'ch.so.arp.nutzungsplanung' 
)
,
hinweisvorschrift AS 
(
    SELECT
        typ_dokument.t_id,
        basket_dataset.basket_t_id AS t_basket,
        basket_dataset.datasetname AS t_datasetname,
        typ_dokument.typ_grundnutzung AS eigentumsbeschraenkung,
        typ_dokument.dokument AS vorschrift_vorschriften_dokument
    FROM
        arp_npl.nutzungsplanung_typ_grundnutzung_dokument AS typ_dokument
        RIGHT JOIN agi_oereb_npl_staging.transferstruktur_eigentumsbeschraenkung AS eigentumsbeschraenkung
        ON typ_dokument.typ_grundnutzung = eigentumsbeschraenkung.t_id,
        basket_dataset
    WHERE
        typ_dokument.t_id IS NOT NULL        
)
,
vorschriften_dokument AS
(
    INSERT INTO 
        agi_oereb_npl_staging.vorschriften_dokument
        (
            t_id,
            t_basket,
            t_datasetname,
            t_type,
            t_ili_tid,
            titel_de,
            offiziellertitel_de,
            abkuerzung_de,
            offiziellenr,
            kanton,
            gemeinde,
            rechtsstatus,
            publiziertab,
            zustaendigestelle
        )   
    SELECT 
        DISTINCT ON (dokument.t_id)
        dokument.t_id AS t_id,
        basket_dataset.basket_t_id,
        basket_dataset.datasetname,
        CASE
            WHEN rechtsvorschrift IS TRUE
                THEN 'vorschriften_rechtsvorschrift'
            ELSE 'vorschriften_dokument'
        END AS t_type,
        '_'||SUBSTRING(REPLACE(CAST(dokument.t_ili_tid AS text), '-', ''),1,15) AS t_ili_tid,        
        dokument.titel AS titel_de,
        dokument.offiziellertitel AS offizellertitel_de,
        dokument.abkuerzung AS abkuerzung_de,
        dokument.offiziellenr AS offiziellenr,
        dokument.kanton AS kanton,
        dokument.gemeinde AS gemeinde,
        dokument.rechtsstatus AS rechtsstatus,
        dokument.publiziertab AS publiziertab,
        CASE
            WHEN abkuerzung = 'RRB'
                THEN 
                (
                    SELECT 
                        t_id
                    FROM
                        agi_oereb_npl_staging.vorschriften_amt
                    WHERE
                        t_datasetname = 'ch.so.arp.nutzungsplanung' -- TODO: tbd
                    AND
                        t_ili_tid = 'ch.so.sk' -- TODO: tbd
                )
            ELSE
                (
                    SELECT 
                        t_id
                    FROM
                        agi_oereb_npl_staging.vorschriften_amt
                    WHERE
                        RIGHT(t_ili_tid, 4) = CAST(gemeinde AS TEXT)
                )
         END AS zustaendigestelle
    FROM
        arp_npl.rechtsvorschrften_dokument AS dokument
        RIGHT JOIN hinweisvorschrift
        ON dokument.t_id = hinweisvorschrift.vorschrift_vorschriften_dokument,
        (
            SELECT
                basket.t_id AS basket_t_id,
                dataset.datasetname AS datasetname               
            FROM
                agi_oereb_npl_staging.t_ili2db_dataset AS dataset
                LEFT JOIN agi_oereb_npl_staging.t_ili2db_basket AS basket
                ON basket.dataset = dataset.t_id
            WHERE
                dataset.datasetname = 'ch.so.arp.nutzungsplanung' 
        ) AS basket_dataset
--     WHERE                                                                      /* PS stimmt das so?, die Dokumente sollen nur 1x importiert werden */
--         dokument.t_id NOT IN (
--             SELECT
--                 t_id
--             FROM
--                 agi_oereb_npl_staging.vorschriften_dokument
--         )
   RETURNING *
)
INSERT INTO
    agi_oereb_npl_staging.transferstruktur_hinweisvorschrift
    (
        t_id,
        t_basket,
        t_datasetname,
        eigentumsbeschraenkung,
        vorschrift_vorschriften_dokument  
    )
SELECT
    t_id, -- TODO: muss nicht zwingend Original-TID sein, oder?
    t_basket,
    t_datasetname,
    eigentumsbeschraenkung,
    vorschrift_vorschriften_dokument
FROM
    hinweisvorschrift
;

/*
 * Umbau der zusätzlichen Dokumente, die im Originalmodell in der 
 * HinweisWeitereDokumente vorkommen und nicht direkt (via Zwischen-
 * Tabelle) mit der Eigentumsbeschränkung / mit dem Typ verknüpft sind. 
 * 
 * (1) Flachwalzen: Anstelle der gnietigen HinweisWeitereDokumente-Tabelle 
 * kann man alles flachwalzen, d.h. alle Dokument-zu-Dokument-Links werden 
 * direkt mit an den Typ / an die Eigentumsbeschränkung verlinkt. Dazu muss man 
 * für jedes Dokument in dieser Schleife das Top-Level-Dokument (das 'wirkliche'
 * Ursprungs-Dokument) kennen, damit dann auch noch die Verbindungstabelle
 * (transferstruktur_hinweisvorschrift) zwischen Eigentumsbeschränkung und 
 * Dokument abgefüllt werden kann.
 * 
 * (2) Umbau sehr gut validieren (wegen des Flachwalzens)!
 * 
 * (3) Die rekursive CTE muss am Anfang stehen.
 * 
 * (4) Achtung: Beim Einfügen der zusätzlichen Dokumente in die Dokumententabelle
 * kann es Duplikate geben, da zwei verschiedene Top-Level-Dokumente auf das gleiche
 * weitere Dokument verweisen. Das wirft einen Fehler (Primary Key Constraint). Aus
 * diesem Grund muss beim Inserten noch ein DISTINCT auf die t_id gemacht werden. 
 * Beim anschliessenden Herstellen der Verknüpfung aber nicht mehr.
 */


WITH RECURSIVE x(ursprung, hinweis, parents, last_ursprung, depth) AS 
(
    SELECT 
        ursprung, 
        hinweis, 
        ARRAY[ursprung] AS parents, 
        ursprung AS last_ursprung, 
        0 AS "depth" 
    FROM 
        arp_npl.rechtsvorschrften_hinweisweiteredokumente
    WHERE
        ursprung != hinweis
    AND ursprung IN 
    (
        SELECT
            t_id
        FROM
            agi_oereb_npl_staging.vorschriften_dokument
        WHERE
            t_datasetname = 'ch.so.arp.nutzungsplanung'
    )

    UNION ALL
  
    SELECT 
        x.ursprung, 
        x.hinweis, 
        parents||t1.hinweis, 
        t1.hinweis AS last_ursprung, 
        x."depth" + 1
    FROM 
        x 
        INNER JOIN arp_npl.rechtsvorschrften_hinweisweiteredokumente t1 
        ON (last_ursprung = t1.ursprung)
    WHERE 
        t1.hinweis IS NOT NULL
)
,
zusaetzliche_dokumente AS 
(
    SELECT 
        DISTINCT ON (x.last_ursprung, x.ursprung)
        x.ursprung AS top_level_dokument,
        x.last_ursprung AS t_id,
        basket_dataset.basket_t_id,
        basket_dataset.datasetname,
        CASE
            WHEN rechtsvorschrift IS TRUE
                THEN 'vorschriften_rechtsvorschrift'
            ELSE 'vorschriften_dokument'
        END AS t_type,
        '_'||SUBSTRING(REPLACE(CAST(dokument.t_ili_tid AS text), '-', ''),1,15) AS t_ili_tid,        
        dokument.titel AS titel_de,
        dokument.offiziellertitel AS offizellertitel_de,
        dokument.abkuerzung AS abkuerzung_de,
        dokument.offiziellenr AS offiziellenr,
        dokument.kanton AS kanton,
        dokument.gemeinde AS gemeinde,
        dokument.rechtsstatus AS rechtsstatus,
        dokument.publiziertab AS publiziertab,
        CASE
            WHEN abkuerzung = 'RRB'
                THEN 
                (
                    SELECT 
                        t_id
                    FROM
                        agi_oereb_npl_staging.vorschriften_amt
                    WHERE
                        t_datasetname = 'ch.so.arp.nutzungsplanung' -- TODO: tbd
                    AND
                        t_ili_tid = 'ch.so.sk' -- TODO: tbd
                )
            ELSE
                (
                    SELECT 
                        t_id
                    FROM
                        agi_oereb_npl_staging.vorschriften_amt
                    WHERE
                        RIGHT(t_ili_tid, 4) = CAST(gemeinde AS TEXT)
                )
         END AS zustaendigestelle        
    FROM 
        x
        LEFT JOIN arp_npl.rechtsvorschrften_dokument AS dokument
        ON dokument.t_id = x.last_ursprung,
        (
            SELECT
                basket.t_id AS basket_t_id,
                dataset.datasetname AS datasetname               
            FROM
                agi_oereb_npl_staging.t_ili2db_dataset AS dataset
                LEFT JOIN agi_oereb_npl_staging.t_ili2db_basket AS basket
                ON basket.dataset = dataset.t_id
            WHERE
                dataset.datasetname = 'ch.so.arp.nutzungsplanung' 
        ) AS basket_dataset        
    WHERE
        last_ursprung NOT IN
        (
            SELECT
                t_id
            FROM
                agi_oereb_npl_staging.vorschriften_dokument
            WHERE
                t_datasetname = 'ch.so.arp.nutzungsplanung'
        )
)
,
zusaetzliche_dokumente_insert AS 
(
    INSERT INTO 
        agi_oereb_npl_staging.vorschriften_dokument
        (
            t_id,
            t_basket,
            t_datasetname,
            t_type,
            t_ili_tid,
            titel_de,
            offiziellertitel_de,
            abkuerzung_de,
            offiziellenr,
            kanton,
            gemeinde,
            rechtsstatus,
            publiziertab,
            zustaendigestelle
        )   
    SELECT
        DISTINCT ON (t_id)    
        t_id,
        basket_t_id,
        datasetname,
        t_type,
        t_ili_tid,
        titel_de,
        offizellertitel_de,
        abkuerzung_de,
        offiziellenr,
        kanton,
        gemeinde,
        rechtsstatus,
        publiziertab,
        zustaendigestelle
    FROM
        zusaetzliche_dokumente
)
INSERT INTO 
    agi_oereb_npl_staging.transferstruktur_hinweisvorschrift 
    (
        t_basket,
        t_datasetname,
        eigentumsbeschraenkung,
        vorschrift_vorschriften_dokument
    )
    SELECT 
        DISTINCT 
        basket_dataset.basket_t_id,
        basket_dataset.datasetname,
        hinweisvorschrift.eigentumsbeschraenkung,
        zusaetzliche_dokumente.t_id AS vorschrift_vorschriften_dokument
    FROM 
        zusaetzliche_dokumente
        LEFT JOIN agi_oereb_npl_staging.transferstruktur_hinweisvorschrift AS hinweisvorschrift
        ON hinweisvorschrift.vorschrift_vorschriften_dokument = zusaetzliche_dokumente.top_level_dokument,
        (
            SELECT
                basket.t_id AS basket_t_id,
                dataset.datasetname AS datasetname               
            FROM
                agi_oereb_npl_staging.t_ili2db_dataset AS dataset
                LEFT JOIN agi_oereb_npl_staging.t_ili2db_basket AS basket
                ON basket.dataset = dataset.t_id
            WHERE
                dataset.datasetname = 'ch.so.arp.nutzungsplanung' 
        ) AS basket_dataset        
;

/*
 * Datenumbau der Links auf die Dokumente, die im Rahmenmodell 'multilingual' sind und daher eher
 * mühsam normalisert sind.
 * 
 * (1) Im NPL-Modell sind die URL nicht vollständig, sondern es werden nur Teile des Pfads verwaltet.
 * Beim Datenumbau in das Rahmenmodell wird daraus eine vollständige URL gemacht.
 */

WITH multilingualuri AS
(
    INSERT INTO
        agi_oereb_npl_staging.multilingualuri
        (
            t_id,
            t_basket,
            t_datasetname,
            t_seq,
            vorschriften_dokument_textimweb
        )
    SELECT
        nextval('agi_oereb_npl_staging.t_ili2db_seq'::regclass) AS t_id,
        basket_dataset.basket_t_id,
        basket_dataset.datasetname,
        0 AS t_seq,
        vorschriften_dokument.t_id AS vorschriften_dokument_textimweb
    FROM
        agi_oereb_npl_staging.vorschriften_dokument AS vorschriften_dokument,
        (
            SELECT
                basket.t_id AS basket_t_id,
                dataset.datasetname AS datasetname               
            FROM
                agi_oereb_npl_staging.t_ili2db_dataset AS dataset
                LEFT JOIN agi_oereb_npl_staging.t_ili2db_basket AS basket
                ON basket.dataset = dataset.t_id
            WHERE
                dataset.datasetname = 'ch.so.arp.nutzungsplanung' 
        ) AS basket_dataset
    WHERE
        vorschriften_dokument.t_datasetname = 'ch.so.arp.nutzungsplanung'
    RETURNING *
)
,
localiseduri AS 
(
    SELECT 
        nextval('agi_oereb_npl_staging.t_ili2db_seq'::regclass) AS t_id,
        basket_dataset.basket_t_id,
        basket_dataset.datasetname,
        0 AS t_seq,
        'de' AS alanguage,
        CAST('https://geo.so.ch/docs/ch.so.arp.zonenplaene/Zonenplaene_pdf/'||rechtsvorschrften_dokument.textimweb AS TEXT) AS atext,
        multilingualuri.t_id AS multilingualuri_localisedtext
    FROM
        arp_npl.rechtsvorschrften_dokument AS rechtsvorschrften_dokument
        RIGHT JOIN multilingualuri 
        ON multilingualuri.vorschriften_dokument_textimweb = rechtsvorschrften_dokument.t_id,
        (
            SELECT
                basket.t_id AS basket_t_id,
                dataset.datasetname AS datasetname               
            FROM
                agi_oereb_npl_staging.t_ili2db_dataset AS dataset
                LEFT JOIN agi_oereb_npl_staging.t_ili2db_basket AS basket
                ON basket.dataset = dataset.t_id
            WHERE
                dataset.datasetname = 'ch.so.arp.nutzungsplanung'                 
        ) AS basket_dataset
)
INSERT INTO
    agi_oereb_npl_staging.localiseduri
    (
        t_id,
        t_basket,
        t_datasetname,
        t_seq,
        alanguage,
        atext,
        multilingualuri_localisedtext
    )
    SELECT 
        t_id,
        basket_t_id,
        datasetname,
        t_seq,
        alanguage,
        atext,
        multilingualuri_localisedtext
    FROM 
        localiseduri
;

/*
 * Umbau der Geometrien, die Inhalt des ÖREB-Katasters sind.
 * 
 * (1) Es werde nicht alle Geometrie der Grundnutzung kopiert, 
 * sondern nur diejenigen, die Inhalt des ÖREB-Katasters sind.
 * Dieser Filter wird bei Umbau des NPL-Typs gesetzt.
 * 
 * (2) Die zuständige Stelle ist identisch mit der zuständigen
 * Stelle der Eigentumsbeschränkung.
 */

INSERT INTO
    agi_oereb_npl_staging.transferstruktur_geometrie
    (
        t_id,
        t_basket,
        t_datasetname,
        flaeche_lv95,
        rechtsstatus,
        publiziertab,
        eigentumsbeschraenkung,
        zustaendigestelle
    )
    SELECT
        grundnutzung.t_id,
        basket_dataset.basket_t_id AS t_basket,
        basket_dataset.datasetname AS t_datasetname,
        ST_MakeValid(ST_RemoveRepeatedPoints(ST_SnapToGrid(grundnutzung.geometrie, 0.001))) AS flaeche_lv95,
        grundnutzung.rechtsstatus AS rechtsstatus,
        grundnutzung.publiziertab AS publiziertab,
        eigentumsbeschraenkung.t_id AS eigentumsbeschraenkung,
        eigentumsbeschraenkung.zustaendigestelle AS zustaendigestelle
    FROM
        arp_npl.nutzungsplanung_grundnutzung AS grundnutzung
        RIGHT JOIN agi_oereb_npl_staging.transferstruktur_eigentumsbeschraenkung AS eigentumsbeschraenkung
        ON grundnutzung.typ_grundnutzung = eigentumsbeschraenkung.t_id,
        (
            SELECT
                basket.t_id AS basket_t_id,
                dataset.datasetname AS datasetname               
            FROM
                agi_oereb_npl_staging.t_ili2db_dataset AS dataset
                LEFT JOIN agi_oereb_npl_staging.t_ili2db_basket AS basket
                ON basket.dataset = dataset.t_id
            WHERE
                dataset.datasetname = 'ch.so.arp.nutzungsplanung' 
        ) AS basket_dataset
--     WHERE
--         grundnutzung.t_id IS NOT NULL                                              /* PS stimmt das so?*/
;

/*
 * Abfüllen der "WMS- und Legendentabellen".
 * 
 * (1) Achtung: nicht korrekte URL für GetMap und Legende!
 * 
 * (2) Query muss gut überprüft werden. Sicher sein, dass das robust ist hinsichtlich den WHERE-clauses
 * und DISTINCTs.
 * 
 * (3) 1px-Dummy-PNG als Symbol damit Datenbank-Constraint nicht verletzt wird.
 *  
 * (4) Query funktioniert nur, wenn nur ein Darstellungsdienst insertet wird. (-> Update-Query würde nicht
 * mehr passen.)
 */ 

WITH transferstruktur_darstellungsdienst AS
(
    INSERT INTO 
        agi_oereb_npl_staging.transferstruktur_darstellungsdienst 
        (
            t_basket,
            t_datasetname,
            verweiswms,
            legendeimweb
        )
        SELECT
            basket_dataset.basket_t_id AS t_basket,
            basket_dataset.datasetname AS t_datasetname,
            'https://geo.so.ch/ows/somap?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&FORMAT=image%2Fpng&TRANSPARENT=true&LAYERS=ch.so.arp.nutzungsplanung.grundnutzung_inkl_digi_zone&STYLES=&SRS=EPSG%3A2056&CRS=EPSG%3A2056&TILED=false&DPI=96&OPACITIES=255&t=60&WIDTH=1375&HEIGHT=723&BBOX=2549048.75%2C1196604.5833333333%2C2694569.583333333%2C1273122.0833333333' AS verweiswms,
            'https://geo.so.ch/api/v1/legend/somap?SERVICE=WMS&REQUEST=GetLegendGraphic&VERSION=1.3.0&FORMAT=image/png&LAYER=ch.so.arp.nutzungsplanung.grundnutzung_inkl_digi_zone&CRS=EPSG:2056&SCALE=400000&WIDTH=1375&HEIGHT=723&BBOX=2549053.187282798,1196569.9945746537,2694574.020616131,1273087.4945746537' AS legendeimweb
        FROM
        (
            SELECT
                basket.t_id AS basket_t_id,
                dataset.datasetname AS datasetname               
            FROM
                agi_oereb_npl_staging.t_ili2db_dataset AS dataset
                LEFT JOIN agi_oereb_npl_staging.t_ili2db_basket AS basket
                ON basket.dataset = dataset.t_id
            WHERE
                dataset.datasetname = 'ch.so.arp.nutzungsplanung' 
        ) AS basket_dataset
    RETURNING *
)
,
transferstruktur_legendeeintrag AS 
(
INSERT INTO 
    agi_oereb_npl_staging.transferstruktur_legendeeintrag
    (
        t_basket,
        t_datasetname,
        t_seq,
        symbol,
        artcode,
        artcodeliste,
        thema,
        subthema,
        transfrstrkstllngsdnst_legende
    )
    SELECT 
        DISTINCT ON (artcode)
        eigentumsbeschraenkung.t_basket,
        eigentumsbeschraenkung.t_datasetname,
        0::int AS t_seq,        
        decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64') AS symbol,
        eigentumsbeschraenkung.artcode,
        eigentumsbeschraenkung.artcodeliste,
        eigentumsbeschraenkung.thema,
        eigentumsbeschraenkung.subthema,
        transferstruktur_darstellungsdienst.t_id AS transfrstrkstllngsdnst_legende
    FROM
        agi_oereb_npl_staging.transferstruktur_eigentumsbeschraenkung AS eigentumsbeschraenkung,
        transferstruktur_darstellungsdienst
    WHERE
        transferstruktur_darstellungsdienst.t_datasetname = 'ch.so.arp.nutzungsplanung'
    RETURNING *
)
UPDATE 
    agi_oereb_npl_staging.transferstruktur_eigentumsbeschraenkung
SET 
    darstellungsdienst = (SELECT t_id FROM transferstruktur_darstellungsdienst)
WHERE
    subthema = 'NutzungsplanungGrundnutzung'
;

/*
 * Hinweise auf die gesetzlichen Grundlagen.
 * 
 * (1) Momentan nur auf die kantonalen Gesetze und Verordnungen, da
 * die die Bundesgesetze und -verordnungen nicht importiert wurden.
 * 
 * (2) Ebenfalls gut zu prüfen.
 */

WITH vorschriften_dokument_gesetze AS (
  SELECT
    t_id AS hinweis
  FROM
    agi_oereb_npl_staging.vorschriften_dokument
  WHERE
    t_ili_tid IN ('ch.so.sk.bgs.711.1', 'ch.so.sk.bgs.711.61') 
)
INSERT INTO agi_oereb_npl_staging.vorschriften_hinweisweiteredokumente (
  t_basket,
  t_datasetname,
  ursprung,
  hinweis
)
SELECT
  vorschriften_dokument.t_basket,
  vorschriften_dokument.t_datasetname,
  vorschriften_dokument.t_id,  
  vorschriften_dokument_gesetze.hinweis
FROM 
  agi_oereb_npl_staging.vorschriften_dokument AS vorschriften_dokument
  LEFT JOIN vorschriften_dokument_gesetze
  ON 1=1
WHERE
  t_type = 'vorschriften_rechtsvorschrift'
AND
  vorschriften_dokument.t_datasetname = 'ch.so.arp.nutzungsplanung'
;
