# XWipe

App para macOS que borra de una sola vez los **posts, respuestas, reposts y me gusta** de tu propia cuenta de X (Twitter), sin pagar ni depender de servicios de terceros.

> 🤖 **Proyecto vibecodeado.** Este código lo escribió una IA ([Claude Code](https://claude.com/claude-code)) iterando conmigo en conversación, probándolo contra mi propia cuenta. Funcionó para mí, pero no es software auditado: léelo antes de confiar en él.

## Características
- Borra posts y respuestas, reposts y me gusta (puedes elegir cuáles).
- **No pide ni guarda tu contraseña.** Inicias sesión tú mismo en un navegador integrado (WKWebView).
- Escanea y borra por tandas de ~100 y repite hasta vaciar la cuenta, sorteando el tope de ~3200 posts que X muestra por recorrido.
- Respeta los límites de X: si te frena, espera sola y continúa.
- Reanudable: guarda lo ya borrado y puedes detenerla en cualquier momento.

## Requisitos
- macOS 13 o superior
- Xcode / Swift 5.9+ (para compilar)

## Instalación y uso
```bash
git clone https://github.com/serjrodriguez/XWipe.git
cd XWipe
./build.sh
open XWipe.app
```
Si macOS bloquea la app por no estar firmada: clic derecho → **Abrir**.

1. Inicia sesión en X en el panel derecho.
2. Marca qué borrar: posts y respuestas, reposts, me gusta.
3. Pulsa **Escanear y borrar…** y confirma.
4. **No toques el panel derecho mientras corre**: la app navega por tu perfil sola.

## Cómo funciona
X no ofrece una API gratuita para esto, así que la app trabaja dentro de la propia página:

1. Abre `x.com/home`, entra a tu perfil con el enlace de la barra lateral y recorre las pestañas **Posts** y **Respuestas** haciendo scroll.
2. Un script inyectado lee las respuestas que la página de X recibe (así no hay que replicar las firmas internas de X) y extrae los posts que son tuyos.
3. Cada tanda se borra con las mismas llamadas GraphQL que usa x.com, ejecutadas dentro de la sesión ya iniciada.
4. Repite desde el inicio hasta que una pasada no borre nada.

Los me gusta se leen y se quitan con las llamadas internas `Likes` y `UnfavoriteTweet`.

Progreso y registro se guardan en `~/Library/Application Support/XWipe/` (`done.json`, `log.txt`).

## Limitaciones
- No borra seguidores/seguidos, mensajes directos, marcadores, listas, foto, banner ni bio.
- Solo borra lo que X muestra en tu perfil; algo oculto o muy antiguo podría no aparecer.
- X cambia sus llamadas internas sin aviso, así que puede dejar de funcionar en cualquier momento.

## ⚠️ Advertencia
Borrar es **irreversible**. Automatizar la web de X puede ir contra sus términos de servicio. Úsalo solo en tu propia cuenta y bajo tu responsabilidad; no hay garantía de ningún tipo.

## Licencia
[MIT](LICENSE)
