--[[

	Networks
	========

	Copyright (C) 2021 Joachim Stolberg

	AGPL v3
	See LICENSE.txt for more information

]]--


-- Networks definition table for each node definition
--
--	networks = {
--      ele3 = {                        -- network type
--          sides = networks.AllSides,  -- node connection sides
--          ntype = "con",              -- node type (one of "con", "gen", "sto", "junc", or others)
--      },
--	}

-- for lazy programmers
local S2P = minetest.string_to_pos
local P2S = function(pos) if pos then return minetest.pos_to_string(pos) end end
local M = minetest.get_meta
local N = tubelib2.get_node_lvm

local Networks = {} -- cache for networks: {netw_type = {netID = <network>, ...}, ...}
local NetIDs = {}   -- cache for netw IDs: {pos_hash = {outdir = netID, ...}, ...}

local MAX_NUM_NODES = 1000
local TTL = 5 * 60  -- 5 minutes
local Route = {} -- Used to determine the already passed nodes while walking
local NumNodes = 0
local DirToSide = {"B", "R", "F", "L", "D", "U"}
local Sides = {B = true, R = true, F = true, L = true, D = true, U = true}
local SideToDir = {B=1, R=2, F=3, L=4, D=5, U=6}
local Flip = {[0]=0,3,4,1,2,6,5} -- 180 degree turn

-------------------------------------------------------------------------------
-- Debugging
-------------------------------------------------------------------------------

-- Maintain simple numbers for the bulky netID hashes
local DbgNetIDs = {}
local DbgCounter = 1

local function netw_num(netID)
	if not DbgNetIDs[netID] then
		DbgNetIDs[netID] = DbgCounter
		DbgCounter = DbgCounter + 1
	end
	return DbgNetIDs[netID]
end
	
local function debug()
	local t = Networks["test"] or {}
	for  netID, network in pairs(t) do
		local tbl = {}
		for node_type,table in pairs(network) do
			if type(table) == "table" then
				tbl[#tbl+1] = "#" .. node_type .. " = " .. #table
			end
		end
		tbl[#tbl+1] = "num_nodes = " .. network.num_nodes
		print("Network " .. netw_num(netID) .. ": " .. table.concat(tbl, ", "))
		
		
		for hash, item in pairs(NetIDs) do
			tbl = {}
			for dir = 0,6 do
				netID = item[dir]
				if netID then
					tbl[#tbl+1] = "dir " .. dir .. " = netw " .. netw_num(netID)
				end
			end
			print("NetIDs " .. N(minetest.get_position_from_hash(hash)).name .. ": " .. table.concat(tbl, ", "))
		end
	end
	minetest.after(4, debug)
end
minetest.after(4, debug)

-------------------------------------------------------------------------------
-- Helper
-------------------------------------------------------------------------------
local function hidden_node(pos, netw_type)
	-- legacy name
	local name = M(pos):get_string("techage_hidden_nodename")
	local ndef = minetest.registered_nodes[name]
	if ndef and ndef.networks then
		return ndef.networks[netw_type] or {} 
	end
	-- new name
	name = M(pos):get_string("tl2_hidden_nodename")
	ndef = minetest.registered_nodes[name]
	if ndef and ndef.networks then
		return ndef.networks[netw_type] or {} 
	end
	return {}
end

-- return the networks table from the node definition
local function net_def(pos, netw_type) 
	local ndef = minetest.registered_nodes[N(pos).name]
	if ndef and ndef.networks then
		return ndef.networks[netw_type] or {} 
	else  -- hidden junction
		return hidden_node(pos, netw_type)
	end
end

local function net_def2(pos, node_name, netw_type) 
	local ndef = minetest.registered_nodes[node_name]
	if ndef and ndef.networks then
		return ndef.networks[netw_type] or {} 
	else  -- hidden junction
		return hidden_node(pos, netw_type)
	end
end

local function connected(tlib2, pos, dir)
	local param2, npos = tlib2:get_primary_node_param2(pos, dir)
	if param2 then
		local d1, d2, num = tlib2:decode_param2(npos, param2)
		if not num then return end
		return Flip[dir] == d1 or Flip[dir] == d2
	end
	-- secondary nodes allowed?
	if tlib2.force_to_use_tubes then
		return tlib2:is_special_node(pos, dir)
	else
		return tlib2:is_secondary_node(pos, dir)
	end
	return false
end

-- Calculate the node outdir based on node.param2 and nominal dir (according to side)
local function dir_to_outdir(dir, param2)
	if dir < 5 then
		return ((dir + param2 - 1) % 4) + 1
	end
	return dir
end

local function indir_to_dir(indir, param2)
	if indir < 5 then
		return ((indir - param2 + 5) % 4) + 1
	end
	return Flip[indir]
end

local function outdir_to_dir(outdir, param2)
	if outdir < 5 then
		return ((outdir - param2 + 3) % 4) + 1
	end
	return outdir
end

local function side_to_outdir(pos, side)
	return dir_to_outdir(SideToDir[side], N(pos).param2)
end

-- determine outdir based on node type
local function get_outdir(node_type, indir)
	if node_type == "junc" then
		return 0 -- same network on all sides
	else
		return Flip[indir]
	end
end

-------------------------------------------------------------------------------
-- Node Connections
-------------------------------------------------------------------------------

-- Get tlib2 connection dirs as table
-- used e.g. for the connection walk
local function get_node_connection_dirs(pos, netw_type)
	local val = M(pos):get_int(netw_type.."_conn")
    local tbl = {}
    if val % 0x40 >= 0x20 then tbl[#tbl+1] = 1 end
    if val % 0x20 >= 0x10 then tbl[#tbl+1] = 2 end
    if val % 0x10 >= 0x08 then tbl[#tbl+1] = 3 end
    if val % 0x08 >= 0x04 then tbl[#tbl+1] = 4 end
    if val % 0x04 >= 0x02 then tbl[#tbl+1] = 5 end
    if val % 0x02 >= 0x01 then tbl[#tbl+1] = 6 end
    return tbl
end

-- store all node sides with tube connections as nodemeta
local function store_node_connection_sides(pos, tlib2)
	local node = N(pos)
	local val = 0
	local ndef = net_def2(pos, node.name, tlib2.tube_type)
	local sides = ndef.sides or ndef.get_sides and ndef.get_sides(pos, node)
	if sides then
		for dir = 1,6 do
			val = val * 2
			local side = DirToSide[outdir_to_dir(dir, node.param2)]
			if sides[side] then
				if connected(tlib2, pos, dir) then
					val = val + 1
				end
			end
		end
		M(pos):set_int(tlib2.tube_type.."_conn", val)
	end
end

-- In outdir is given, return outdir, otherwise return all dirs with connections
local function get_outdirs(pos, tlib2, outdir)
	if outdir then
		return {outdir}
	end
	return get_node_connection_dirs(pos, tlib2.tube_type)
end

-------------------------------------------------------------------------------
-- Connection Walk
-------------------------------------------------------------------------------
local function pos_already_reached(pos)
	local key = minetest.hash_node_position(pos)
	if not Route[key] and NumNodes < MAX_NUM_NODES then
		Route[key] = true
		NumNodes = NumNodes + 1
		return false
	end
	return true
end

-- check if the given pipe dir into the node is valid
local function valid_indir(pos, indir, node, net_name)
	local ndef = net_def2(pos, node.name, net_name)
	local sides = ndef.sides or ndef.get_sides and ndef.get_sides(pos, node)
	local side = DirToSide[indir_to_dir(indir, node.param2)]
	if not sides or sides and not sides[side] then return false end
	return true
end

local function is_junction(pos, name, tube_type)
	local ndef = net_def2(pos, name, tube_type)
	return ndef.ntype == "junc"
end

-- Do the walk through the tubelib2 network.
-- `indir` is the direction which should not be covered by the walk
-- (coming from there).
-- if outdir is given, only this dir is used
local function connection_walk(pos, outdir, indir, node, tlib2, clbk)
	if clbk then clbk(pos, indir, node) end
	if outdir or is_junction(pos, node.name, tlib2.tube_type) then
		for _,outdir in ipairs(get_outdirs(pos, tlib2, outdir)) do
			local pos2, indir2 = tlib2:get_connected_node_pos(pos, outdir)
			local node = N(pos2)
			if valid_indir(pos2, indir2, node, tlib2.tube_type) and not pos_already_reached(pos2) then
				connection_walk(pos2, nil, indir2, node, tlib2, clbk)
			end
		end
	end
end

local function collect_network_nodes(pos, tlib2, outdir)
	Route = {}
	NumNodes = 0
	pos_already_reached(pos) 
	local netw = {}
	local node = N(pos)
	local netw_type = tlib2.tube_type
	-- outdir corresponds to the indir coming from
	connection_walk(pos, outdir, Flip[outdir], node, tlib2, function(pos, indir, node)
		local ntype = net_def2(pos, node.name, netw_type).ntype
		if not netw[ntype] then netw[ntype] = {} end
		netw[ntype][#netw[ntype] + 1] = {pos = pos, indir = indir}
	end)
	netw.ttl = minetest.get_gametime() + TTL
	netw.num_nodes = NumNodes
	return netw
end

-------------------------------------------------------------------------------
-- Maintain Network
-------------------------------------------------------------------------------
local function set_network(netw_type, netID, network)
	if netID then
		Networks[netw_type] = Networks[netw_type] or {}
		Networks[netw_type][netID] = network
		Networks[netw_type][netID].ttl = minetest.get_gametime() + TTL
	end
end

local function get_network(netw_type, netID)
	local netw = Networks[netw_type] and Networks[netw_type][netID]
	if netw then
		netw.ttl = minetest.get_gametime() + TTL
		return netw
	end
end

local function delete_network(netw_type, netID)
	if Networks[netw_type] and Networks[netw_type][netID] then
		Networks[netw_type][netID] = nil
	end
end

-- keep data base small and valid
local function remove_outdated_networks()
	local to_be_deleted = {}
	local t = minetest.get_gametime()
	for net_name,tbl in pairs(Networks) do
		for netID,network in pairs(tbl) do
			local valid = (network.ttl or 0) - t
			if valid < 0 then
				to_be_deleted[#to_be_deleted+1] = {net_name, netID}
			end
		end
	end
	for _,item in ipairs(to_be_deleted) do
		local net_name, netID = unpack(item)
		Networks[net_name][netID] = nil
		print("Network " .. netw_num(netID) .. " timed out")
	end
	minetest.after(60, remove_outdated_networks)
end
minetest.after(60, remove_outdated_networks)

-------------------------------------------------------------------------------
-- Maintain netID
-------------------------------------------------------------------------------

-- Return node netID and netwotk if available.
-- The function updates the network TTL, thus keeping the network alive.
local function get_netID_and_network(pos, tlib2, outdir)
	local hash = minetest.hash_node_position(pos)
	NetIDs[hash] = NetIDs[hash] or {}
	local netID = NetIDs[hash][outdir]
	
	if netID then
		return netID, get_network(tlib2.tube_type, netID)
	end
end

-- determine network ID (largest hash number of all nodes with given type)
local function determine_netID(tlib2, netw, node_type)
	local netID = 0
	for _, item in ipairs(netw[node_type] or {}) do
		local outdir = Flip[item.indir]
		local new = minetest.hash_node_position(item.pos) * 8 + outdir
		if netID <= new then
			netID = new
		end
	end
	return netID
end

-- store network ID for each network node
local function store_netID(tlib2, netw, netID)
	for node_type, table in pairs(netw) do
		if type(table) == "table" then
			for _, item in ipairs(table) do
				local hash = minetest.hash_node_position(item.pos)
				local outdir = get_outdir(node_type, item.indir)
				NetIDs[hash] = NetIDs[hash] or {}
				NetIDs[hash][outdir] = netID
			end
		end
	end
	set_network(tlib2.tube_type, netID, netw)
end

-- delete network and netID for all nodes in the network
-- `outdir` shall be 0 for junctions
local function delete_netID(pos, tlib2, outdir)
	local netID, netw = get_netID_and_network(pos, tlib2, outdir)
	if netID and netw then
		for node_type, table in pairs(netw) do
			if type(table) == "table" then
				for _, item in ipairs(table) do
					local hash = minetest.hash_node_position(item.pos)
					local outdir = get_outdir(node_type, item.indir)
					NetIDs[hash][outdir] = nil
					print("deleted")
				end
			end
		end
		delete_network(tlib2.tube_type, netID)
	end
end

-------------------------------------------------------------------------------
-- API Functions
-------------------------------------------------------------------------------

-- Table fo a 180 degree turn
networks.Flip = Flip

-- networks.net_def(pos, netw_type)
networks.net_def = net_def

networks.AllSides = Sides -- table for all 6 node sides

-- networks.side_to_outdir(pos, side)
networks.side_to_outdir = side_to_outdir

-- networks.node_connections(pos, tlib2)
--networks.node_connections = node_connections

-- networks.collect_network_nodes(pos, tlib2, outdir)
--networks.collect_network_nodes = collect_network_nodes

-- Function returns {outdir} or all node dirs with connections
-- networks.get_outdirs(pos, tlib2, outdir)
networks.get_outdirs = get_outdirs

networks.MAX_NUM_NODES = MAX_NUM_NODES

-- To be called from each node via 'tubelib2_on_update2'
-- 'output' is optional and only needed for nodes with dedicated
-- pipe sides (e.g. pumps).
function networks.update_network(pos, outdir, tlib2)
	print("update_network", P2S(pos), N(pos).name)
	store_node_connection_sides(pos, tlib2) -- update node internal data
	delete_netID(pos, tlib2, outdir or 0) -- delete node netIDs and network
end

-- Provide or determine netID
-- `node_type` is nedded to determine the netID
function networks.get_netID(pos, tlib2, outdir, node_type)
	local netID = get_netID_and_network(pos, tlib2, outdir)
	if netID then   
		return netID
	end
	
	local netw = collect_network_nodes(pos, tlib2, outdir)
	if netw.num_nodes > 1 then
		netID = determine_netID(tlib2, netw, node_type)
		if netID > 0 then
			store_netID(tlib2, netw, netID)
			return netID
		end
	end
end

-- Provide network with all node tables
function networks.get_network_table(pos, tlib2, outdir)
	local netID, netw = get_netID_and_network(pos, tlib2, outdir)
	return netw or {}
end

-- Override methods of tubelib2 to store tube/cable info as metadata.
-- This allows hidden cables/tubes/junctions/switches.
function networks.use_metadata(tlib2)
	tlib2.get_primary_node_param2 = function(self, pos, dir)
		local npos = vector.add(pos, tubelib2.Dir6dToVector[dir or 0])
		local param2 = M(npos):get_int("tl2_param2")
		if param2 ~= 0 then
			return param2, npos
		end
	end
	tlib2.is_primary_node = function(self, pos, dir)
		local npos = vector.add(pos, tubelib2.Dir6dToVector[dir or 0])
		local param2 = M(npos):get_int("tl2_param2")
		return param2 ~= 0
	end
	tlib2.get_secondary_node = function(self, pos, dir)
		local npos = vector.add(pos, tubelib2.Dir6dToVector[dir or 0])
		local node = self:get_node_lvm(npos)
		if self.secondary_node_names[node.name] or 
				self.secondary_node_names[M(npos):get_string("tl2_hidden_nodename")] or
				self.secondary_node_names[M(npos):get_string("techage_hidden_nodename")] then
			return node, npos, true
		end
	end
	tlib2.is_secondary_node = function(self, pos, dir)
		local npos = vector.add(pos, tubelib2.Dir6dToVector[dir or 0])
		local node = self:get_node_lvm(npos)
		return self.secondary_node_names[node.name] or 
				self.secondary_node_names[M(npos):get_string("tl2_hidden_nodename")] or
				self.secondary_node_names[M(npos):get_string("techage_hidden_nodename")]
	end
end

-- Function is called from `tubelib2.after_place_tube` callback
-- Handle tube/cable nodes with 'use_metadata' feature, to change only the metadata,
-- and not to replace the node.
-- Function returns true, if node still has to be replaced.
function networks.node_to_be_replaced(pos, param2, tube_type, num_tubes)
	M(pos):set_int("tl2_param2", param2)
	return M(pos):get_string("tl2_hidden_nodename") == "" and
		M(pos):get_string("techage_hidden_nodename") == ""
end
