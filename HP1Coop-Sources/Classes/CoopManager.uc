//================================================================================
// CoopManager - heart of the HP1 co-op mod. Milestone 1: pose sync only.
//
// KEY ARCHITECTURAL DIFFERENCE FROM HP2COOP
// -----------------------------------------
// HP2Coop hooks the game by recompiling the player class with
// "class CoopHarry injects harry", a non-standard keyword provided by the M212
// toolchain. HP1 does not need that. This actor is created and kept alive by
// CoopConsole, which the stock ini key
//     [Engine.Engine] Console=HP1Coop.CoopConsole
// already redirects. Nothing in HarryPotter.u or HPBase.u is modified, so none
// of the embedded meshes/textures in those 14 MB packages are at risk.
//
// An earlier revision spawned this actor from
//     [Engine.GameEngine] ServerActors=HP1Coop.CoopManager
// That was tested and does NOT work: UE1 only instantiates ServerActors when
// the engine comes up as a server, and single-player HP1 is NM_Standalone. It
// did work under "UCC server", which is what made the failure confusing.
//
// Text protocol over UDP ("|" delimited) - identical to HP2Coop v1 so the two
// codebases stay diffable:
//   HPCOOP|1|HELLO|name
//   HPCOOP|1|HELLOACK|name
//   HPCOOP|1|PING|seq
//   HPCOOP|1|PONG|seq
//   HPCOOP|1|S|map|x|y|z|yaw|pitch|vx|vy|vz|anim|rate|hp
//   HPCOOP|1|MAP|mapfile.unr
//   HPCOOP|1|SP|seq|class|x|y|z|pitch|yaw   (sent 3x, deduped by seq)
//   HPCOOP|1|BYE
// Milestone 2+ will add SP (spells), PICK (props), LTRIG (lumos secrets).
//================================================================================

class CoopManager extends Actor
  config;

const PROTO = "HPCOOP|1";
const SEND_RATE = 0.05;      // 20 Hz
const HELLO_RATE = 1.0;
const PING_RATE = 2.0;
const HIDE_TIMEOUT = 3.0;
const DROP_TIMEOUT = 10.0;

var config string LastHost;
var config int LastPort;
var config string PlayerName;
var config bool bAutoHost;      // this instance hosts as soon as a level loads
var config bool bAutoConnect;   // this instance dials LastHost as soon as a level loads
var config bool bShowDebug;
// Vertical re-base from Harry's cylinder centre to Ron's. See CoopPuppet.
// Tunable live with CoopZ because it depends on mesh origins baked into
// HarryPotter.u.
var config float PuppetZOffset;

var PlayerPawn Player;       // HP1: Harry extends baseHarry extends PlayerPawn
var CoopLink Link;
var CoopPuppet Puppet;

var bool bConnected;
var bool bIsHost;
var float LastRecvTime;
var float SendAccum;
var float HelloAccum;
var float PingAccum;
var float FindAccum;
var int RecvCount;
var int SentCount;
var int PingSeq;
var float PingSentAt;
var int EstPingMs;

var string RemoteName;
var string RemoteMap;
var string LastAnnouncedMap;
var vector RLoc;
var rotator RRot;
var vector RVel;
var name RAnim;
var float RAnimRate;
var int RHealth;

// Spell sync. We do NOT hook Harry.Cast() - that would need package injection.
// baseWand already records its own last shot in LastCastedSpell, so detecting a
// new cast is one pointer comparison per tick instead of an AllActors sweep.
var baseSpell LastSentSpell;
// A cast is a one-off event, not a stream: if its packet is lost the spell
// simply never appears for the peer. So it goes out three times and the
// receiver drops repeats by sequence number.
var int SpellSeq;
var int LastRecvSpellSeq;

// ---------------------------------------------------------------------------

event PostBeginPlay()
{
    Super.PostBeginPlay();
    if (PlayerName == "")
        PlayerName = "Harry";
    if (LastPort == 0)
        LastPort = 7777;
    log("[HP1Coop] manager up on " $ MapName());
    Enable('Tick');
}

function LogMsg(coerce string msg)
{
    log("[HP1Coop] " $ msg);
    if (Player != None)
        Player.ClientMessage("[HP1Coop] " $ msg);
}

// The local player pawn is not guaranteed to exist when ServerActors are
// spawned, and the game swaps it during cutscenes - so re-acquire lazily.
function bool EnsurePlayer()
{
    local PlayerPawn p;

    if (Player != None && !Player.bDeleteMe)
        return true;

    foreach AllActors(class'PlayerPawn', p)
    {
        if (p.Player != None)
        {
            Player = p;
            return true;
        }
    }
    return false;
}

static function int StrSplit(coerce string Text, string delim, out string parts[24])
{
    local int n, i;
    local string rest;

    rest = Text;
    n = 0;
    while (rest != "" && n < 24)
    {
        i = InStr(rest, delim);
        if (i == -1)
        {
            parts[n] = rest;
            n++;
            rest = "";
        }
        else
        {
            parts[n] = Left(rest, i);
            n++;
            rest = Mid(rest, i + Len(delim));
        }
    }
    return n;
}

// ---------------------------------------------------------------------------
// Session control
// ---------------------------------------------------------------------------

// ARREGLO BUG 2 (2026-08-27) - re-hospedar fallaba con "failed to bind UDP
// port 7777".
//
// Antes esto hacia DisconnectLink() (que destruia el socket) y acto seguido
// pedia el MISMO puerto. En UE1 Destroy() solo marca el actor: el socket nativo
// no se cierra hasta la recogida de basura, que dentro de una partida puede
// tardar muchisimo. Y como StartHost pide el puerto exacto (BindPort con
// bUseNextAvailable=False), no se recuperaba solo nunca.
//
// La solucion es no destruir el socket: si ya tenemos uno bindeado al puerto
// que nos piden, se reutiliza y solo se limpia el estado de sesion.
function Host(optional int port)
{
    if (port == 0)
        port = 7777;

    if (Link != None && !Link.bDeleteMe && Link.BoundPort == port)
    {
        // Ya estamos escuchando en ese puerto: reciclar en vez de re-bindear.
        ResetSession();
        Link.Reset();
        bIsHost = true;
        bAutoHost = true;
        bAutoConnect = false;
        LastPort = port;
        SaveConfig();
        LogMsg("hosting on UDP port " $ port $ ", waiting for a player...");
        return;
    }

    DisconnectLink();

    Link = Spawn(class'CoopLink');
    Link.Init(Self);
    bIsHost = true;
    bConnected = false;
    ResetStats();

    if (Link.StartHost(port))
    {
        LastPort = port;
        bAutoHost = true;
        bAutoConnect = false;
        SaveConfig();
    }
    else
    {
        Link.Destroy();
        Link = None;
    }
}

function ConnectTo(string ip, optional int port)
{
    if (port == 0)
        port = 7777;
    DisconnectLink();

    Link = Spawn(class'CoopLink');
    Link.Init(Self);
    bIsHost = false;
    bConnected = false;
    HelloAccum = 0.0;
    ResetStats();

    if (Link.StartClient(ip, port))
    {
        LastHost = ip;
        LastPort = port;
        bAutoConnect = true;
        bAutoHost = false;
        SaveConfig();
        // Knock straight away instead of waiting a full HELLO_RATE. Without
        // this the 20 Hz "S" stream reaches the host first and adopts the
        // session before names are ever exchanged.
        Link.SendTo(PROTO $ "|HELLO|" $ PlayerName);
    }
    else
    {
        Link.Destroy();
        Link = None;
    }
}

// Parte del ARREGLO BUG 2: al desconectar se conserva el socket. Antes se
// destruia, y como UE1 no lo cierra hasta la recogida de basura, el siguiente
// CoopHost no podia volver a coger el puerto. Conservarlo es ademas mas barato:
// re-hospedar pasa a ser instantaneo.
function DisconnectNow()
{
    if (Link != None)
    {
        Link.SendTo(PROTO $ "|BYE");
        Link.Reset();
    }
    ResetSession();
    bAutoHost = false;
    bAutoConnect = false;
    SaveConfig();
    LogMsg("disconnected");
}

// Limpia el estado de la sesion sin tocar el socket.
function ResetSession()
{
    bConnected = false;
    RemoteName = "";
    RemoteMap = "";
    LastAnnouncedMap = "";
    ResetStats();
    HidePuppet();
}

// Cierre completo, socket incluido. Se usa al cambiar de puerto y al recoger
// el nivel; para CoopDisconnect basta con ResetSession().
function DisconnectLink()
{
    if (Link != None)
    {
        Link.Destroy();
        Link = None;
    }
    bConnected = false;
    RemoteName = "";
    LastAnnouncedMap = "";
    HidePuppet();
}

function ResetStats()
{
    RecvCount = 0;
    SentCount = 0;
    EstPingMs = 0;
    PingSeq = 0;
    SpellSeq = 0;
    LastRecvSpellSeq = 0;
}

function PrintStatus()
{
    local string role;

    if (Link == None)
    {
        LogMsg("no session. Use CoopHost [port] or CoopConnect <ip> [port]");
        return;
    }
    if (bIsHost)
        role = "host";
    else
        role = "client";

    LogMsg("role=" $ role $ ", connected=" $ bConnected $ ", peer=" $ RemoteName
         $ ", peerMap=" $ RemoteMap $ ", sent=" $ SentCount $ ", recv=" $ RecvCount
         $ ", ping=" $ EstPingMs $ "ms");
}

// Live height tuning: CoopZ <n>. Re-places the puppet so the change is visible
// immediately instead of on the next level.
function SetZOffset(float z)
{
    PuppetZOffset = z;
    SaveConfig();
    if (Puppet != None)
    {
        Puppet.ZOffset = z;
        Puppet.bDidFirstPlace = false;
    }
    LogMsg("puppet Z offset = " $ PuppetZOffset);
}

function ToggleDebug()
{
    bShowDebug = !bShowDebug;
    SaveConfig();
    LogMsg("debug=" $ bShowDebug);
}

// ---------------------------------------------------------------------------
// Packet handling
// ---------------------------------------------------------------------------

function OnPeerFound(string addr)
{
    LogMsg("incoming player from " $ addr);
}

function OnPacket(string Text)
{
    local string parts[24];
    local int n, seq;
    local float ms;
    local vector SpLoc;
    local rotator SpRot;

    n = StrSplit(Text, "|", parts);
    if (n < 3)
        return;
    if ((parts[0] $ "|" $ parts[1]) != PROTO)
        return;

    if (bShowDebug && parts[2] != "S")
        LogMsg("Recibido paquete: " $ parts[2]);

    LastRecvTime = Level.TimeSeconds;
    RecvCount++;

    if (parts[2] == "HELLO")
    {
        if (n >= 4)
            RemoteName = parts[3];
        if (!bConnected)
        {
            bConnected = true;
            LastAnnouncedMap = "";
            LogMsg(RemoteName $ " joined the game");
        }
        Link.SendTo(PROTO $ "|HELLOACK|" $ PlayerName);
    }
    else if (parts[2] == "HELLOACK")
    {
        if (n >= 4)
            RemoteName = parts[3];
        if (!bConnected)
        {
            bConnected = true;
            LastAnnouncedMap = "";
            LogMsg("connected to the host game of " $ RemoteName);
        }
    }
    else if (parts[2] == "PING")
    {
        if (n >= 4)
            Link.SendTo(PROTO $ "|PONG|" $ parts[3]);
    }
    else if (parts[2] == "PONG")
    {
        if (n >= 4)
        {
            seq = int(parts[3]);
            if (seq == PingSeq && PingSentAt > 0.0)
            {
                ms = (Level.TimeSeconds - PingSentAt) * 1000.0;
                if (EstPingMs == 0)
                    EstPingMs = int(ms);
                else
                    EstPingMs = (EstPingMs * 3 + int(ms)) / 4;
            }
        }
    }
    else if (parts[2] == "S")
    {
        if (n < 15)
            return;
        if (!bConnected)
        {
            bConnected = true;
            LastAnnouncedMap = "";      // force a MAP announce now that we have a peer
            LogMsg("player state stream started");
        }
        // Late or lost handshake: ask again rather than run the whole session
        // with an unnamed peer.
        if (RemoteName == "")
            Link.SendTo(PROTO $ "|HELLO|" $ PlayerName);
        RemoteMap  = parts[3];
        RLoc.X     = float(parts[4]);
        RLoc.Y     = float(parts[5]);
        RLoc.Z     = float(parts[6]);
        RRot.Yaw   = int(parts[7]);
        RRot.Pitch = int(parts[8]);
        RRot.Roll  = 0;
        RVel.X     = float(parts[9]);
        RVel.Y     = float(parts[10]);
        RVel.Z     = float(parts[11]);
        RAnim      = name(parts[12]);
        RAnimRate  = float(parts[13]);
        RHealth    = int(parts[14]);
        UpdatePuppet();
    }
    else if (parts[2] == "MAP")
    {
        if (n >= 4)
        {
            RemoteMap = parts[3];
            if (RemoteName != "")
                LogMsg(RemoteName $ " moved to " $ RemoteMap);
            else
                LogMsg("peer moved to " $ RemoteMap);
                
            // Follow peer if we are the client and in a different map
            if (!bIsHost && Player != None && RemoteMap != MapName())
            {
                LogMsg("Following peer to " $ RemoteMap);
                Player.ClientTravel(RemoteMap, TRAVEL_Absolute, false);
            }
        }
    }
    else if (parts[2] == "SP")
    {
        if (n < 10)
            return;
        seq = int(parts[3]);
        if (seq <= LastRecvSpellSeq)
            return;                     // repeat of a cast we already played
        LastRecvSpellSeq = seq;
        SpLoc.X     = float(parts[5]);
        SpLoc.Y     = float(parts[6]);
        SpLoc.Z     = float(parts[7]);
        SpRot.Pitch = int(parts[8]);
        SpRot.Yaw   = int(parts[9]);
        SpRot.Roll  = 0;
        ApplyRemoteSpell(parts[4], SpLoc, SpRot);
    }
    else if (parts[2] == "BYE")
    {
        LogMsg(RemoteName $ " left the game");
        bConnected = false;
        HidePuppet();
        if (!bIsHost)
            HelloAccum = 0.0;
    }
}

// ---------------------------------------------------------------------------
// Puppet
// ---------------------------------------------------------------------------

function UpdatePuppet()
{
    // Only mirror the peer while both of us stand in the same level.
    if (RemoteMap != MapName())
    {
        HidePuppet();
        return;
    }
    if (Player == None)
        return;

    if (Puppet == None)
    {
        Puppet = Spawn(class'CoopPuppet');
        if (Puppet == None)
        {
            log("[HP1Coop] failed to spawn puppet");
            return;
        }
    }

    // Must be set before the first placement, which traces to the floor.
    Puppet.ZOffset = PuppetZOffset;

    if (!Puppet.bDidFirstPlace)
        Puppet.PlaceFirstTime(RLoc, RRot, Player.Location, Player.Rotation);

    Puppet.bHidden = false;
    Puppet.SetTarget(RLoc, RVel, RRot, RAnim, RAnimRate, RemoteName);
}

function HidePuppet()
{
    if (Puppet != None)
        Puppet.bHidden = true;
}

// Startup.unr is the front-end menu and Entry.unr the engine's boot map.
// Auto-hosting there binds port 7777 to a manager that dies the moment the
// player loads a save, and the real level then cannot bind it.
function bool bIsMenuMap()
{
    local string m;
    m = Caps(MapName());
    return (m == "STARTUP" || m == "ENTRY");
}

// ARREGLO BUG 3 (2026-08-27) - la identidad del nivel.
//
// Level.Outer.Name NO sirve: en HP1 una partida guardada ES un mapa. Cargar
// desde el menu ejecuta literalmente  open save0.usa  (FESlotPage.uc:252), asi
// que el paquete del nivel pasa a llamarse "save0" y los dos jugadores dejan de
// coincidir en cuanto uno cruza una transicion y el otro no. Observado en
// partida: uno en "save0", el otro en "LEV_TUT1B", y el muneco desaparece.
// Peor aun, la logica de seguimiento intentaba ClientTravel("save0").
//
// El juego si sabe donde esta: HPConsole.doLevelSave saca el nombre real de
// Level.LevelEnterText, cortando en el primer punto (HPConsole.uc:252-256).
// Esa propiedad vive en el LevelInfo, o sea que viaja dentro del savegame y
// sigue siendo correcta despues de cargar. Y es un nombre al que ClientTravel
// puede viajar de verdad, cosa que "save0" no era.
//
// Caps() porque se compara entre maquinas y no queremos que una diferencia de
// mayusculas separe a dos jugadores que estan en el mismo sitio.
function string MapName()
{
    local string s;
    local int n;

    s = Level.LevelEnterText;
    n = InStr(s, ".");
    if (n != -1)
        s = Left(s, n);

    if (s != "")
        return Caps(s);

    // Sin LevelEnterText no hay nada mejor que el nombre del paquete.
    return Caps(string(Level.Outer.Name));
}

// ---------------------------------------------------------------------------
// HUD
// ---------------------------------------------------------------------------

function DrawHUD(canvas C)
{
    local string S;
    local float XL, YL;
    
    if (!bConnected || RemoteName == "")
        return;
        
    C.DrawColor.R = 255;
    C.DrawColor.G = 255;
    C.DrawColor.B = 255;
    
    S = "Co-op: Connected to " $ RemoteName;
    if (RHealth > 0)
        S = S $ " (HP: " $ RHealth $ ")";
        
    C.TextSize(S, XL, YL);
    C.SetPos(10, C.ClipY - YL - 30); // Draw at the bottom left, above console
    C.DrawText(S, false);
}

// ---------------------------------------------------------------------------

event Tick(float dt)
{
    local string pkt;

    // Re-acquire the local pawn at most twice a second.
    FindAccum += dt;
    if (FindAccum >= 0.5)
    {
        FindAccum = 0.0;
        if (!EnsurePlayer())
            return;
        if (Link == None && !bIsMenuMap())
        {
            if (bAutoHost)
                Host(LastPort);
            else if (bAutoConnect && LastHost != "")
                ConnectTo(LastHost, LastPort);
        }
    }
    if (Player == None || Link == None)
        return;

    // Client keeps knocking until the host answers.
    if (!bIsHost && !bConnected)
    {
        HelloAccum += dt;
        if (HelloAccum >= HELLO_RATE)
        {
            HelloAccum = 0.0;
            if (bShowDebug) LogMsg("Enviando paquete HELLO a " $ LastHost $ "...");
            Link.SendTo(PROTO $ "|HELLO|" $ PlayerName);
        }
    }

    if (bConnected)
    {
        PingAccum += dt;
        if (PingAccum >= PING_RATE)
        {
            PingAccum = 0.0;
            PingSeq++;
            PingSentAt = Level.TimeSeconds;
            Link.SendTo(PROTO $ "|PING|" $ PingSeq);
        }

        if (Level.TimeSeconds - LastRecvTime > HIDE_TIMEOUT)
            HidePuppet();
        if (Level.TimeSeconds - LastRecvTime > DROP_TIMEOUT)
        {
            LogMsg("peer timed out");
            bConnected = false;
            HidePuppet();
        }
    }

    // Announce map changes so the peer can hide its puppet. Only once
    // connected - otherwise LastAnnouncedMap is consumed while nobody is
    // listening and the announce never happens again.
    if (bConnected && MapName() != LastAnnouncedMap)
    {
        LastAnnouncedMap = MapName();
        Link.SendTo(PROTO $ "|MAP|" $ LastAnnouncedMap);
    }

    SendAccum += dt;
    if (SendAccum < SEND_RATE)
        return;
    SendAccum = 0.0;

    pkt = PROTO $ "|S|" $ MapName()
        $ "|" $ int(Player.Location.X) $ "|" $ int(Player.Location.Y) $ "|" $ int(Player.Location.Z)
        $ "|" $ (Player.Rotation.Yaw & 65535) $ "|" $ Player.Rotation.Pitch
        $ "|" $ int(Player.Velocity.X) $ "|" $ int(Player.Velocity.Y) $ "|" $ int(Player.Velocity.Z)
        $ "|" $ string(Player.AnimSequence) $ "|" $ Player.AnimRate
        $ "|" $ Player.Health;

    Link.SendTo(pkt);
    SentCount++;

    if (bConnected)
        CheckLocalSpell();
}

// ---------------------------------------------------------------------------
// Spells
// ---------------------------------------------------------------------------

function CheckLocalSpell()
{
    local baseWand w;
    local baseSpell s;
    local string SpellPkt;

    w = baseWand(Player.Weapon);
    if (w == None)
        return;

    s = w.LastCastedSpell;
    if (s == None || s == LastSentSpell)
        return;

    // A new projectile actor exists that the local Harry just cast.
    LastSentSpell = s;
    SpellSeq++;

    SpellPkt = PROTO $ "|SP|" $ SpellSeq $ "|" $ string(s.Class)
        $ "|" $ int(s.Location.X) $ "|" $ int(s.Location.Y) $ "|" $ int(s.Location.Z)
        $ "|" $ s.Rotation.Pitch $ "|" $ (s.Rotation.Yaw & 65535);

    Link.SendTo(SpellPkt);
    Link.SendTo(SpellPkt);
    Link.SendTo(SpellPkt);

    if (bShowDebug)
        LogMsg("hechizo lanzado: " $ string(s.Class));
}

// Recreate the peer's projectile locally. Spawned unowned on purpose: it must
// not be attributed to our Harry, and it must never feed back into
// CheckLocalSpell (which only ever reads our own wand).
function ApplyRemoteSpell(string clsName, vector loc, rotator rot)
{
    local class<baseSpell> c;
    local baseSpell s;

    c = class<baseSpell>(DynamicLoadObject(clsName, class'Class', true));
    if (c == None)
        c = class<baseSpell>(DynamicLoadObject("HPBase." $ clsName, class'Class', true));
    if (c == None)
    {
        log("[HP1Coop] clase de hechizo desconocida: " $ clsName);
        return;
    }

    s = Spawn(c, None, , loc, rot);
    if (s == None)
    {
        if (bShowDebug)
            LogMsg("no se pudo crear el hechizo remoto " $ clsName);
        return;
    }

    s.Velocity = vector(rot) * s.default.Speed;
    if (bShowDebug)
        LogMsg("hechizo remoto: " $ clsName);
}

// ---------------------------------------------------------------------------
// RECONSTRUIDO 2026-08-27. Ver nota en CoopPuppet.uc.
// PuppetZOffset era 12.0 (centro de Harry -> centro de Ron). Con la malla de
// Harry en el muneco ya no hay que re-basar nada: 0.0.
// ---------------------------------------------------------------------------
defaultproperties
{
    PuppetZOffset=0.000000
    bHidden=True
}
