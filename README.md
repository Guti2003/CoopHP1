# HP1 Co-op

Mod cooperativo para **Harry Potter y la Piedra Filosofal** (PC, 2001, Unreal Engine 1).

Dos jugadores, cada uno con su propia partida, se ven mutuamente en el mapa y
los hechizos que lanza uno existen de verdad en la partida del otro.

Portado desde [hp2-coop-multiplayer](https://github.com/jenyaalexanov/hp2-coop-multiplayer)
(jenyaalexanov, MIT), que hace lo mismo para La Cámara Secreta.
Recursos de modding de HP1: metallicafan212 y Han / OldUnreal.

> **Este repositorio no incluye el juego.** Hace falta una copia propia instalada.

## Estado

Hito 3 — funciona la presencia y los hechizos. El mundo todavía no se comparte.

| | |
|---|---|
| Posición, rotación y animación a 20 Hz | ✅ |
| Seguir al compañero al cambiar de mapa | ✅ |
| Hechizos (vuelan, chocan y explotan en ambas partidas) | ✅ |
| Objetos recogibles, secretos de Lumos | ⬜ pendiente |
| Enemigos, puertas, mecanismos | ❌ fuera de alcance realista |

**Tres bugs confirmados en partida real.** Ver [ARREGLOS.md](HP1Coop-Sources/ARREGLOS.md).
El de las animaciones ya está corregido en las fuentes; los otros dos esperan a
poder compilar.

## Qué hay aquí

```
CONTEXTO.md               historia del proyecto, arquitectura y decisiones
HP1CoopHito3/             la build que funciona, con instalador
HP1Coop-Sources/
  Classes/*.uc            las cuatro clases del mod
  ARREGLOS.md             los tres bugs y sus arreglos
  LEEME-FUENTES.md        de dónde salieron estas fuentes
```

## Nota sobre las fuentes

El código se perdió: el PC donde se desarrollaba se borró. Las clases de
`HP1Coop-Sources/Classes/` se **recuperaron del propio paquete compilado** —
UnrealEngine 1 guarda el texto fuente de cada clase dentro del `.u`, así que no
hubo que descompilar nada.

Lo único que no viaja ahí son los bloques `defaultproperties`, que están
reconstruidos a mano y **sin verificar contra una compilación**.

## Instalación

`HP1CoopHito3/HP1Coop/Instalar.bat`. Necesita haber abierto el juego al menos una
vez. Los dos jugadores deben instalar el **mismo** archivo — 52.760 bytes.

Comandos en la consola del juego (TAB), ya en partida:

```
CoopHost [puerto]            CoopConnect <ip> [puerto]
CoopStatus                   CoopZ <n>
CoopDisconnect               CoopDebug
```

## Licencia

MIT, heredada del proyecto original de HP2.
