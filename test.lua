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

-------------------------------------------------------------------------------
-- Cable
-------------------------------------------------------------------------------
local Cable = tubelib2.Tube:new({
	dirs_to_check = {1,2,3,4,5,6},
	max_tube_length = 20, 
	show_infotext = true,
	tube_type = "ele",
	primary_node_names = {"networks:cableS", "networks:cableA"}, 
	secondary_node_names = {
		"networks:generator", "networks:consumer", "networks:consumer_on", 
		"networks:junction", "networks:storage"},
	after_place_tube = function(pos, param2, tube_type, num_tubes, tbl)
		minetest.swap_node(pos, {name = "networks:cable"..tube_type, param2 = param2})
	end,
})

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
		networks.update_network(pos, nil, tlib2)
	end,
	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		Cable:after_dig_node(pos)
	end,
	networks = {
		ele = {
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
	end,

	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		local outdir = tonumber(oldmetadata.fields.outdir or 0)
		Cable:after_dig_node(pos, {outdir})
	end,
	
	on_timer = function(pos, elapsed)
		local outdir = M(pos):get_int("outdir")
		local mem = tubelib2.get_mem(pos)
		mem.provided = networks.provide_power(pos, Cable, outdir, GEN_MAX)
		M(pos):set_string("infotext", "providing "..mem.provided)
		return true
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
			M(pos):set_string("infotext", "providing "..mem.provided)
			minetest.get_node_timer(pos):start(CYCLE_TIME)
		end
	end,
	
	networks = {
		ele = {
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

local function on_turn_on(pos, tlib2)
	swap_node(pos, "networks:consumer_on")
	M(pos):set_string("infotext", "on")
	local mem = tubelib2.get_mem(pos)
	mem.running = true
	minetest.get_node_timer(pos):start(CYCLE_TIME)
end

local function on_turn_off(pos, tlib2)
	swap_node(pos, "networks:consumer")
	M(pos):set_string("infotext", "off")
	local mem = tubelib2.get_mem(pos)
	mem.running = false
	minetest.get_node_timer(pos):stop()
end

local function node_timer(pos, elapsed)
	local consumed = networks.consume_power(pos, Cable, nil, CON_MAX)
	if consumed < CON_MAX then
		on_turn_off(pos, Cable)
		return false
	end
	return true
end

local function on_rightclick(pos, node, clicker)
	local mem = tubelib2.get_mem(pos)
	if not mem.running and networks.power_available(pos, Cable) then
		on_turn_on(pos, Cable)
	else
		on_turn_off(pos, Cable)
	end
end

local function after_place_node(pos)
	M(pos):set_string("infotext", "off")
	Cable:after_place_node(pos)
end

local function after_dig_node(pos, oldnode)
	Cable:after_dig_node(pos)
	tubelib2.del_mem(pos)
end

local function tubelib2_on_update2(pos, outdir, tlib2, node) 
	networks.update_network(pos, outdir, tlib2)
end

local netdef = {
	ele = {
		sides = networks.AllSides, -- connection sides for cables
		ntype = "con",
	},
}

minetest.register_node("networks:consumer", {
	description = "Consumer",
	tiles = {'networks_con.png^[colorize:#000000:50'},
	
	on_turn_on = on_turn_on,
	on_timer = node_timer,
	on_rightclick = on_rightclick,
	after_place_node = after_place_node,
	after_dig_node = after_dig_node,
	tubelib2_on_update2 = tubelib2_on_update2,
	networks = netdef,
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

	on_turn_off = on_turn_off,
	on_timer = node_timer,
	on_rightclick = on_rightclick,
	after_place_node = after_place_node,
	after_dig_node = after_dig_node,
	tubelib2_on_update2 = tubelib2_on_update2,
	networks = netdef,
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
		mem.load = networks.get_storage_load(pos, Cable)
		M(pos):set_string("infotext", "load = "..math.floor(mem.load * 100))
		return true
	end,
	after_place_node = function(pos)
		Cable:after_place_node(pos)
		minetest.get_node_timer(pos):start(CYCLE_TIME)
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
		ele = {
		  sides = networks.AllSides,
		  ntype = "sto",
		},
	},
	paramtype2 = "facedir",
	groups = {choppy = 2, cracky = 2, crumbly = 2},
	is_ground_content = false,
	sounds = default.node_sound_wood_defaults(),
})
