# oerebdaten

Docker Image
https://github.com/schmandr/oereb-db/tree/210aefea62fe13660266870ba618de1994e5e6be


Gretljobs Bundesdaten

Gesetze
./start-gretl.sh --docker-image sogis/gretl-runtime:latest --job-directory ~/gretljobs/oereb_bundesdaten_gesetze oereb_dbImport_Gesetze

Daten
./start-gretl.sh --docker-image sogis/gretl-runtime:latest --job-directory ~/gretljobs/oereb_bundesdaten/ getAllOerebThemes
