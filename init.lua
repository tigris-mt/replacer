replacer = {
    -- Same as MkII drill.
    charge = 200000,
    -- Nodes that can be replaced per full charge.
    nodes = 1000,
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

technic.register_power_tool("replacer:replacer", replacer.charge)

local function handle_meta(s, node)
    local meta = minetest.deserialize(s:get_metadata())
    if not meta or not meta.charge then
        meta = {
            charge = 0,
        }
    end
    -- Set item from available sources, revert to default:cobble if no other node is specified.
    meta.item = node or meta.item or {name = "default:cobble", param1 = 0, param2 = 0}
    s:set_metadata(minetest.serialize(meta))
    s:get_meta():set_string("description", "Node Replacer (" .. meta.item.name .. ")")
    return s, meta.item
end

minetest.register_tool("replacer:replacer", {
    description = "Node Replacer",
    inventory_image = "replacer_replacer.png",
    liquids_pointable = true,

    wear_represents = "technic_RE_charge",
    on_refill = technic.refill_RE_charge,

    on_place = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()

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
    end,

    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        local _,item = handle_meta(itemstack)

        if pointed_thing.type ~= "node" then
            minetest.chat_send_player(name, "Error: No node selected")
            return
        end

        local pos = minetest.get_pointed_thing_position(pointed_thing)
        local node = minetest.get_node_or_nil(pos)

        if not node then
            minetest.chat_send_player(name, "Error: Node not yet loaded.")
            return
        end

        -- Check for node in user's inventory.
        local inv = user:get_inventory()
        if not inv:contains_item("main", ItemStack(item.name)) then
            minetest.chat_send_player(name, "Error: Inventory does not contain necessary items.")
            return
        end

        -- Handle charge.
        local meta = minetest.deserialize(itemstack:get_metadata())
        if meta.charge >= replacer.per then
            meta.charge = meta.charge - replacer.per
            technic.set_RE_wear(itemstack, meta.charge, replacer.charge)
        else
            return
        end
        itemstack:set_metadata(minetest.serialize(meta))

        -- Dig node as user.
        minetest.node_dig(pos, node, user)

        -- Update and ensure node has been removed.
        node = minetest.get_node(pos)
        if node.name ~= "air" then
            minetest.chat_send_player(name, "Error: Unable to clear position.")
            return itemstack
        end

        -- Remove item.
        inv:remove_item("main", ItemStack(item.name))

        -- Place item (adding y+1 will ensure we get placed at pos).
        minetest.place_node(vector.add(pos, vector.new(0, 1, 0)), item)
        -- Swap params in for correct rotation.
        minetest.swap_node(pos, item)

        return itemstack
    end,
})

minetest.register_craft({
    output = 'replacer:replacer',
    recipe = {
        {'default:tin_ingot', 'technic:diamond_drill_head', 'default:tin_ingot'},
        {'technic:stainless_steel_ingot', 'technic:motor', 'technic:stainless_steel_ingot'},
        {'pipeworks:filter', 'technic:green_energy_crystal', 'default:copper_ingot'},
    }
})
