#if defined _TFJump_included
 #endinput
#endif
#define _TFJump_included

#pragma semicolon 1

#define ALPHA

#define PLUGIN_AUTHOR "rush"
#define PLUGIN_NAME "TF2 Jump"
#define PLUGIN_DESC "A sourcemod plugin to provide a sever with utilities to aid with jumping."
#define PLUGIN_VERSION "1.0.0a"

#define TAG	 "{aliceblue}[{cadetblue}TF{aliceblue}Jump]"
#define T1 "{cadetblue}"
#define T2 "{aliceblue}"
#define T3 "{firebrick}"

#define ERROR_MDL "models/error.mdl"
#define CAP_MDL "models/props_gameplay/cap_point_base.mdl"
#define HOLO_MDL "models/effects/cappoint_hologram.mdl"

#define CL 201
#define JMAX 201
#define MAX MAXPLAYERS+1

#define UPD_BASE "http://raw.github.com/n0cpra/TFJump"
#define UPD_BRANCH "master"
#define UPD_FILE "updatefile.txt"

#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#include <sdkhooks>
#include <tf2attributes>
#include <morecolors>
#include <updater>

enum {
		Health = 0,
		Ammo
}
enum {
		Primary = 0,
		Secondary,
		Melee
}
enum MSG {
		Msg_Saved = 0,
		Msg_Teleport,
		Msg_Adverts,
		Msg_CapPoint
}
enum {
		TEAM_NONE = 0,
		TEAM_SPEC,
		TEAM_RED,
		TEAM_BLUE	
}
enum SND {
		SND_FALL = 0,
		SND_FLESH,
		SND_REGEN,
		SND_PAIN,
		SND_JUMP,
		SND_AMMO
}
public Plugin myinfo = 
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESC,
	version = PLUGIN_VERSION,
	url = ""
};