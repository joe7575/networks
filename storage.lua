--[[

	Networks
	========

	Copyright (C) 2021 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

]]--

local storage = minetest.get_mod_storage()

local function update_mod_storage()
	storage:set_int("Version", 1)
	storage:set_string("Power", minetest.serialize(networks.Power or {}))
	
	-- run every 10 minutes
	minetest.after(600, update_mod_storage)
end

minetest.register_on_mods_loaded(function()
	local version = storage:get_int("Version")
	networks.Power = minetest.deserialize(storage:get_string("Power")) or {}
	minetest.after(600, update_mod_storage)
end)

minetest.register_on_shutdown(function()
	 update_mod_storage()
end)

