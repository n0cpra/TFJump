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

#define TAG	 "[TFJump]"

#define ERROR_MDL "models/error.mdl"
#define CAP_MDL "models/props_gameplay/cap_point_base.mdl"
#define HOLO_MDL "models/effects/cappoint_hologram.mdl"

#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#include <sdkhooks>
#include <tf2attributes>
#include <morecolors>

public Plugin myinfo = 
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESC,
	version = PLUGIN_VERSION,
	url = ""
};