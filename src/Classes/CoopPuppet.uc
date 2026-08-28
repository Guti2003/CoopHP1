//================================================================================
// HP1 Co-op  -  modo cooperativo para Harry Potter y la Piedra Filosofal (2001)
// Miguel Gutierrez (@Guti2003). Todos los derechos reservados - ver LICENSE.
//================================================================================
// CoopPuppet - ghost of the remote player.
//
// 2026-08-27: se dibujaba como Ron y por eso NO animaba. skronMesh no tiene el
// set de animaciones de Harry, y el emisor manda nombres de Harry. Ahora usa la
// malla de Harry. Ver ARREGLOS.md (BUG 1).
//
// Differences from the HP2 original:
//  - Mesh lives in the HarryPotter package on HP1, not HPModels.
//    HP1: SkeletalMesh'HarryPotter.skronMesh'   (verified in RON.uc)
//    HP2: SkeletalMesh'HPModels.skharryMesh'
//  - Height handling is NOT the HP2 formula. HP2 subtracted the full 42 because
//    its bare-Pawn puppet drew the mesh from the actor Location upward. On HP1
//    that sinks Ron to the waist (reported from play). HP1's Harry has
//    CollisionHeight=42 and Ron has CollisionHeight=30, so the peer's Location
//    (Harry's cylinder centre = feet + 42) has to be re-based to Ron's centre
//    (feet + 30) - a 12 unit drop, not 42. ZOffset defaults to that and is
//    tunable live with the CoopZ console command, since the exact value depends
//    on mesh origins baked into HarryPotter.u that cannot be read from source.
//  - Collision is forced off so the puppet never fires level triggers twice.
//    This is the single most important invariant of the whole mod.
//================================================================================

class CoopPuppet extends Pawn;

const SIDE_OFFSET = 80.0;
const HARRY_HEIGHT = 42.0;   // Harry.uc defaultproperties CollisionHeight

var float ZOffset;           // peer centre -> puppet centre; set by CoopManager

var vector TargetLoc;
var vector TargetVel;
var rotator TargetRot;
var name TargetAnim;
var float TargetAnimRate;
var string PlayerName;
var float LastPacketAge;
var bool bDidFirstPlace;
var name TriedAnim;          // ultima animacion que se intento reproducir

event PostBeginPlay()
{
    Super.PostBeginPlay();
    DisableCollision();
}

function DisableCollision()
{
    SetCollision(False, False, False);
    bProjTarget = False;
}

// Peer sends Harry's Location, which is his collision cylinder centre.
// Re-base it onto Ron's centre.
function vector PeerToLocal(vector peerMid)
{
    local vector v;
    v = peerMid;
    v.Z = peerMid.Z - ZOffset;
    return v;
}

// Height at which the puppet's centre must sit for its feet to rest on floorZ.
function float FloorToCentre(float floorZ)
{
    return floorZ + HARRY_HEIGHT - ZOffset;
}

function SetTarget(vector L, vector V, rotator R, name Anim, float AnimRate, string Name)
{
    TargetLoc = PeerToLocal(L);
    TargetVel = V;
    TargetRot = R;
    TargetAnim = Anim;
    TargetAnimRate = AnimRate;
    PlayerName = Name;
    LastPacketAge = 0.0;
}

// Trace world geometry under XY; returns a centre-height Location standing on
// whatever floor is below 'at'.
function vector SnapFeetToFloor(vector at)
{
    local vector HitLoc, HitNorm, start, end;
    local Actor HitAct;

    start = at;
    start.Z = at.Z + 250.0;
    end = at;
    end.Z = at.Z - 1000.0;

    HitAct = Trace(HitLoc, HitNorm, end, start, false);
    if (HitAct != None)
    {
        HitLoc.Z = FloorToCentre(HitLoc.Z);
        return HitLoc;
    }

    at.Z = at.Z - ZOffset;
    return at;
}

// One-shot: place beside the local player, then snap to the real floor.
function PlaceFirstTime(vector remoteLoc, rotator remoteRot, vector localLoc, rotator localRot)
{
    local vector flat, dir, p;
    local int attempt;
    local rotator tryRot;

    DisableCollision();

    flat = remoteLoc - localLoc;
    flat.Z = 0;
    if (VSize(flat) > 40.0)
        dir = Normal(flat);
    else
        dir = Normal(vect(0,1,0) << localRot);

    p = SnapFeetToFloor(localLoc + dir * SIDE_OFFSET);
    for (attempt = 1; attempt <= 3; attempt++)
    {
        if (Abs(p.Z - (localLoc.Z - ZOffset)) < 80.0)
            break;
        tryRot.Yaw = localRot.Yaw + attempt * 16384;
        dir = Normal(vect(0,1,0) << tryRot);
        p = SnapFeetToFloor(localLoc + dir * SIDE_OFFSET);
    }

    SetLocation(p);
    remoteRot.Pitch = 0;
    remoteRot.Roll = 0;
    SetRotation(remoteRot);
    TargetLoc = PeerToLocal(remoteLoc);
    bDidFirstPlace = true;
    bHidden = false;
}

simulated event Tick(float dt)
{
    local vector desired, d;
    local int yawDiff;
    local rotator newRot;
    local float blend;

    // Pawn base may flip collision back on.
    if (bCollideActors || bBlockActors || bBlockPlayers)
        DisableCollision();

    LastPacketAge += dt;

    // Dead reckoning: extrapolate for a quarter second, then freeze.
    if (LastPacketAge < 0.25)
        desired = TargetLoc + TargetVel * LastPacketAge;
    else
        desired = TargetLoc;

    blend = FClamp(dt * 14.0, 0.0, 1.0);

    d = desired - Location;
    if (VSize(d) > 800.0)
        SetLocation(desired);          // teleport / big desync
    else if (VSize(d) > 1.0)
        SetLocation(Location + d * blend);

    yawDiff = (TargetRot.Yaw - Rotation.Yaw) & 65535;
    if (yawDiff > 32768)
        yawDiff -= 65536;
    newRot = Rotation;
    newRot.Yaw = (Rotation.Yaw + int(float(yawDiff) * blend)) & 65535;
    newRot.Pitch = 0;
    newRot.Roll = 0;
    SetRotation(newRot);

    // La condicion era  AnimSequence != TargetAnim.  Si PlayAnim fallaba (la
    // secuencia no existe en la malla), AnimSequence nunca llegaba a igualar a
    // TargetAnim y esto se reintentaba en CADA tick: la animacion se reiniciaba
    // 60 veces por segundo, o sea que el muneco se veia congelado, y el log se
    // llenaba - 21.352 lineas en una sola partida. Recordar lo que ya se
    // intento corta las dos cosas de raiz.
    if (TargetAnim != '' && TargetAnim != TriedAnim)
    {
        TriedAnim = TargetAnim;
        PlayAnim(TargetAnim, TargetAnimRate, 0.15);
    }
    else if (bAnimFinished && TargetAnim != '' && TargetAnimRate > 0)
    {
        PlayAnim(TargetAnim, TargetAnimRate, 0.0);
    }
}

// ---------------------------------------------------------------------------
// RECONSTRUIDO 2026-08-27. UE1 no guarda defaultproperties en el ScriptText del
// .u, asi que este bloque no se recupero: esta deducido del codigo, de los
// comentarios de cabecera y de la tabla de nombres del paquete.
//
// ARREGLO BUG 1 - la malla era SkeletalMesh'HarryPotter.skronMesh'.
// skronMesh NO contiene el set de animaciones de Harry, y como el emisor manda
// nombres de animacion de Harry, PlayAnim fallaba en cada tick y el muneco se
// veia congelado (21.352 lineas de error en una sola sesion). Verificado:
// skharryMesh existe en HarryPotter.u y contiene breath, Jump, climb32,
// climb96start, climb96end y runback, que son justo las que faltaban.
// Coste aceptado por Miguel: se ven dos Harrys.
//
// OJO - con la malla de Harry el re-basado de altura sobra: el peer manda el
// centro del cilindro de Harry y el muneco YA es Harry. PuppetZOffset pasa a
// 0.0 en CoopManager. Si tu config guardada trae 12, corrigelo con  CoopZ 0
// ---------------------------------------------------------------------------
defaultproperties
{
    DrawType=DT_Mesh
    Mesh=SkeletalMesh'HarryPotter.skharryMesh'
    bHidden=True
    bCollideActors=False
    bBlockActors=False
    bBlockPlayers=False
    bProjTarget=False
    CollisionRadius=17.000000
    CollisionHeight=42.000000
    Role=ROLE_Authority
    RemoteRole=ROLE_None

    // ARREGLO BUG 4 - esto faltaba en la reconstruccion y costo caro.
    // Sin Health el muneco nace con 0, o sea que para el motor es un cadaver:
    // la limpieza de pawns del juego se lo llevaba cuando alguien moria y el
    // companero se volvia invisible para siempre. Ver CoopManager.UpdatePuppet.
    Health=1000
    bCanTeleport=False
    bIsPlayer=False
    bCollideWorld=False
    Physics=PHYS_None
    AnimRate=1.000000
}
