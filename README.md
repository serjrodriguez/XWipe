# XWipe

App para macOS (SwiftUI + WKWebView) que borra de una sola vez los posts, respuestas, reposts y me gusta de tu propia cuenta de X.

Inicias sesión tú mismo en el navegador integrado; la app no pide ni guarda tu contraseña. Recorre tu perfil como lo haría un usuario y borra cada tanda con las mismas llamadas que usa x.com, repitiendo hasta vaciar la cuenta.

## Uso
```bash
./build.sh
open XWipe.app
```
1. Inicia sesión en X en el panel derecho.
2. Marca qué borrar (posts y respuestas, reposts, me gusta).
3. Pulsa **Escanear y borrar…** y no toques el panel derecho mientras corre.

El progreso y el registro se guardan en `~/Library/Application Support/XWipe/` (`done.json`, `log.txt`).

## Aviso
Es irreversible y automatiza la web de X, lo cual puede ir contra sus términos. Úsalo solo en tu cuenta y bajo tu responsabilidad. X cambia sus llamadas internas con frecuencia, así que puede dejar de funcionar.
