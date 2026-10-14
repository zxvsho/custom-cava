# custom-cava

Mini visualizador de audio para Waybar que **no consume nada cuando no suena música**.

A diferencia de los scripts que dejan `cava` corriendo todo el tiempo, este escucha los eventos MPRIS por D-Bus (con `playerctl --follow`) y solo lanza `cava` cuando algún reproductor pasa a `Playing`. Al pausar o parar, mata `cava` y el módulo queda vacío, por lo que Waybar lo oculta solo. Con **clic derecho** puedes apagarlo y encenderlo a mano.

```
▂▄▅▇▅▃▂▁   ← sonando
(nada)     ← pausado: sin cava, 0 % de CPU
▁▁▁        ← desactivado con clic derecho
```

## Cómo funciona

| Estado | Qué corre | Coste |
|---|---|---|
| Sin música | Un `bash` y `playerctl` bloqueados esperando eventos D-Bus | 0 % CPU, ~2 MB de RAM real |
| Sonando | Lo anterior + `cava` + un único `sed` en streaming | ~1-2 % CPU (15 fps, 8 barras) |
| Desactivado | Igual que sin música; no se lanza `cava` aunque suene algo | 0 % CPU |

No hay polling ni procesos por frame: un solo `sed -u` traduce la salida de `cava` a bloques (`▁▂▃▄▅▆▇█`).

> Mediciones puntuales con `top` en un i5-12450H con PipeWire. Tus números variarán según el audio y la configuración.

## Requisitos

- [`cava`](https://github.com/karlstav/cava)
- [`playerctl`](https://github.com/altdesktop/playerctl)
- `waybar`
- `bash` y `sed` (GNU)
- Una fuente con los bloques `▁▂▃▄▅▆▇█` (las Nerd Font los traen)

En Arch Linux:

```bash
sudo pacman -S cava playerctl waybar
```

## Instalación

```bash
git clone https://github.com/zxvsho/custom-cava.git
cd custom-cava
install -Dm755 waybar-cava.sh ~/.local/bin/waybar-cava
```

Puedes dejar el script en otra ruta y apuntar `exec` ahí; solo necesita permiso de ejecución.

## Añadirlo a Waybar

En tu `config.jsonc`, define el módulo y añádelo a la lista donde lo quieras:

```jsonc
"modules-left": ["custom/cava"],

"custom/cava": {
  "exec": "$HOME/.local/bin/waybar-cava",
  "format": "{}",
  "on-click-right": "$HOME/.local/bin/waybar-cava toggle"
}
```

No hace falta `interval` ni `return-type`: el script imprime una línea por frame y Waybar la muestra tal cual. Cuando imprime una línea vacía, Waybar oculta el módulo.

Estilo opcional en `style.css`:

```css
#custom-cava {
  padding: 0 10px;
  letter-spacing: 1px;
}
```

Aplica los cambios reiniciando Waybar:

```bash
pkill waybar; waybar &
```

## Clic derecho: apagar y encender

`waybar-cava toggle` alterna el visualizador:

- **Apagado:** mata `cava`, ignora los eventos de reproducción y el módulo muestra `▁▁▁`. Ese marcador existe a propósito: un módulo vacío se oculta y no podrías hacer clic para volver a encenderlo.
- **Encendido:** si hay algo sonando, `cava` arranca al instante; si no, el módulo vuelve a ocultarse.

El estado se guarda en `$XDG_RUNTIME_DIR` (o `/tmp`), así que se reinicia al cerrar sesión. Puedes cambiar el marcador con la variable `CAVA_OFF_TEXT`:

```jsonc
"exec": "env CAVA_OFF_TEXT=off $HOME/.local/bin/waybar-cava"
```

El módulo solo es clicable mientras es visible, es decir, sonando o apagado.

## Configuración

Los parámetros están en el bloque de configuración de `cava` dentro de `waybar-cava.sh`:

| Opción | Por defecto | Efecto |
|---|---|---|
| `bars` | `8` | Número de barras. Menos barras, menos trabajo. |
| `framerate` | `15` | Fotogramas por segundo. Es lo que más influye en el consumo de `cava` y de Waybar al repintar. |
| `method` | `pipewire` | Backend de audio. Cámbialo a `pulse` si usas PulseAudio puro. |
| `sleep_timer` | `1` | Minutos de silencio tras los que `cava` se duerme solo. |

El archivo temporal de configuración (`$XDG_RUNTIME_DIR/cava-waybar.conf`) se regenera al arrancar, así que edita siempre el script.

## Comprobar que funciona

Con música pausada no debe haber `cava`:

```bash
pgrep -a cava                         # sin salida
pgrep -af "waybar-cava|playerctl"     # solo el script y un playerctl
```

Con música sonando:

```bash
playerctl -a status                   # Playing
pgrep -a cava                         # cava -p .../cava-waybar.conf
```

Para medir el consumo:

```bash
top -b -n 2 -d 3 -p $(pgrep -d, -x 'cava|sed|waybar') | tail -n 5
```

## ¿Y el módulo nativo `cava` de Waybar?

Waybar incluye un módulo `cava` propio, pero necesita estar compilado con libcava, y el paquete oficial de Arch no lo activa por defecto (existe un paquete aparte en el AUR, `waybar-cava`).

En mi laptop lo probé con la misma configuración (15 fps, 8 barras) y la misma música:

| | CPU sonando |
|---|---|
| Módulo nativo | ~4-4,7 % (`waybar`) |
| Este script | ~1,7 % (`waybar` + `cava` + `sed`) |

Son medidas puntuales de `top`; mídelo en tu equipo si te importa. Además, este script no hace nada en reposo, porque `cava` ni siquiera existe hasta que suena algo.

## Solución de problemas

**Las barras no aparecen aunque suena música.**
Comprueba con `playerctl -l` que el reproductor expone MPRIS. Si no aparece, el script no puede detectarlo. Revisa también que no lo hayas apagado con el clic derecho.

**Aparecen cuadrados o caracteres raros.**
La fuente de tu barra no tiene los bloques `▁▂▃▄▅▆▇█`. Usa una Nerd Font en `style.css`.

**Sale texto en blanco al lanzar desde el compositor.**
Waybar puede arrancar sin un locale UTF-8, y `sed` falla con caracteres multibyte. Añade `export LC_ALL=C.UTF-8` al inicio del script.

**`cava` falla al abrir el audio.**
Cambia `method` a `pulse` o ajusta `source` según tu sistema.

**Hay varias copias del script tras recargar Waybar.**
Comprueba con `pgrep -af waybar-cava`. El script se limpia al recibir `SIGTERM`; si quedan restos de una versión anterior, mátalos con `pkill -f waybar-cava`.

## Limitaciones

- Solo detecta reproductores que exponen MPRIS (navegadores, Spotify, mpv con el plugin MPRIS, etc.).
- Con varios reproductores abiertos, `playerctl --follow status` puede seguir solo a uno y perder eventos de los demás.
- El mínimo de consumo mientras suena lo marca `cava`, que captura el audio y calcula la FFT. Se reduce con `framerate` y `bars`, pero no desaparece.

## Licencia y créditos

[MIT](LICENSE). Puedes usarlo, modificarlo y redistribuirlo libremente, pero cualquier copia o fork debe conservar el aviso de copyright y el texto de la licencia, lo que mantiene el crédito al autor original.
