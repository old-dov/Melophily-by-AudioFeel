# Changelog

## [Non publié]

### Changement de nom
- **OnlyAudio devient Melophily** (« l'amour de la musique »). L'ancien nom était trop proche d'ONLYOFFICE, la suite bureautique.
- Renommage de ce que l'on voit : titres de fenêtre, textes de l'interface, raccourcis et textes de l'installateur, propriétés des exécutables Windows, nom de l'application Android (« Melophily Remote »), documentation.
- Fichiers téléchargeables renommés (`Melophily_Setup.exe`, `Melophily_Remote.apk`, `Melophily-macOS.zip`, `Melophily-Linux-x86_64-…`) et dépôt renommé `Melophily-by-AudioFeel` (l'ancienne adresse redirige automatiquement).
- Inchangés volontairement : identifiants techniques (paquets, identifiant Android, identifiant de l'installateur) et nom de reconnaissance entre le bureau et la télécommande, afin que les installations existantes continuent de se mettre à jour et de se retrouver.
- La télécommande reconnaît désormais un bureau qui s'annonce sous l'un ou l'autre nom.

## [2.5.0-beta.1] - 2026-10-05

### Nouveautés
- Commandes multimédias Bluetooth et touches de casque sur le lecteur desktop
- Intégration SMTC sous Windows, MPRIS sous Linux et centre de contrôle sous macOS
- Synchronisation du titre, de l'artiste, de l'album, de la durée, de la position et de l'état lecture/pause
- Commandes système : lecture, pause, piste précédente, piste suivante et seek

## [2.0.0] - 2026-04-12

### Nouveautés
- **Télécommande Android** — Nouvelle application mobile pour contrôler OnlyAudio depuis votre téléphone
  - Connexion automatique par scan réseau ou saisie manuelle de l'IP
  - Contrôles complets : lecture/pause, précédent/suivant, volume, shuffle, repeat
  - Barre de progression avec seek
  - Affichage de la pochette, titre, artiste et album en temps réel
  - Notification média Android avec contrôles dans la barre de notifications
  - Navigation dans la playlist avec recherche
  - Sauvegarde de la dernière connexion

### Améliorations
- **Installateur** — Détection et désinstallation automatique de la version précédente lors de la mise à jour
- **Serveur distant** — API Flask intégrée au player desktop (port 5000) pour la communication avec la télécommande

### Technique
- Application Android développée en Flutter/Dart
- Communication HTTP temps réel entre mobile et desktop
- Compatible Android 5.0+ (API 21+)
- Compatible Xiaomi/MIUI et autres surcouches constructeur

## [1.0.0] - 2026

### Première release
- Lecteur audio desktop Windows (Python/Kivy)
- Lecture MP3/FLAC/WAV/OGG/M4A
- Affichage des métadonnées et pochettes d'album
- Playlist avec shuffle et repeat
- Interface sombre moderne
- Installateur Windows
