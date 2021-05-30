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

networks.power = {}

-- Storage parameters:
-- capa = maximum value in power units
-- load = current value in power units
-- level = ratio value (load/capa) (0..1)

local Power = {}  -- {netID = {curr_load, min_load, max_load, max_capa, consumed, provided, available}}

-- Determine load, capa and other power network data
local function get_power_data(pos, tlib2, outdir)
	local netw = networks.get_network_table(pos, tlib2, outdir)
	local max_capa = 0
	local curr_load = 0
	-- Generators
	for _,item in ipairs(netw.gen or {}) do
		local ndef = minetest.registered_nodes[N(item.pos).name]
		local data = ndef.get_generator_data(item.pos, tlib2)
		max_capa = max_capa + data.perf -- generator performance = capa
		curr_load = curr_load + (data.level * data.perf)
	end
	-- Storage systems
	for _,item in ipairs(netw.sto or {}) do
		local ndef = minetest.registered_nodes[N(item.pos).name]
		local data = ndef.get_storage_data(item.pos, tlib2)
		max_capa = max_capa + data.capa
		curr_load = curr_load + (data.level * data.capa)
	end
	return {
		curr_load = curr_load,    -- network storage value
		min_load = curr_load,     -- minimal storage value
		max_load = curr_load,     -- maximal storage value
		max_capa = max_capa,      -- network storage capacity
		consumed = 0,             -- consumed power over all consumers
		provided = 0,             -- provided power over all generators
		available = 0,            -- max. available power over all generators
		num_nodes = netw.num_nodes,
	}
end

-------------------------------------------------------------------------------
-- Consumer/Generator/Storage
-------------------------------------------------------------------------------
-- names: list of node names
-- tlib2: tubelib2 instance
-- node_type: one of "gen", "con", "sto", "junc"
-- valid_sides: something like {"L", "R"} or nil
function networks.power.register_node(names, tlib2, node_type, valid_sides)
	if node_type == "gen" or node_type == "sto" then
		assert(#valid_sides == 1)
	elseif node_type == "con" or node_type == "junc" then
		assert(not valid_sides or type(valid_sides) == "table")
		valid_sides = valid_sides or {"B", "R", "F", "L", "D", "U"}
	else
		error("parameter error")
	end
	
	tlib2:add_secondary_node_names(names)
	
	for _, name in ipairs(names) do
		local ndef = minetest.registered_nodes[name]
		local tbl = ndef.networks or {}
		tbl[tlib2.tube_type] = {ntype = node_type}
		minetest.override_item(name, {networks = tbl})
		tlib2:set_valid_sides(name, valid_sides)
	end
end

-- To be called for each power network change via
-- tubelib2_on_update2 or register_on_tube_update2
function networks.power.update_network(pos, outdir, tlib2, node)
	local netID = networks.get_netID(pos, tlib2, outdir)
	if netID then
		Power[netID] = nil
	end
	networks.update_network(pos, outdir, tlib2, node)
end

-------------------------------------------------------------------------------
-- Consumer
-------------------------------------------------------------------------------
-- Function checks for a power grid, not for enough power
-- For consumers, outdir is optional
function networks.power.power_available(pos, tlib2)
	local netID = networks.get_netID(pos, tlib2)
	if netID then
		local pwr = Power[netID] or get_power_data(pos, tlib2)
		return pwr.curr_load > 0
	end
end

-- For consumers, outdir is optional
function networks.power.consume_power(pos, tlib2, amount)
	local netID = networks.get_netID(pos, tlib2)
	if netID then
		local pwr = Power[netID] or get_power_data(pos, tlib2)
		if pwr.curr_load >= amount then
			pwr.curr_load = pwr.curr_load - amount
			pwr.min_load = math.min(pwr.min_load, pwr.curr_load)
			pwr.consumed = pwr.consumed + amount
			Power[netID] = pwr
			return amount
		else
			local consumed = pwr.curr_load
			pwr.curr_load = 0
			pwr.min_load = 0
			pwr.consumed = pwr.consumed + consumed
			Power[netID] = pwr
			return consumed
		end
	end
	return 0
end

-------------------------------------------------------------------------------
-- Generator
-------------------------------------------------------------------------------
-- amount is the maximum power, the generator can provide.
-- cp1 and cp2 are control points for the charge regulator.
-- From cp1 the charging power is reduced more and more and reaches zero at cp2.
function networks.power.provide_power(pos, tlib2, outdir, amount, cp1, cp2)
	local netID = networks.get_netID(pos, tlib2, outdir)
	if netID then
		local pwr = Power[netID] or get_power_data(pos, tlib2, outdir)
		local x = pwr.curr_load / pwr.max_capa
		
		pwr.available = pwr.available + amount
		amount = math.min(amount, pwr.max_capa - pwr.curr_load)
		cp1 = cp1 or 0.5
		cp2 = cp2 or 1.0
		
		if x < cp1 then  -- charge with full power
			pwr.curr_load = pwr.curr_load + amount
			pwr.max_load = math.max(pwr.max_load, pwr.curr_load)
			pwr.provided = pwr.provided + amount
			Power[netID] = pwr
			return amount
		elseif x < cp2 then  -- charge with reduced power
			local factor = 1 - ((x - cp1) / (cp2 - cp1))
			local provided = amount * factor
			pwr.curr_load = pwr.curr_load + provided
			pwr.max_load = math.max(pwr.max_load, pwr.curr_load)
			pwr.provided = pwr.provided + provided
			Power[netID] = pwr
			return provided
		else  -- turn off
			return 0
		end
	end
	return 0
end

-------------------------------------------------------------------------------
-- Storage
-------------------------------------------------------------------------------
-- Function returns a table with storage level as ratio (0..1) and the
-- charging state (1 = charging, -1 = uncharging, or 0)
-- Param outdir is optional
-- Function provides nil if no network is available
function networks.power.get_storage_data(pos, tlib2, outdir)
	for _,outdir in ipairs(networks.get_outdirs(pos, tlib2, outdir)) do
		local netID = networks.get_netID(pos, tlib2, outdir)
		if netID then
			local pwr = Power[netID] or get_power_data(pos, tlib2, outdir)
			local charging = (pwr.provided > pwr.consumed and 1) or (pwr.provided < pwr.consumed and -1) or 0
			return {level = pwr.curr_load / pwr.max_capa, charging = charging}
		end
	end
end

-- To be called for each network storage change (turn on/off of storage/generator nodes)
function networks.power.start_storage_calc(pos, tlib2, outdir)
	for _,outdir in ipairs(networks.get_outdirs(pos, tlib2, outdir)) do
		local netID = networks.get_netID(pos, tlib2, outdir)
		if netID then
			Power[netID] = nil
		end
	end
end

-------------------------------------------------------------------------------
-- Switch
-------------------------------------------------------------------------------
function networks.power.turn_switch_on(pos, tlib2, name_off, name_on)
	local node = N(pos)
	local meta = M(pos)
	if node.name == name_off then
		node.name = name_on
		minetest.swap_node(pos, node)
		tlib2:after_place_tube(pos)
		meta:set_int("networks_nodename", node.param2)
		return true
	elseif meta:contains("networks_param2_copy") then
		meta:set_int("networks_param2", meta:get_int("networks_param2_copy"))
		tlib2:after_place_tube(pos)
		return true
	end
end

function networks.power.turn_switch_off(pos, tlib2, name_off, name_on)
	local node = N(pos)
	local meta = M(pos)
	if node.name == name_on then
		node.name = name_off
		minetest.swap_node(pos, node)
		meta:set_int("networks_param2", 0)
		tlib2:after_dig_tube(pos, node)
		return true
	elseif meta:contains("networks_param2") then
		meta:set_int("networks_param2_copy", meta:get_int("networks_param2"))
		meta:set_int("networks_param2", 0)
		tlib2:after_dig_tube(pos, node)
		return true
	end
end

-------------------------------------------------------------------------------
-- Statistics
-------------------------------------------------------------------------------
function networks.power.get_network_data(pos, tlib2, outdir)
	for _,outdir in ipairs(networks.get_outdirs(pos, tlib2, outdir)) do
		local netID = networks.get_netID(pos, tlib2, outdir)
		if netID then
			local pwr = Power[netID] or get_power_data(pos, tlib2, outdir)
			local res = {
				curr_load = pwr.curr_load,
				min_load = pwr.min_load, 
				max_load = pwr.max_load, 
				max_capa = pwr.max_capa,
				consumed = pwr.consumed,
				provided = pwr.provided,
				available = pwr.available,
				netw_num = networks.netw_num(netID),
			}
			pwr.consumed = 0
			pwr.provided = 0
			pwr.available = 0
			return res
		end
	end
end

function networks.power.reset_min_max_load_values(pos, tlib2, outdir)
	for _,outdir in ipairs(networks.get_outdirs(pos, tlib2, outdir)) do
		local netID = networks.get_netID(pos, tlib2, outdir)
		if netID then
			local pwr = Power[netID] or get_power_data(pos, tlib2, outdir)
			pwr.min_load = pwr.curr_load
			pwr.max_load = pwr.curr_load
			return
		end
	end
end
