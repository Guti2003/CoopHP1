# HP1 Co-op

**Modo cooperativo online para *Harry Potter y la Piedra Filosofal* (PC, 2001).**

Hasta cuatro personas recorren Hogwarts a la vez. Os veis moveros y animaros,
os seguís entre niveles, los hechizos que lanza uno existen de verdad en la
partida de los demás, y lo que recogéis se comparte.

Creado por **Miguel Gutiérrez** ([@Guti2003](https://github.com/Guti2003)).

> **Este repositorio no incluye el juego.** Necesitas tu propia copia instalada.

---

## Qué funciona

| | |
|---|---|
| Hasta 4 jugadores a la vez | ✅ |
| Posición, rotación y animaciones a 20 Hz | ✅ |
| Seguir al anfitrión al cambiar de nivel | ✅ |
| Hechizos reales en todas las partidas | ✅ |
| Mecanismos y secretos de Lumos | ✅ |
| Grageas, estrellas y cromos compartidos | ✅ |
| Enemigos, cinemáticas, progreso de partida | ❌ fuera de alcance |

**Los hechizos no son un adorno visual.** El proyectil existe de verdad en cada
partida: vuela, choca y explota. Por eso los calderos, las placas de presión y
los secretos de Lumos funcionan solos — todos ellos se activan con un hechizo, y
el hechizo está de verdad en los dos mundos.

**Lo que se comparte:** grageas, estrellas y cromos de mago. Si uno recoge una
gragea la tenéis todos, y el objeto desaparece del mundo de los demás para que
no se duplique.

**Lo que no:** las ranas de chocolate (son salud, no colección) y los puntos de
casa (se ganan por hacer algo, y todos hacéis lo mismo, así que ya los ganáis
por separado).

---

## Instalación

1. Abre el juego **al menos una vez** y ciérralo. Necesita crear su configuración.
2. Descomprime y ejecuta `dist/HP1Coop/Instalar.bat`.
3. Si no encuentra el juego, te pedirá la carpeta — la que contiene `System\` y `Maps\`.

El instalador copia un archivo a `System\` y cambia una línea de configuración,
con copia de seguridad de todo lo que toca. No modifica ningún archivo original
del juego. Para deshacerlo, `Desinstalar.bat`.

**Todos los jugadores deben instalar exactamente el mismo archivo.** Si las
versiones no coinciden, el mod os avisa al conectar.

---

## Cómo jugar

Abrid el juego, **cargad una partida**, y pulsad **TAB** para la consola. Los
comandos no funcionan en el menú principal: necesitan a Harry en el mapa.

```
El anfitrión:   CoopHost
Los demás:      CoopConnect <ip-del-anfitrión>
```

Solo el anfitrión necesita abrir el puerto **UDP 7777** si jugáis por internet.
Con una VPN (Radmin, ZeroTier, Tailscale) no hay que abrir nada.

### Comandos

| Comando | Qué hace |
|---|---|
| `CoopHost [puerto]` | Hacer de anfitrión |
| `CoopConnect <ip>[:puerto]` | Conectarse (solo IP numérica) |
| `CoopName <nombre>` | Tu nombre. Se guarda solo |
| `CoopStatus` | Estado, jugadores conectados y ping |
| `CoopShare` | Activa o desactiva el inventario compartido |
| `CoopZ <n>` | Altura del muñeco, si flota o se hunde |
| `CoopDebug` | Información extra en el log |
| `CoopDisconnect` | Cortar la sesión |

Para poner un puerto distinto del 7777, **pégalo con dos puntos**:
`CoopConnect 25.26.239.149:7778`. La consola de UE1 reparte mal los argumentos
cuando hay un texto seguido de un número.

---

## Si algo falla

El registro está en `Documentos\Harry Potter\HP.log`, y todas las líneas del mod
empiezan por `[HP1Coop]`. Con `CoopDebug` activado sale bastante más.

**No conecta.** Comprueba, en este orden: que el anfitrión haya escrito
`CoopHost` ya en partida; que vea `hospedando en el puerto UDP 7777`; que todos
tengáis el mismo archivo. Si nadie contesta, el mod te avisa a los diez
intentos.

**El juego no arranca**, incluso sin el mod. El renderizador por software a
pantalla completa ya no funciona en Windows 10/11. En
`Documentos\Harry Potter\HP.ini`, cambia las dos líneas `StartupFullscreen=True`
a `False`. Ese archivo está fuera de la carpeta del juego, así que reinstalar no
lo arregla.

---

## Estructura

```
src/Classes/     el código del mod (UnrealScript)
dist/HP1Coop/    versión compilada lista para instalar
docs/            arquitectura, decisiones de diseño e historial de bugs
```

Para compilar hace falta `UCC.exe` del toolkit de modding de HP1. El proceso y
sus dos trampas están en [docs/arquitectura.md](docs/arquitectura.md).

---

## Cómo está hecho

El mod **no modifica ningún archivo del juego**. Se engancha por la clave
`Console=` de la configuración, y desde ahí monta todo lo demás.

La idea que lo hizo posible: **antes de asumir que hay que interceptar una
llamada, mirar si el juego ya guarda ese dato en algún sitio accesible.** Se
daba por hecho que sincronizar hechizos exigía inyectar código en el paquete del
juego. No hacía falta: la varita ya apuntaba su último disparo. Lo mismo pasó
con el nombre real del nivel y con los contadores de objetos.

Los detalles están en [docs/arquitectura.md](docs/arquitectura.md), y los ocho
bugs que aparecieron jugando —con su causa y su arreglo— en
[docs/historial-de-bugs.md](docs/historial-de-bugs.md).

---

## Licencia

**Descárgalo y juega libremente. No lo redistribuyas.**

| | |
|---|---|
| Descargar, usar y jugar gratis | ✅ |
| Leer el código y aprender de él | ✅ |
| Modificarlo para ti o tus amigos | ✅ |
| Publicar copias o versiones modificadas | ❌ enlaza aquí en vez de subir la tuya |
| Venderlo o incluirlo en algo de pago | ❌ |

Si quieres hacer algo de lo prohibido, **pídelo**: la respuesta puede ser que sí.
Los términos completos están en [LICENSE](LICENSE).

### Origen

Este mod es un port a *La Piedra Filosofal* de
[hp2-coop-multiplayer](https://github.com/jenyaalexanov/hp2-coop-multiplayer),
de jenyaalexanov, que hace lo mismo para *La Cámara Secreta* y se publicó bajo
licencia MIT. Las restricciones de arriba cubren el trabajo propio; las partes
heredadas siguen siendo MIT para quien las obtenga del proyecto original.

El compilador y las fuentes de UnrealScript de HP1 provienen del archivo de
preservación de [OldUnreal](https://www.oldunreal.com/) y del trabajo de
recopilación de metallicafan212 y Han.

El juego no está incluido y este repositorio no concede ningún derecho sobre él.
