--[[

	Networks
	========

	Copyright (C) 2021 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

]]--

networks = {}

-- Version for compatibility checks, see readme.md/history
networks.version = 0.04

if not minetest.global_exists("tubelib2") or tubelib2.version < 2.1 then
	minetest.log("error", "[networks] Networks requires tubelib2 version 2.1 or newer!")
	return
end

local MP = minetest.get_modpath("networks")

dofile(MP .. "/hidden.lua")
dofile(MP .. "/networks.lua")
dofile(MP .. "/junction.lua")
dofile(MP .. "/power.lua")
--dofile(MP .. "/liquid.lua")

-- Only for testing/demo purposes
dofile(MP .. "/test/test_power.lua")