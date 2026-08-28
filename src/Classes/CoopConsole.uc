//================================================================================
// HP1 Co-op  -  modo cooperativo para Harry Potter y la Piedra Filosofal (2001)
// Miguel Gutierrez (@Guti2003). Todos los derechos reservados - ver LICENSE.
//================================================================================
// CoopConsole - entry point and console command surface for the co-op mod.
//
// WHY THE CONSOLE AND NOT ServerActors
// ------------------------------------
// The first design spawned CoopManager from
//     [Engine.GameEngine] ServerActors=HP1Coop.CoopManager
// That was verified to work under "UCC server" but NOT in the normal game:
// UE1 only instantiates ServerActors when the engine comes up as a server, and
// single-player HP1 runs NM_Standalone. Confirmed against HP.log - the actor
// never spawned, while "CoopConsole Transient.CoopConsole0" did.
//
// The console, by contrast, is instantiated on every level in every net mode,
// and Default.ini already redirects it:
//     [Engine.Engine] Console=HPMenu.HPConsole   ->   HP1Coop.CoopConsole
// So the console owns the mod lifecycle. HPConsole extends baseConsole extends
// UWindow.WindowConsole extends Engine.Console; cross-package subclassing was
// verified by the compiler.
//
// Commands:
//   CoopHost [port]            start hosting, default 7777
//   CoopConnect <ip> [port]    join a host by numeric IP
//   CoopDisconnect
//   CoopStatus
//   CoopDebug
//   CoopZ <n>                  tune the remote puppet's height, live
//
// The console opens with TAB by default (see DesiredConsoleKey below).
// It only reaches the co-op commands during actual gameplay - in the front-end
// menu there is no PlayerPawn, so Ready() reports "not ready yet".
//================================================================================

class CoopConsole extends HPConsole;

var CoopManager Coop;
var float EnsureAccum;
var bool bForcedDebug;

// Console key, as an EInputKey ordinal (Engine/Classes/Actor.uc).
//   9  = IK_Tab      <- default: free in HP1, User.ini ships "Tab=" empty
//   192 = the key left of "1" (retail default; the degree key on a Spanish
//         layout, backquote/tilde elsewhere)
// globalconfig so it can be changed in the ini without recompiling:
//   [HP1Coop.CoopConsole] DesiredConsoleKey=192
var globalconfig byte DesiredConsoleKey;

// RETAIL HP1 SHIPS WITH THE CONSOLE DISABLED.
// HPConsole.KeyEvent swallows the console key unless bDebugMode is set, and
// HPConsole.ShowConsole returns immediately for the same reason. bDebugMode is
// only ever set by ToggleDebugMode(), which refuses unless
// class'Version'.default.bDebugEnabled - and that has no value in
// defaultproperties, so it is False in the retail build.
//
// bDebugMode is 'globalconfig' on HPBase.baseConsole, so it can also be set from
// the ini ([HPBase.baseConsole] bDebugMode=True), and the installer does that.
// Forcing it here too means the mod's commands are reachable even if the ini
// gets reset or the user copies HP1Coop.u somewhere by hand.
//
// Side effect worth knowing: bDebugMode also enables the hold-space
// fast-forward through cutscenes (HPConsole.StartFastforward). Harmless, and
// arguably useful.
function ForceConsoleEnabled()
{
    bForcedDebug = true;
    bDebugMode = true;
    if (Root != None)
        Root.bAllowConsole = true;

    if (DesiredConsoleKey == 0)
        DesiredConsoleKey = 9;          // IK_Tab
    ConsoleKey = DesiredConsoleKey;

    log("[HP1Coop] console enabled (bDebugMode forced, ConsoleKey=" $ ConsoleKey $ ")");
}

// HPConsole.Tick already runs every frame in every level; piggyback on it so
// the manager is re-created after each level travel without any ini hooks.
event Tick(float delta)
{
    Super.Tick(delta);

    if (!bForcedDebug)
        ForceConsoleEnabled();

    EnsureAccum += delta;
    if (EnsureAccum < 1.0)
        return;
    EnsureAccum = 0.0;

    // Cheap in the steady state: one pointer check per second.
    GetCoop();
}

// THE LEVEL-TRAVEL ZOMBIE BUG
// ---------------------------
// This console object survives level travel; the CoopManager does not. But UE1
// tears an outgoing level down wholesale instead of calling Destroy() on each
// actor, so the old manager keeps bDeleteMe == False, and this console keeps a
// hard reference to it - which also stops it being garbage collected.
//
// The result: after "menu -> load save", the stale pointer looked alive, a new
// manager was never spawned, and the UDP socket that was still bound belonged
// to an actor in an unloaded level that no longer ticks. Symptom: the host
// reports it is hosting, and recv stays at 0 forever.
//
// Comparing Level catches it exactly - a zombie's Level is the old one.
function CoopManager GetCoop()
{
    local CoopManager m;

    if (Viewport == None || Viewport.Actor == None)
        return None;

    if (Coop != None && !Coop.bDeleteMe && Coop.Level == Viewport.Actor.Level)
        return Coop;

    // BUG 6 (2026-08-27) - al cambiar de nivel se perdia la conexion, y solo
    // le pasaba al que hospedaba.
    //
    // Esta consola sobrevive al cambio de nivel; el manager no. Pero mientras
    // esta variable siga apuntando al manager viejo, ese manager NO es basura
    // recogible, y con el sobrevive su CoopLink... que sigue reteniendo el
    // puerto 7777. El manager del nivel nuevo pedia ese mismo puerto y se lo
    // encontraba ocupado por el fantasma del nivel anterior.
    //
    // Al cliente no le afectaba porque pide un puerto efimero cualquiera, que
    // siempre hay libre. De ahi que fallara solo un lado.
    //
    // Es el mismo fondo que el BUG 2: en UE1 el socket no se suelta cuando uno
    // quiere, sino cuando pasa el recolector. La solucion es la misma: soltarlo
    // explicitamente, aqui antes de olvidarse del manager viejo.
    if (Coop != None)
        Coop.DisconnectLink();

    Coop = None;

    foreach Viewport.Actor.AllActors(class'CoopManager', m)
    {
        Coop = m;
        return Coop;
    }

    Coop = Viewport.Actor.Spawn(class'CoopManager');
    if (Coop == None)
        log("[HP1Coop] CoopConsole failed to spawn CoopManager");
    return Coop;
}

// Every command routes through this so a missing manager degrades to a console
// message instead of an "Accessed None" script warning.
function bool Ready()
{
    if (GetCoop() != None)
        return true;
    // Engine.Console: event Message(PlayerReplicationInfo PRI, coerce string Msg, name N)
    Message(None, "[HP1Coop] not ready yet - load a level first", 'Console');
    return false;
}

exec function CoopHost(optional int port)
{
    if (Ready())
    {
        if (port == 0) port = 7777;
        Message(None, "[HP1Coop] Arrancando servidor en el puerto " $ port $ "...", 'Console');
        Coop.Host(port);
    }
}

// Formas aceptadas:
//     CoopConnect 25.26.239.149          (puerto 7777)
//     CoopConnect 25.26.239.149:7778     (puerto explicito, forma recomendada)
//     CoopConnect 25.26.239.149 7778     (funciona, pero ver el aviso de abajo)
//
// AVISO SOBRE LA CONSOLA DE UE1. El reparto de argumentos cuando hay un string
// seguido de un int no es de fiar. Observado en partida con la misma orden:
//     ip="25.26.239.149 7778"  port=0      -> se conectaba al 7777 sin avisar
//     ip="25.26.239.149 778"   port=25     -> se perdio un caracter por el camino
// Por eso el puerto se saca del propio texto en vez de confiar en el segundo
// parametro: un solo token no tiene espacios y el motor no puede partirlo mal.
// El parametro int se mantiene solo por si acaso llega bien.
exec function CoopConnect(string ip, optional int port)
{
    local int i, p;
    local string rest;

    if (!Ready())
        return;

    // Quitar espacios de los extremos, que es de donde vienen los troceos raros.
    while (Left(ip, 1) == " ")
        ip = Mid(ip, 1);
    while (Right(ip, 1) == " ")
        ip = Left(ip, Len(ip) - 1);

    // Puerto pegado a la IP, por ":" o por espacio.
    i = InStr(ip, ":");
    if (i == -1)
        i = InStr(ip, " ");
    if (i != -1)
    {
        rest = Mid(ip, i + 1);
        ip = Left(ip, i);
        p = int(rest);
        if (p > 0 && p < 65536)
            port = p;
    }

    if (port <= 0 || port > 65535)
        port = 7777;

    Message(None, "[HP1Coop] Conectando a " $ ip $ ":" $ port $ "...", 'Console');
    Coop.ConnectTo(ip, port);
}

exec function CoopDisconnect()
{
    if (Ready())
    {
        Message(None, "[HP1Coop] Desconectando...", 'Console');
        Coop.DisconnectNow();
    }
}

// Con varios jugadores el estado ya no cabe en una linea: el manager lo imprime
// el mismo, una linea por jugador conectado.
exec function CoopStatus()
{
    if (Ready())
        Coop.PrintStatus();
}

// Ron sank to the waist on the first play test; this makes the fix a 5 second
// console tweak rather than a recompile.
exec function CoopZ(float z)
{
    if (Ready())
        Coop.SetZOffset(z);
}

// Los dos jugadores se llamaban "Harry" por defecto, asi que el HUD y el log
// eran ambiguos: "Harry se ha unido a la partida" no decia nada. Se guarda en
// la configuracion, o sea que se pone una vez y ya.
exec function CoopName(string nombre)
{
    if (Ready())
        Coop.SetPlayerName(nombre);
}

// Compartir inventario es cuestion de gusto, asi que se puede apagar. Cada uno
// decide por su cuenta: apagarlo significa que TU no repartes lo que recoges,
// pero sigues recibiendo lo que reparten los demas.
exec function CoopShare()
{
    if (Ready())
        Coop.ToggleShare();
}

exec function CoopDebug()
{
    if (Ready())
    {
        Coop.ToggleDebug();
        Message(None, "[HP1Coop] debug=" $ Coop.bShowDebug, 'Console');
    }
}

event PostRender(canvas C)
{
    Super.PostRender(C);
    
    if (Coop != None)
    {
        C.Font = LocalSmallFont;
        Coop.DrawHUD(C);
    }
}

// RECONSTRUIDO 2026-08-27. DesiredConsoleKey no se pone aqui a proposito: es
// globalconfig y el codigo le asigna 9 (IK_Tab) si vale 0, para que el ini del
// usuario mande.
defaultproperties
{
}
