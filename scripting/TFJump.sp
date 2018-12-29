/*
		TODO List
		DoGoto, Send player, Bring player (admin menus), DoHelp, delcaps, dostats
		DB Stuff left:
		3. Delete locations in db.
		Combine speedrank into this.
		Check if spawn triggers on changing team to spec
		Do the same for explosions.
		/goto timer lock
		
		Re-do jumplist menu to use the data from the DB.
		SQL for jumplist order by x * 1
		
		Re-work capture point stuff. So broken ass maps with broken ass cp's will work as well as ones with working CP's.
		1. Change to finding team_control_point in PreGame, if none use  OnStartTouchBrokenCP event.
*/
#include <TFJump>
#pragma newdecls required;

ConVar
		cEnabled,						cWelcomeMsg,
		cAdvertTimer,					cPushAway,
		cCancel,						cBranch;
Handle 
		hsDisplayLeft, 					hsDisplayDown,
		hsDisplayRight,					hsDisplayDJ,
		hsDisplayForward,				hsDisplayM1M2,
		hAdverts;
bool
		bNoSteamId[MAX],				bRegen[MAX][3],
		bMapHasRegen = false,			bStatsDisabled = false,
		bCanAddCaps = false,			bLate = false,
		bGetClientKeys[MAX],			bMessages[MAX][MSG],
		bUsedReset[MAX],				bTouchedFake[MAX][CL],
		bIsPreviewing[MAX],				bHardcore[MAX],
		bSpeedRun[MAX],					bBeatMap[MAX],
		bSounds[MAX][SND],				bConnected = false,
		bTouched[MAX][CL],				bEvent = true;
float
		pOrigin[MAX][3],				pAngles[MAX][3],
		fOrigin[MAX][3],				fAngles[MAX][3],
		fLastSavePos[MAX][3],			fLastSaveAngles[MAX][3],
		fJumpList[JMAX][3],				afJumpList[JMAX][3],
		fVelocity[3] = { 0.0, ... };
int
		iControlPoints = 0,				iButtons[MAX],
		iForceTeam = 0,					pMaxClip[MAX][3],
		iClass = 0,						iDiff,
		iJumps = 0,						iAdvertCount,
		iControlList[CL],				iTouched[MAX];
char
		SteamId[MAX][32],				MapName[MAX_NAME_LENGTH],		
		JumpList[JMAX][128],			HostName[128],
		URL[256];
Database
		dTFJump = null;
Transaction
		dTrans = null;
TFTeam
		tfTeam[MAX];
char
		SoundHook[][] = {
							"regenerate",
							"ammo_pickup",
							"pain",
							"fall_damage",
							"grenade_jump",
							"fleshbreak"
						};
/******************************************************
					Plugin Stuff					  *
******************************************************/
public void OnPluginStart()
{
	char sBranch[32];
	RegPluginLibrary("TFJump");

	CreateConVar("tf2jump_version", PLUGIN_VERSION, "TF2 Jump version", FCVAR_SPONLY|FCVAR_NOTIFY);
	cEnabled = CreateConVar("tfjump_enable", "1", "Turns TF2 Jump on/off.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cWelcomeMsg = CreateConVar("tfjump_welcomemsg", "1", "Show clients the welcome message when they join?", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	//cSoundBlock = CreateConVar("tfjump_sounds", "1", "Block pain, regenerate, and ammo pickup sounds?", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cAdvertTimer = CreateConVar("tfjump_time", "3", "Sets the time for advertisement in minutes. (0 to disable.)", FCVAR_NOTIFY, true, 0.0, true, 5.0);
	Format(sBranch, sizeof sBranch, "Select a branch folder from %s to update from.", UPD_BASE);
	cBranch = CreateConVar("tfjump_branch", UPD_BRANCH, sBranch, FCVAR_NOTIFY);
	
	RegConsoleCmd("sm_save", cmdSave, "Saves your current location. (Same As: sm_s)");
	RegConsoleCmd("sm_s", cmdSave, "Saves your current position.");
	RegConsoleCmd("sm_tele", cmdTeleport, "Teleports you to your current saved location. (Same As: sm_t)");
	RegConsoleCmd("sm_t", cmdTeleport, "Teleports you to your current saved location.");
	RegConsoleCmd("sm_reset", cmdReset, "Sends you back to the beginning without deleting your save.");
	RegConsoleCmd("sm_restart", cmdRestart, "Deletes your save, and sends you back to the beginning (Same As: sm_r).");
	RegConsoleCmd("sm_r", cmdRestart, "Deletes your save, and sends you back to the beginning.");
	RegConsoleCmd("sm_settings", cmdSettings, "Changes your player settings.");
	RegConsoleCmd("sm_goto", cmdGoto, "Goto <target>");
	RegConsoleCmd("sm_regen", cmdDoRegen, "Changes regeneration settings.");
	RegConsoleCmd("sm_undo", cmdDoUndo, "Restores your last saved position.");
	RegConsoleCmd("sm_skeys", cmdDoSkeys, "Toggle showing a clients key's.");
	RegConsoleCmd("sm_stats", cmdCheckStats, "Checks useless stats.");
	RegConsoleCmd("sm_info", cmdInfo, "Displays map information if any.");
	RegConsoleCmd("sm_preview", cmdEnablePreview, "Allows you to preview a jump.");
	RegConsoleCmd("sm_help", cmdHelp, "Shows help for TF2 Jump");

	// Admin / Root menu
	RegAdminCmd("sm_tfjump", cmdAdminMenu, ADMFLAG_GENERIC, "Admin menu");

	HookEvent("player_team", eChangeTeam);
	HookEvent("player_changeclass", eChangeClass);
	HookEvent("player_spawn", eSpawn);
	HookEvent("player_death", eDeath, EventHookMode_Pre);
	HookEvent("teamplay_round_start", eRoundStart);
	HookEvent("post_inventory_application", eInventory);
	HookEvent("teamplay_flag_event", eIntelBlock, EventHookMode_Pre);
	HookEvent("controlpoint_starttouch", eControlPoint);

	AddTempEntHook("TFExplosion", TEBlock);
	AddTempEntHook("TFBlood", TEBlock);
	
	HookUserMessage(GetUserMessageId("VoiceSubtitle"), HookVoice, true);
	AddNormalSoundHook(view_as<NormalSHook>(sound_hook));
	
	hsDisplayForward = CreateHudSynchronizer();
	hsDisplayDown = CreateHudSynchronizer();
	hsDisplayLeft = CreateHudSynchronizer();
	hsDisplayRight = CreateHudSynchronizer();
	hsDisplayDJ = CreateHudSynchronizer();
	
	cCancel = FindConVar("mp_waitingforplayers_cancel");
	cPushAway = FindConVar("tf_avoidteammates_pushaway");
	
	AddCommandListener(DoJoinTeam, "jointeam");
	
	// Connect to our database.
	Database.Connect(OnDatabaseConnect, "TFJump");
	
	char uBranch[32];
	cBranch.GetString(uBranch, sizeof uBranch);
	if (!VerifyBranch(uBranch))
	{
		cBranch.SetString(UPD_BRANCH);
	}
	Format(URL, sizeof URL,"%s/%s/%s", UPD_BASE, uBranch, UPD_FILE);

	if (LibraryExists("updater"))
	{
		Updater_AddPlugin(URL);
	}
	else
	{
		LogMessage("Updater plugin not found.");
	}
}
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) 
{
	EngineVersion version = GetEngineVersion();
	if (version == Engine_TF2)
	{
		bLate = late;
	} else {
		SetFailState("This plugin can only be run on Team Fortress 2.");
		return APLRes_Failure;
	}
	return APLRes_Success;
}
public void OnConfigsExecuted()
{
	if (cEnabled.BoolValue)
	{
		GetConVarString(FindConVar("hostname"), HostName, sizeof HostName);
	}
}
public void OnPluginEnd()
{
	if (cEnabled.BoolValue)
	{
		CleanUp();
		for (int i = 1; i <= MaxClients; i++)
		{
			if (bIsPreviewing[i])
			{
				RestoreLocation(i);
			}
		}
	}
}
public void OnMapStart()
{	
	if (cEnabled.BoolValue)
	{
		dTrans = new Transaction();

		// Precache models
		if (!IsModelPrecached(ERROR_MDL)) PrecacheModel(ERROR_MDL);
		if (!IsModelPrecached(CAP_MDL)) PrecacheModel(CAP_MDL);
		if (!IsModelPrecached(HOLO_MDL)) PrecacheModel(HOLO_MDL);

		// Precache cap sounds
		PrecacheSound("misc/tf_nemesis.wav");
		PrecacheSound("misc/freeze_cam.wav");
		PrecacheSound("misc/null.wav");
		
		GetCurrentMap(MapName, sizeof MapName);

		PreGame(); Adverts(); CreateTimer(0.7, tMapStart);

		CreateTimer(60.0, tSteamId, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		int entity;
		while ((entity = FindEntityByClassname(entity, "team_control_point")) != -1)
		{
			bEvent = false;
		}
	}
}
public void OnMapEnd()
{
	if (cEnabled.BoolValue)
	{
		CleanUp();
		iClass = 0; iForceTeam = 0; iDiff = 0;
	}
}
public void OnClientPostAdminCheck(int client)
{
	if (cEnabled.BoolValue)
	{
		if (GetClientAuthId(client, AuthId_Steam2, SteamId[client], sizeof SteamId))
		{
			bNoSteamId[client] = false;
		} else {
			bNoSteamId[client] = true;
		}
	}
}
public void OnClientPutInServer(int client)
{
	if (cEnabled.BoolValue)
	{
		if (IsValidClient(client))
		{
			if (bConnected)
			{ 
				CreateTimer(0.7, tProfile, client);
			}

			if (cWelcomeMsg.BoolValue)
			{
				CreateTimer(10.0, tWelcome, client);
			}
			DoHooks(2, client);
			ResetPlayer(client);
		}
	}
}
public void OnClientDisconnect(int client)
{
	if (cEnabled.BoolValue)
	{
		ResetPlayer(client);
	}
}
public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "updater"))
	{
		Updater_AddPlugin(URL);
	}
}
public Action Updater_OnPluginChecking()
{
	CPrintToChatAll("%s Checking for updates...", TAG);
	return Plugin_Continue;
}
public int Updater_OnPluginUpdating()
{
	CPrintToChatAll("%s Downloading a new update.", TAG);
}
public int Updater_OnPluginUpdated()
{
	CPrintToChatAll("%s Finished updating. %sReloading%s TFJump.", TAG, T1, T2);
	ReloadPlugin(INVALID_HANDLE);
}
/******************************************************
					Chat Commands					  *
******************************************************/
Action cmdSave(int client, int args)
{
	if (cEnabled.BoolValue)
	{
		DoSave(client);
	}
	return Plugin_Handled;	
}
Action cmdTeleport(int client, int args)
{
	if (cEnabled.BoolValue)
	{
		DoTeleport(client);
	}
	return Plugin_Handled;	
}
Action cmdReset(int client, int args)
{
	if (cEnabled.BoolValue)
	{
		DoReset(client, 1);
	}
	return Plugin_Handled;	
}
Action cmdRestart(int client, int args)
{
	if (cEnabled.BoolValue)
	{
		DoReset(client, 2);
	}
	return Plugin_Handled;	
}
Action cmdDoUndo(int client, int args)
{
	if (cEnabled.BoolValue)
	{
		DoUndo(client);
	}
}
// Menu
Action cmdSettings(int client, int args)
{
	if (cEnabled.BoolValue)
	{
		DoSettings(client);
	}
	return Plugin_Handled;	
}
Action cmdGoto(int client, int args)
{
	if (cEnabled.BoolValue)
	{
		if (bIsPreviewing[client] || IsClientObserver(client))
		{
			CPrintToChat(client, "%s Command is %slocked%s.", TAG, T1, T2);
			return Plugin_Handled;
		}
		if (IsUserAdmin(client))
		{
			if (args < 1)
			{
				CReplyToCommand(client, "%s Command: %s!goto%s [name|partial]", TAG, T1, T2);
				return Plugin_Handled;
			}
			if (IsClientObserver(client))
			{
				CReplyToCommand(client, "%s Can't target players in %sspectate%s.", TAG, T1, T2);
				return Plugin_Handled;
			}

			char arg1[MAX_NAME_LENGTH], target_name[MAX_TARGET_LENGTH];
			GetCmdArg(1, arg1, sizeof(arg1));
			
			int target_list[MAXPLAYERS], target_count;
			bool tn_is_ml;

			float TeleportOrigin[3], PlayerOrigin[3], goAngle[3], PlayerOrigin2[3], goPosVec[3];
			if ((target_count = ProcessTargetString(arg1, client, target_list, MAXPLAYERS, COMMAND_FILTER_NO_IMMUNITY, target_name, sizeof(target_name), tn_is_ml)) <= 0)
			{
				CReplyToCommand(client, "%s No matching clients found.", TAG);
				return Plugin_Handled;
			}
			if (target_count > 1)
			{
				CReplyToCommand(client, "%s More than one client matched.", TAG);
				return Plugin_Handled;
			}
			for (int i = 0; i < target_count; i++)
			{
				if (IsClientObserver(target_list[i]) || !IsValidClient(target_list[i]))
				{
					CReplyToCommand(client, "%s Cannot go to %s%s%s.", TAG, T1, target_name, T2);
					return Plugin_Handled;
				}
				if (target_list[i] == client)
				{
					CReplyToCommand(client, "%s You can't go to %syourself%s!", TAG, T1, T2);
					return Plugin_Handled;
				}
				GetClientAbsOrigin(target_list[i], PlayerOrigin);
				GetClientAbsAngles(target_list[i], PlayerOrigin2);

				TeleportOrigin[0] = PlayerOrigin[0];
				TeleportOrigin[1] = PlayerOrigin[1];
				TeleportOrigin[2] = PlayerOrigin[2];

				goAngle[0] = PlayerOrigin2[0];
				goAngle[1] = PlayerOrigin2[1];
				goAngle[2] = PlayerOrigin2[2];

				goPosVec[0] = 0.0;
				goPosVec[1] = 0.0;
				goPosVec[2] = 0.0;

				TeleportEntity(client, TeleportOrigin, goAngle, goPosVec);
				CPrintToChat(client, "%s You have been teleported to %s%s%s.", TAG, T1, target_name, T2);
				CPrintToChat(target_list[i], "%s %s%N%s has teleported to your location", TAG, T1, client, T2);
			}
		} else {
			CReplyToCommand(client, "%s You %sdo not%s have access to this command.", TAG, T1, T2);
			return Plugin_Handled;
		}
	}
	return Plugin_Handled;	
}
// Menu
Action cmdDoRegen(int client, int args)
{
	if (cEnabled.BoolValue)
	{
		DoRegen(client);
	}
	return Plugin_Handled;	
}
Action cmdDoSkeys(int client, int args)
{
	if (cEnabled.BoolValue)
	{
		DoSkeys(client, 0);
	}
	return Plugin_Handled;	
}
Action cmdCheckStats(int client, int args)
{
	if (cEnabled.BoolValue)
	{
		//DoStats(client);
	}
	return Plugin_Handled;	
}
Action cmdInfo(int client, int args)
{
	if (cEnabled.BoolValue)
	{
		DoInfo(client);
	}
	return Plugin_Handled;	
}
Action cmdEnablePreview(int client, int args)
{
	if (cEnabled.BoolValue)
	{
		MoveType movetype = GetEntityMoveType(client);
		
		if (movetype != MOVETYPE_NOCLIP)
		{
			int flags = GetEntityFlags(client);
			if (!(flags & FL_ONGROUND))
			{
				CPrintToChat(client, "%s You can't preview while in the air.", TAG);
				return Plugin_Handled;
			}
			if ((flags & FL_DUCKING))
			{
				CPrintToChat(client, "%s You can't preview while ducking.", TAG);
				return Plugin_Handled;
			}
			if (!bIsPreviewing[client])
			{
				SaveLocation(client);
				bIsPreviewing[client] = true;
				CPrintToChat(client, "%s You step into the %sdarkness%s.", TAG, T1, T2);
			}
		} 
		else if (bIsPreviewing[client])
		{
			RestoreLocation(client);
			TeleportEntity(client, pOrigin[client], pAngles[client], NULL_VECTOR);
			bIsPreviewing[client] = false;
			CPrintToChat(client, "%s You emerge from the %sdarkness%s.", TAG, T1, T2);
		}
	}
	return Plugin_Handled;	
}
Action cmdHelp(int client, int args)
{
	if (cEnabled.BoolValue)
	{
		DoHelp(client);
	}
	return Plugin_Handled;	
}
// Admin: Map Settings, Send player, and teleport player to a jump.
// Root: Add/Delete capture points
Action cmdAdminMenu(int client, int args)
{
	if (cEnabled.BoolValue)
	{
		DoAdmin(client);
	}
	return Plugin_Handled;	
}
/******************************************************
					Functions						  *
******************************************************/
void DebugLog(char[] text, any ...)
{
	char path[PLATFORM_MAX_PATH], date[32], time[32];

	FormatTime(date, sizeof date, "%m-%d-%y", GetTime());
	FormatTime(time, sizeof time, "%I:%M:%S", GetTime());
	BuildPath(Path_SM, path, PLATFORM_MAX_PATH, "logs/TFJump-Log-%s.log", date);

	int len = strlen(text) + 255;
	char[] text2 = new char[len];
	VFormat(text2, len, text, 2);
	PrintToServer("%s %s", time, text2);

	if (!FileExists(path))
	{
		File log = OpenFile(path, "w");
		log.WriteLine("----- TFJump log [Time:%s] [Date:%s] -----" , time, date);
		log.WriteLine("Plugin Name: %s", PLUGIN_NAME);
		log.WriteLine("Plugin Version: %s", PLUGIN_VERSION);
		log.WriteLine("Plugin Author: %s", PLUGIN_AUTHOR);
		log.WriteLine("[%s] %s", time, text2);
		log.Close();
	} else {
		File log = OpenFile(path, "a");
		log.WriteLine("[%s] %s", time, text2);
		log.Close();
	}
}
void DoSettings(int client)
{
	char info[32];
	Panel SettingsMenu = new Panel();
	SettingsMenu.SetTitle("TF2 Jump Settings");
	SettingsMenu.DrawItem("[+] Regen");
	SettingsMenu.DrawItem("[+] Messages");
	SettingsMenu.DrawItem("[+] Sounds");
	Format(info, sizeof info, "Hardcore: %s", (bHardcore[client]?"On":"Off"));
	SettingsMenu.DrawItem(info);
	SettingsMenu.DrawItem("", ITEMDRAW_SPACER);
	SettingsMenu.DrawItem("", ITEMDRAW_SPACER);
	SettingsMenu.DrawItem("", ITEMDRAW_SPACER);
	SettingsMenu.DrawItem("", ITEMDRAW_SPACER);
	SettingsMenu.DrawItem("Help");
	SettingsMenu.DrawItem("Exit");
	SettingsMenu.Send(client, OnSettingsMenu, MENU_TIME_FOREVER);
	delete SettingsMenu;
}
void DoRegen(int client)
{
	Panel RegenMenu = new Panel();
	RegenMenu.SetTitle("Regen Settings");
	RegenMenu.DrawItem("", ITEMDRAW_RAWLINE);
	char info[15];
	Format(info, sizeof info, "Ammo: %s", (bRegen[client][Ammo]?"On":"Off"));
	RegenMenu.DrawItem(info, (bHardcore[client]?ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT));
	Format(info, sizeof info, "Health: %s", (bRegen[client][Health]?"On":"Off"));
	RegenMenu.DrawItem(info, (bHardcore[client]?ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT));
	RegenMenu.DrawItem("", ITEMDRAW_SPACER);
	RegenMenu.DrawItem("", ITEMDRAW_SPACER);
	RegenMenu.DrawItem("", ITEMDRAW_SPACER);
	RegenMenu.DrawItem("", ITEMDRAW_SPACER);
	RegenMenu.DrawItem("Help");
	RegenMenu.DrawItem("", ITEMDRAW_SPACER);
	RegenMenu.DrawItem("Go Back");
	RegenMenu.DrawItem("Exit");
	RegenMenu.Send(client, OnRegenMenu, MENU_TIME_FOREVER);
	delete RegenMenu;	
}
void DoAdmin(int client)
{
	if (IsUserRoot(client))
	{
		Panel RootMenu = new Panel();
		RootMenu.SetTitle("Root Admin Menu");
		RootMenu.DrawItem("Send Player", ITEMDRAW_DISABLED);
		RootMenu.DrawItem("Bring Player", ITEMDRAW_DISABLED);
		RootMenu.DrawItem("Teleport Player");
		RootMenu.DrawItem("Reload Plugin");
		RootMenu.DrawItem("Update Plugin");
		RootMenu.DrawItem("[+] Map Settings");
		RootMenu.DrawItem("", ITEMDRAW_SPACER);
		RootMenu.DrawItem("Help");
		RootMenu.DrawItem("", ITEMDRAW_SPACER);
		RootMenu.DrawItem("", ITEMDRAW_SPACER);
		RootMenu.DrawItem("Exit");
		RootMenu.Send(client, OnRootMenu, MENU_TIME_FOREVER);
		delete RootMenu;
	} else if (IsUserAdmin(client))
	{
		Panel AdminMenu = new Panel();
		AdminMenu.SetTitle("Admin Menu");
		AdminMenu.DrawItem("Send Player", ITEMDRAW_DISABLED);
		AdminMenu.DrawItem("Bring Player", ITEMDRAW_DISABLED);
		AdminMenu.DrawItem("Teleport Player");
		AdminMenu.DrawItem("[+] Map Settings");
		AdminMenu.DrawItem("", ITEMDRAW_SPACER);
		AdminMenu.DrawItem("", ITEMDRAW_SPACER);
		AdminMenu.DrawItem("Help");
		AdminMenu.DrawItem("", ITEMDRAW_SPACER);
		AdminMenu.DrawItem("", ITEMDRAW_SPACER);
		AdminMenu.DrawItem("Exit");
		AdminMenu.Send(client, OnAdminMenu, MENU_TIME_FOREVER);
		delete AdminMenu;
	}
}
void DoMessages(int client)
{
	Panel MessagesMenu = new Panel();
	MessagesMenu.SetTitle("Message Settings");
	MessagesMenu.DrawItem("", ITEMDRAW_RAWLINE);
	char info[64];
	Format(info, sizeof info, "Save: %s", (bMessages[client][Msg_Saved]?"On":"Off"));
	MessagesMenu.DrawItem(info);
	Format(info, sizeof info, "Teleport: %s", (bMessages[client][Msg_Teleport]?"On":"Off"));
	MessagesMenu.DrawItem(info);
	Format(info, sizeof info, "Advertisements: %s", (bMessages[client][Msg_Adverts]?"On":"Off"));
	MessagesMenu.DrawItem(info);
	Format(info, sizeof info, "Cap Message: %s", (bMessages[client][Msg_CapPoint]?"On":"Off"));
	MessagesMenu.DrawItem(info);
	MessagesMenu.DrawItem("", ITEMDRAW_SPACER);
	MessagesMenu.DrawItem("", ITEMDRAW_SPACER);
	MessagesMenu.DrawItem("Help");
	MessagesMenu.DrawItem("", ITEMDRAW_SPACER);
	MessagesMenu.DrawItem("Go Back");
	MessagesMenu.DrawItem("Exit");
	MessagesMenu.Send(client, OnMessagesMenu, MENU_TIME_FOREVER);
	delete MessagesMenu;	
}
void DoSounds(int client)
{
	Panel SoundsMenu = new Panel();
	SoundsMenu.SetTitle("Toggle Sounds");
	char info[20];
	Format(info, sizeof info, "Fall: %s", (bSounds[client][SND_FALL]?"Sound On":"Sound Off"));
	SoundsMenu.DrawItem(info);
	Format(info, sizeof info, "Pain: %s", (bSounds[client][SND_PAIN]?"Sound On":"Sound Off"));
	SoundsMenu.DrawItem(info);
	Format(info, sizeof info, "Flesh: %s", (bSounds[client][SND_FLESH]?"Sound On":"Sound Off"));
	SoundsMenu.DrawItem(info);
	Format(info, sizeof info, "Regen: %s", (bSounds[client][SND_REGEN]?"Sound On":"Sound Off"));
	SoundsMenu.DrawItem(info);
	Format(info, sizeof info, "Jump: %s", (bSounds[client][SND_JUMP]?"Sound On":"Sound Off"));
	SoundsMenu.DrawItem(info);
	SoundsMenu.DrawItem("", ITEMDRAW_SPACER);
	SoundsMenu.DrawItem("Help");
	SoundsMenu.DrawItem("", ITEMDRAW_SPACER);
	SoundsMenu.DrawItem("Go Back");
	SoundsMenu.DrawItem("Exit");
	SoundsMenu.Send(client, OnSoundsMenu, MENU_TIME_FOREVER);
	delete SoundsMenu;
}
void DoJumpList(int client)
{
	// Replace w/ SQL later on.
	Menu mJumpList = new Menu(OnJumpList);
	mJumpList.SetTitle("Select a jump");
	for (int i=0;i<=iJumps;i++)
	{
		mJumpList.AddItem(JumpList[i], JumpList[i]);
	}
	mJumpList.Display(client, MENU_TIME_FOREVER);
}
void DoMapSettings(int client)
{
	char info[32];
	Panel mSettings = new Panel();
	mSettings.SetTitle("Map Settings");
	Format(info, sizeof info, "Team: %s", GetInfo(1, iForceTeam));
	mSettings.DrawItem(info);
	Format(info, sizeof info, "Class: %s", GetInfo(2, iClass));
	mSettings.DrawItem(info);
	Format(info, sizeof info, "Tier: %s", GetInfo(3, iDiff));
	mSettings.DrawItem(info);
	mSettings.DrawItem("", ITEMDRAW_SPACER);
	mSettings.DrawItem("", ITEMDRAW_SPACER);
	mSettings.DrawItem("", ITEMDRAW_SPACER);
	mSettings.DrawItem("Help");
	mSettings.DrawItem("", ITEMDRAW_SPACER);
	mSettings.DrawItem("Go Back");
	mSettings.DrawItem("Exit");
	mSettings.Send(client, OnMapSettings, MENU_TIME_FOREVER);
	delete mSettings;
}
public int OnMapSettings(Menu menu, MenuAction action, int client, int setting)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			switch (setting)
			{
				case 1:
				{
					if (iForceTeam != TEAM_RED)
						iForceTeam = TEAM_RED;
					else
						iForceTeam = TEAM_BLUE;
					DoMapSettings(client);
				}
				case 2:
				{
					if (iClass == 0)
						iClass = 3;
					else if (iClass == 3)
						iClass = 4;
					else if (iClass == 4)
						iClass = 9;
					else
						iClass = 3;
					DoMapSettings(client);
				}
				case 3:
				{
					if (iDiff == 0)
						iDiff = 1;
					else if (iDiff == 1)
						iDiff = 2;
					else if (iDiff == 2)
						iDiff = 3;
					else if (iDiff == 3)
						iDiff = 4;
					else if (iDiff == 4)
						iDiff = 5;
					else if (iDiff == 5)
						iDiff = 6;
					else
						iDiff = 1;
					DoMapSettings(client);
				}
				case 7:
				{
					//DoHelp(client);
				}
				case 9:
				{
					DoAdmin(client);
				}
				case 10:
				{
					UpdateMap(client); CheckTeams();
				}
			}
		}
	}
}
public int OnJumpList(Menu menu, MenuAction action, int client, int setting)
{
	char info[32];
	if (action == MenuAction_Select)
	{
		menu.GetItem(setting, info, sizeof info);
		for (int i=0;i<=iJumps;i++)
		{
			if (strcmp(JumpList[i], info) == 0)
			{
				TeleportEntity(client, fJumpList[i], NULL_VECTOR, NULL_VECTOR);
			}
		}
	} else if (action == MenuAction_End) {
		delete menu;
	}
}
public int OnRootMenu(Menu menu, MenuAction action, int client, int setting)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			switch (setting)
			{
				case 1: // Send player
				{
				}
				case 2: // Bring player
				{
				}
				case 3: // Jump list
				{
					DoJumpList(client);
				}
				case 4: // Reload Plugin
				{
					ReloadPlugin(INVALID_HANDLE);
				}
				case 5:
				{
					Updater_ForceUpdate();
				}
				case 6:
				{
					DoMapSettings(client);
				}
			}
		}
	}
}
public int OnAdminMenu(Menu menu, MenuAction action, int client, int setting)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			switch (setting)
			{
				case 1: // Send player
				{
				}
				case 2: // Bring player
				{
				}
				case 3: // Jump list
				{
					DoJumpList(client);
				}
				case 4:
				{
					DoMapSettings(client);	
				}
			}
		}
	}
}
public int OnRegenMenu(Menu menu, MenuAction action, int client, int setting)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			switch (setting)
			{
				case 1:
				{
					if (bRegen[client][Ammo])
						bRegen[client][Ammo] = false;
					else
						bRegen[client][Ammo] = true;
					DoRegen(client);
				}
				case 2:
				{
					if (bRegen[client][Health])
						bRegen[client][Health] = false;
					else
						bRegen[client][Health] = true;
					DoRegen(client);
				}
				case 7:
				{
					//DoHelp(client);	
				}
				case 9:
				{
					DoSettings(client);	
				}
				case 10:
				{
					UpdateProfile(client, 0);
				}
			}
		}
	}
}
public int OnSettingsMenu(Menu menu, MenuAction action, int client, int setting)
{
	switch (setting)
	{
		case 1:
		{
			DoRegen(client);
		}
		case 2:
		{
			DoMessages(client);
		}
		case 3:
		{
			DoSounds(client);
		}
		case 4:
		{
			if (bHardcore[client])
				bHardcore[client] = false;
			else
				bHardcore[client] = true;
			DoSettings(client);
		}
		case 5:
		{
			DoMapSettings(client);
		}
		case 9:
		{
			//  DoHelp(client);
		}
	}
}
public int OnMessagesMenu(Menu menu, MenuAction action, int client, int setting)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			switch (setting)
			{
				case 1:
				{
					if (bMessages[client][Msg_Saved])
						bMessages[client][Msg_Saved] = false;
					else
						bMessages[client][Msg_Saved] = true;
					DoMessages(client);				
				}
				case 2:
				{
					if (bMessages[client][Msg_Teleport])
						bMessages[client][Msg_Teleport] = false;
					else
						bMessages[client][Msg_Teleport] = true;
					DoMessages(client);
				}
				case 7:
				{
					//DoHelp(client);	
				}
				case 9:
				{
					DoSettings(client);	
				}
				case 10:
				{
					UpdateProfile(client, 1);
				}
			}
		}
	}
}
public int OnSoundsMenu(Menu menu, MenuAction action, int client, int setting)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			switch (setting)
			{
				case 1:
				{
					if (bSounds[client][SND_FALL])
						bSounds[client][SND_FALL] = false;
					else
						bSounds[client][SND_FALL] = true;
					DoSounds(client);				
				}
				case 2:
				{
					if (bSounds[client][SND_PAIN])
						bSounds[client][SND_PAIN] = false;
					else
						bSounds[client][SND_PAIN] = true;
					DoSounds(client);
				}
				case 3:
				{
					if (bSounds[client][SND_FLESH])
						bSounds[client][SND_FLESH] = false;
					else
						bSounds[client][SND_FLESH] = true;
					DoSounds(client);
				}
				case 4:
				{
					if (bSounds[client][SND_REGEN])
						bSounds[client][SND_REGEN] = false;
					else
						bSounds[client][SND_REGEN] = true;
					DoSounds(client);
				}
				case 5:
				{
					if (bSounds[client][SND_JUMP])
						bSounds[client][SND_JUMP] = false;
					else
						bSounds[client][SND_JUMP] = true;
					DoSounds(client);
				}
				case 7:
				{
					//DoHelp(client);	
				}
				case 9:
				{
					DoSettings(client);	
				}
				case 10:
				{
					UpdateProfile(client, 2);
				}
			}
		}
	}
}
char GetInfo(int Mode, int Data)
{
	char buffer[24];
	switch (Mode)
	{
		case 1: // Team
		{
			if (Data == TEAM_NONE)
			{
				Format(buffer, sizeof buffer, "None");
				return buffer;
			} else if (Data == TEAM_SPEC) {
				Format(buffer, sizeof buffer, "Spec");
				return buffer;
			}  else if (Data == TEAM_RED) {
				Format(buffer, sizeof buffer, "Red");
				return buffer;
			}  else if (Data == TEAM_BLUE) {
				Format(buffer, sizeof buffer, "Blue");
				return buffer;
			} else {
				Format(buffer, sizeof buffer, "Unknown");
				return buffer;
			}
		}
		case 2: // Class
		{
			if (view_as<TFClassType>(Data) == TFClass_DemoMan)
			{
				Format(buffer, sizeof buffer, "Demoman");
				return buffer;
			} else if (view_as<TFClassType>(Data) == TFClass_Soldier) {
				Format(buffer, sizeof buffer, "Soldier");
				return buffer;
			} else if (view_as<TFClassType>(Data) == TFClass_Engineer) {
				Format(buffer, sizeof buffer, "Engineer");
				return buffer;
			} else {
				Format(buffer, sizeof buffer, "None");
				return buffer;
			}
		}
		case 3:
		{
			if (Data == 0)
			{
				Format(buffer, sizeof buffer, "Not set");
				return buffer;
			} else if (Data == 1) {
				Format(buffer, sizeof buffer, "I");
				return buffer;
			} else if (Data == 2) {
				Format(buffer, sizeof buffer, "II");
				return buffer;
			} else if (Data == 3) {
				Format(buffer, sizeof buffer, "III");
				return buffer;
			} else if (Data == 4) {
				Format(buffer, sizeof buffer, "IV");
				return buffer;
			} else if (Data == 5) {
				Format(buffer, sizeof buffer, "V");
				return buffer;
			} else if (Data == 6) {
				Format(buffer, sizeof buffer, "VI");
				return buffer;
			} else {
				Format(buffer, sizeof buffer, "Error Unknown");
				return buffer;
			}
		}
	}
	Format(buffer, sizeof buffer, "Invalid Paramaters");
	return buffer;
}
void DoHelp(int client)
{
	CPrintToChat(client, "%s Not yet impletmented.", TAG);
}
void DoSave(int client)
{
	if (cEnabled.BoolValue && !bIsPreviewing[client] && !bSpeedRun[client] && !bHardcore[client])
	{
		if (!IsPlayerAlive(client) || !IsClientInWorld(client))
			CPrintToChat(client, "%s You need to be alive to save.", TAG);
		else if (bHardcore[client])
			CPrintToChat(client, "%s You can't do this in a hardcore run.", TAG);
		else if (!(GetEntityFlags(client) & FL_ONGROUND))
			CPrintToChat(client, "%s You can't save in the air.", TAG);
		else if (GetEntProp(client, Prop_Send, "m_bDucked") == 1)
			CPrintToChat(client, "%s You can't save while ducked.", TAG);
		else
		{
			fLastSavePos[client][0] = fOrigin[client][0]; fLastSaveAngles[client][0] = fAngles[client][0];
			fLastSavePos[client][1] = fOrigin[client][1]; fLastSaveAngles[client][1] = fAngles[client][1];
			fLastSavePos[client][2] = fOrigin[client][2]; fLastSaveAngles[client][2] = fAngles[client][2];
	
			GetClientAbsOrigin(client, fOrigin[client]);
			GetClientAbsAngles(client, fAngles[client]);
			if (IsDatabaseConnected()) { SaveDB(client); }
			if (bMessages[client][Msg_Saved])
			{
				CPrintToChat(client, "%s %sSaved%s location.", TAG, T1, T2);
			}
		}
	}
}
void DoUndo(int client)
{
	if (!bHardcore[client])
	{
		if (fLastSavePos[client][0] == 0.0 || fOrigin[client][0] == 0.0)
			CPrintToChat(client, "%s You don't have a current save, or a last save.", TAG);
		else
		{
			fOrigin[client][0] = fLastSavePos[client][0]; fOrigin[client][1] = fLastSavePos[client][1]; fOrigin[client][2] = fLastSavePos[client][2];
			fAngles[client][0] = fLastSaveAngles[client][0]; fAngles[client][1] = fLastSaveAngles[client][1]; fAngles[client][2] = fLastSaveAngles[client][2];
			CPrintToChat(client, "%s Your save has been %sreverted%s.", TAG, T1, T2);
		}
	} else {
		CPrintToChat(client, "%s You can't do this in a hardcore run.", TAG);
	}
}
void DoReset(int client, int Type)
{
	switch (Type)
	{
		case 1:
		{
			bUsedReset[client] = true;
			TF2_RespawnPlayer(client);			
		}
		case 2:
		{
			DeleteSave(client);
			TF2_RespawnPlayer(client);
		}
	}
		
}
void DeleteSave(int client)
{
	if (IsValidClient(client))
	{
		for (int i=0;i<3;i++)
		{
			fOrigin[client][i] = 0.0;
			fAngles[client][i] = 0.0;
			fLastSavePos[client][i] = 0.0;
			fLastSaveAngles[client][i] = 0.0;
		}
		if (IsDatabaseConnected())
		{
			// Do db	
		}
	}
}
void DoTeleport(int client)
{
	if (cEnabled.BoolValue)
	{
		if (IsClientInWorld(client))
		{
			if (bHardcore[client])
			CPrintToChat(client, "%s You can't teleport while in a %shardcore%s run.", TAG, T1, T2);
			else if (!IsPlayerAlive(client))
				CPrintToChat(client, "%s You can't teleport while dead.", TAG);
			else if (fOrigin[client][0] == 0.0)
				CPrintToChat(client, "%s You don't have a save.", TAG);
			else
			{
				TeleportEntity(client, fOrigin[client], fAngles[client], fVelocity);
				if (bMessages[client][Msg_Teleport])
				{
					CPrintToChat(client, "%s %sTeleported%s to your save.", TAG, T1, T2);
				}
			}
		}
	}
}
void ResetPlayer(int client)
{
	if (IsValidClient(client))
	{
		bRegen[client][Ammo] = false;				bRegen[client][Health] = false;
		bHardcore[client] = false;					bIsPreviewing[client] = false;
		bSpeedRun[client] = false;					bMessages[client][Msg_Saved] = true;
		bMessages[client][Msg_Teleport] = true;		bGetClientKeys[client] = false;
		bUsedReset[client] = false;					iTouched[client] = 0,
		bSounds[client][SND_FALL] = false,			bSounds[client][SND_PAIN] = false,
		bSounds[client][SND_REGEN] = false,			bSounds[client][SND_FLESH] = false,
		bSounds[client][SND_JUMP] = false,			bSounds[client][SND_AMMO] = false;
		for (int i=0;i<32;i++)
		{
			bTouched[client][i] = false;
		}
	}
}
int GetClip(int client, int slot)
{
	if (IsValidClient(client))
	{
		int weapon = GetPlayerWeaponSlot(client, slot);
		if (IsValidEntity(weapon))
		{
			return GetEntProp(weapon, Prop_Data, "m_iClip1");
		}
	}
	return 0;
}
void SetClip(int iWeapon, int iAmmo)
{
	if (!IsValidEntity(iWeapon)) return;
	SetEntProp(iWeapon, Prop_Data, "m_iClip1", iAmmo);
}
void SaveLocation(int client)
{
	GetClientAbsOrigin(client, pOrigin[client]);
	GetClientAbsAngles(client, pAngles[client]);
	SetEntityMoveType(client, MOVETYPE_NOCLIP);
}

void RestoreLocation(int client)
{
	TeleportEntity(client, pOrigin[client], pAngles[client], NULL_VECTOR);
	SetEntityMoveType(client, MOVETYPE_WALK);
}
bool IsClientInWorld(int client)
{
	TFTeam team = TF2_GetClientTeam(client);
	if (team == TFTeam_Spectator || team == TFTeam_Unassigned) return false;
	return true;
}
void FindAndHookIntel()
{
	int intel = INVALID_ENT_REFERENCE;
	while ((intel = FindEntityByClassname(intel, "item_teamflag")) != INVALID_ENT_REFERENCE)
	{
		SDKHook(intel, SDKHook_StartTouch, OnIntelStartTouch);
		SDKHook(intel, SDKHook_EndTouch, OnIntelEndTouch);
		DebugLog("Hooking intel %i", intel);
	}
}
stock bool IsUsingJumper(int client)
{
	if (IsValidClient(client))
	{
		if (TF2_GetPlayerClass(client) == TFClass_Soldier)
		{
			int sol_weap = GetEntProp(GetPlayerWeaponSlot(client, 0), Prop_Send, "m_iItemDefinitionIndex");
			switch (sol_weap)
			{
				case 237:
					return true;
			}
			return false;
		}
	
		if (TF2_GetPlayerClass(client) == TFClass_DemoMan)
		{
			int dem_weap = GetEntProp(GetPlayerWeaponSlot(client, 1), Prop_Send, "m_iItemDefinitionIndex");
			switch (dem_weap)
			{
				case 265:
					return true;
			}
			return false;
		}
	}
	return false;
}
void CheckTeams()
{
	for (int i=1;i<=MaxClients;i++)
	{
		if (iForceTeam != TEAM_NONE)
		{
			if (IsValidClient(i) && TF2_GetClientTeam(i) != view_as<TFTeam>(iForceTeam))
			{
				ChangeClientTeam(i, iForceTeam);
			}
		}
	}
}
bool VerifyBranch(char[] branch)
{
	return (!strcmp(branch, "master") || !strcmp(branch, "dev"));
}
void DoHooks(int Type, any data = 0)
{
	switch (Type)
	{
		case 1:
		{
			// Map start
			FindAndHookIntel();
		}
		case 2:
		{
			// Connected
			int client = data;
			if (IsValidClient(client))
			{
				SDKHook(client, SDKHook_SetTransmit, OnSetTransmit);
				DebugLog("Hooking client %N", client);
			}
		}
		case 3:
		{
			// Disconnect
			int client = data;
			if (IsValidClient(client))
			{
				SDKUnhook(client, SDKHook_SetTransmit, OnSetTransmit);
				DebugLog("Un-Hooking client %N", client);
			}
		}
	}
}
bool IsDatabaseConnected()
{
	if (dTFJump == null)
		return false;
	else
		return true;
}
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	iButtons[client] = buttons;
	int iClientToShow, iObserverMode;
	for (int i=1;i<MaxClients;i++)
	{
		if (bGetClientKeys[i])
		{
			if (iButtons[i] & IN_SCORE) { return Plugin_Continue; }
			iObserverMode = GetEntPropEnt(i, Prop_Send, "m_iObserverMode");
			if (IsClientObserver(i)) { iClientToShow = GetEntPropEnt(i, Prop_Send, "m_hObserverTarget"); } else { iClientToShow = i; }
			if (!IsValidClient(i) || !IsValidClient(iClientToShow) || iObserverMode == 6) { return Plugin_Continue; }

			if (iButtons[iClientToShow] & IN_FORWARD)
			{
				SetHudTextParams(0.60, 0.40, 0.3, 255, 0, 0, 255, 0, 0.0, 0.0, 0.0);
				ShowSyncHudText(i, hsDisplayForward, "↑");
			} else {
				SetHudTextParams(0.60, 0.40, 0.3, 255, 255, 255, 255, 0, 0.0, 0.0, 0.0);
				ShowSyncHudText(i, hsDisplayForward, "↑");
			}
			if (iButtons[client] & IN_BACK)
			{
				SetHudTextParams(0.60, 0.43, 0.3, 255, 0, 0, 255, 0, 0.0, 0.0, 0.0);
				ShowSyncHudText(i, hsDisplayDown, "↓");
			} else {
				SetHudTextParams(0.60, 0.43, 0.3, 255, 255, 255, 255, 0, 0.0, 0.0, 0.0);
				ShowSyncHudText(i, hsDisplayDown, "↓");		
			}
			if (iButtons[client] & IN_MOVELEFT)
			{
				SetHudTextParams(0.58, 0.42, 0.3, 255, 0, 0, 255, 0, 0.0, 0.0, 0.0);
				ShowSyncHudText(i, hsDisplayLeft, "←");
			} else {
				SetHudTextParams(0.58, 0.42, 0.3, 255, 255, 255, 255, 0, 0.0, 0.0, 0.0);
				ShowSyncHudText(i, hsDisplayLeft, "←");		
			}
			if (iButtons[client] & IN_MOVERIGHT)
			{
				SetHudTextParams(0.62, 0.42, 0.3, 255, 0, 0, 255, 0, 0.0, 0.0, 0.0);
				ShowSyncHudText(i, hsDisplayRight, "→");
			} else {
				SetHudTextParams(0.62, 0.42, 0.3, 255, 255, 255, 255, 0, 0.0, 0.0, 0.0);
				ShowSyncHudText(i, hsDisplayRight, "→");		
			}
			bool Duck = view_as<bool>(iButtons[client] & IN_DUCK), Jump = view_as<bool>(iButtons[client] & IN_JUMP);
			SetHudTextParams(0.57, 0.46, 0.3, 255, 0, 0, 255, 0, 0.0, 0.0, 0.0);
			ShowSyncHudText(i, hsDisplayDJ, "%s %s", (Duck?"Duck":""), (Jump?"Jump":""));
			
			bool M1 = view_as<bool>(iButtons[client] & IN_ATTACK), M2 = view_as<bool>(iButtons[client] & IN_ATTACK2);
			SetHudTextParams(0.47, 0.56, 0.3, 255, 0, 0, 255, 0, 0.0, 0.0, 0.0);
			ShowSyncHudText(i, hsDisplayM1M2, "%s %s", (M1?"M1":""), (M2?"M2":""));
		}
	}

	Regen(client);

	if (bIsPreviewing[client] && buttons & IN_ATTACK && GetEntityMoveType(client) == MOVETYPE_NOCLIP)
	{
		buttons &= ~IN_ATTACK;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}
void Regen(int client)
{
	if (IsValidClient(client) && IsClientInWorld(client))
	{
		if (bRegen[client][Health] && !bHardcore[client])
		{
			if (TF2_GetPlayerClass(client) == TFClass_Soldier)
			{
				SetEntityHealth(client, 750);
			} else {
				int iMaxHealth = (GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, client));
				SetEntityHealth(client, iMaxHealth);
			}
		} 
		if (bRegen[client][Ammo] && !bHardcore[client])
		{
			
			int iWeaponP = GetPlayerWeaponSlot(client, 0);
			int iWeaponS = GetPlayerWeaponSlot(client, 1);
			int iWeaponM = GetPlayerWeaponSlot(client, 2);
			
			if (!IsValidWeapon(iWeaponP) || !IsValidWeapon(iWeaponS) || !IsValidWeapon(iWeaponM))
			{
				// Spams error log on certain occasions
				//DebugLog("Got Invalid weapon for (%i/%i/%i) %N", iWeaponP, iWeaponS, iWeaponM, client);
				return;
			}
			// Bulk weapon reloading..
			if (GetClip(client, iWeaponP != pMaxClip[client][Primary]))
			{
				SetClip(iWeaponP, pMaxClip[client][Primary]);
			} 
			if (GetClip(client, iWeaponS != pMaxClip[client][Secondary]))
			{
				SetClip(iWeaponS, pMaxClip[client][Secondary]);
			}
			GivePlayerAmmo(client, 200, 1, false);
			GivePlayerAmmo(client, 200, 2, false);
			// Primary weapons
			switch(GetEntProp(iWeaponP, Prop_Send, "m_iItemDefinitionIndex"))
			{
				// Cow mangler support
				case 441:
				{
					SetEntPropFloat(iWeaponP, Prop_Send, "m_flEnergy", 100.0);
				}
				// Beggars
				case 730:
				{
				}
			}
			// Melee weapons
			switch(GetEntProp(iWeaponM, Prop_Send, "m_iItemDefinitionIndex"))
			{
				default:{}
			}
		}
	}
}
void DoSkeys(int client, int Type)
{
	switch (Type)
	{
		case 0: // Show
		{
			if (bGetClientKeys[client])
			{
				bGetClientKeys[client] = false;
				CPrintToChat(client, "%s", TAG);
			} else {
				bGetClientKeys[client] = true;
				CPrintToChat(client, "%s", TAG);
			}
		}
		case 1: // Position
		{
			// else if (bGetClientKeys[i] && iButtons[i] & IN_JUMP)
		// {
				// float x = view_as<float>(mouse[0]);
				// float y = view_as<float>(mouse[1]);
				// SetEntityFlags(i, GetEntityFlags(i)|FL_ATCONTROLS|FL_FROZEN);
				// SetHudTextParams(x, y, 0.3, g_iSkeysRed[i], g_iSkeysGreen[i], g_iSkeysBlue[i], 255, 0, 0.0, 0.0, 0.0);
				// ShowSyncHudText(i, HudDisplayForward, "W");
				// SetHudTextParams(x+4, y+5, 0.3, g_iSkeysRed[i], g_iSkeysGreen[i], g_iSkeysBlue[i], 255, 0, 0.0, 0.0, 0.0);
				// ShowSyncHudText(i, HudDisplayDuck, "Duck");
				// SetHudTextParams(x+4, y, 0.3, g_iSkeysRed[i], g_iSkeysGreen[i], g_iSkeysBlue[i], 255, 0, 0.0, 0.0, 0.0);
				// ShowSyncHudText(i, HudDisplayJump, "Jump");
				
				// char g_sButtons[64]; Format(g_sButtons, sizeof(g_sButtons), " A S D");
				// SetHudTextParams(x-2, y+5, 0.3, g_iSkeysRed[i], g_iSkeysGreen[i], g_iSkeysBlue[i], 255, 0, 0.0, 0.0, 0.0);
				// ShowSyncHudText(i, HudDisplayASD, g_sButtons);
		// }
		}
	}
}
bool IsValidWeapon(int iEntity)
{
	char strClassname[128];
	if (IsValidEntity(iEntity) && GetEntityClassname(iEntity, strClassname, sizeof(strClassname)) && StrContains(strClassname, "tf_weapon", false) != -1)  return true;
	return false;
}
void PreGame()
{
	GameRules_SetProp("m_nGameType", 2);
	
	if (iControlPoints == 0) { bCanAddCaps = true; bStatsDisabled = true; } else { bStatsDisabled = false; }

	int lastEnt = GetMaxEntities(), count = 0;
	for (int ent=MaxClients+1;ent<=lastEnt;ent++)
	{
		if (!IsValidEntity(ent))
			continue;
			
		char classname[64];
		GetEntityClassname(ent, classname, sizeof classname); 
		if (strcmp(classname, "func_regenerate") == 0)
		{
			bMapHasRegen = true;
			Override(ent);
			count++;
		}
		if (strcmp(classname, "logic_timer") == 0)
		{
			DebugLog("Killed 'logic_timer': %s on map: %s", classname, MapName);
			AcceptEntityInput(ent, "Kill");
			count++;
		}
		if (bEvent)
		{
			if (strcmp(classname, "trigger_capture_area") == 0)
			{
				SDKHook(ent, SDKHook_StartTouch, OnStartTouchBrokenCP);
				iControlList[count] = ent;
				count++;
			}
		}
	}
	DebugLog("Scanned %i entities, and altered %i entities.", lastEnt, count);
	DoHooks(1, _);
}
void AutoList()
{
	DebugLog("Building Jump List");
	int entity, count = 0;
	entity = INVALID_ENT_REFERENCE, count = 0;
	while ((entity = FindEntityByClassname(entity, "info_teleport_destination")) != -1)
	{
		AddToJumpList(entity);
		count++;
	}
	DebugLog("Done with Jump List (%i jumps)", count);
	AutoList_Upload();
}
void AutoList_Upload()
{
	if (iJumps > 0)
	{
		dTFJump.Execute(dTrans);
		DebugLog("Executing bulk SQL insert for AutoList()");
	}
}
void Override(int ent)
{
	SDKHook(ent, SDKHook_StartTouch, OnPlayerTouchRegen);
	SDKHook(ent, SDKHook_Touch, OnPlayerTouchRegen);
	SDKHook(ent, SDKHook_EndTouch, OnPlayerTouchRegen);
}
void AddToJumpList(int entity)
{
	GetEntPropString(entity, Prop_Data, "m_iName", JumpList[iJumps], sizeof JumpList);
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", fJumpList[iJumps]);
	GetEntPropVector(entity, Prop_Data, "m_angAbsRotation", afJumpList[iJumps]);
	char query[1024];
	Format(query, sizeof query, "INSERT INTO `Teleports` VALUES(null, '%s', '%s', '%f', '%f', '%f', '%f', '%f', '%f');", 
					MapName, JumpList[iJumps], fJumpList[iJumps][0], fJumpList[iJumps][1], fJumpList[iJumps][2], afJumpList[iJumps][0],
					afJumpList[iJumps][1], afJumpList[iJumps][2]);
	dTrans.AddQuery(query);
	iJumps++;
/*
	DebugLog("Added %s to jump list #%i", JumpList[iJumps], iJumps);
	DebugLog("Origin: %f %f %f", fJumpList[iJumps][0], fJumpList[iJumps][1], fJumpList[iJumps][2]);
*/
}
void DoLock()
{
	int i = -1;
	while ((i = FindEntityByClassname(i, "trigger_capture_area")) != -1)
	{
		SetVariantString("2 0");
		AcceptEntityInput(i, "SetTeamCanCap");
		SetVariantString("3 0");
		AcceptEntityInput(i, "SetTeamCanCap");
		iControlPoints++;
	}
	DebugLog("Locked %i control points.", iControlPoints);
}
void CleanUp()
{
	for (int i=1;i<=MaxClients;i++)
	{
		DoHooks(3, i);
	}
}
stock void AddCapPoint(int client, char[] name)
{
	if (cEnabled.BoolValue)
	{
		if (!bCanAddCaps) { CPrintToChat(client, "%s %sUnable%s to add capture point.", TAG, T1, T2); return; }
		if (iCapturePoints >= CL) { CPrintToChat(client, "%s Can't add anymore capture points to the map. %sLimit reached%s.", TAG, T1, T2); return; }

		int cap = CreateEntityByName("prop_dynamic"), cap2 = CreateEntityByName("team_control_point"), cap3 = CreateEntityByName("trigger_capture_area");
		char name[MAX_NAME_LENGTH], pIndex[256], cap_name[256], cap_name2[256];

		if (IsValidEntity(cap) && IsValidEntity(cap2) && IsValidEntity(cap3))
		{
			float origin[3];
			GetClientAbsOrigin(client, origin);

			// Model base
			SetEntityModel(cap, CAP_MDL);
			Format(pIndex, sizeof(pIndex), "prop_cap_1");
			DispatchKeyValue(cap, "targetname", pIndex);
			SetEntProp(cap, Prop_Data, "m_CollisionGroup", 0);
			SetEntProp(cap, Prop_Data, "m_usSolidFlags", 28);
			SetEntProp(cap, Prop_Data, "m_nSolidType", 6);
			DispatchSpawn(cap);
		
			TeleportEntity(cap, origin, NULL_VECTOR, NULL_VECTOR);
			
			if (iCapturePoints == 0) { pIndex = "TFJ_Capture_Point0"; cap_name2 = "TFJ_Capture_Point0"; } else { Format(pIndex, sizeof(pIndex), "TFJ_Capture_Point%i",
								iCapturePoints); Format(cap_name2, sizeof(cap_name2), "TFJ_Capture_Point%i", iCapturePoints); }

			DispatchKeyValue(cap2, "point_printname", name);
			cap_name = name;
			DispatchKeyValue(cap2, "point_default_owner", "0");
			DispatchKeyValue(cap2, "targetname", pIndex);
			DispatchKeyValue(cap2, "point_start_locked", "0");
			Format(pIndex, sizeof(pIndex), "%i", iCapturePoints);
			DispatchKeyValue(cap2, "point_index", pIndex);
			DispatchKeyValue(cap2, "StartDisabled", "0");
			DispatchKeyValue(cap2, "team_icon_0", "sprites/obj_icons/icon_obj_neutral");
			DispatchKeyValue(cap2, "team_icon_2", "sprites/obj_icons/icon_obj_red");
			DispatchKeyValue(cap2, "team_icon_3", "sprites/obj_icons/icon_obj_blu");
			DispatchKeyValue(cap2, "team_model_0", HOLO_MDL);
			DispatchKeyValue(cap2, "team_model_2", HOLO_MDL);
			DispatchKeyValue(cap2, "team_model_3", HOLO_MDL);

			DispatchSpawn(cap2);
			ActivateEntity(cap2);

			TeleportEntity(cap2, origin, NULL_VECTOR, NULL_VECTOR);

			DispatchKeyValue(cap3, "spawnflags", "1");
			DispatchKeyValue(cap3, "wait", "0");
			DispatchKeyValue(cap3, "team_startcap_3", "0");
			DispatchKeyValue(cap3, "team_startcap_2", "0");
			DispatchKeyValue(cap3, "team_spawn_3", "0");
			DispatchKeyValue(cap3, "team_spawn_2", "0");
			DispatchKeyValue(cap3, "team_numcap_3", "1");
			DispatchKeyValue(cap3, "team_numcap_2", "1");
			DispatchKeyValue(cap3, "team_cancap_3", "1");
			DispatchKeyValue(cap3, "team_cancap_2", "1");
			DispatchKeyValue(cap3, "StartDisabled", "0");
			DispatchKeyValue(cap3, "area_time_to_cap", "5");
			Format(pIndex, sizeof(pIndex), "TFJ_Capture_Point%i", iCapturePoints);
			DispatchKeyValue(cap3, "targetname", pIndex);
			DispatchKeyValue(cap3, "area_cap_point", pIndex);

			DispatchSpawn(cap3);
			ActivateEntity(cap3);
			
			TeleportEntity(cap3, origin, NULL_VECTOR, NULL_VECTOR);
			
			SetEntityModel(cap3, ERROR_MDL);
			SetEntProp(cap3, Prop_Send, "m_nSolidType", 2);

			// set mins and maxs for entity
			float vecMins[3], vecMaxs[3], vDimensions[3] = {256.0, 256.0, 200.0};
			vecMins[0] = -(vDimensions[0] / 2);
			vecMins[1] = -(vDimensions[1] / 2);
			vecMins[2] = -(vDimensions[2] / 2);
			vecMaxs[0] =  (vDimensions[0] / 2);
			vecMaxs[1] =  (vDimensions[1] / 2);
			vecMaxs[2] =  (vDimensions[2] / 2);
			SetEntPropVector(cap3, Prop_Send, "m_vecMins", vecMins);
			SetEntPropVector(cap3, Prop_Send, "m_vecMaxs", vecMaxs);
			
			int enteffects = GetEntProp(cap3, Prop_Send, "m_fEffects"); 
			enteffects |= 32; 
			SetEntProp(cap3, Prop_Send, "m_fEffects", enteffects);  

			SDKHook(cap3, SDKHook_StartTouch, OnStartTouch);
			iCapturePoints++;

			//SaveCapPoint(client, cap_name, cap_name2, origin, MapName);

		}
	}
}
stock void DelCaps(int client)
{

}
stock void DoInfo(int client)
{
	CPrintToChat(client, "%s This map is designed for %s%s%s, and has a difficulty rating of %s%s%s.", TAG, T1, GetInfo(2, iClass), T2, T1, GetInfo(3, iDiff), T2);
}
stock void DoStats(int client)
{
	if (!bStatsDisabled)
	{
		
	}
}
void Adverts()
{
	hAdverts = CreateArray(32);
	char buffer[128];
	Format(buffer, sizeof buffer, "Remember you can %s!s %s, and %s!t%s.", T1, T2, T1, T2); PushArrayString(hAdverts, buffer);
	Format(buffer, sizeof buffer, "Stuck on a jump? You can %s!preview%s and look at it.", T1, T2); PushArrayString(hAdverts, buffer);
	Format(buffer, sizeof buffer, "Map information: %s!info%s.", T1, T2); PushArrayString(hAdverts, buffer);
	Format(buffer, sizeof buffer, "Curious how well you're doing? Type %s!stats%s to see.", T1, T2); PushArrayString(hAdverts, buffer);
	Format(buffer, sizeof buffer, "Useful commands: %s!settings%s, %s!regen%s, %s!reset%s, and %s!restart%s.", T1, T2, T1, T2, T1, T2, T1, T2); PushArrayString(hAdverts, buffer);
	Format(buffer, sizeof buffer, "Accidently save? %s!undo%s it.", T1, T2); PushArrayString(hAdverts, buffer);
	Format(buffer, sizeof buffer, "Beat the map? You can %s!goto%s any player and help them!", T1, T2); PushArrayString(hAdverts, buffer);

	float fAdvert = (view_as<float>(float(cAdvertTimer.IntValue)) * 60);
	if (cAdvertTimer.IntValue > 0)
	{
		iAdvertCount = 0;
		CreateTimer(fAdvert, tAdverts, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}
bool IsUserRoot(int client) { return GetUserAdmin(client).HasFlag(Admin_Root); }
bool IsUserAdmin(int client) { return GetUserAdmin(client).HasFlag(Admin_Generic); }
bool IsValidClient(int client) { return (1 <= client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));  }
/******************************************************
					ConVars							  *
******************************************************/

/******************************************************
					Timers							  *
******************************************************/
Action tWelcome(Handle timer, any client)
{
	if (IsValidClient(client))
	{
		CPrintToChat(client, "%s Welcome to %s%s%s. Please, follow the %s!rules%s.", TAG, T1, HostName, T2, T1, T2);
	}
}
Action tProfile(Handle timer, any client)
{
	if (IsValidClient(client))
	{
		Profile(client);
	}
}
Action tAdverts(Handle timer, any client)
{
	char buffer[128]; GetArrayString(hAdverts, iAdvertCount, buffer, sizeof buffer);

	CPrintToChatAll("%s %s", TAG, buffer);
	if (iAdvertCount >= GetArraySize(hAdverts)-1) { iAdvertCount = 0; } else { iAdvertCount++; }
	return Plugin_Handled;
}
Action tRespawn(Handle timer, any client)
{
	if (IsValidClient(client) && IsClientInWorld(client))
	{
		if (TF2_GetClientTeam(client) != TFTeam_Spectator)
		{
			TF2_RespawnPlayer(client);
			if (!bUsedReset[client])
			{
				if (fOrigin[client][0] != 0.0)
					TeleportEntity(client, fOrigin[client], fAngles[client], fVelocity);
			} else {
				bUsedReset[client] = false;	
			}
		}
	}
}
Action tSteamId(Handle timer, any client)
{
	for (int i=1;i<=MaxClients;i++)
	{
		if (bNoSteamId[i])
		{
			if (IsValidClient(i))
			{
				DebugLog("%N doesn't have a Steam Id. Attempting to get.", i);
				if (GetClientAuthId(i, AuthId_Steam2, SteamId[i], sizeof SteamId))
				{
					bNoSteamId[i] = false;
					CPrintToChat(i, "%s Features have been %sre-enabled%s for you.", TAG, T1, T2);
					DebugLog("Got Steam Id for %N", i);
				} else {
					bNoSteamId[i] = true;
					DebugLog("Failed to get %N's Steam Id", i);
				}
			}
		}
	}
}
Action tMapStart(Handle timer, any client)
{
	if (bConnected)
		CheckMapSettings();
}
/******************************************************
					Events							  *
******************************************************/
Action DoJoinTeam(int client, const char[] cmd, int args)
{
	if (cEnabled.BoolValue)
	{
		char arg1[32]; GetCmdArg(1, arg1, sizeof arg1);
		if (strcmp(arg1, "spectate") == 0)
		{
			return Plugin_Continue;
		} else if (strcmp(arg1, "red") == 0 && iForceTeam == TEAM_BLUE) {
			if (iClass != 0 && TF2_GetClientTeam(client) == TFTeam_Spectator)
			{
				LoadDB(client);
				ChangeClientTeam(client, TEAM_BLUE);
				TF2_SetPlayerClass(client, view_as<TFClassType>(iClass), true, true);
			} else {
				ChangeClientTeam(client, TEAM_BLUE);
			}
			return Plugin_Stop;
		} else if (strcmp(arg1, "blue") == 0 && iForceTeam == TEAM_RED) {
			if (iClass != 0 && TF2_GetClientTeam(client) == TFTeam_Spectator)
			{
				LoadDB(client);
				ChangeClientTeam(client, TEAM_RED);
				TF2_SetPlayerClass(client, view_as<TFClassType>(iClass), true, true);	
			} else {
				ChangeClientTeam(client, TEAM_RED);
			}
			return Plugin_Stop;
		} else {
			return Plugin_Continue;
		}
	}
	return Plugin_Continue;
}
bool BlockSound(int client, char[] Sample)
{
	if (strcmp(Sample, "regenerate") == 0 && !bSounds[client][SND_REGEN])
		return true;
	else if (strcmp(Sample, "ammo_pickup") == 0 && !bSounds[client][SND_AMMO])
		return true;
	else if (strcmp(Sample, "pain") == 0 && !bSounds[client][SND_PAIN])
		return true;
	else if (strcmp(Sample, "fall_damage") == 0 && !bSounds[client][SND_FALL])
		return true;
	else if (strcmp(Sample, "grenade_jump") == 0 && !bSounds[client][SND_JUMP])
		return true;
	else if (strcmp(Sample, "fleshbreak") == 0 && !bSounds[client][SND_FLESH])
		return true;
	else
		return false;
}
public Action sound_hook(int clients[64], int& numClients, char[] sample, int& entity, int& channel, float& volume, int& level, int& pitch, int& flags)
{
	if (cEnabled.BoolValue )
	{
		for (int j=0;j<=numClients;j++)
		{
			for (int i=0;i<=sizeof(SoundHook)-1;i++)
			{
				if (StrContains(sample, SoundHook[i], false) != -1 && BlockSound(clients[j], SoundHook[i]))
				{
					//PrintToServer("STOPPING SOUND: %s - %i", sample, entity);
					return Plugin_Stop;
				}
			}
			//PrintToServer("ALLOWING SOUND: Sample:%s - Entity:%i", sample, entity);
			return Plugin_Continue;
		}
	}
	return Plugin_Continue;
}
public Action HookVoice(UserMsg msg_id, Handle bf, const char[] players, int playersNum, bool reliable, bool init)
{
	if (cEnabled.BoolValue)
	{
		int client = BfReadByte(bf), vMenu1 = BfReadByte(bf), vMenu2 = BfReadByte(bf);
		
		if (IsPlayerAlive(client) && IsValidClient(client))
		{
			if ((vMenu1 == 0) && (vMenu2 == 0))
			{
				Regen(client);
			}
		}
	}
	return Plugin_Continue;
}
public Action TEBlock(const char[] te_name, const int[] Players, int numClients, float delay)
{
	if (strcmp(te_name, "TFExplosion", false) == 0 || strcmp(te_name, "TFBlood", false) == 0)
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}
Action eControlPoint(Event event, const char[] name, bool dontBroadcast)
{
	int client = event.GetInt("player"), area = event.GetInt("area"), entity;
	if (cEnabled.BoolValue && IsValidClient(client))
	{
		char cpName[32];

		if (!bTouched[client][area])
		{
			while ((entity = FindEntityByClassname(entity, "team_control_point")) != -1)
			{
				int pIndex = GetEntProp(entity, Prop_Data, "m_iPointIndex");
				if (pIndex == area)
				{				
					GetEntPropString(entity, Prop_Data, "m_iszPrintName", cpName, sizeof(cpName));

					if (bHardcore[client])
					{
						// "Hardcore" mode
						CPrintToChatAll("%s %s%N%s has reached %s%s%s [%sHardcore%s]", TAG, T1, client, T2, T1, cpName, T2, T3, T2);
						EmitSoundToAll("misc/tf_nemesis.wav");
					} else {
						// Normal mode
						CPrintToChatAll("%s %s%N%s has reached %s%s%s ", TAG, T1, client, T2, T1, cpName, T2);
						EmitSoundToAll("misc/freeze_cam.wav");
					}
				}
			}
		}
		bTouched[client][area] = true;
		iTouched[client]++;
	}
}
void OnStartTouchBrokenCP(int entity, int other)
{
	if (cEnabled.BoolValue && IsValidClient(other) && !bIsPreviewing[other] && bEvent)
	{
		int client = other;
		char playerName[64], cpName[32];

		for (int i=0;i<CL;i++)
		{
			if (iControlList[i] == entity && !bTouchedFake[client][i])
			{
				bTouchedFake[client][i] = true;
	
				GetClientName(client, playerName, 64);

				GetEntPropString(entity, Prop_Data, "m_iszCapPointName", cpName, sizeof cpName);
				if (bHardcore[client])
				{
					CPrintToChatAll("%s %s%s%s has reached %s%s %s[%sHardcore%s] ", TAG, T1, playerName, T2, T1, cpName, T2, T3, T2);
					EmitSoundToAll("misc/tf_nemesis.wav");
				} else {
					CPrintToChatAll("%s %s%s%s has reached %s%s%s.", TAG, T1, playerName, T2, T1, cpName, T2);
					EmitSoundToAll("misc/freeze_cam.wav");
				}
			}
		}
	}
}
Action eIntelBlock(Event event, const char[] name, bool dontBroadcast)
{
	if (cEnabled.BoolValue)
	{
		event.BroadcastDisabled = true;
	}
}
Action eDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (cEnabled.BoolValue)
	{
		int client = GetClientOfUserId(event.GetInt("userid"));
		event.BroadcastDisabled = true;
		if (bIsPreviewing[client])
			bIsPreviewing[client] = false;
		CreateTimer(0.1, tRespawn, client);
	}
}
Action eInventory(Event event, const char[] name, bool dontBroadcast)
{
	if (cEnabled.BoolValue)
	{
		int client = GetClientOfUserId(event.GetInt("userid"));
		if (IsValidClient(client))
		{
			pMaxClip[client][Primary] = GetClip(client, 0);
			pMaxClip[client][Secondary] = GetClip(client, 1);
		}
	}
}
Action eRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (cEnabled.BoolValue)
	{
		DoLock();
		int entity = -1;
		while ((entity = FindEntityByClassname(entity, "logic_timer")) != INVALID_ENT_REFERENCE)
		{
			AcceptEntityInput(entity, "Kill");
		}
		CheckAutoList();
		cPushAway.SetInt(0);
		cCancel.SetInt(1);
	}
}
Action eChangeTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (cEnabled.BoolValue)
	{
		int client = GetClientOfUserId(event.GetInt("userid"));
		tfTeam[client] = TF2_GetClientTeam(client);
	}
}
Action eChangeClass(Event event, const char[] name, bool dontBroadcast)
{
	if (cEnabled.BoolValue)
	{
		int client = GetClientOfUserId(event.GetInt("userid"));
		if (IsValidClient(client))
		{
			DeleteSave(client);
			TF2_RespawnPlayer(client);
		}
	}
}
public Action OnPlayerTouchRegen(int entity, int other)
{
	if (IsValidClient(other) && TF2_GetPlayerClass(other) == TFClass_Soldier && !bHardcore[other])
	{
		return Plugin_Stop;
	}
	return Plugin_Continue;
}
Action OnIntelStartTouch(int entity, int other)
{
	if (IsValidEntity(entity) && bIsPreviewing[other])
	{
		AcceptEntityInput(entity, "Disable");
		return Plugin_Continue;
	}
	return Plugin_Continue;
}
Action OnIntelEndTouch(int entity, int other)
{
	if (IsValidEntity(entity) && bIsPreviewing[other])
	{
		AcceptEntityInput(entity, "Enable");
		return Plugin_Continue;
	}
	return Plugin_Continue;
}
public Action OnSetTransmit(int entity, int client)
{
	if (entity != client && GetEntityMoveType(entity) == MOVETYPE_NOCLIP)
		return Plugin_Handled;

	return Plugin_Continue;
}
Action eSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	TFTeam team = TF2_GetClientTeam(client);
	if (cEnabled.BoolValue)
	{
		if (!IsValidClient(client) || team == TFTeam_Spectator) { return; }
		if (TF2_GetPlayerClass(client) == TFClass_Soldier)
		{
			TF2Attrib_SetByName(client, "max health additive bonus", 550.0);
		} else {
			if (TF2Attrib_GetByName(client, "max health additive bonus") != Address_Null)
			{
				TF2Attrib_RemoveByName(client, "max health additive bonus");
			}
		}
		TF2_RemoveAllWeapons(client);
		TF2_RegeneratePlayer(client);

		if (!bMapHasRegen)
		{
			// For old imported maps (conc, tfc etc)
			if (!bRegen[client][Ammo] && !bRegen[client][Health])
			{
				bRegen[client][Ammo] = true;
				bRegen[client][Health] = true;
				CPrintToChat(client, "%s Regen has been %sturned on%s for you.", TAG, T1, T2);
			}
		}
		if (fOrigin[client][0] != 0.0)
			TeleportEntity(client, fOrigin[client], fAngles[client], fVelocity);
	}
}
/******************************************************
					Database Functions				  *
******************************************************/
void DBCheck()
{
	char dType[32], Ai[32], query[1024];
	DBDriver drivType = dTFJump.Driver;	drivType.GetProduct(dType, sizeof dType);
	strcopy(Ai, sizeof(Ai), (StrEqual(dType, "mysql", false)) ? "AUTO_INCREMENT" : "AUTOINCREMENT");
	DebugLog("Using %s; Using %s", dType, Ai);
	
	dTFJump.Format(query, sizeof query,
					"CREATE TABLE IF NOT EXISTS `Profiles` ( " ...
					"`ID`	INTEGER PRIMARY KEY %s," ...
					"`SteamID`	VARCHAR(32) UNIQUE," ...
					"`Ammo`	INTEGER," ...
					"`Health`	INTEGER," ...
 					"`MsgSaved`	INTEGER," ...
					"`MsgTeleport`	INTEGER," ...
					"`MsgAdverts`	INTEGER," ...
					"`MsgCapPoints`	INTEGER," ...
					"`SndFall`	INTEGER," ...
					"`SndPain`	INTEGER," ...
					"`SnfFlesh`	INTEGER," ...
					"`SndRegen`	INTEGER," ...
					"`SndJump`	INTEGER);", Ai);
	dTFJump.Query(OnDefault, query, 1, DBPrio_High);
	dTFJump.Format(query, sizeof query, 
					"CREATE TABLE IF NOT EXISTS  `Maps` ( " ...
					"`ID`	INTEGER PRIMARY KEY %s," ...
					"`Name`	TEXT NOT NULL," ...
					"`Team`	INTEGER NOT NULL," ...
					"`Class`	INTEGER NOT NULL," ...
					"`Difficulty`	INTEGER NOT NULL);", Ai);
	dTFJump.Query(OnDefault, query, 2, DBPrio_High);
	dTFJump.Format(query, sizeof query, 
					"CREATE TABLE IF NOT EXISTS `Teleports` ( " ...
					"`ID` INTEGER PRIMARY KEY %s NOT NULL," ...
					"`Map` TEXT NOT NULL," ...
					"`Name` TEXT NOT NULL," ...
					"`L1` FLOAT NOT NULL," ...
					"`L2` FLOAT NOT NULL," ...
					"`L3` FLOAT NOT NULL," ...
					"`A1` FLOAT NOT NULL," ...
					"`A2` FLOAT NOT NULL," ...
					"`A3` FLOAT NOT NULL)", Ai);
	dTFJump.Query(OnDefault, query, 3, DBPrio_High);
	dTFJump.Format(query, sizeof query,
					"CREATE TABLE IF NOT EXISTS `Stats` ( " ...
					"`ID` INTEGER PRIMARY KEY %s NOT NULL," ...
					"`SteamID` TEXT NOT NULL," ...
					"`Map` TEXT," ...
					"`cap_points_reached` INTEGER," ...
					"`cap_points_max` INTEGER)", Ai);
	dTFJump.Query(OnDefault, query, 4, DBPrio_High);
	dTFJump.Format(query, sizeof query,
					"CREATE TABLE IF NOT EXISTS `Points` ( " ...
					"`ID` INTEGER NOT NULL PRIMARY KEY %s UNIQUE," ... 
					"`Name` TEXT," ...
					"`Name2` TEXT," ...
					"`L1` FLOAT," ...
					"`L2` FLOAT," ...
					"`L3` FLOAT," ...
					"`Map` TEXT)", Ai);
	dTFJump.Query(OnDefault, query, 5, DBPrio_High);
	dTFJump.Format(query, sizeof query,
					"CREATE TABLE IF NOT EXISTS `Saves` ( " ...
					"`ID`	INTEGER PRIMARY KEY %s," ...
					"`SteamId` VARCHAR(32) NOT NULL," ...
					"`Map`	TEXT NOT NULL," ...
					"`Class`	INTEGER NOT NULL," ...
					"`Team`	INTEGER NOT NULL," ...
					"`F1`	FLOAT NOT NULL," ...
					"`F2`	FLOAT NOT NULL," ...
					"`F3`	FLOAT NOT NULL," ...
					"`A1`	FLOAT);", Ai);
	dTFJump.Query(OnDefault, query, 6, DBPrio_High);
}
void UpdateProfile(int client, int Type)
{
	if (bNoSteamId[client])
	{
		DebugLog("Profile update aborted for %N (No SteamId)", client);
		return;
	}
	char query[512];
	switch (Type)
	{
		case 0:
		{
			// Regen
			dTFJump.Format(query, sizeof query, "UPDATE `Profiles` SET Ammo=%i, Health=%i WHERE SteamId = '%s'",
							bRegen[client][Ammo], bRegen[client][Health], SteamId[client]);
			dTFJump.Query(OnDefault, query);
			DebugLog("Updated profile (regen settings) for %N", client);
		}
		case 1:
		{
			// Messages
			dTFJump.Format(query, sizeof query, "UPDATE `Profiles` SET MsgSaved=%i, MsgTeleport=%i, MsgAdverts=%i, MsgCapPoints=%i WHERE SteamId = '%s'",
							bMessages[client][Msg_Saved], bMessages[client][Msg_Teleport], bMessages[client][Msg_Adverts], 
							bMessages[client][Msg_CapPoint], SteamId[client]);
			dTFJump.Query(OnDefault, query);
			DebugLog("Updated profile (message settings) for %N", client);
		}
		case 2:
		{
			// Sounds
			dTFJump.Format(query, sizeof query, "UPDATE `Profiles` SET SndFall=%i, SndFlesh=%i, SndRegen=%i, SndPain=%i, SndJump=%i WHERE SteamId = '%s'",
							bSounds[client][SND_FALL], bSounds[client][SND_FLESH], bSounds[client][SND_REGEN], 
							bSounds[client][SND_PAIN], bSounds[client][SND_JUMP], SteamId[client]);
			dTFJump.Query(OnDefault, query);
			DebugLog("Updated profile (sound settings) for %N", client);
		}
	}
}
void CheckAutoList()
{
	if (dTFJump != null)
	{
		char query[512];
		dTFJump.Format(query, sizeof query, "SELECT * FROM `Teleports` WHERE Map = '%s'", MapName);
		dTFJump.Query(OnCheckJumpListAuto, query);
	}
}
void CheckMapSettings()
{
	char query[512];
	dTFJump.Format(query, sizeof query, "SELECT * FROM Maps WHERE Name = '%s'", MapName);
	dTFJump.Query(OnCheckMapSettings, query); 
}
void UpdateMap(int client)
{
	char query[512];
	dTFJump.Format(query, sizeof query, "UPDATE `Maps` SET Team=%i, Class=%i, Difficulty=%i WHERE Name = '%s'",
					iForceTeam, iClass, iDiff, MapName);
	dTFJump.Query(OnDefault, query);
	DebugLog("%N has updated map settings for %s", client, MapName);
}
void Profile(int client)
{
	char query[512];
	dTFJump.Format(query, sizeof query, "SELECT * FROM `Profiles` WHERE SteamId = '%s'", SteamId[client]);
	dTFJump.Query(OnCheckProfile, query, client);
}
void SaveDB(int client)
{
	char query[512];
	int Team = GetClientTeam(client), Class = view_as<int>(TF2_GetPlayerClass(client));
	dTFJump.Format(query, sizeof query, "SELECT * FROM `Saves` WHERE steamID = '%s' AND Team = '%i' AND Class = '%i' AND Map = '%s'", 
					SteamId[client], Team, Class, MapName);
	dTFJump.Query(OnSaveDB, query, client);	
}
void SaveDB_Update(int client)
{
	char query[512];
	int Team = GetClientTeam(client), Class = view_as<int>(TF2_GetPlayerClass(client));

	dTFJump.Format(query, sizeof query, "UPDATE `Saves` SET F1 = '%f', F2 = '%f', F3 = '%f', A1 = '%f' where SteamId = '%s' AND Team = '%i' AND Class = '%i' AND Map = '%s'", 
					fOrigin[client][0], fOrigin[client][1], fOrigin[client][2], fAngles[client][1],	SteamId[client], Team, Class, MapName);
	dTFJump.Query(OnDefault, query);
}
void SaveDB_Insert(int client)
{
	char query[1024];
	int Team = GetClientTeam(client), Class = view_as<int>(TF2_GetPlayerClass(client));

	dTFJump.Format(query, sizeof query, "INSERT INTO `Saves` VALUES(null, '%s', '%s', '%i', '%i', '%s', '%f', '%f', '%f')", 
				SteamId[client], MapName, Class, Team, fOrigin[client][0], fOrigin[client][1], fOrigin[client][2], fAngles[client][1]);
	dTFJump.Query(OnDefault, query);
					
}
void LoadDB(int client)
{
	char query[512];
	int Team = GetClientTeam(client), Class = view_as<int>(TF2_GetPlayerClass(client));
	dTFJump.Format(query, sizeof query, "SELECT * FROM `Saves` WHERE SteamId = '%s' AND Team = '%i' AND Class = '%i' AND Map = '%s'", 
					SteamId[client], Team, Class, MapName);
	dTFJump.Query(OnLoadDB, query, client);	
}
/******************************************************
					Database Callbacks				  *
******************************************************/
public void OnDatabaseConnect(Database db, const char[] error, any data)
{
	if (db == null)
	{
		DebugLog("Database did not connect. Running in offline mode. ");
		return;
	}
	DebugLog("Database connected.");
	dTFJump = db; DBCheck();
	bConnected = true;

	if (bLate)
	{
		for (int i=1;i<=MaxClients;i++)
		{
			if (IsValidClient(i))
			{
				if (GetClientAuthId(i, AuthId_Steam2, SteamId[i], sizeof SteamId))
				{
					bNoSteamId[i] = false;
				} else {
					bNoSteamId[i] = true;
				}
				DoHooks(2, i);
				ResetPlayer(i);
				TF2_RemoveAllWeapons(i);
				TF2_RegeneratePlayer(i);
				Profile(i);
				LoadDB(i);
			}
		}
		bLate = false;
	}
}
public void OnDefault(Database db, DBResultSet results, const char[] error, any data)
{
	if (strcmp(error, "") != 0)
	{
		switch (view_as<int>(data))
		{
			case 1: { DebugLog("SQL query failed at Profiles: (%s)", error); }
			case 2: { DebugLog("SQL query failed at Maps: (%s)", error); }
			case 3: { DebugLog("SQL query failed at Teleports: (%s)", error); }
			case 4: { DebugLog("SQL query failed at Stats: (%s)", error); }
			case 5: { DebugLog("SQL query failed at Points: (%s)", error); }
			case 6: { DebugLog("SQL query failed at Saves: (%s)", error); }
			default: { DebugLog("SQL query failed (%s)", error); }
		}
	} else {
		switch (view_as<int>(data))
		{
			case 1: { DebugLog("Checking Profiles, ok!"); }
			case 2: { DebugLog("Checking Maps, ok!"); }
			case 3: { DebugLog("Checking Teleports, ok!"); }
			case 4: { DebugLog("Checking Stats, ok!"); }
			case 5: { DebugLog("Checking Points, ok!"); }
			case 6: { DebugLog("Checking Saves, ok!"); }
			default: { DebugLog("Query successful."); }
		}
	}
}
public void OnCheckProfile(Database db, DBResultSet results, const char[] error, any data)
{
	if (db == null || results == null)
	{
		DebugLog("%s", error);
		return;
	}
	int client = data;
	if (results.RowCount > 0)
	{
		results.FetchRow();
		// Regen
		bRegen[client][Ammo] = view_as<bool>(results.FetchInt(2));
		bRegen[client][Health] = view_as<bool>(results.FetchInt(3));
		// Messages
		bMessages[client][Msg_Saved] = view_as<bool>(results.FetchInt(4));
		bMessages[client][Msg_Teleport] = view_as<bool>(results.FetchInt(5));
		bMessages[client][Msg_Adverts] = view_as<bool>(results.FetchInt(6));
		bMessages[client][Msg_CapPoint] = view_as<bool>(results.FetchInt(7));
		// Sounds
		bSounds[client][SND_FALL] = view_as<bool>(results.FetchInt(8));
		bSounds[client][SND_PAIN] = view_as<bool>(results.FetchInt(9));
		bSounds[client][SND_FLESH] = view_as<bool>(results.FetchInt(10));
		bSounds[client][SND_REGEN] = view_as<bool>(results.FetchInt(11));
		bSounds[client][SND_JUMP] = view_as<bool>(results.FetchInt(12));
	} else {
		char query[512];
		dTFJump.Format(query, sizeof query, "INSERT INTO `Profiles` VALUES(null, '%s', 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0);", SteamId[client]);
		dTFJump.Query(OnDefault, query);
	}
}
public void OnCheckJumpListAuto(Database db, DBResultSet results, const char[] error, any data)
{
	if (db == null || results == null)
	{
		DebugLog("%s", error);
		return;
	}
	
	if (results.RowCount > 0)
	{
		DebugLog("Map already has jump points saved.");		
	} else {
		AutoList();
	}
}
public void OnCheckMapSettings(Database db, DBResultSet results, const char[] error, any data)
{
	if (db == null || results == null)
	{
		DebugLog("%s", error);
		return;
	}
	
	if (results.RowCount > 0)
	{
		results.FetchRow();
		
		iForceTeam = results.FetchInt(2);
		iClass = results.FetchInt(3);
		iDiff = results.FetchInt(4);
		DebugLog("%s has saved settings, loading.", MapName);
		CheckTeams();
	} else {
		DebugLog("%s has no saved settings, creating.", MapName);
		char query[512];
		dTFJump.Format(query, sizeof query, "INSERT INTO `Maps` VALUES(null, '%s', '%i', '%i', '%i');", MapName, iForceTeam, iClass, iDiff);
		dTFJump.Query(OnDefault, query);
	}
}
public void OnSaveDB(Database db, DBResultSet results, const char[] error, any data)
{ 
	if (db == null || results == null) 
	{ 
		LogError("%s", error); 
	} 
	if (results.RowCount > 0)
	{
		SaveDB_Update(data);
	} 
	else 
	{
		SaveDB_Insert(data);
	} 
}
public void OnLoadDB(Database db, DBResultSet results, const char[] error, any data)
{ 
	if (db == null || results == null) 
	{ 
		LogError("%s", error); 
	} 
	if (results.RowCount > 0)
	{
		results.FetchRow();
		fOrigin[data][0] = results.FetchFloat(5);
		fOrigin[data][1] = results.FetchFloat(6);
		fOrigin[data][2] = results.FetchFloat(7);

		fAngles[data][0] = 0.0;
		fAngles[data][1] = results.FetchFloat(8);
		fAngles[data][2] = 0.0;
	}
}