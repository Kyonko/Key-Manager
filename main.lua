-- Key Manager plugin. Written by Tyler "Scuba Steve 9.0/Khalitz/Kavec/etc" Gibbons
-- Key distribution function written by Ben "Waffles" Lawrence
-- Some key selection code stolen from Slime's quickJump plugin
-- Bear with me, the comments are going to get weird. I am/was a bit loopy on minocycline when I wrote this.

--TODO: Cache rosters? Dunno!
--TODO: Complete other todos hidden throughout source

--Load up the http lib. REMOVE THIS AS NECESSARY
local anyx = {}
anyx.HTTP, anyx.json, anyx.b64, anyx.TCP = dofile("httplib/httplib.lua")
local HTTP, json, b64 = anyx.HTTP, anyx.json, anyx.b64

--Rest of stuff below
local function __EXISTS(val)
	return pcall(loadstring("return "..val))
end

local __DEBUG = false
local km = ""
if __DEBUG then
	km = "keymgr"
else
	km = SHA1(math.random())
end

--I feel like scrambling table names to be a twerp
--Paranoid that alts can be ID'd by proprietary plugin tables that are used.
--Umm, I mean, preventing table key collisions. Yeah!

--Make sure we don't hit anyone!
--Give it ten tries, if that does work, abort.
if __EXISTS(km) and not __DEBUG then 
	local broke = false
	for i=1, 10 do
		km = SHA1(math.random())
		if not __EXISTS(km) then
			broke = true
			break
		end
	end
	
	if not broke then 
		print("\127FF2020KEYMANAGER ERROR: \127ffffffFailed to find free namespace. Try reloading interface?")
		return 
	end
end




----------OPEN PLUGIN BODY----------
local guildspage = "http://www.vendetta-online.com/x/guildinfo"
local err = "\127ff2020KEYMANAGER ERROR: "

--This variable will hold our plugin
local plug = {}
plug.GuildList, plug.GuildListByTag, plug.queue, plug.LastUpdated, plug.VERSION = {}, {}, {}, nil, "1.0.0"
local glist, glist_tags = plug.GuildList, plug.GuildListByTag

plug.testroster = {}

local given = {}
local function collate_cb(...)
	local args = {...}
end

local function manage_keys(namelist, keyid, func)
	for ind, name in pairs(namelist) do
		func(name, keyid)
	end
end

function plug.IssueKeys(namelist, keyid)
	manage_keys(namelist, keyid, Keychain.giveuserkey)
end

function plug.RevokeKeys(namelist, keyid)
	manage_keys(namelist, keyid, Keychain.revokekey)
end


function plug.response(cb, ...)
	local vararg = {...}
	local resp_cb = function(response)
		if response and response.body then
			--Pass any args on
			cb(response.body.get(), unpack(vararg))
		else
			print(err.."\127ffffffInvalid response from server")
		end
	end
	return resp_cb
end

function plug.ProcessGuildList(page, echo)
	page = page:gsub("[\t\r\n]", ""):gsub(".-(<tr><td><a href=\"/x//?guildinfo/.-</tr>)</table></div></div>.*", "%1")
	local parse_guild_list = function(gid, fullname, tag) 
		glist[fullname:lower()] = {id = gid, tag = tag}
		glist_tags[tag:lower()]	= {id = gid, name = fullname}
	end
	
	page:gsub("<tr><td><a href=\"/x//?guildinfo/(%d+)/\">(.-)</a></td><td>%[(.-)%]</td><td>%d+</td></tr>", parse_guild_list)
	
	if echo then 
		print("\127ffffffKeyManager Guilds cache updated!")
	end
	
	plug.LastUpdated = gkmisc.GetGameTime()
	
	--Execute any functions waiting on guild list updates.
	for func, args in pairs(plug.queue) do
		func(unpack(args))
		plug.queue[func] = nil
	end
end

function plug.GetGuildList(echo)
	local http = HTTP.new()
	http.urlopen(guildspage, plug.response(plug.ProcessGuildList, echo))
end

function plug.ProcessGuildRoster(page, keyid, revoke)
	if not keyid then
		print(err .. "\127ffffffNo keys to give!")
		return
	end
	local roster = {}
	page = page:gsub("[\t\r\n]", ""):gsub(".-(<tr><td class=guildText align=left>.-)</table>.*", "%1")
	local parse_guild_roster = function(name)
		table.insert(roster, name)
	end
	
	page:gsub("<tr>.-<a href=\"/x/stats/%d+/\"><font class=.->(.-)</font></a>.-</tr>", parse_guild_roster)
	
	if revoke == 1 then
		--Take all the keys! Bwahahahahaha!
		plug.RevokeKeys(roster, keyid)
	elseif revoke == 0 then
		--Give everyone keys, I guess
		plug.IssueKeys(roster, keyid)
	else
		--We'll worry about this in a later version
		--TODO: Write logic that removes guild keys as necessary
	end
	
	print(("\127ffffffKeys have been %s!"):format((revoke==1 and "revoked") or (revoke==0 and "granted") or "updated"))
end

function plug.ManageGuildRoster(guildname, ...)
	if not glist[guildname:lower()] then return false end
	local vararg = {...}
	print("\127ffffffFetching guild roster for " .. guildname)
	local http = HTTP.new()
	local url = ("%s/%d/"):format(guildspage, glist[guildname:lower()].id)
	http.urlopen(url, plug.response(plug.ProcessGuildRoster, unpack(vararg)))
	return true
end

function plug.ManageGuildRosterByTag(guildtag, ...)
	guildtag = guildtag:lower()
	if not glist_tags[guildtag] then return false end
	local vararg = {...}
	local http = HTTP.new()
	print("\127ffffffFetching guild roster for " .. glist_tags[guildtag].name)
	local url = ("%s/%d/"):format(guildspage, glist_tags[guildtag].id)
	http.urlopen(url, plug.response(plug.ProcessGuildRoster, unpack(vararg)))
	return true
end

--Returns the ID of the first valid userkey we have an ownerkey for.
--TODO: Give some way to select between different user keys to give
function plug.FindKey(loc)
	local ownerkeys, keyid, okeyid = {}, nil, nil
	
	for i=1, GetNumKeysInKeychain() do
		local key = {GetKeyInfo(i)}
		if(key[2]:find(loc, 1, true) and key[7] and key[3]) then
			keyid = key[1]
			okeyid = key[3]
		elseif not key[3] then
			ownerkeys[key[1]] = true 
		end
	end
	if not ownerkeys[okeyid] then
		print("\127ffffffYou do not have an active owner key for "..loc)
		return false
	elseif keyid then 
		return keyid
	end

	
	print("\127ffffffKeyManager could not find a user key for that sector to give. Is it created and/or labeled correctly, i.e. similar to 'Latos I-8'?")
	return false
end

function plug.GetKey(loc)
	--TODO: Implement this
	if not loc then return plug.FindKey(ShortLocationStr(GetCurrentSectorid())) end
	local sectorid = SectorIDFromLocationStr(loc) or SectorIDFromLocationStr(SystemNames[GetCurrentSystemid()].." "..loc)
	if not sectorid then
		print("\127ffffffKeyManager could not locate that sector. Please check for spelling errors.")
		return false
	else
		return plug.FindKey(ShortLocationStr(sectorid))
	end
end

function plug.cli(func, args)
	if (not args) or ((not args[1]) or args[1]:lower() == "help") then 
		print(("\127ffffffKeyManager v%s\nUsage: /%sguildkeys <\"Guild Name\"|TAG> [location]"):format(plug.VERSION, func))
		print("\127ffffff\t'location' can be any valid system name or sysname + sector(i.e., 'latos i8').")
		print("\127ffffff\tIf you do not include 'location', keymanager will use your current sector to give/revoke keys instead")
		print("\127ffffff\tYou can also do '/keymanager forceupdate' to force an update to the current Guilds cache")
		return 
	elseif args[1]:lower() == "forceupdate" then
		--Get guild list and echo when done.
		plug.GetGuildList(true)
		return
	end
	local revoke = (func=="revoke" and 1) or (func == "give" and 0) or nil
	
	local guild, keyid = args[1], plug.GetKey(args[2])
	if not keyid then return false end
	
	local do_guild = function(guild, keyid, revoke)
		if not plug.ManageGuildRosterByTag(guild, keyid, revoke) then
			if not plug.ManageGuildRoster(guild, keyid, revoke) then
				print("\127ffffffKeyManager could not find " .. guild)
			end
		end
	end
	--Update our local guild list once per four hours!
	local update_guilds = ((not plug.LastUpdated) or gkmisc.DiffTime(gkmisc.GetGameTime(), plug.LastUpdated)%1000 > 14400) and true or false
	if not update_guilds then
		do_guild(guild, keyid, revoke)
	else 
		plug.queue[do_guild] = {guild, keyid, revoke}
		plug.GetGuildList()
	end
		
end

----------CLOSE PLUGIN BODY----------

--Write our table to global namespace as randomized name. What is wrong with me?
declare(km, plug)

--Do any RegisterUserCommand or RegisterEvent, etc here. Make sure to use plug.X or plug:X as necessary~~
--Doing it below the declare() makes sure the garbage collector doesn't punish us for not using global references
--Lua passes tables by reference, so this works to index whatever the hell km is above.
--Examples below
RegisterUserCommand("revokeguildkeys", plug.cli, "revoke")
RegisterUserCommand("giveguildkeys", plug.cli, "give")
plug.GetGuildList()
--RegisterEvent(plug.test, "KMGR")