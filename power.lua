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

local DEFAULT_CAPA = 100
local Power = {}  -- {netID = {curr_load, max_capa}}

-- Determine load and capa for all network storage systems
local function get_storage_load(pos, tlib2, outdir)
	local netw = networks.get_network_table(pos, tlib2, outdir)
	local max_capa = DEFAULT_CAPA
	local curr_load = 0
	for _,item in ipairs(netw.sto or {}) do
		local ndef = minetest.registered_nodes[N(item.pos).name]
		local cload, mcapa = ndef.get_storage_load(item.pos)
		curr_load = curr_load + cload
		max_capa = max_capa + mcapa
	end
	return {curr_load = curr_load, max_capa = max_capa}
end

-- Function checks for a power grid, not for enough power
-- For consumers, outdir is optional
function networks.power_available(pos, tlib2, outdir)
	for _,outdir in ipairs(networks.get_outdirs(pos, tlib2, outdir)) do
		local netID = networks.get_netID(pos, tlib2, outdir, "gen")
		if netID then
			local pwr = Power[netID] or get_storage_load(pos, tlib2, outdir)
			return pwr.curr_load > 0
		end
	end
end

-- For consumers, outdir is optional
function networks.consume_power(pos, tlib2, outdir, amount)
	for _,outdir in ipairs(networks.get_outdirs(pos, tlib2, outdir)) do
		local netID = networks.get_netID(pos, tlib2, outdir, "gen")
		if netID then
			local pwr = Power[netID] or get_storage_load(pos, tlib2, outdir)
			if pwr.curr_load >= amount then
				pwr.curr_load = pwr.curr_load - amount
				Power[netID] = pwr
				return amount
			else
				local consumed = pwr.curr_load
				pwr.curr_load = 0
				Power[netID] = pwr
				return consumed
			end
		end
	end
	return 0
end

-- amount is the maximum power, the generator can provide.
-- cp1 and cp2 are control points for the charge regulator.
-- From cp1 the charging power is reduced more and more and reaches zero at cp2.
function networks.provide_power(pos, tlib2, outdir, amount, cp1, cp2)
	local netID = networks.get_netID(pos, tlib2, outdir, "gen")
	if netID then
		local pwr = Power[netID] or get_storage_load(pos, tlib2, outdir)
		local x = pwr.curr_load / pwr.max_capa
		cp1 = cp1 or 0.5
		cp2 = cp2 or 1.0
		if x < cp1 then  -- charge with full power
			pwr.curr_load = pwr.curr_load + amount
			Power[netID] = pwr
			return amount
		elseif x < cp2 then  -- charge with reduced power
			local factor = 1 - ((x - cp1) / (cp2 - cp1))
			local provided = amount * factor
			pwr.curr_load = pwr.curr_load + provided
			Power[netID] = pwr
			return provided
		else  -- turn off
			return 0
		end
	end
	return 0
end

-- Function returns the load/charge as ratio (0..1)
-- Param outdir is optional
-- Function provides nil if no network is available
function networks.get_storage_load(pos, tlib2, outdir)
	for _,outdir in ipairs(networks.get_outdirs(pos, tlib2, outdir)) do
		local netID = networks.get_netID(pos, tlib2, outdir, "gen")
		if netID then
			local pwr = Power[netID] or get_storage_load(pos, tlib2, outdir)
			return pwr.curr_load / pwr.max_capa
		end
	end
end

function networks.turn_switch_on(pos, tlib2, name_off, name_on)
	local node = N(pos)
	local meta = M(pos)
	if node.name == name_off then
		node.name = name_on
		minetest.swap_node(pos, node)
		tlib2:after_place_tube(pos)
		meta:set_int("tl2_param2", node.param2)
		return true
	elseif meta:contains("tl2_param2_copy") then
		meta:set_int("tl2_param2", meta:get_int("tl2_param2_copy"))
		tlib2:after_place_tube(pos)
		return true
	end
end

function networks.turn_switch_off(pos, tlib2, name_off, name_on)
	local node = N(pos)
	local meta = M(pos)
	if node.name == name_on then
		node.name = name_off
		minetest.swap_node(pos, node)
		tlib2:after_dig_tube(pos, node)
		meta:set_int("tl2_param2", 0)
		return true
	elseif meta:contains("tl2_param2") then
		meta:set_int("tl2_param2_copy", meta:get_int("tl2_param2"))
		meta:set_int("tl2_param2", 0)
		tlib2:i(pos, node)
		return true
	end
end
