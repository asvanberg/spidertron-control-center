local base_remote = data.raw["spidertron-remote"]["spidertron-remote"]
local scc_remote = table.deepcopy(base_remote)

scc_remote.name = "scc-spidertron-remote"

local flags = scc_remote.flags or {}
table.insert(flags, "only-in-cursor")
table.insert(flags, "hidden")
table.insert(flags, "not-stackable")
scc_remote.flags = flags

data:extend({scc_remote})

data:extend({
  -- base
  { type = "selection-tool"
  , name = "scc-set-home-tool"
  -- item
  , flags = { "hidden", "only-in-cursor", "not-stackable" }
  , stack_size = 1
  , icon = "__core__/graphics/spawn-flag.png"
  , icon_size = 64
  -- item_with_label
  -- selection_tool
  , selection_color = {1, 1, 1}
  , selection_cursor_box_type = "entity"
  , selection_mode = "nothing"
  , alt_selection_color = {1, 1, 1}
  , alt_selection_cursor_box_type = "entity"
  , alt_selection_mode = "nothing"
  }
})

data:extend({
  { type = "custom-input"
  , name = "scc-toggle-frame"
  , key_sequence = "ALT + S"
  }
})

data:extend({
  { type = "shortcut"
  , name = "scc-toggle-frame"
  , action = "lua"
  , toggleable = true
  , technology_to_unlock = "spidertron"
  , associated_control_input = "scc-toggle-frame"
  , icon =
    { filename = "__base__/graphics/technology/spidertron.png"
    , size = 256
    , mipmap_count = 4
    , flags = {"gui-icon"}
    }
  }
})
