using System;
using System.Collections.Generic;
using System.Globalization;

namespace AppleMusicScrobbler
{
    /// <summary>
    /// Translations of the app's text. English is written in the code; L("…") looks it up here.
    /// Placeholders are {0}, {1}… as in string.Format. The log, the Discord status and Last.fm data stay
    /// in English. To add a language: add a table and a case in Table. The tests check that every L("…")
    /// in the code has a translation with the same placeholders. (The Mac version has its own table in
    /// macos/Sources/ScrobblerCore/Localization.swift.)
    /// </summary>
    public static class Localization
    {
        /// <summary>"en" or a code with a table ("es"). From the Windows display language, or --language.</summary>
        public static string Language { get; set; } = Detect(CultureInfo.CurrentUICulture);

        public static string Detect(CultureInfo culture)
        {
            string code = culture?.TwoLetterISOLanguageName ?? "en";
            return Table(code) != null ? code : "en";
        }

        public static IReadOnlyDictionary<string, string> Table(string language) =>
            language == "es" ? Spanish : null;

        /// <summary>The app's text in the user's language.</summary>
        public static string L(string english, params object[] args)
        {
            string text = Table(Language) != null && Table(Language).TryGetValue(english, out var translated) ? translated : english;
            return args.Length > 0 ? string.Format(CultureInfo.CurrentCulture, text, args) : text;
        }

        /// <summary>Spanish (neutral Latin American, "tú").</summary>
        public static readonly Dictionary<string, string> Spanish = new Dictionary<string, string>
        {
            ["Nothing playing"] = "No se está reproduciendo nada",
            ["Nothing scrobbled yet"] = "Todavía no hay scrobbles",
            ["Last scrobbled: {0}"] = "Último scrobble: {0}",
            ["{0} (paused)"] = "{0} (en pausa)",
            ["{0} (not scrobbled)"] = "{0} (sin scrobble)",
            ["Recent scrobbles"] = "Scrobbles recientes",
            ["Recent scrobbles ({0} waiting)"] = "Scrobbles recientes ({0} pendientes)",
            ["1 waiting to send"] = "1 pendiente de enviar",
            ["{0} waiting to send"] = "{0} pendientes de enviar",
            ["Send now"] = "Enviar ahora",
            ["Open on Last.fm"] = "Abrir en Last.fm",
            ["Open my Last.fm library"] = "Abrir mi biblioteca de Last.fm",
            ["Update available"] = "Actualización disponible",
            ["⬆ Update available: {0}"] = "⬆ Actualización disponible: {0}",
            ["Installing {0}..."] = "Instalando {0}...",
            ["♥ Love this song on Last.fm"] = "♥ Me encanta esta canción en Last.fm",
            ["Don't scrobble this artist"] = "No hacer scrobble de este artista",
            ["Don't scrobble {0}"] = "No hacer scrobble de {0}",
            ["Scrobble {0} again"] = "Volver a hacer scrobble de {0}",
            ["Ignored artists"] = "Artistas ignorados",
            ["No ignored artists. Use \"Don't scrobble\" while one plays."] = "No hay artistas ignorados. Usa \"No hacer scrobble\" mientras suena uno.",
            ["Not sent to Last.fm or shown on Discord. Click to undo:"] = "No se envían a Last.fm ni se muestran en Discord. Haz clic para deshacer:",
            ["Pause scrobbling"] = "Pausar el scrobbling",
            ["♥ Keyboard shortcut"] = "♥ Atajo de teclado",
            ["Off"] = "Desactivado",
            ["Show a notification when a song starts"] = "Mostrar una notificación cuando empiece una canción",
            ["Play a song in Apple Music, then press {0} to love it."] = "Pon una canción en Apple Music y presiona {0} para marcarla con “Me encanta”.",
            ["Already loved"] = "Ya tiene “Me encanta”",
            ["Removed from your loved tracks"] = "Se quitó de tus canciones con “Me encanta”",
            ["Couldn't remove the love"] = "No se pudo quitar el “Me encanta”",
            ["Open my Last.fm profile"] = "Abrir mi perfil de Last.fm",
            ["Options"] = "Opciones",
            ["Start with Windows"] = "Iniciar con Windows",
            ["Check for updates automatically"] = "Buscar actualizaciones automáticamente",
            ["Clean up titles (remove “Remaster”, “- Single”…)"] = "Limpiar títulos (quitar “Remaster”, “- Single”…)",
            ["“Song [2022 Remaster]” is scrobbled as “Song”, “Album (Deluxe Edition)” as “Album”"] = "“Song [2022 Remaster]” se envía como “Song”, y “Album (Deluxe Edition)” como “Album”",
            ["Scrobble only the main artist of collaborations"] = "Solo el artista principal en las colaboraciones",
            ["“Joji & BENEE” is scrobbled as “Joji”. Bands like “Simon & Garfunkel” are left alone (Last.fm's listener counts tell them apart)."] = "“Joji & BENEE” se envía como “Joji”. Las bandas como “Simon & Garfunkel” se quedan igual (las cifras de oyentes de Last.fm las distinguen).",
            ["Show “Listening to” on Discord"] = "Mostrar “Escuchando” en Discord",
            ["Show “Listening to” on Discord (waiting for Discord)"] = "Mostrar “Escuchando” en Discord (esperando a Discord)",
            ["Switch Last.fm account..."] = "Cambiar de cuenta de Last.fm...",
            ["Open log"] = "Abrir el registro",
            ["Report a problem..."] = "Reportar un problema...",
            ["About {0}"] = "Acerca de {0}",
            ["Quit"] = "Salir",
            ["Scrobbling paused"] = "Scrobbling en pausa",
            ["Updated to {0}"] = "Actualizado a {0}",
            ["{0} is up to date. Click to see what's new."] = "{0} está al día. Haz clic para ver las novedades.",
            ["Connected to Last.fm"] = "Conectado a Last.fm",
            ["Scrobbling Apple Music as {0}. I'll be here in the tray."] = "Haciendo scrobble de Apple Music como {0}. Estaré aquí, en la bandeja del sistema.",
            ["♥ Loved on Last.fm"] = "♥ Marcada con “Me encanta” en Last.fm",
            ["Couldn't love this song"] = "No se pudo marcar con “Me encanta”",
            ["You're up to date"] = "Estás al día",
            ["{0} {1} is the latest version."] = "{0} {1} es la versión más reciente.",
            ["{0} {1} is out. Click to install it."] = "Ya salió {0} {1}. Haz clic para instalarla.",
            ["Couldn't check for updates"] = "No se pudieron buscar actualizaciones",
            ["{0} {1} is out, but the app can't update itself because {2}.\n\nOpen the release page to download it?"] = "Ya salió {0} {1}, pero la app no puede actualizarse sola porque {2}.\n\n¿Abrir la página de la versión para descargarla?",
            ["Update to {0} {1}?\n\nThe app downloads the new version, checks it, and restarts. Your settings and Last.fm login are kept.\n\nYes: install and restart\nNo: open the release notes instead"] = "¿Actualizar a {0} {1}?\n\nLa app descarga la nueva versión, la verifica y se reinicia. Se conservan tus ajustes y tu sesión de Last.fm.\n\nSí: instalar y reiniciar\nNo: abrir las notas de la versión",
            ["Couldn't install the update"] = "No se pudo instalar la actualización",
            ["{0}. Click to download it from the release page."] = "{0}. Haz clic para descargarla desde la página de la versión.",
            ["this release has no checked download for Windows"] = "esta versión no tiene una descarga verificada para Windows",
            ["it doesn't have permission to replace its exe in {0}"] = "no tiene permiso para reemplazar su exe en {0}",
            ["the download doesn't match the published SHA-256"] = "la descarga no coincide con el SHA-256 publicado",
            ["the download isn't the expected app"] = "la descarga no es la app esperada",
            ["{0} {1}\n\nScrobbles the Apple Music app for Windows to Last.fm.\nNot affiliated with Apple or Last.fm."] = "{0} {1}\n\nEnvía a Last.fm lo que escuchas en la app Apple Music para Windows.\nSin relación con Apple ni con Last.fm.",
            ["\n\nOpen the project page (and check for updates)?"] = "\n\n¿Abrir la página del proyecto (y buscar actualizaciones)?",
            ["Last.fm needs you to reconnect"] = "Last.fm necesita que vuelvas a conectarte",
            ["Right-click the tray icon and choose Options > \"Switch Last.fm account...\". Your scrobbles are saved until then."] = "Haz clic derecho en el icono de la bandeja y elige Opciones > \"Cambiar de cuenta de Last.fm...\". Tus scrobbles se guardan mientras tanto.",
            ["Apple Music Scrobbler is already running.\n\nLook for the red note icon in the system tray (you may need to click the ^ arrow)."] = "Apple Music Scrobbler ya está abierto.\n\nBusca el icono de nota rojo en la bandeja del sistema (puede que tengas que hacer clic en la flecha ^).",
            ["Connect to Last.fm"] = "Conectar con Last.fm",
            ["This app watches what the Apple Music app is playing and adds it to your Last.fm profile."] = "Esta app ve lo que suena en Apple Music y lo agrega a tu perfil de Last.fm.",
            ["{0}. Get a free Last.fm API key"] = "{0}. Consigue una API key gratuita de Last.fm",
            ["Last.fm requires every app to have one. It takes a minute: fill in any application name and description, leave \"Callback URL\" empty, and submit. Then copy the API key and Shared secret here."] = "Last.fm se la pide a cada app. Toma un minuto: escribe cualquier nombre y descripción de la aplicación, deja vacío \"Callback URL\" y envía el formulario. Luego copia aquí la API key y el Shared secret.",
            ["Create a Last.fm API account"] = "Crear una cuenta de API de Last.fm",
            ["API key"] = "API key",
            ["Shared secret"] = "Shared secret",
            ["{0}. Allow access to your account"] = "{0}. Permite el acceso a tu cuenta",
            ["Click Connect. Last.fm opens in your browser: click \"Yes, allow access\" there and this window finishes by itself."] = "Haz clic en Conectar. Last.fm se abre en tu navegador: haz clic ahí en \"Yes, allow access\" (\"Sí, permitir el acceso\") y esta ventana termina sola.",
            ["Start automatically when I sign in to Windows"] = "Abrir automáticamente al iniciar sesión en Windows",
            ["Cancel"] = "Cancelar",
            ["Connect"] = "Conectar",
            ["Open the Last.fm page again"] = "Abrir de nuevo la página de Last.fm",
            ["Paste both the API key and the Shared secret first."] = "Primero pega la API key y el Shared secret.",
            ["Contacting Last.fm..."] = "Conectando con Last.fm...",
            ["Waiting for you to click \"Yes, allow access\" on the Last.fm page in your browser..."] = "Esperando a que hagas clic en \"Yes, allow access\" (\"Sí, permitir el acceso\") en la página de Last.fm de tu navegador...",
            ["Last.fm didn't accept that API key. Check you copied the API key and Shared secret correctly."] = "Last.fm no aceptó esa API key. Revisa que copiaste bien la API key y el Shared secret.",
            ["Couldn't reach Last.fm: {0}"] = "No se pudo conectar con Last.fm: {0}",
            ["Timed out waiting for approval. Click Connect to try again."] = "Se acabó el tiempo de espera. Haz clic en Conectar para intentarlo de nuevo.",
            ["That approval link expired. Click Connect to try again."] = "Ese enlace de aprobación caducó. Haz clic en Conectar para intentarlo de nuevo.",
            ["Last.fm rejected the Shared secret. Check you copied it correctly."] = "Last.fm rechazó el Shared secret. Revisa que lo copiaste bien.",
        };
    }
}
