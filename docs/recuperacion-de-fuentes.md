# Cómo se recuperaron las fuentes

Extraídas el 2026-08-27 desde `System\HP1Coop.u` (52.760 bytes) de la instalación
en `E:\Harry Potter y la Piedra Filosofal`.

**De dónde salen:** UnrealEngine 1 guarda el texto fuente completo de cada clase
dentro del `.u`, en la propiedad `ScriptText` del objeto `Class`. No es
descompilado ni reconstruido: es el código original tal cual se escribió,
con comentarios e indentación.

## Qué se recuperó — completo

```
Classes/CoopPuppet.uc     154 líneas    10 llaves / 10 cierres
Classes/CoopManager.uc    634 líneas    62 / 62
Classes/CoopLink.uc        79 líneas    10 / 10
Classes/CoopConsole.uc    181 líneas    19 / 19
```

Llaves balanceadas en las cuatro. Todo el código ejecutable está.

## Qué FALTA — los bloques `defaultproperties`

UE1 **no** guarda `defaultproperties` en el `ScriptText`: los serializa aparte,
como propiedades por defecto del objeto, en binario. Así que hay que
reconstruirlos a mano antes de poder compilar.

Nombres de propiedad presentes en la tabla del paquete, que indican qué contenían:

| Clase | Propiedades a reconstruir |
|---|---|
| `CoopPuppet` | `Mesh` (**`skronMesh`** ← el bug 1 vive aquí), `DrawType`, `bHidden`, `CollisionRadius`, `CollisionHeight`, `bCollideActors`, `bBlockActors`, `bBlockPlayers`, `bProjTarget`, `Role`, `RemoteRole` |
| `CoopManager` | `PuppetZOffset` (por defecto 12.0) |
| `CoopConsole` | `DesiredConsoleKey` (9 = IK_Tab) |
| `CoopLink` | probablemente vacío |

Son pocas líneas por clase y sus valores se deducen del código y de los
comentarios. El paquete conserva `SkeletalMesh` y `skronMesh` en la tabla de
nombres, lo que confirma cómo se asignaba la malla del muñeco.

## Para compilar

Falta `ucc.exe`. No está en la instalación del juego (`System\` no lo trae y
`Support\` solo tiene instaladores). Hace falta el toolkit de modding de HP1
(metallicafan212 / OldUnreal).

Una vez se tenga, el ciclo es el estándar de UE1:

1. `System\HP1Coop\Classes\*.uc`
2. `EditPackages=HP1Coop` en el ini de compilación
3. `ucc make`

## Aviso

Estas fuentes están **sin verificar contra una compilación**. Reconstruyen el
código, no lo garantizan idéntico al original: si el compilador se queja, lo más
probable es que falte algo de los `defaultproperties` o alguna directiva del
principio del archivo (`#exec`), que tampoco viaja en el `ScriptText`.

Ver `..\CONTEXTO.md` para los tres bugs confirmados y sus arreglos.
