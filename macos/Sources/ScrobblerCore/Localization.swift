import Foundation

/// Translations of the app's text. English is written in the code; `L("…")` looks it up here.
/// Placeholders are %@ (in order). The log, the Discord status and Last.fm data stay in English.
/// To add a language: add a table below and a case in `table`. Keep the keys exactly as in the code;
/// the tests check that every `L("…")` in the app has a translation with the same placeholders.
public enum Localization {
    /// "en" or a code with a table ("es"). Set from the system's preferred languages, or --language.
    nonisolated(unsafe) public static var language: String = detect(Locale.preferredLanguages)

    public static func detect(_ preferred: [String]) -> String {
        for code in preferred {
            let base = String(code.prefix(2)).lowercased()
            if base == "en" { return "en" }
            if table(base) != nil { return base }
        }
        return "en"
    }

    public static func table(_ language: String) -> [String: String]? {
        switch language {
        case "es": return spanish
        default: return nil
        }
    }

    /// Spanish (neutral Latin American, "tú").
    public static let spanish: [String: String] = [
        // Menu
        "Nothing playing": "No se está reproduciendo nada",
        "Nothing scrobbled yet": "Todavía no hay scrobbles",
        "Last scrobbled: %@": "Último scrobble: %@",
        "%@ (paused)": "%@ (en pausa)",
        "%@ (not scrobbled)": "%@ (sin scrobble)",
        "Recent Scrobbles": "Scrobbles recientes",
        "Recent Scrobbles (%@ Waiting)": "Scrobbles recientes (%@ pendientes)",
        "1 Waiting to Send": "1 pendiente de enviar",
        "%@ Waiting to Send": "%@ pendientes de enviar",
        "Send Now": "Enviar ahora",
        "Open on Last.fm": "Abrir en Last.fm",
        "Open My Last.fm Library": "Abrir mi biblioteca de Last.fm",
        "\u{2B06} Update Available: %@": "\u{2B06} Actualización disponible: %@",
        "Installing %@\u{2026}": "Instalando %@\u{2026}",
        "Allow Access to Music\u{2026}": "Permitir acceso a Música\u{2026}",
        "Music Access Is Off (Repeats May Be Missed)\u{2026}": "Sin acceso a Música (pueden perderse repeticiones)\u{2026}",
        "\u{2665} Love This Song on Last.fm": "\u{2665} Me encanta esta canción en Last.fm",
        "Don\u{2019}t Scrobble This Artist": "No hacer scrobble de este artista",
        "Don\u{2019}t Scrobble %@": "No hacer scrobble de %@",
        "Scrobble %@ Again": "Volver a hacer scrobble de %@",
        "Pause Scrobbling": "Pausar el scrobbling",
        "Open My Last.fm Profile": "Abrir mi perfil de Last.fm",
        "Options": "Opciones",
        "Start at Login": "Abrir al iniciar sesión",
        "Show \u{201C}Listening to\u{201D} on Discord": "Mostrar \u{201C}Escuchando\u{201D} en Discord",
        "Show \u{201C}Listening to\u{201D} on Discord (Waiting for Discord)": "Mostrar \u{201C}Escuchando\u{201D} en Discord (esperando a Discord)",
        "Clean Up Titles (Remove \u{201C}Remaster\u{201D}, \u{201C}- Single\u{201D}\u{2026})": "Limpiar títulos (quitar \u{201C}Remaster\u{201D}, \u{201C}- Single\u{201D}\u{2026})",
        "Scrobble Only the Main Artist of Collaborations": "Solo el artista principal en las colaboraciones",
        "Catch Up on Plays from Other Devices": "Recuperar lo que escuchas en otros dispositivos",
        "Check for Updates Automatically": "Buscar actualizaciones automáticamente",
        "Ignored Artists": "Artistas ignorados",
        "No ignored artists. Use \u{201C}Don\u{2019}t Scrobble\u{201D} while one plays.": "No hay artistas ignorados. Usa \u{201C}No hacer scrobble\u{201D} mientras suena uno.",
        "Not sent to Last.fm or shown on Discord. Click to undo:": "No se envían a Last.fm ni se muestran en Discord. Haz clic para deshacer:",
        "Switch Last.fm Account\u{2026}": "Cambiar de cuenta de Last.fm\u{2026}",
        "Open Log": "Abrir el registro",
        "Report a Problem\u{2026}": "Reportar un problema\u{2026}",
        "About %@": "Acerca de %@",
        "Quit": "Salir",
        "Scrobbling paused": "Scrobbling en pausa",
        "%@ waiting to send": "%@ pendientes de enviar",
        "\u{201C}Joji & BENEE\u{201D} is scrobbled as \u{201C}Joji\u{201D}. Bands like \u{201C}Simon & Garfunkel\u{201D} are left alone (Last.fm's listener counts tell them apart).":
            "\u{201C}Joji & BENEE\u{201D} se envía como \u{201C}Joji\u{201D}. Las bandas como \u{201C}Simon & Garfunkel\u{201D} se quedan igual (las cifras de oyentes de Last.fm las distinguen).",
        "Scrobbles songs from your library that you played on your iPhone or iPad, from Music's play history (synced through iCloud).":
            "Hace scrobble de las canciones de tu biblioteca que escuchaste en tu iPhone o iPad, con el historial de Música (sincronizado por iCloud).",
        "\u{201C}Song [2022 Remaster]\u{201D} is scrobbled as \u{201C}Song\u{201D}, \u{201C}Album (Deluxe Edition)\u{201D} as \u{201C}Album\u{201D}":
            "\u{201C}Song [2022 Remaster]\u{201D} se envía como \u{201C}Song\u{201D}, y \u{201C}Album (Deluxe Edition)\u{201D} como \u{201C}Album\u{201D}",

        "\u{2665} Keyboard Shortcut (%@)": "\u{2665} Atajo de teclado (%@)",
        "Show a Notification When a Song Starts": "Mostrar una notificación cuando empiece una canción",
        "Play a song in Music, then press %@ to love it.": "Pon una canción en Música y presiona %@ para marcarla con \u{201C}Me encanta\u{201D}.",
        "Already loved": "Ya tiene \u{201C}Me encanta\u{201D}",
        "Removed from your loved tracks": "Se quitó de tus canciones con \u{201C}Me encanta\u{201D}",
        "Couldn't remove the love": "No se pudo quitar el \u{201C}Me encanta\u{201D}",

        // Alerts
        "%@ is already running.": "%@ ya está abierto.",
        "Look for the \u{266A} note icon in the menu bar.": "Busca el icono de nota \u{266A} en la barra de menús.",
        "Update to %@ %@?": "¿Actualizar a %@ %@?",
        "The app downloads the new version, checks it, and restarts. Your settings and Last.fm login are kept.":
            "La app descarga la nueva versión, la verifica y se reinicia. Se conservan tus ajustes y tu sesión de Last.fm.",
        "Install and Restart": "Instalar y reiniciar",
        "It can't update itself because %@. You can download the new version from the release page.":
            "No puede actualizarse sola porque %@. Puedes descargar la nueva versión desde la página de la versión.",
        "You can download the new version from the release page.": "Puedes descargar la nueva versión desde la página de la versión.",
        "Open Release Page": "Abrir la página de la versión",
        "Later": "Más tarde",
        "Release Notes": "Notas de la versión",
        "Catch up on plays from other devices?": "¿Recuperar lo que escuchas en otros dispositivos?",
        "Songs you play on your iPhone or iPad are recorded in your Music library and synced to this Mac through iCloud. Every 15 minutes the app looks for plays it didn't see here and that aren't on Last.fm yet, and scrobbles them with the time you played them. It starts with the last 24 hours.\n\n\u{2022} Only songs in your library count, and only the latest play of each song.\n\u{2022} It needs access to Music, and your Mac has to be on.\n\u{2022} If you use Scan in the Last.fm iPhone app, use one or the other: the same plays could be sent twice.":
            "Las canciones que escuchas en tu iPhone o iPad quedan registradas en tu biblioteca de Música y se sincronizan con esta Mac por iCloud. Cada 15 minutos, la app busca reproducciones que no vio aquí y que todavía no están en Last.fm, y les hace scrobble con la hora en que las escuchaste. Empieza con las últimas 24 horas.\n\n\u{2022} Solo cuentan las canciones de tu biblioteca, y solo la última vez que sonó cada una.\n\u{2022} Necesita acceso a Música, y tu Mac tiene que estar encendida.\n\u{2022} Si usas Scan en la app de Last.fm del iPhone, usa una cosa o la otra: las mismas reproducciones podrían enviarse dos veces.",
        "Turn On": "Activar",
        "Cancel": "Cancelar",
        "OK": "Aceptar",
        "Scrobbles the Music app on your Mac to Last.fm.\nNot affiliated with Apple or Last.fm.":
            "Envía a Last.fm lo que escuchas en la app Música de tu Mac.\nSin relación con Apple ni con Last.fm.",
        "Open Project Page": "Abrir la página del proyecto",

        // Notifications
        "Updated to %@": "Actualizado a %@",
        "%@ is up to date. See what's new on the release page.": "%@ está al día. Mira las novedades en la página de la versión.",
        "Connected to Last.fm": "Conectado a Last.fm",
        "Scrobbling Music as %@. I'll be here in the menu bar.": "Haciendo scrobble de Música como %@. Estaré aquí, en la barra de menús.",
        "\u{2665} Loved on Last.fm": "\u{2665} Marcada con \u{201C}Me encanta\u{201D} en Last.fm",
        "Couldn't love this song": "No se pudo marcar con \u{201C}Me encanta\u{201D}",
        "You're up to date": "Estás al día",
        "%@ %@ is the latest version.": "%@ %@ es la versión más reciente.",
        "Couldn't check for updates": "No se pudieron buscar actualizaciones",
        "Update available": "Actualización disponible",
        "%@ %@ is out. Click to install it.": "Ya salió %@ %@. Haz clic para instalarla.",
        "Last.fm needs you to reconnect": "Last.fm necesita que vuelvas a conectarte",
        "Click the menu bar icon and choose Options › Switch Last.fm Account. Your scrobbles are saved until then.":
            "Haz clic en el icono de la barra de menús y elige Opciones › Cambiar de cuenta de Last.fm. Tus scrobbles se guardan mientras tanto.",
        "Couldn't install the update": "No se pudo instalar la actualización",
        "%@. Opening the download page instead.": "%@. Se abrirá la página de descarga.",

        // Updater reasons (shown inside the messages above)
        "not running as an app": "no se está ejecutando como app",
        "the app is running from a temporary copy; move it to Applications first": "se está ejecutando desde una copia temporal; muévela primero a Aplicaciones",
        "no permission to replace the app in %@": "no tiene permiso para reemplazar la app en %@",
        "this release has no checked download for Mac": "esta versión no tiene una descarga verificada para Mac",
        "the download failed": "la descarga falló",
        "the download doesn't match the published SHA-256": "la descarga no coincide con el SHA-256 publicado",
        "the download isn't the expected app": "la descarga no es la app esperada",

        // Setup window
        "Connect to Last.fm": "Conectar con Last.fm",
        "This app watches what the Music app is playing and adds it to your Last.fm profile.": "Esta app ve lo que suena en la app Música y lo agrega a tu perfil de Last.fm.",
        "Get a free Last.fm API key": "Consigue una API key gratuita de Last.fm",
        "Last.fm requires every app to have one. It takes a minute: fill in any application name and description, leave \u{201C}Callback URL\u{201D} empty, and submit. Then copy the API key and Shared secret here.":
            "Last.fm se la pide a cada app. Toma un minuto: escribe cualquier nombre y descripción de la aplicación, deja vacío \u{201C}Callback URL\u{201D} y envía el formulario. Luego copia aquí la API key y el Shared secret.",
        "Create a Last.fm API account": "Crear una cuenta de API de Last.fm",
        "API key": "API key",
        "Shared secret": "Shared secret",
        "Allow access to Music": "Permite el acceso a Música",
        "So repeated songs are counted, the app reads how far into a song you are. macOS asks you once: click Allow.":
            "Para contar las canciones que repites, la app lee en qué parte de la canción vas. macOS te lo pregunta una vez: haz clic en Permitir.",
        "Allowed": "Permitido",
        "Not allowed. Scrobbling still works, but repeats may be missed.": "No permitido. El scrobbling funciona igual, pero pueden perderse repeticiones.",
        "Open Privacy Settings": "Abrir ajustes de privacidad",
        "Allow access to your Last.fm account": "Permite el acceso a tu cuenta de Last.fm",
        "Click Connect. Last.fm opens in your browser: click \u{201C}Yes, allow access\u{201D} there and this window finishes by itself.":
            "Haz clic en Conectar. Last.fm se abre en tu navegador: haz clic ahí en \u{201C}Yes, allow access\u{201D} (\u{201C}Sí, permitir el acceso\u{201D}) y esta ventana termina sola.",
        "Start automatically when I log in": "Abrir automáticamente al iniciar sesión",
        "Open the Last.fm page again": "Abrir de nuevo la página de Last.fm",
        "Connect": "Conectar",
        "Paste both the API key and the Shared secret first.": "Primero pega la API key y el Shared secret.",
        "Contacting Last.fm...": "Conectando con Last.fm...",
        "Waiting for you to click \u{201C}Yes, allow access\u{201D} on the Last.fm page in your browser...":
            "Esperando a que hagas clic en \u{201C}Yes, allow access\u{201D} (\u{201C}Sí, permitir el acceso\u{201D}) en la página de Last.fm de tu navegador...",
        "Last.fm didn't accept that API key. Check you copied the API key and Shared secret correctly.":
            "Last.fm no aceptó esa API key. Revisa que copiaste bien la API key y el Shared secret.",
        "Couldn't reach Last.fm: %@": "No se pudo conectar con Last.fm: %@",
        "Timed out waiting for approval. Click Connect to try again.": "Se acabó el tiempo de espera. Haz clic en Conectar para intentarlo de nuevo.",
        "That approval link expired. Click Connect to try again.": "Ese enlace de aprobación caducó. Haz clic en Conectar para intentarlo de nuevo.",
        "Last.fm rejected the Shared secret. Check you copied it correctly.": "Last.fm rechazó el Shared secret. Revisa que lo copiaste bien.",
    ]
}

/// The app's text in the user's language (see Localization). Placeholders are %@, filled in order.
public func L(_ english: String, _ args: CustomStringConvertible...) -> String {
    let text = Localization.table(Localization.language)?[english] ?? english
    var result = ""
    var rest = Substring(text)
    var index = 0
    while let range = rest.range(of: "%@") {
        result += rest[..<range.lowerBound]
        result += index < args.count ? args[index].description : ""
        index += 1
        rest = rest[range.upperBound...]
    }
    return result + rest
}
