--[[

	Networks
	========

	Copyright (C) 2021 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

]]--

networks = {}

-- Version for compatibility checks, see readme.md/history
networks.version = 1.00

if minetest.global_exists("tubelib2") and tubelib2.version < 2.0 then
	minetest.log("error", "[networks] Networks requires tubelib2 version 2.0 or newer!")
	return
end
local MP = minetest.get_modpath("networks")

dofile(MP .. "/networks.lua")
dofile(MP .. "/junction.lua")
dofile(MP .. "/storage.lua")
dofile(MP .. "/power.lua")
--dofile(MP .. "/liquids.lua")
-- Only for testing/demo purposes
dofile(MP .. "/test.lua")