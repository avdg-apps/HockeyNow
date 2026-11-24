import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case finnish = "fi"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .finnish: return "Suomi"
        }
    }

    func localize(_ key: String) -> String {
        let translations: [String: [AppLanguage: String]] = [
            "title": [.english: "HockeyNow", .spanish: "HockeyNow", .french: "HockeyNow", .german: "HockeyNow", .italian: "HockeyNow", .finnish: "HockeyNow"],
            "sub": [.english: "Live Data Feed", .spanish: "Datos en Vivo", .french: "Données en Direct", .german: "Live-Daten-Feed", .italian: "Dati in Diretta", .finnish: "Live-Tulokset"],
            "noMatches": [.english: "No matches found for this date.", .spanish: "No se encontraron partidos.", .french: "Aucun match trouvé.", .german: "Keine Spiele für dieses Datum gefunden.", .italian: "Nessuna partita trouvata.", .finnish: "Ei otteluita tälle päivälle."],
            "noGamesScheduled": [.english: "No NHL games are scheduled for this date.", .spanish: "No hay partidos de la NHL programados para esta fecha.", .french: "Aucun match de la NHL n'est prévu à cette date.", .german: "Für dieses Datum sind keine NHL-Spiele angesetzt.", .italian: "Nessuna partita NHL è programmata per questa data.", .finnish: "Tälle päivälle ei ole NHL-otteluita."],
            "settings": [.english: "Configuration", .spanish: "Ajustes", .french: "Réglages", .german: "Einstellungen", .italian: "Impostazioni", .finnish: "Asetukset"],
            "appearance": [.english: "Theme", .spanish: "Tema", .french: "Thème", .german: "Design", .italian: "Tema", .finnish: "Teema"],
            "language": [.english: "Language", .spanish: "Idioma", .french: "Langue", .german: "Sprache", .italian: "Italiano", .finnish: "Kieli"],
            "timezone": [.english: "Timezone", .spanish: "Zona Horaria", .french: "Fuseau Claire", .german: "Zeitzone", .italian: "Fuso Orario", .finnish: "Aikavyöhyke"],
            "quit": [.english: "Quit Application", .spanish: "Salir de la aplicación", .french: "Quitter", .german: "Anwendung beenden", .italian: "Esci", .finnish: "Sulje sovellus"],
            "loadingSummary": [.english: "Fetching game data...", .spanish: "Cargando datos...", .french: "Données...", .german: "Spieldaten werden geladen...", .italian: "Caricamento dati...", .finnish: "Haetaan ottelutietoja..."],
            "noPlays": [.english: "No scoring plays recorded yet.", .spanish: "Sin goles registrados.", .french: "Aucun but inscrit.", .german: "Noch keine Tore aufgezeichnet.", .italian: "Nessun gol registrato.", .finnish: "Ei tilastomerkintöjä maaleista."],
            "penaltiesTitle": [.english: "Game Penalties", .spanish: "Penalizaciones", .french: "Pénalités", .german: "Strafzeiten", .italian: "Penalità", .finnish: "Rangaistukset"],
            "menuStyle": [.english: "Menu Display", .spanish: "Estilo de Menú", .french: "Style de Menu", .german: "Menüstil", .italian: "Stile Menu", .finnish: "Valikkotyyli"],
            "menuFull": [.english: "Full Label", .spanish: "Etiqueta Completa", .french: "Étiquette Complète", .german: "Vollständiges Label", .italian: "Etichetta Completa", .finnish: "Koko Teksti"],
            "menuIcon": [.english: "Shortened Label", .spanish: "Etiqueta Corta", .french: "Étiquette Courte", .german: "Kurzes Label", .italian: "Etichetta Breve", .finnish: "Lyhyt Teksti"],
            "dashboard": [.english: "Games", .spanish: "Partidos", .french: "Matchs", .german: "Spiele", .italian: "Partite", .finnish: "Ottelut"],
            "standings": [.english: "Standings", .spanish: "Clasificación", .french: "Classement", .german: "Tabelle", .italian: "Classifica", .finnish: "Sarjataulukko"],
            "players": [.english: "Players", .spanish: "Jugadores", .french: "Joueurs", .german: "Spieler", .italian: "Giocatori", .finnish: "Pelaajat"],
            "skaters": [.english: "Skaters", .spanish: "Patinadores", .french: "Patineurs", .german: "Feldspieler", .italian: "Pattinatori", .finnish: "Kenttäpelaajat"],
            "goalies": [.english: "Goalies", .spanish: "Porteros", .french: "Gardiens", .german: "Torhüter", .italian: "Portieri", .finnish: "Maalivahdit"],
            "notiLabel": [.english: "Goal Alerts", .spanish: "Alertas de Gol", .french: "Alertes de But", .german: "Torbenachrichtigungen", .italian: "Notifiche Gol", .finnish: "Maalihälytykset"],
            "settingsGeneral": [.english: "General", .spanish: "General", .french: "Général", .german: "Allgemein", .italian: "Generale", .finnish: "Yleiset"],
            "settingsAdvanced": [.english: "Advanced", .spanish: "Avanzado", .french: "Avancé", .german: "Erweitert", .italian: "Avanzate", .finnish: "Lisäasetukset"],
            "favoriteTeam": [.english: "Favourite Team", .spanish: "Equipo Favorito", .french: "Équipe Favorite", .german: "Lieblingsteam", .italian: "Squadra Preferita", .finnish: "Suosikkijoukkue"],
            "favoriteTeamNone": [.english: "None", .spanish: "Ninguno", .french: "Aucune", .german: "Keine", .italian: "Nessuna", .finnish: "Ei mikään"],
            "closeSettings": [.english: "Close", .spanish: "Cerrar", .french: "Fermer", .german: "Schließen", .italian: "Chiudi", .finnish: "Sulje"],
            "advancedTheme": [.english: "Accent Color", .spanish: "Color de acento", .french: "Couleur d'accent", .german: "Akzentfarbe", .italian: "Colore accento", .finnish: "Korostusväri"],
            "launchAtLogin": [.english: "Launch at Login", .spanish: "Iniciar con el sistema", .french: "Lancer à la connexion", .german: "Beim Login starten", .italian: "Avvia all'accesso", .finnish: "Käynnistä kirjautuessa"],
            "lowPowerMode": [.english: "Low Power Mode", .spanish: "Modo de bajo consumo", .french: "Mode basse consommation", .german: "Energiesparmodus", .italian: "Modalità risparmio energetico", .finnish: "Virransäästötila"],
            "lowPowerModeHint": [.english: "Refreshes scores less often to save battery", .spanish: "Actualiza los resultados con menos frecuencia para ahorrar batería", .french: "Actualise les scores moins souvent pour économiser la batterie", .german: "Aktualisiert Ergebnisse seltener, um Akku zu sparen", .italian: "Aggiorna i punteggi meno spesso per risparmiare batteria", .finnish: "Päivittää tulokset harvemmin akun säästämiseksi"],
            "twentyFourHour": [.english: "24-Hour Time", .spanish: "Formato de 24 horas", .french: "Format 24 heures", .german: "24-Stunden-Format", .italian: "Formato 24 ore", .finnish: "24 tunnin kello"],
            "hideDockIcon": [.english: "Show Dock Icon", .spanish: "Mostrar icono del Dock", .french: "Afficher l'icône du Dock", .german: "Dock-Symbol anzeigen", .italian: "Mostra icona nel Dock", .finnish: "Näytä Dock-kuvake"],
            "disableNotchHUD": [.english: "Live Notch Overlay", .spanish: "Superposición en vivo", .french: "Superposition en direct", .german: "Live-Notch-Overlay", .italian: "Overlay live sul notch", .finnish: "Live-ilmoitusalue"],
            "goalAlertSound": [.english: "Goal Alert Sound", .spanish: "Sonido de alerta de gol", .french: "Son d'alerte de but", .german: "Ton bei Torbenachrichtigung", .italian: "Suono avviso gol", .finnish: "Maalihälytyksen ääni"],
            "contactDeveloper": [.english: "Report a Bug", .spanish: "Informar de un error", .french: "Signaler un bug", .german: "Fehler melden", .italian: "Segnala un bug", .finnish: "Ilmoita virheestä"],
            "copiedAddress": [.english: "Copied avdgapps@gmail.com to clipboard", .spanish: "avdgapps@gmail.com copiado al portapapeles", .french: "avdgapps@gmail.com copié dans le presse-papiers", .german: "avdgapps@gmail.com in die Zwischenablage kopiert", .italian: "avdgapps@gmail.com copiato negli appunti", .finnish: "avdgapps@gmail.com kopioitu leikepöydälle"],
            "automaticUpdates": [.english: "Automatically Check for Updates", .spanish: "Buscar actualizaciones automáticamente", .french: "Rechercher les mises à jour automatiquement", .german: "Automatisch nach Updates suchen", .italian: "Cerca aggiornamenti automaticamente", .finnish: "Tarkista päivitykset automaattisesti"],
            "checkForUpdates": [.english: "Check for Updates…", .spanish: "Buscar actualizaciones…", .french: "Rechercher les mises à jour…", .german: "Nach Updates suchen…", .italian: "Cerca aggiornamenti…", .finnish: "Tarkista päivitykset…"]
        ]
        return translations[key]?[self] ?? key
    }
}
