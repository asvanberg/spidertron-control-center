local mod_gui = require("mod-gui")

-- player_index -> {home -> {unit_number -> positon}, gui -> {frame, list, visible}}
global.players = {}
-- path_request_id -> {request, spidertron}
global.path_requests = {}
-- unit_number -> entity
global.spidertrons = {}
-- unit_number -> player_index (follow player on autopiloting done)
global.follow_after_autopilot = {}

do
  local function create_player_data(player_index)
    global.players[player_index] = {
      gui = { visible = true },
      home = {}
    }
  end

  local function populate_initial_spidertrons()
    for _, surface in pairs(game.surfaces) do
      for _, spidertron in pairs(surface.find_entities_filtered({type = "spider-vehicle"})) do
        if spidertron.valid and spidertron.name ~= "companion" then
          global.spidertrons[spidertron.unit_number] = spidertron
        end
      end
    end
  end

  local function update_all_guis()
    for player_index, _ in pairs(game.players) do
      update_gui(player_index)
    end
  end

  local function mod_compatibility()
    -- Compatibility: Spidertron Weapon Switcher
    do
      if remote.interfaces["SpidertronWeaponSwitcher"] then
        local sws_events = remote.call("SpidertronWeaponSwitcher", "get_events")
        script.on_event(sws_events.on_spidertron_switched, function(event)
          local new_unit_number = event.new_spidertron.unit_number
          local old_unit_number = event.old_spidertron.unit_number

          -- Restore home position
          for _, data in pairs(global.players) do
            local old_home = data.home[old_unit_number]
            data.home[new_unit_number] = old_home
            data.home[old_unit_number] = nil
          end
          -- Restore pathing requests
          for path_request_id, target in pairs(global.path_requests) do
            if target.spidertron.unit_number == old_unit_number then
              target.spidertron = event.new_spidertron
            end
          end
          -- Update spidertron list
          global.spidertrons[new_unit_number] = event.new_spidertron
          global.spidertrons[old_unit_number] = nil

          -- Restore autofollow
          global.follow_after_autopilot[new_unit_number] = global.follow_after_autopilot[old_unit_number]
          global.follow_after_autopilot[old_unit_number] = nil

          update_all_guis()
        end)
      end
    end
  end

  script.on_init(function()
    populate_initial_spidertrons()
    for index, _ in pairs(game.players) do
      create_player_data(index)
      update_gui(index)
    end
    mod_compatibility()
  end)

  script.on_load(function()
    mod_compatibility()
  end)

  script.on_configuration_changed(function()
    global.follow_after_autopilot = {}
    for unit_number, spidertron in pairs(global.spidertrons) do
      if not spidertron.valid or spidertron.name == "companion" then
        global.spidertrons[unit_number] = nil
      end
      script.register_on_entity_destroyed(spidertron)
    end
    update_all_guis()
  end)

  script.on_event(defines.events.on_player_created, function(event)
    create_player_data(event.player_index)
    update_gui(event.player_index)
  end)

  script.on_event(defines.events.on_player_changed_surface, function(event)
    update_gui(event.player_index)
  end)

  script.on_event(defines.events.on_player_removed, function(event)
    global.players[event.player_index] = nil
  end)

  -- spidertron built
  do
    local function is_blacklisted(spidertron_entity_name)
      return spidertron_entity_name == "companion"
          or spidertron_entity_name == "spidertron-enhancements-dummy-spidertron"
    end
    local function spidertron_built(spidertron_entity)
      if is_blacklisted(spidertron_entity.name) then
        return
      end
      global.spidertrons[spidertron_entity.unit_number] = spidertron_entity
      script.register_on_entity_destroyed(spidertron_entity)
      -- TODO update only specific force/surface for performance
      update_all_guis()
    end
    script.on_event(defines.events.on_built_entity, function(event) spidertron_built(event.created_entity) end, {{filter = "type", type = "spider-vehicle"}})
    script.on_event(defines.events.script_raised_built, function(event) spidertron_built(event.entity) end, {{filter = "type", type = "spider-vehicle"}})
  end

  -- spidertron destroyed
  do
    local function spidertron_destroyed(event)
      if not event.unit_number or not global.spidertrons[event.unit_number] then
        return
      end
      global.spidertrons[event.unit_number] = nil
      -- TODO update only specific force/surface for performance
      update_all_guis()
    end
    script.on_event(defines.events.on_entity_destroyed, spidertron_destroyed)
  end

  script.on_event(defines.events.on_entity_renamed, function(event)
    -- TODO update only specific force/surface for performance
    update_all_guis()
  end)
end

do
  local function get_or_create_gui(player_index)
    local player_data = global.players[player_index]
    if not player_data.gui.frame or not player_data.gui.frame.valid then
      local frame_flow = mod_gui.get_frame_flow(game.players[player_index])
      local scc_frame = frame_flow.add({type = "frame", caption = {"frame.title"}})
      local scc_spidertron_list = scc_frame.add({type = "flow", direction = "vertical"})
      player_data.gui.frame = scc_frame
      player_data.gui.list = scc_spidertron_list
    end
    return player_data.gui
  end

  local function valid_spidertrons_for_force_and_surface(t, force, surface)
    local function iter(table, key)
      local next_key, spidertron = next(table, key)
      if spidertron == nil then
        return nil
      else
        if spidertron.valid and spidertron.force == force and spidertron.surface == surface then
          return next_key, spidertron
        else
          return iter(table, next_key)
        end
      end
    end
    return iter, t, nil
  end

  function update_gui(player_index)
    local gui = get_or_create_gui(player_index)
    local player = game.players[player_index]

    player.set_shortcut_toggled("scc-toggle-frame", gui.visible)

    gui.list.clear()

    local spidertrons_sorted_by_name = {}
    for _, spidertron in valid_spidertrons_for_force_and_surface(global.spidertrons, player.force, player.surface) do
      if not spidertron.entity_label or not spidertron.entity_label:find("^%-%-") then
        table.insert(spidertrons_sorted_by_name, spidertron)
      end
    end
    table.sort(spidertrons_sorted_by_name, function(s1, s2)
      if s1.entity_label and s2.entity_label then
        return s1.entity_label < s2.entity_label
      elseif s1.entity_label then
        return true
      elseif s2.entity_label then
        return false
      else
        return s1.unit_number < s2.unit_number
      end
    end)

    for _, spidertron in pairs(spidertrons_sorted_by_name) do
      local spidertron_flow = gui.list.add({type = "flow", direction = "horizontal"})
      spidertron_flow.style.vertical_align = "center"
      spidertron_flow.add({type = "label", caption = spidertron.entity_label or spidertron.prototype.localised_name})
      local filler = spidertron_flow.add({
        type = "empty-widget",
        ignored_by_interaction = true
      })
      filler.style.horizontally_stretchable = true
      local remote_button = spidertron_flow.add({
        type = "sprite-button",
        sprite = "item/spidertron-remote",
        tags = {["scc-action"] = "remote", ["scc-unit-number"] = spidertron.unit_number},
        tooltip = {"tooltip.remote"}
      })
      remote_button.style.height = 28
      remote_button.style.width = 28
      local come_here_button = spidertron_flow.add({
        type = "sprite-button",
        sprite = "entity/character",
        tags = {["scc-action"] = "call", ["scc-unit-number"] = spidertron.unit_number},
        tooltip = {"tooltip.call-to-player"}
      })
      come_here_button.style.height = 28
      come_here_button.style.width = 28

      local home_button = spidertron_flow.add({
        type = "sprite-button",
        sprite = "entity/assembling-machine-3",
        tags = {["scc-action"] = "home", ["scc-unit-number"] = spidertron.unit_number},
        tooltip = {"tooltip.call-to-home"}
      })
      home_button.style.height = 28
      home_button.style.width = 28

      local map_button = spidertron_flow.add({
        type = "sprite-button",
        sprite = "entity/radar",
        tags = {["scc-action"] = "window_spidertron", ["scc-unit-number"] = spidertron.unit_number},
        tooltip = {"tooltip.map-view"}
      })
      map_button.style.height = 28
      map_button.style.width = 28
    end

    -- Show frame if there's something to show
    gui.frame.visible = gui.visible and (#gui.list.children > 0)
  end
end

do
  local function get_valid_spidertron(wanted_unit_number)
    for _, spidertron in pairs(global.spidertrons) do
      if spidertron.valid and spidertron.unit_number == wanted_unit_number then
        return spidertron
      end
    end
  end

  local function go_to_position(spidertron_entity, target_position)
    local request = {
      bounding_box = {{-0.05, -0.05}, {0.05, 0.05}}, -- size of a spidertron leg
      collision_mask = {"water-tile", "colliding-with-tiles-only"},
      start = spidertron_entity.position,
      goal = target_position,
      force = spidertron_entity.force,
      pathfind_flags = {
        prefer_straight_paths = true,
        cache = false,
      }
    }
    local path_request_id = spidertron_entity.surface.request_path(request)
    global.path_requests[path_request_id] = { spidertron = spidertron_entity, request = request }
  end

  local function window_spidertron(spidertron_entity, player)
    player.open_map(spidertron_entity.position, .1)
  end

  script.on_event(defines.events.on_gui_click, function(event)
    local action = event.element.tags["scc-action"]
    if not action then
      return
    end

    local player = game.players[event.player_index]
    if not player or not player.valid then
      return
    end

    local spidertron = get_valid_spidertron(event.element.tags["scc-unit-number"])
    if not spidertron then
      return
    end

    local driver = spidertron.get_driver()
    if driver and driver.valid then
      local driving_player = driver.is_player() and driver or driver.player
      if driving_player and driving_player.valid and driving_player.index ~= player.index then
        player.create_local_flying_text({
          text = {"error.other-player-is-driving"},
          create_at_cursor = true
        })
        return
      end
    end

    if action == "window_spidertron" then
      window_spidertron(spidertron, player)
    end
    if action == "remote" then
      global.follow_after_autopilot[spidertron.unit_number] = nil
      local cursor = player.cursor_stack
      if not (cursor and cursor.valid) then
        player.create_local_flying_text({
          text = {"error.not-available-in-spectator-mode"},
          create_at_cursor = true
        })
      elseif cursor.valid_for_read then -- hand is not empty
        player.create_local_flying_text({
          text = {"error.clear-cursor"},
          create_at_cursor = true
        })
      else
        cursor.set_stack({name="scc-spidertron-remote"})
        cursor.connected_entity = spidertron
      end
    elseif action == "call" then
      go_to_position(spidertron, player.position)
      if event.shift then
        global.follow_after_autopilot[spidertron.unit_number] = event.player_index
      else
        global.follow_after_autopilot[spidertron.unit_number] = nil
      end
    elseif action == "home" then
      if event.shift then
        local cursor = player.cursor_stack
        if not (cursor and cursor.valid) then
          player.create_local_flying_text({
            text = {"error.not-available-in-spectator-mode"},
            create_at_cursor = true
          })
        elseif cursor.valid_for_read then -- hand is not empty
          player.create_local_flying_text({
            text = {"error.clear-cursor"},
            create_at_cursor = true
          })
        else
          global.players[event.player_index].setting_home_for = spidertron
          cursor.set_stack({name="scc-set-home-tool"})
        end
      else
        global.follow_after_autopilot[spidertron.unit_number] = nil
        local home_position = global.players[event.player_index].home[spidertron.unit_number]
        if home_position then
          go_to_position(spidertron, home_position)
        else
          player.create_local_flying_text({
            text = {"error.no-home-set", spidertron.entity_label or spidertron.prototype.localised_name},
            create_at_cursor = true
          })
        end
      end
    end
  end)
end

script.on_event(defines.events.on_spider_command_completed, function(event)
  local spidertron = event.vehicle
  if spidertron and spidertron.valid then
    local player_index_to_follow = global.follow_after_autopilot[spidertron.unit_number]
    if player_index_to_follow then
      local player = game.get_player(player_index_to_follow)
      if player and player.valid then
        local character = player.character
        if character and character.valid then
          spidertron.follow_target = character
        end
      end
    end
  end
end)

do
  local function deduplicate_path(start, path)
    local previous_position = start
    local deduped_path = {}
    for _, waypoint in pairs(path) do
      local position = waypoint.position
      local dx = math.abs(position.x - previous_position.x)
      local dy = math.abs(position.y - previous_position.y)
      if not (dx == 0 or dy == 0 or dx == dy) then
        table.insert(deduped_path, previous_position)
        previous_position = position
      end
    end
    table.insert(deduped_path, path[#path].position)
    return deduped_path
  end

  script.on_event(defines.events.on_script_path_request_finished, function(event)
    local path_request = global.path_requests[event.id]

    if not path_request then
      return
    else
      global.path_requests[event.id] = nil
    end

    if not event.path and event.try_again_later then
      local new_request_id = path_request.spidertron.surface.request_path(path_request.request)
      global.path_requests[new_request_id] = path_request
    else
      local spidertron = path_request.spidertron
      if event.path then
        spidertron.autopilot_destination = nil

        local deduped_path = deduplicate_path(spidertron.position, event.path)
        for _, position in pairs(deduped_path) do
          spidertron.add_autopilot_destination(position)
        end
      else
        game.print({"error.no-path-found", spidertron.entity_label or spidertron.prototype.localised_name})
      end
    end
  end)
end

do
  script.on_event(defines.events.on_player_selected_area, function(event)
    if event.item ~= "scc-set-home-tool" then return end
    local spidertron = global.players[event.player_index].setting_home_for
    if spidertron then
      local center =
        { x = (event.area.left_top.x + event.area.right_bottom.x) / 2
        , y = (event.area.left_top.y + event.area.right_bottom.y) / 2
        }
      global.players[event.player_index].home[spidertron.unit_number] = center
      global.players[event.player_index].setting_home_for = nil
      local player = game.players[event.player_index]
      player.cursor_stack.clear()
      local spidertron_name = spidertron.entity_label or spidertron.prototype.localised_name
      player.create_local_flying_text({
        text = {"feedback.new-home-set", spidertron_name},
        create_at_cursor = true
      })
    end
  end)
end

do
  local function toggle_frame(event)
    local player_data = global.players[event.player_index]
    player_data.gui.visible = not player_data.gui.visible
    local player = game.players[event.player_index]
    update_gui(event.player_index)
  end

  script.on_event("scc-toggle-frame", toggle_frame)
  script.on_event(defines.events.on_lua_shortcut, function(event)
    if event.prototype_name == "scc-toggle-frame" then
      toggle_frame(event)
    end
  end)
end
