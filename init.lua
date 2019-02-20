replacer = {
    -- 2x MkII drill.
    charge = 400000,
    -- Nodes that can be replaced per full charge.
    nodes = 3000,
    -- Maximum square mode.
    max_square = 3,
    blacklist = {},
}

-- Calculate per-node charge.
replacer.per = replacer.charge / replacer.nodes

-- Blacklisted nodes cannot be placed by the tool.
function replacer.register_blacklisted_node(name)
    replacer.blacklist[name] = true
end

-- Builtin blacklist.
replacer.register_blacklisted_node("air")
replacer.register_blacklisted_node("ignore")

local name = {
	"Node",
	"3x3",
	"5x5",
}

for i=1,replacer.max_square do
	for _,place in ipairs((i == 1) and {false, true} or {false}) do
		local ncur = "replacer:replacer" .. i
		local nnext = "replacer:replacer" .. ((i == replacer.max_square) and 1 or (i + 1))
		local desc = "Node Replacer (" .. (name[i] or "Square " .. i) .. ")"
		if place then
			ncur = "replacer:replacer_p"
			nnext = "replacer:replacer_p"
			desc = "Node Replacer (Place)"
		end

		technic.register_power_tool(ncur, replacer.charge)

		local function handle_meta(s, node)
			local meta = minetest.deserialize(s:get_metadata())
			if not meta or not meta.charge then
				meta = {
					charge = 0,
				}
			end
			-- Set item from available sources, revert to default:cobble if no other node is specified.
			meta.item = node or ((meta.item and meta.item.name) and meta.item) or {name = "default:cobble", param1 = 0, param2 = 0}
			s:set_metadata(minetest.serialize(meta))
			s:get_meta():set_string("description", minetest.registered_items[s:get_name()].description .. " (" .. meta.item.name .. " " .. (meta.item.param1 or 0) .. " " .. (meta.item.param2 or 0) .. ")")
			return s, meta.item
		end

		minetest.register_tool(ncur, {
			description = desc,
			inventory_image = "replacer_replacer.png^technic_tool_mode" .. i .. ".png",
			wield_image = "replacer_replacer.png",
			liquids_pointable = true,
			groups = {not_in_creative_inventory = (i == 1) and 0 or 1},

			wear_represents = "technic_RE_charge",
			on_refill = technic.refill_RE_charge,

			on_place = function(itemstack, user, pointed_thing)
				local name = user:get_player_name()

				if user:get_player_control().aux1 then
					itemstack:set_name(place and "replacer:replacer1" or "replacer:replacer_p")
					itemstack = handle_meta(itemstack)
					minetest.chat_send_player(name, minetest.registered_items[itemstack:get_name()].description)
					return itemstack
				end

				local function set_node()
					if pointed_thing.type ~= "node" then
						minetest.chat_send_player(name, "Error: No node selected.")
						return
					end

					local pos = minetest.get_pointed_thing_position(pointed_thing)
					local node = minetest.get_node(pos)

					if replacer.blacklist[node.name] then
						minetest.chat_send_player(name, "You cannot use that node in a replacer.")
						return
					end

					-- Handle meta, setting item to pointed node.
					local item
					itemstack, item = handle_meta(itemstack, node)
					-- Send alert to player about change.
					minetest.chat_send_player(name, "Node Replacer: " .. item.name)
					return itemstack
				end

				if user:get_player_control().sneak then
					if place then
						return set_node()
					else
						itemstack:set_name(nnext)
						itemstack = handle_meta(itemstack)
						minetest.chat_send_player(name, minetest.registered_items[nnext].description)
						return itemstack
					end
				end

				if place then
					return minetest.registered_items[ncur].on_use(itemstack, user, pointed_thing, true)
				else
					return set_node()
				end
			end,

			on_use = function(itemstack, user, pointed_thing, do_place)
				local name = user:get_player_name()
				local _,item = handle_meta(itemstack)

				if pointed_thing.type ~= "node" then
					minetest.chat_send_player(name, "Error: No node selected")
					return
				end

				local pos = minetest.get_pointed_thing_position(pointed_thing, do_place)
				local node = minetest.get_node_or_nil(pos)

				if not node then
					minetest.chat_send_player(name, "Error: Node not yet loaded.")
					return
				end

				local look = user:get_look_dir()
				local extreme = "x"
				for _,c in ipairs{"y", "z"} do
					if math.abs(look[c]) > math.abs(look[extreme]) then
						extreme = c
					end
				end

				local coords = {
					x = true,
					y = true,
					z = true,
				}

				coords[extreme] = nil

				local r = vector.new()
				for c in pairs(coords) do
					r[c] = i - 1
				end
				local nodes = minetest.find_nodes_in_area(vector.subtract(pos, r), vector.add(pos, r), {node.name})

				-- Check for nodes in user's inventory.
				local inv = user:get_inventory()
				local old = inv:get_list("main")
				for i=1,#nodes do
					if not inv:contains_item("main", ItemStack(item.name)) then
						inv:set_list("main", old)
						minetest.chat_send_player(name, "Error: Inventory does not contain necessary items.")
						return
					end
					inv:remove_item("main", ItemStack(item.name))
				end
				inv:set_list("main", old)

				-- Handle charge.
				local meta = minetest.deserialize(itemstack:get_metadata())
				if meta.charge >= replacer.per * #nodes then
					meta.charge = meta.charge - replacer.per * #nodes
					technic.set_RE_wear(itemstack, meta.charge, replacer.charge)
				else
					return
				end
				itemstack:set_metadata(minetest.serialize(meta))

				local function run(pos, node)
					-- Check protection for position.
					if minetest.is_protected(pos, user:get_player_name()) then
						return
					end

					if not do_place then
						-- Dig node as user.
						minetest.node_dig(pos, node, user)
					end

					-- Update and ensure node has been removed.
					node = minetest.get_node(pos)
					if node.name ~= "air" then
						return
					end

					-- Remove item.
					inv:remove_item("main", ItemStack(item.name))

					-- Place item (adding y+1 will ensure we get placed at pos).
					minetest.place_node(vector.add(pos, vector.new(0, 1, 0)), item)
					-- Swap params in for correct rotation.
					minetest.swap_node(pos, item)
				end

				for _,pos in ipairs(nodes) do
					run(pos, minetest.get_node(pos))
				end

				return itemstack
			end,
		})
	end
end

minetest.register_alias("replacer:replacer", "replacer:replacer1")

for _,drill in ipairs{"", "_1", "_2", "_3", "_4", "_5"} do
    minetest.register_craft({
        output = "replacer:replacer1",
        recipe = {
            {"technic:diamond_drill_head", "technic:mining_drill_mk3" .. drill, "technic:diamond_drill_head"},
            {"technic:stainless_steel_ingot", "technic:motor", "technic:stainless_steel_ingot"},
            {"pipeworks:filter", "technic:blue_energy_crystal", "default:copper_ingot"},
        }
    })
end
