# oerebdaten

Docker Image
https://github.com/schmandr/oereb-db/tree/210aefea62fe13660266870ba618de1994e5e6be


*Gretljobs Bundesdaten*

Gesetze

Die Gesetze werden einmalig zu Beginn importiert: "http://models.geo.admin.ch/V_D/OeREB/OeREBKRM_V1_1_Gesetze_20180501.xml"
Aus meiner Sicht müsste noch abgefangen werden, wenn eine neue Datei verfügbar ist.
./start-gretl.sh --docker-image sogis/gretl-runtime:latest --job-directory ~/gretljobs/oereb_bundesdaten_gesetze oereb_dbImport_Gesetze

Daten
./start-gretl.sh --docker-image sogis/gretl-runtime:latest --job-directory ~/gretljobs/oereb_bundesdaten/ getAllOerebThemes
