# HP1 Co-op

**Modo cooperativo online para *Harry Potter y la Piedra Filosofal* (PC, 2001).**

Hasta cuatro personas recorren Hogwarts al mismo tiempo. Se ven moverse y
animarse, se siguen entre niveles, los hechizos que lanza uno existen de verdad
en la partida de los demás, y lo que recogen se comparte.

Creado por **Miguel Gutiérrez** ([@Guti2003](https://github.com/Guti2003)).

> **Este repositorio no incluye el juego.** Necesitas tu propia copia instalada.

---

## ⬇️ Descargar

### **[▶ Descargar HP1Coop.zip](../../raw/main/dist/HP1Coop.zip)**

Un solo archivo con todo lo necesario: el mod, el instalador y las
instrucciones. Descomprímelo y ejecuta `Instalar.bat`.

**Todos los que vayan a jugar juntos tienen que instalar este mismo archivo.**

<sub>Si tu antivirus dice algo, es un falso positivo por el instalador: es un script
de PowerShell que copia un archivo y cambia una línea de configuración, y ese
patrón se parece al de un instalador malicioso. El código está a la vista en
[`dist/HP1Coop/installer/`](dist/HP1Coop/installer/) — son 120 líneas legibles.</sub>

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
gragea la tienen todos, y el objeto desaparece del mundo de los demás para que
no se duplique.

**Lo que no:** las ranas de chocolate (son salud, no colección) y los puntos de
casa (se ganan por hacer algo, y todos hacen lo mismo, así que ya los ganan por
separado).

---

## Instalación

1. Abre el juego **al menos una vez** y ciérralo. Necesita crear su configuración.
2. Descomprime el `.zip` y ejecuta `Instalar.bat`.
3. Si no encuentra el juego, te va a pedir la carpeta — la que contiene
   `System\` y `Maps\`.

El instalador copia un archivo a `System\` y cambia una línea de configuración,
con respaldo de todo lo que toca. No modifica ningún archivo original del juego.
Para deshacerlo, `Desinstalar.bat`.

**Todos los jugadores tienen que instalar exactamente el mismo archivo.** Si las
versiones no coinciden, el mod avisa al conectar.

---

## Cómo conectarse

Lo más simple es una **red privada virtual (VPN)**: los pone a todos en la misma
red local y no hay que abrir puertos en el módem.

**Recomendado: [Hamachi](https://vpn.net/)** (LogMeIn Hamachi).

1. Que todos lo instalen y creen una cuenta.
2. Uno crea una red: *Red → Crear una red nueva*, con un nombre y contraseña.
3. Los demás entran con *Red → Unirse a una red existente*.
4. Cuando estén conectados, cada uno ve su IP de Hamachi arriba en la ventana
   (empieza por `25.`). **Esa es la IP que hay que usar en el juego**, no la de
   internet.

Sirven igual **Radmin VPN**, **ZeroTier** o **Tailscale**. Con cualquiera de
ellas no hay que configurar nada más.

Si prefieren jugar por internet directo, sin VPN, solo el anfitrión necesita
abrir el puerto **UDP 7777** en su módem.

---

## Cómo jugar

Abran el juego, **carguen una partida**, y presionen **TAB** para la consola.
Los comandos no funcionan en el menú principal: necesitan a Harry en el mapa.

```
El anfitrión:   CoopHost
Los demás:      CoopConnect <ip-del-anfitrión>
```

Con Hamachi, la IP del anfitrión es la que empieza por `25.` — por ejemplo
`CoopConnect 25.10.20.30`.

Pónganse nombre para distinguirse: `CoopName TuNombre`. Se guarda solo.

### Comandos

| Comando | Qué hace |
|---|---|
| `CoopHost [puerto]` | Hacer de anfitrión |
| `CoopConnect <ip>[:puerto]` | Conectarse (solo IP numérica) |
| `CoopName <nombre>` | Tu nombre. Se guarda solo |
| `CoopStatus` | Estado, jugadores conectados y ping |
| `CoopShare` | Activa o desactiva el inventario compartido |
| `CoopZ <n>` | Altura del muñeco, si flota o se hunde |
| `CoopDebug` | Información extra en el registro |
| `CoopDisconnect` | Cortar la sesión |

Para usar un puerto distinto del 7777, **péguenlo con dos puntos**:
`CoopConnect 25.10.20.30:7778`. La consola de UE1 reparte mal los argumentos
cuando hay un texto seguido de un número.

---

## Quitar el modo depuración

El mod tiene que activar el modo depuración del juego, porque **la consola viene
desactivada de fábrica** y sin él no habría forma de escribir los comandos. El
efecto secundario es que quedan a la vista textos de depuración que estorban.

Una vez que estén todos conectados, presiona **F7** y desaparecen.

**Ojo con esto:** F7 también apaga la consola. Es la misma llave para las dos
cosas — el juego revisa el modo depuración antes de abrirla. Así que:

> **Conéctense primero, y presionen F7 después.**

Si necesitas la consola de nuevo, escribe esto **durante la partida**, sin abrir
nada, tal cual:

```
HARRYDEBUGMODEON
```

Es un truco del propio juego. Vuelve a activar el modo depuración, y con él la
consola y los comandos del mod.

---

## Si algo falla

El registro está en `Documentos\Harry Potter\HP.log`, y todas las líneas del mod
empiezan por `[HP1Coop]`. Con `CoopDebug` activado sale bastante más.

**No conecta.** Revisa, en este orden: que el anfitrión haya escrito `CoopHost`
ya estando en partida; que vea `hospedando en el puerto UDP 7777`; que todos
tengan el mismo archivo; y que estén usando la IP de la VPN, no la de internet.
Si nadie contesta, el mod avisa a los diez intentos.

**El juego no abre**, incluso sin el mod. El renderizador por software a
pantalla completa ya no funciona en Windows 10/11. En
`Documentos\Harry Potter\HP.ini`, cambia las dos líneas `StartupFullscreen=True`
a `False`. Ese archivo está fuera de la carpeta del juego, así que reinstalar no
lo arregla.

---

## Estructura

```
src/Classes/       el código del mod (UnrealScript)
dist/HP1Coop.zip   lo que se descarga
dist/HP1Coop/      su contenido, por si prefieres verlo suelto
docs/              arquitectura, decisiones de diseño e historial de fallas
```

Para compilar hace falta `UCC.exe` del toolkit de modding de HP1. El proceso y
sus dos trampas están en [docs/arquitectura.md](docs/arquitectura.md).

---

## Cómo está hecho

El mod **no modifica ningún archivo del juego**. Se engancha por la clave
`Console=` de la configuración, y desde ahí monta todo lo demás.

La idea que lo hizo posible: **antes de dar por hecho que hay que interceptar
una llamada, revisar si el juego ya guarda ese dato en algún lugar accesible.**
Se asumía que sincronizar hechizos exigía inyectar código en el paquete del
juego. No hacía falta: la varita ya anotaba su último disparo. Lo mismo pasó con
el nombre real del nivel y con los contadores de objetos.

Los detalles están en [docs/arquitectura.md](docs/arquitectura.md), y las ocho
fallas que aparecieron jugando —con su causa y su arreglo— en
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

El compilador y las fuentes de UnrealScript de HP1 vienen del archivo de
preservación de [OldUnreal](https://www.oldunreal.com/) y del trabajo de
recopilación de metallicafan212 y Han.

El juego no está incluido y este repositorio no otorga ningún derecho sobre él.
