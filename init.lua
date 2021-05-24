--[[

	Networks
	========

	Copyright (C) 2021 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

]]--

networks = {}

-- Version for compatibility checks, see readme.md/history
networks.version = 0.02

if minetest.global_exists("tubelib2") and tubelib2.version < 2.1 then
	minetest.log("error", "[networks] Networks requires tubelib2 version 2.1 or newer!")
	return
end
local MP = minetest.get_modpath("networks")

dofile(MP .. "/hidden.lua")
dofile(MP .. "/networks.lua")
dofile(MP .. "/junction.lua")
dofile(MP .. "/power.lua")
--dofile(MP .. "/liquids.lua")

-- Only for testing/demo purposes
dofile(MP .. "/test.lua")