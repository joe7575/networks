--[[

	Networks
	========

	Copyright (C) 2021 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

]]--

-- for lazy programmers
local P2S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local S2P = minetest.string_to_pos
local M = minetest.get_meta

local CYCLE_TIME = 2
local STORAGE_CAPA = 500
local GEN_MAX = 20
local CON_MAX = 5

local function round(val)
	return math.floor(val + 0.5)
end

-------------------------------------------------------------------------------
-- Cable
-------------------------------------------------------------------------------
local Cable = tubelib2.Tube:new({
	dirs_to_check = {1,2,3,4,5,6},
	max_tube_length = 20, 
	tube_type = "test",
	primary_node_names = {"networks:cableS", "networks:cableA"}, 
	secondary_node_names = {
		"networks:generator", "networks:consumer", "networks:consumer_on", 
		"networks:junction", "networks:storage"},
	after_place_tube = function(pos, param2, tube_type, num_tubes, tbl)
		if networks.node_to_be_replaced(pos, param2, tube_type, num_tubes) then
			minetest.swap_node(pos, {name = "networks:cable"..tube_type, param2 = param2})
		end
	end,
})

-- Enable hidden cables
networks.use_metadata(Cable)

minetest.register_node("networks:cableS", {
	description = "Cable",
	tiles = { -- Top, base, right, left, front, back
		"networks_cable.png",
		"networks_cable.png",
		"networks_cable.png",
		"networks_cable.png",
		"networks_hole.png",
		"networks_hole.png",
	},
	after_place_node = function(pos, placer, itemstack, pointed_thing)
		if not Cable:after_place_tube(pos, placer, pointed_thing) then
			minetest.remove_node(pos)
			return true
		end
		return false
	end,
	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		Cable:after_dig_tube(pos, oldnode, oldmetadata)
	end,
	paramtype2 = "facedir", -- important!
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			{-3/16, -3/16, -4/8,  3/16, 3/16, 4/8},
		},
	},
	on_rotate = screwdriver.disallow, -- important!
	paramtype = "light",
	use_texture_alpha = "clip",
	sunlight_propagates = true,
	is_ground_content = false,
	groups = {crumbly = 3, cracky = 3, snappy = 3},
	sounds = default.node_sound_defaults(),
})

minetest.register_node("networks:cableA", {
	description = "Cable",
	tiles = { -- Top, base, right, left, front, back
		"networks_cable.png",
		"networks_hole.png",
		"networks_cable.png",
		"networks_cable.png",
		"networks_cable.png",
		"networks_hole.png",
	},
	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		Cable:after_dig_tube(pos, oldnode, oldmetadata)
	end,
	paramtype2 = "facedir", -- important!
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			{-3/16, -4/8, -3/16,  3/16, 3/16,  3/16},
			{-3/16, -3/16, -4/8,  3/16, 3/16, -3/16},
		},
	},
	on_rotate = screwdriver.disallow, -- important!
	paramtype = "light",
	use_texture_alpha = "clip",
	sunlight_propagates = true,
	is_ground_content = false,
	groups = {crumbly = 3, cracky = 3, snappy = 3, not_in_creative_inventory=1},
	sounds = default.node_sound_defaults(),
	drop = "networks:cableS",
})

local size = 3/16
local Boxes = {
	{{-size, -size,  size, size,  size, 0.5 }}, -- z+
	{{-size, -size, -size, 0.5,   size, size}}, -- x+
	{{-size, -size, -0.5,  size,  size, size}}, -- z-
	{{-0.5,  -size, -size, size,  size, size}}, -- x-
	{{-size, -0.5,  -size, size,  size, size}}, -- y-
	{{-size, -size, -size, size,  0.5,  size}}, -- y+
}

networks.register_junction("networks:junction", size, Boxes, Cable, {
	description = "Junction",
	tiles = {"networks_junction.png"},
	after_place_node = function(pos, placer, itemstack, pointed_thing)
		local name = "networks:junction"..networks.junction_type(pos, Cable)
		minetest.swap_node(pos, {name = name, param2 = 0})
		Cable:after_place_node(pos)
	end,
	tubelib2_on_update2 = function(pos, dir1, tlib2, node)
		local name = "networks:junction"..networks.junction_type(pos, Cable)
		minetest.swap_node(pos, {name = name, param2 = 0})
		networks.update_network(pos, 0, tlib2)
	end,
	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		Cable:after_dig_node(pos)
	end,
	networks = {
		test = {
			sides = networks.AllSides, -- connection sides for cables
			ntype = "junc",
		},
	},
	paramtype = "light",
	use_texture_alpha = "clip",
	sunlight_propagates = true,
	is_ground_content = false,
	groups = {crumbly = 3, cracky = 3, snappy = 3},
	sounds = default.node_sound_defaults(),
})

-------------------------------------------------------------------------------
-- Generator
-------------------------------------------------------------------------------
minetest.register_node("networks:generator", {
	description = "Generator",
	tiles = {
		-- up, down, right, left, back, front
		'networks_gen.png',
		'networks_gen.png',
		'networks_gen.png',
		'networks_gen.png',
		'networks_gen.png',
		'networks_conn.png',
	},
	after_place_node = function(pos, placer)
		local outdir = networks.side_to_outdir(pos, "F")
		M(pos):set_int("outdir", outdir)
		Cable:after_place_node(pos, {outdir})		
		M(pos):set_string("infotext", "off")
		tubelib2.init_mem(pos)
	end,
	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		local outdir = tonumber(oldmetadata.fields.outdir or 0)
		Cable:after_dig_node(pos, {outdir})
		tubelib2.del_mem(pos)
	end,
	on_timer = function(pos, elapsed)
		local outdir = M(pos):get_int("outdir")
		local mem = tubelib2.get_mem(pos)
		mem.provided = networks.provide_power(pos, Cable, outdir, GEN_MAX)
		M(pos):set_string("infotext", "providing "..round(mem.provided))
		return true
	end,
	tubelib2_on_update2 = function(pos, outdir, tlib2, node)
		print("tubelib2_on_update2")
		networks.update_network(pos, outdir, tlib2)
	end,
	on_rightclick = function(pos, node, clicker)
		local mem = tubelib2.get_mem(pos)
		if mem.running then
			mem.running = false
			M(pos):set_string("infotext", "off")
			minetest.get_node_timer(pos):stop()
		else
			mem.provided = mem.provided or 0
			mem.running = true
			M(pos):set_string("infotext", "providing "..round(mem.provided))
			minetest.get_node_timer(pos):start(CYCLE_TIME)
		end
	end,
	networks = {
		test = {
		  sides = networks.AllSides,
		  ntype = "gen",
		},
	},
	paramtype2 = "facedir", -- important!
	on_rotate = screwdriver.disallow, -- important!
	paramtype = "light",
	sunlight_propagates = true,
	is_ground_content = false,
	groups = {crumbly = 3, cracky = 3, snappy = 3},
	sounds = default.node_sound_glass_defaults(),
})

-------------------------------------------------------------------------------
-- Consumer
-------------------------------------------------------------------------------
local function swap_node(pos, name)
	local node = tubelib2.get_node_lvm(pos)
	if node.name == name then
		return
	end
	node.name = name
	minetest.swap_node(pos, node)
end

local function turn_on(pos, tlib2)
	swap_node(pos, "networks:consumer_on")
	M(pos):set_string("infotext", "on")
	local mem = tubelib2.get_mem(pos)
	mem.running = true
	minetest.get_node_timer(pos):start(CYCLE_TIME)
end

local function turn_off(pos, tlib2)
	swap_node(pos, "networks:consumer")
	M(pos):set_string("infotext", "off")
	local mem = tubelib2.get_mem(pos)
	mem.running = false
	minetest.get_node_timer(pos):stop()
end

local function on_rightclick(pos, node, clicker)
	local mem = tubelib2.get_mem(pos)
	if not mem.running and networks.power_available(pos, Cable) then
		turn_on(pos, Cable)
	else
		turn_off(pos, Cable)
	end
end

local function after_place_node(pos)
	M(pos):set_string("infotext", "off")
	Cable:after_place_node(pos)
	tubelib2.init_mem(pos)
end

local function after_dig_node(pos, oldnode)
	Cable:after_dig_node(pos)
	tubelib2.del_mem(pos)
end

minetest.register_node("networks:consumer", {
	description = "Consumer",
	tiles = {'networks_con.png^[colorize:#000000:50'},
	
	on_rightclick = on_rightclick,
	after_place_node = after_place_node,
	after_dig_node = after_dig_node,
	tubelib2_on_update2 = networks.update_network,
	networks = {
		test = {
			sides = networks.AllSides, -- connection sides for cables
			ntype = "con",
		},
	},
	paramtype = "light",
	light_source = 0,	
	paramtype2 = "facedir",
	groups = {choppy = 2, cracky = 2, crumbly = 2},
	is_ground_content = false,
	sounds = default.node_sound_wood_defaults(),
})

minetest.register_node("networks:consumer_on", {
	description = "Consumer",
	tiles = {'networks_con.png'},

	on_timer = function(pos, elapsed)
		local consumed = networks.consume_power(pos, Cable, nil, CON_MAX)
		if consumed < CON_MAX then
			turn_off(pos, Cable)
			return false
		end
		return true
	end,
	on_rightclick = on_rightclick,
	after_place_node = after_place_node,
	after_dig_node = after_dig_node,
	tubelib2_on_update2 = networks.update_network,
	networks = {
		test = {
			sides = networks.AllSides, -- connection sides for cables
			ntype = "con",
		},
	},
	paramtype = "light",
	light_source = minetest.LIGHT_MAX,	
	paramtype2 = "facedir",
	diggable = false,
	drop = "",
	groups = {not_in_creative_inventory = 1},
	is_ground_content = false,
	sounds = default.node_sound_wood_defaults(),
})

-------------------------------------------------------------------------------
-- Storage
-------------------------------------------------------------------------------
minetest.register_node("networks:storage", {
	description = "Storage",
	tiles = {"networks_sto.png"},
	on_timer = function(pos, elapsed)
		local mem = tubelib2.get_mem(pos)
		local val = networks.get_storage_load(pos, Cable)
		if val then
			mem.load = val * STORAGE_CAPA
		end
		local percent = (mem.load or 0) / STORAGE_CAPA * 100
		M(pos):set_string("infotext", "load = "..round(percent))
		return true
	end,
	after_place_node = function(pos)
		Cable:after_place_node(pos)
		minetest.get_node_timer(pos):start(CYCLE_TIME)
		tubelib2.init_mem(pos)
	end,
	after_dig_node = function(pos, oldnode)
		Cable:after_dig_node(pos)
		tubelib2.del_mem(pos)
	end,
	tubelib2_on_update2 = function(pos, outdir, tlib2, node) 
		networks.update_network(pos, outdir, tlib2)
	end,
	get_storage_load = function(pos)
		local mem = tubelib2.get_mem(pos)
		return mem.load or 0, STORAGE_CAPA
	end,
	networks = {
		test = {
		  sides = networks.AllSides,
		  ntype = "sto",
		},
	},
	paramtype2 = "facedir",
	groups = {choppy = 2, cracky = 2, crumbly = 2},
	is_ground_content = false,
	sounds = default.node_sound_wood_defaults(),
})

-------------------------------------------------------------------------------
-- Switch/valve
-------------------------------------------------------------------------------
local Param2ToDir = {
	[0] = 6,
	[1] = 5,
	[2] = 2,
	[3] = 4,
	[4] = 1,
	[5] = 3,
}

local function is_switchbox(pos)
	return techage.get_node_lvm(pos).name == "techage:powerswitch_box" or 
			M(pos):get_string("techage_hidden_nodename") == "techage:powerswitch_box"
end

local function switch_on(pos, node, clicker, name)
	if clicker and minetest.is_protected(pos, clicker:get_player_name()) then
		return
	end
	node.name = name
	minetest.swap_node(pos, node)
	minetest.sound_play("techage_button", {
			pos = pos,
			gain = 0.5,
			max_hear_distance = 5,
		})
	local dir = Param2ToDir[node.param2]
	local pos2 = tubelib2.get_pos(pos, dir)
	
	if is_switchbox(pos2) then
		if M(pos2):get_int("tl2_param2_copy") == 0 then
			M(pos2):set_int("tl2_param2", techage.get_node_lvm(pos2).param2)
		else
			M(pos2):set_int("tl2_param2", M(pos2):get_int("tl2_param2_copy"))
		end
		Cable:after_place_tube(pos2, clicker)
	end
end

local function switch_off(pos, node, clicker, name)
	if clicker and minetest.is_protected(pos, clicker:get_player_name()) then
		return
	end
	node.name = name
	minetest.swap_node(pos, node)
	minetest.get_node_timer(pos):stop()
	minetest.sound_play("techage_button", {
			pos = pos,
			gain = 0.5,
			max_hear_distance = 5,
		})
	local dir = Param2ToDir[node.param2]
	local pos2 = tubelib2.get_pos(pos, dir)
	
	if is_switchbox(pos2) then
		local node2 = techage.get_node_lvm(pos2)
		node2.param2 = M(pos2):get_int("tl2_param2")
		M(pos2):set_int("tl2_param2_copy", M(pos2):get_int("tl2_param2"))
		M(pos2):set_int("tl2_param2", 0)
		Cable:after_dig_tube(pos2, node2)
	end
end


--minetest.register_node("techage:powerswitch", {
--	description = S("TA Power Switch"),
--	inventory_image = "techage_appl_switch_inv.png",
--	tiles = {
--		'techage_appl_switch_off.png',
--	},

--	drawtype = "nodebox",
--	node_box = {
--		type = "fixed",
--		fixed = {
--			{ -1/4, -8/16, -1/4,  1/4, -7/16, 1/4},
--			{ -1/6, -12/16, -1/6,  1/6, -8/16, 1/6},
--		},
--	},
	
--	after_place_node = function(pos, placer)
--		local meta = M(pos)
--		local number = techage.add_node(pos, "techage:powerswitch")
--		meta:set_string("node_number", number)
--		meta:set_string("owner", placer:get_player_name())
--		meta:set_string("infotext", S("TA Power Switch").." "..number)
--		local node = minetest.get_node(pos)
--		switch_on(pos, node, placer, "techage:powerswitch_on")
--	end,

--	on_rightclick = function(pos, node, clicker)
--		switch_on(pos, node, clicker, "techage:powerswitch_on")
--	end,

--	on_rotate = screwdriver.disallow,
--	paramtype = "light",
--	use_texture_alpha = techage.CLIP,
--	sunlight_propagates = true,
--	paramtype2 = "wallmounted",
--	groups = {choppy=2, cracky=2, crumbly=2},
--	is_ground_content = false,
--	sounds = default.node_sound_wood_defaults(),
--})
