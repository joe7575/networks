--[[

	Networks
	========

	Copyright (C) 2021 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

]]--


-- for lazy programmers
local S2P = minetest.string_to_pos
local P2S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local M = minetest.get_meta
local N = tubelib2.get_node_lvm

local hidden_message = ""
local tFillingMaterial = {}

-------------------------------------------------------------------------------
-- API
-------------------------------------------------------------------------------
function networks.hidden_name(pos)
	local meta = M(pos)
	if meta:contains("networks_nodename") then
		return meta:get_string("networks_nodename")
	end
end

function networks.hidden_param2(pos)
	local meta = M(pos)
	if meta:contains("networks_param2") then
		return meta:get_string("networks_param2")
	end
end

function networks.get_nodename(pos)
	local meta = M(pos)
	if meta:contains("networks_nodename") then
		return meta:get_string("networks_nodename")
	end
	return tubelib2.get_node_lvm(pos).name
end

function networks.get_node(pos)
	local meta = M(pos)
	if meta:contains("networks_nodename") then
		return {name = meta:get_string("networks_nodename"), param2 = meta:get_int("networks_param2")}
	end
	return tubelib2.get_node_lvm(pos)
end


-- Override methods of tubelib2 to store tube/cable info as metadata.
-- This allows hidden cables/tubes/junctions/switches.
function networks.use_metadata(tlib2)
	tlib2.get_primary_node_param2 = function(self, pos, dir)
		local npos = vector.add(pos, tubelib2.Dir6dToVector[dir or 0])
		local param2 = M(npos):get_int("networks_param2")
		if param2 ~= 0 then
			return param2, npos
		end
	end
	tlib2.is_primary_node = function(self, pos, dir)
		local npos = vector.add(pos, tubelib2.Dir6dToVector[dir or 0])
		local param2 = M(npos):get_int("networks_param2")
		return param2 ~= 0
	end
	tlib2.get_secondary_node = function(self, pos, dir)
		local npos = vector.add(pos, tubelib2.Dir6dToVector[dir or 0])
		local node = self:get_node_lvm(npos)
		if self.secondary_node_names[node.name] or 
				self.secondary_node_names[networks.hidden_name(npos)] then
			return node, npos, true
		end
	end
	tlib2.is_secondary_node = function(self, pos, dir)
		local npos = vector.add(pos, tubelib2.Dir6dToVector[dir or 0])
		local node = self:get_node_lvm(npos)
		return self.secondary_node_names[node.name] or 
				self.secondary_node_names[networks.hidden_name(npos)]
	end
end

-- Function is called from `tubelib2.after_place_tube` callback
-- Handle tube/cable nodes with 'use_metadata' feature, to change only the metadata,
-- and not to replace the node.
-- Function returns true, if node still has to be replaced.
function networks.node_to_be_replaced(pos, param2, tube_type, num_tubes)
	M(pos):set_int("networks_param2", param2)
	return networks.hidden_name(pos) == nil
end

function networks.hide_node(pos, node, placer)
	local inv = placer:get_inventory()
	local stack = inv:get_stack("main", 1)
	local taken = stack:take_item(1)
	
	if taken:get_count() == 1 and tFillingMaterial[taken:get_name()] then
		local meta = M(pos)
		meta:set_string("networks_nodename", node.name)
		local param2 = 0
		local ndef = minetest.registered_nodes[taken:get_name()]
		if ndef.paramtype2 and ndef.paramtype2 == "facedir" then
			param2 = minetest.dir_to_facedir(placer:get_look_dir(), true)
		end
		minetest.swap_node(pos, {name = taken:get_name(), param2 = param2})
		inv:set_stack("main", 1, stack)
		return true
	end
end

function networks.open_node(pos, node, placer)
	local name = networks.hidden_name(pos)
	local param2 = networks.hidden_param2(pos)
	minetest.swap_node(pos, {name = name, param2 = param2})
	local meta = M(pos)
	meta:set_string("networks_nodename", "")
	local inv = placer:get_inventory()
	inv:add_item("main", ItemStack(node.name))
	return true
end

-------------------------------------------------------------------------------
-- Patch registered nodes
-------------------------------------------------------------------------------
function networks.register_hidden_message(msg)
	hidden_message = msg
end

-- Register item names to be used as filling material to hide tubes/cables
function networks.register_filling_items(names)
	for _, name in ipairs(names) do
		tFillingMaterial[name] = true
	end
end

local function get_new_can_dig(old_can_dig)
	return function(pos, player, ...)
		if networks.hidden_name(pos) then
			if player and player.get_player_name then
				minetest.chat_send_player(player:get_player_name(), hidden_message)
			end
			return false
		end
		if old_can_dig then
			return old_can_dig(pos, player, ...)
		else
			return true
		end
	end
end

-- Change can_dig for registered filling materials.
minetest.register_on_mods_loaded(function()
	for name, _ in pairs(tFillingMaterial) do
		local ndef = minetest.registered_nodes[name]
		if ndef then
			local old_can_dig = ndef.can_dig
			minetest.override_item(ndef.name, {
				can_dig = get_new_can_dig(old_can_dig)
			})
		end
	end
end)

