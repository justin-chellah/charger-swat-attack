#include <sourcemod>

#define REQUIRE_EXTENSIONS
#include <dhooks>

#define TEAM_SURVIVOR 2
#define TEAM_ZOMBIE 3

#define ACT_TERROR_ATTACK 613
#define PLAYERANIMEVENT_ATTACK 33
#define SEQ_CHARGER_SWAT 7

#define GAMEDATA_FILE "charger_swat_attack"

#define MIN(%0,%1) ((%0) > (%1) ? (%1) : (%0))
#define MAX(%0,%1) ((%0) < (%1) ? (%1) : (%0))

enum ZombieClassType
{
	Zombie_Common = 0,
	Zombie_Smoker,
	Zombie_Boomer,
	Zombie_Hunter,
	Zombie_Spitter,
	Zombie_Jockey,
	Zombie_Charger,
	Zombie_Witch,
	Zombie_Tank,
	Zombie_Survivor,
};

enum SurvivorCharacterType
{
	SurvivorCharacter_Gambler = 0,
	SurvivorCharacter_Producer,
	SurvivorCharacter_Coach,
	SurvivorCharacter_Mechanic,
	SurvivorCharacter_NamVet,
	SurvivorCharacter_TeenGirl,
	SurvivorCharacter_Biker,
	SurvivorCharacter_Manager,
	SurvivorCharacter_Unknown
};

// Gesture Slots.
enum
{
	GESTURE_SLOT_ATTACK_AND_RELOAD,
	GESTURE_SLOT_GRENADE,
	GESTURE_SLOT_JUMP,
	GESTURE_SLOT_SWIM,
	GESTURE_SLOT_FLINCH,
	GESTURE_SLOT_VCD,
	GESTURE_SLOT_CUSTOM,

	GESTURE_SLOT_COUNT,
};

DynamicHook g_hDHook_CBaseAbility_HandleCustomCollision = null;
DynamicHook g_hDHook_CBaseAnimating_SelectWeightedSequence = null;

Handle g_hSDKVCall_CCSPlayer_DoAnimationEvent = null;
Handle g_hSDKCall_CMultiPlayerAnimState_IsGestureSlotPlaying = null;
Handle g_hSDKCall_ThrowImpactedSurvivor = null;

int g_nOffset_CCharge_m_bHitSurvivors = -1;
int g_nOffset_CTerrorPlayer_m_animState = -1;

ConVar claw_swing_interval = null;
ConVar z_charge_duration = null;

bool IsCarryingSomeone( int iClient )
{
	return GetEntPropEnt( iClient, Prop_Send, "m_carryVictim" ) != INVALID_ENT_REFERENCE;
}

bool CMultiPlayerAnimState_IsGestureSlotPlaying( Address addrAnimState, int iGestureSlot, int iGestureActivity )
{
	return SDKCall( g_hSDKCall_CMultiPlayerAnimState_IsGestureSlotPlaying, addrAnimState, iGestureSlot, iGestureActivity );
}

bool CCharge_HasAlreadyHitSurvivor( int iCustomAbility, SurvivorCharacterType eSurvivorCharacter )
{
	return view_as< bool >( GetEntData( iCustomAbility, g_nOffset_CCharge_m_bHitSurvivors + view_as< int >( eSurvivorCharacter ), 1 ) );
}

ZombieClassType GetZombieClass( int iClient )
{
	return view_as< ZombieClassType >( GetEntProp( iClient, Prop_Send, "m_zombieClass" ) );
}

void CCSPlayer_DoAnimationEvent( int iClient, int nEvent, int nData = 0 )
{
	SDKCall( g_hSDKVCall_CCSPlayer_DoAnimationEvent, iClient, nEvent, nData );
}

void ThrowImpactedSurvivor( int iAttacker, int iVictim, float flForce, bool bApplyDamage )
{
	SDKCall( g_hSDKCall_ThrowImpactedSurvivor, iAttacker, iVictim, flForce, bApplyDamage );
}

void CCharge_MarkSurvivorAsHit( int iCustomAbility, SurvivorCharacterType eSurvivorCharacter )
{
	SetEntData( iCustomAbility, g_nOffset_CCharge_m_bHitSurvivors + view_as< int >( eSurvivorCharacter ), true, 1 );
}

void PlaySound( int iEntity, const char[] szGameSound )
{
    int nChannel;
    int nLevel;
    float flVolume;
    int nPitch;
    char szSample[PLATFORM_MAX_PATH];

    if ( !GetGameSoundParams( szGameSound, nChannel, nLevel, flVolume, nPitch, szSample, sizeof( szSample ), iEntity ) )
	{
        return;
    }

    PrecacheSound( szSample );
    EmitSoundToAll( szSample, iEntity, nChannel, nLevel, SND_NOFLAGS, flVolume, nPitch );
}

public MRESReturn DHook_CCharge_HandleCustomCollision( int iCustomAbility, DHookReturn hReturn, DHookParam hParams )
{
	int iEntity = hParams.Get( 1 );

	if ( !iEntity )
	{
		return MRES_Ignored;
	}

	if ( GetEntProp( iCustomAbility, Prop_Send, "m_isCharging", 1 ) )
	{
		int iOwnerEntity = GetEntPropEnt( iCustomAbility, Prop_Send, "m_hOwnerEntity" );

		if ( !IsCarryingSomeone( iOwnerEntity ) )
		{
			Address addrAnimState = LoadFromAddress( GetEntityAddress( iOwnerEntity ) + view_as< Address >( g_nOffset_CTerrorPlayer_m_animState ), NumberType_Int32 );

			if ( iEntity <= MaxClients && GetClientTeam( iEntity ) == TEAM_SURVIVOR && CMultiPlayerAnimState_IsGestureSlotPlaying( addrAnimState, GESTURE_SLOT_ATTACK_AND_RELOAD, ACT_TERROR_ATTACK ) )
			{
				SurvivorCharacterType eSurvivorCharacter = view_as< SurvivorCharacterType >( GetEntProp( iEntity, Prop_Send, "m_survivorCharacter" ) );

				if ( !CCharge_HasAlreadyHitSurvivor( iCustomAbility, eSurvivorCharacter ) )
				{
					CCharge_MarkSurvivorAsHit( iCustomAbility, eSurvivorCharacter );

					int nCheckpointPZNumChargeVictims = GetEntProp( iOwnerEntity, Prop_Send, "m_checkpointPZNumChargeVictims" );

					SetEntProp( iOwnerEntity, Prop_Send, "m_checkpointPZNumChargeVictims", ++nCheckpointPZNumChargeVictims );

					PlaySound( iOwnerEntity, "ChargerZombie.HitPerson" );

					float flForce = MAX( MIN( ( GetGameTime() - GetEntPropFloat( iCustomAbility, Prop_Send, "m_chargeStartTime" ) ) / z_charge_duration.FloatValue, 1.0 ), 0.5 );

					ThrowImpactedSurvivor( iOwnerEntity, iEntity, flForce, true );

					DHookSetReturn( hReturn, true );

					return MRES_Supercede;
				}
			}
		}
	}

	return MRES_Ignored;
}

public MRESReturn DHook_CTerrorPlayer_SelectWeightedSequence_Post( int iClient, DHookReturn hReturn, DHookParam hParams )
{
	int nActivity = hParams.Get( 1 );

	if ( nActivity != ACT_TERROR_ATTACK )
	{
		return MRES_Ignored;
	}

	if ( GetClientTeam( iClient ) == TEAM_ZOMBIE && GetZombieClass( iClient ) == Zombie_Charger && !IsCarryingSomeone( iClient ) )
	{
		int iCustomAbility = GetEntPropEnt( iClient, Prop_Send, "m_customAbility" );

		if ( iCustomAbility != INVALID_ENT_REFERENCE && GetEntProp( iCustomAbility, Prop_Send, "m_isCharging", 1 ) )
		{
			DHookSetReturn( hReturn, SEQ_CHARGER_SWAT );

			return MRES_Supercede;
		}
	}

	return MRES_Ignored;
}

public void OnEntityCreated( int iEntity, const char[] szClassname )
{
	if ( StrEqual( szClassname, "ability_charge" ) )
	{
		g_hDHook_CBaseAbility_HandleCustomCollision.HookEntity( Hook_Pre, iEntity, DHook_CCharge_HandleCustomCollision );
	}
}

public void OnClientPutInServer( int iClient )
{
	// Bots aren't able to do a SWAT attack
	if ( IsFakeClient( iClient ) )
	{
		return;
	}

	g_hDHook_CBaseAnimating_SelectWeightedSequence.HookEntity( Hook_Post, iClient, DHook_CTerrorPlayer_SelectWeightedSequence_Post );
}

public void OnPlayerRunCmdPre( int iClient, int fButtons, int nImpulse, const float flVel[3], const float flAngles[3], int iWeapon, int nSubType, int nCmdNum, int nTickcount, int nSeed, const int nMouse[2] )
{
	if ( !IsPlayerAlive( iClient ) )
	{
		return;
	}

	if ( !( fButtons & IN_ATTACK2 ) )
	{
		return;
	}

	if ( GetClientTeam( iClient ) != TEAM_ZOMBIE )
	{
		return;
	}

	if ( GetZombieClass( iClient ) != Zombie_Charger )
	{
		return;
	}

	if ( IsCarryingSomeone( iClient ) )
	{
		return;
	}

	int iCustomAbility = GetEntPropEnt( iClient, Prop_Send, "m_customAbility" );

	if ( iCustomAbility != INVALID_ENT_REFERENCE && GetEntProp( iCustomAbility, Prop_Send, "m_isCharging", 1 ) )
	{
		Address addrAnimState = LoadFromAddress( GetEntityAddress( iClient ) + view_as< Address >( g_nOffset_CTerrorPlayer_m_animState ), NumberType_Int32 );

		if ( !CMultiPlayerAnimState_IsGestureSlotPlaying( addrAnimState, GESTURE_SLOT_ATTACK_AND_RELOAD, ACT_TERROR_ATTACK ) )
		{
			int iActiveWeapon = GetEntPropEnt( iClient, Prop_Send, "m_hActiveWeapon" );

			if ( iActiveWeapon != INVALID_ENT_REFERENCE )
			{
				float flNextSecondaryAttack = GetEntPropFloat( iActiveWeapon, Prop_Send, "m_flNextSecondaryAttack" );

				if ( GetGameTime() >= flNextSecondaryAttack )
				{
					SetEntPropFloat( iActiveWeapon, Prop_Send, "m_flNextSecondaryAttack", GetGameTime() + claw_swing_interval.FloatValue );

					PlaySound( iClient, "Claw.Swing" );

					CCSPlayer_DoAnimationEvent( iClient, PLAYERANIMEVENT_ATTACK );
				}
			}
		}
	}
}

public void OnPluginStart()
{
	GameData hGameData = new GameData( GAMEDATA_FILE );

	if ( !hGameData )
	{
		SetFailState( "Unable to load gamedata file \"" ... GAMEDATA_FILE ... "\"" );
	}

#define GET_OFFSET_WRAPPER(%0,%1)\
	%1 = hGameData.GetOffset( %0 );\
	\
	if ( %1 == -1 )\
	{\
		delete hGameData;\
		\
		SetFailState( "Unable to find gamedata offset entry for \"" ... %0 ... "\"" );\
	}

#define PREP_SDK_CALL_SET_FROM_CONF_WRAPPER(%0,%1)\
	if ( !PrepSDKCall_SetFromConf( hGameData, %0, %1 ) ) \
	{\
		delete hGameData;\
		\
		SetFailState( "Unable to find gamedata offset entry for \"" ... %1 ... "\"" );\
	}

	int iVtbl_CBaseAbility_HandleCustomCollision;
	GET_OFFSET_WRAPPER( "CBaseAbility::HandleCustomCollision", iVtbl_CBaseAbility_HandleCustomCollision )

	int iVtbl_CBaseAnimating_SelectWeightedSequence;
	GET_OFFSET_WRAPPER( "CBaseAnimating::SelectWeightedSequence", iVtbl_CBaseAnimating_SelectWeightedSequence )

	GET_OFFSET_WRAPPER( "CCharge::m_bHitSurvivors", g_nOffset_CCharge_m_bHitSurvivors )
	GET_OFFSET_WRAPPER( "CTerrorPlayer::m_animState", g_nOffset_CTerrorPlayer_m_animState )

	StartPrepSDKCall( SDKCall_Player );
	PREP_SDK_CALL_SET_FROM_CONF_WRAPPER( SDKConf_Virtual, "CCSPlayer::DoAnimationEvent" )
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_hSDKVCall_CCSPlayer_DoAnimationEvent = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Raw );
	PREP_SDK_CALL_SET_FROM_CONF_WRAPPER( SDKConf_Signature, "CMultiPlayerAnimState::IsGestureSlotPlaying" )
	PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain );
	g_hSDKCall_CMultiPlayerAnimState_IsGestureSlotPlaying = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Static );
	PREP_SDK_CALL_SET_FROM_CONF_WRAPPER( SDKConf_Signature, "ThrowImpactedSurvivor" )
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	PrepSDKCall_AddParameter( SDKType_Float, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );
	g_hSDKCall_ThrowImpactedSurvivor = EndPrepSDKCall();

	g_hDHook_CBaseAbility_HandleCustomCollision = new DynamicHook( iVtbl_CBaseAbility_HandleCustomCollision, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity );
	g_hDHook_CBaseAbility_HandleCustomCollision.AddParam( HookParamType_CBaseEntity );
	g_hDHook_CBaseAbility_HandleCustomCollision.AddParam( HookParamType_VectorPtr );
	g_hDHook_CBaseAbility_HandleCustomCollision.AddParam( HookParamType_VectorPtr );
	g_hDHook_CBaseAbility_HandleCustomCollision.AddParam( HookParamType_ObjectPtr );
	g_hDHook_CBaseAbility_HandleCustomCollision.AddParam( HookParamType_ObjectPtr );

	g_hDHook_CBaseAnimating_SelectWeightedSequence = new DynamicHook( iVtbl_CBaseAnimating_SelectWeightedSequence, HookType_Entity, ReturnType_Int, ThisPointer_CBaseEntity );
	g_hDHook_CBaseAnimating_SelectWeightedSequence.AddParam( HookParamType_Int );

	delete hGameData;

	claw_swing_interval = FindConVar( "claw_swing_interval" );
	z_charge_duration = FindConVar( "z_charge_duration" );

	for ( int iClient = 1; iClient <= MaxClients; iClient++ )
	{
		if ( IsClientInGame( iClient ) )
		{
			OnClientPutInServer( iClient );
		}
	}
}

public Plugin myinfo =
{
	name = "[ZE] Charger SWAT Attack",
	author = "Justin \"Sir Jay\" Chellah",
	description = "Allows chargers to throw survivors up in the air by pressing the right mouse button during a charge",
	version = "1.0.0",
	url = "https://justin-chellah.com"
};