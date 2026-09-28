#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
    name = "Pluto Comp Mode Vote & Welcome",
    author = "Apollo",
    description = "Automatic vote at 12 players, !comp / !casual vote commands, and join announcements",
    version = "1.0.0",
    url = "https://apollan.cc"
};

bool g_bVoteInProgress = false;
bool g_bIsCompMode = false;
bool g_bAutoVoteTriggered = false;
float g_flLastVoteTime = 0.0;

#define VOTE_COOLDOWN 60.0 // 60 seconds between votes

public void OnPluginStart() {
    RegConsoleCmd("sm_comp", Command_VoteComp, "Vote to switch to Competitive 6v6 mode");
    RegConsoleCmd("sm_6s", Command_VoteComp, "Vote to switch to Competitive 6v6 mode");
    RegConsoleCmd("sm_casual", Command_VoteCasual, "Vote to return to Casual Pub mode");
    RegConsoleCmd("sm_pub", Command_VoteCasual, "Vote to return to Casual Pub mode");

    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
}

public void OnMapStart() {
    g_bVoteInProgress = false;
    g_bAutoVoteTriggered = false;
    g_flLastVoteTime = 0.0;
}

public void OnClientPutInServer(int client) {
    if (!IsFakeClient(client)) {
        CreateTimer(6.0, Timer_WelcomeMessage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && IsClientInGame(client) && !IsFakeClient(client)) {
        CreateTimer(2.0, Timer_CheckAutoVote, 0, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_WelcomeMessage(Handle timer, int userid) {
    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client)) {
        PrintToChat(client, "\x04[Pluto]\x01 Welcome to the server!");
        PrintToChat(client, "\x04[Pluto]\x01 When \x0512 full players\x01 connect, an automatic vote for \x05Competitive 6v6\x01 will trigger.");
        PrintToChat(client, "\x04[Pluto]\x01 You can also type \x03!comp\x01 or \x03!casual\x01 in chat at any time to call a vote.");
    }
    return Plugin_Stop;
}

public Action Timer_CheckAutoVote(Handle timer, int data) {
    if (g_bVoteInProgress || g_bIsCompMode || g_bAutoVoteTriggered) {
        return Plugin_Stop;
    }

    int humans = GetHumanCount();
    if (humans >= 12) {
        g_bAutoVoteTriggered = true;
        StartCompVote("12 full players have connected!");
    }
    return Plugin_Stop;
}

int GetHumanCount() {
    int count = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i)) {
            count++;
        }
    }
    return count;
}

public Action Command_VoteComp(int client, int args) {
    if (g_bIsCompMode) {
        ReplyToCommand(client, "[Pluto] The server is already in Competitive 6v6 mode.");
        return Plugin_Handled;
    }

    if (g_bVoteInProgress) {
        ReplyToCommand(client, "[Pluto] A vote is already in progress.");
        return Plugin_Handled;
    }

    float flNow = GetEngineTime();
    if (flNow - g_flLastVoteTime < VOTE_COOLDOWN) {
        int wait = RoundToCeil(VOTE_COOLDOWN - (flNow - g_flLastVoteTime));
        ReplyToCommand(client, "[Pluto] Please wait %d seconds before calling another vote.", wait);
        return Plugin_Handled;
    }

    char szCaller[64];
    if (client > 0 && IsClientInGame(client)) {
        GetClientName(client, szCaller, sizeof(szCaller));
    } else {
        strcopy(szCaller, sizeof(szCaller), "Console");
    }

    char szReason[128];
    Format(szReason, sizeof(szReason), "%s has called a vote!", szCaller);
    StartCompVote(szReason);
    return Plugin_Handled;
}

public Action Command_VoteCasual(int client, int args) {
    if (!g_bIsCompMode) {
        ReplyToCommand(client, "[Pluto] The server is already in Casual Pub mode.");
        return Plugin_Handled;
    }

    if (g_bVoteInProgress) {
        ReplyToCommand(client, "[Pluto] A vote is already in progress.");
        return Plugin_Handled;
    }

    float flNow = GetEngineTime();
    if (flNow - g_flLastVoteTime < VOTE_COOLDOWN) {
        int wait = RoundToCeil(VOTE_COOLDOWN - (flNow - g_flLastVoteTime));
        ReplyToCommand(client, "[Pluto] Please wait %d seconds before calling another vote.", wait);
        return Plugin_Handled;
    }

    StartCasualVote();
    return Plugin_Handled;
}

void StartCompVote(const char[] reason) {
    if (IsVoteInProgress()) {
        return;
    }

    g_bVoteInProgress = true;
    g_flLastVoteTime = GetEngineTime();

    PrintToChatAll("\x04[Pluto]\x01 %s", reason);
    PrintToChatAll("\x04[Pluto]\x01 Starting vote: \x05Switch to Competitive 6v6 mode?\x01");

    Menu menu = new Menu(Handler_CompVote);
    menu.SetTitle("Switch to Competitive 6v6 Mode?");
    menu.AddItem("yes", "Yes, start Comp 6s");
    menu.AddItem("no", "No, stay in Casual Pub");
    menu.ExitButton = false;
    menu.DisplayVoteToAll(20);
}

public int Handler_CompVote(Menu menu, MenuAction action, int param1, int param2) {
    if (action == MenuAction_End) {
        delete menu;
        g_bVoteInProgress = false;
    } else if (action == MenuAction_VoteEnd) {
        if (param1 == 0) { // "yes"
            PrintToChatAll("\x04[Pluto]\x01 Vote \x04PASSED\x01! Switching to \x05Competitive 6v6\x01 mode...");
            g_bIsCompMode = true;
            ServerCommand("exec comp_6s.cfg");
        } else {
            PrintToChatAll("\x04[Pluto]\x01 Vote \x07FAILED\x01. Staying in Casual Pub mode.");
        }
        g_bVoteInProgress = false;
    }
    return 0;
}

void StartCasualVote() {
    if (IsVoteInProgress()) {
        return;
    }

    g_bVoteInProgress = true;
    g_flLastVoteTime = GetEngineTime();

    PrintToChatAll("\x04[Pluto]\x01 Starting vote: \x05Return to Casual Pub mode (with bots)?\x01");

    Menu menu = new Menu(Handler_CasualVote);
    menu.SetTitle("Return to Casual Pub Mode (with Bots)?");
    menu.AddItem("yes", "Yes, return to Casual");
    menu.AddItem("no", "No, stay in Comp");
    menu.ExitButton = false;
    menu.DisplayVoteToAll(20);
}

public int Handler_CasualVote(Menu menu, MenuAction action, int param1, int param2) {
    if (action == MenuAction_End) {
        delete menu;
        g_bVoteInProgress = false;
    } else if (action == MenuAction_VoteEnd) {
        if (param1 == 0) { // "yes"
            PrintToChatAll("\x04[Pluto]\x01 Vote \x04PASSED\x01! Returning to \x03Casual Pub\x01 mode...");
            g_bIsCompMode = false;
            g_bAutoVoteTriggered = false;
            ServerCommand("exec casual.cfg");
        } else {
            PrintToChatAll("\x04[Pluto]\x01 Vote \x07FAILED\x01. Staying in Competitive mode.");
        }
        g_bVoteInProgress = false;
    }
    return 0;
}
