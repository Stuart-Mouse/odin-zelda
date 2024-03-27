package main

import sdl "vendor:sdl2"
import "core:fmt"
import "core:math"
import "shared:imgui"

EditorInputKeys :: enum {
    UP,
    DOWN,
    LEFT,
    RIGHT,
    TOGGLE_TILE_PICKER,
    CAMERA_DRAG,
    FLOOD_FILL,
    COUNT,
}

editor_controller : [EditorInputKeys.COUNT] InputKey = {
    EditorInputKeys.UP                 = { sc = .UP    },
    EditorInputKeys.DOWN               = { sc = .DOWN  },
    EditorInputKeys.LEFT               = { sc = .LEFT  },
    EditorInputKeys.RIGHT              = { sc = .RIGHT },
    EditorInputKeys.TOGGLE_TILE_PICKER = { sc = .T     },
    EditorInputKeys.CAMERA_DRAG        = { sc = .SPACE },
    EditorInputKeys.FLOOD_FILL         = { sc = .F, mod = { .LCTRL, .RCTRL } },
}

EditorState : struct {
    world_screen_index  : Vec2i,
    mouse_tile_index    : i32,
    mouse_tile_position : Vector2,
    selected_type       : typeid,
    selected_entity     : Entity,
    selected_tile_id    : u32,
    hovered_tile_id     : u32,
    show_tile_picker    : bool,
    camera              : Vector2,
    tile_unit           : f32
}

/*
    TODO: implement a stack allocator for undo / redo?
*/
update_editor :: proc() {
    using EditorState
    using EditorInputKeys
    update_input_controller(editor_controller[:])

    CAMERA_MOVE_SPEED :: 0.2

    if bool(editor_controller[UP].state & KEYSTATE_PRESSED) {
        camera.y -= CAMERA_MOVE_SPEED
    }
    if bool(editor_controller[DOWN].state & KEYSTATE_PRESSED) {
        camera.y += CAMERA_MOVE_SPEED
    }
    if bool(editor_controller[LEFT].state & KEYSTATE_PRESSED) {
        camera.x -= CAMERA_MOVE_SPEED
    }
    if bool(editor_controller[RIGHT].state & KEYSTATE_PRESSED) {
        camera.x += CAMERA_MOVE_SPEED
    }

    if bool(editor_controller[CAMERA_DRAG].state & KEYSTATE_DOWN) {
        mouse_tile_velocity := pixel_to_internal_units(
            pixel_position = Mouse.velocity, 
            internal_unit  = tile_unit, 
        )
        camera -= mouse_tile_velocity
    }

    if Mouse.wheel.x != 0 {
        tile_unit = clamp(tile_unit + f32(Mouse.wheel.x), 16, 32)
    }

    if Mouse.wheel.y != 0 {
        selected_tile_id = cast(u32)clamp(int(selected_tile_id) + int(Mouse.wheel.y), 0, int(len(tile_info_lookup)-1))
    }

    // get mouse position in the game world
    mouse_tile_position = pixel_to_internal_units(
        pixel_position  = Mouse.position, 
        internal_unit   = tile_unit, 
        internal_offset = camera,
    )
    // figure out which screen the mouse is inside
    world_screen_index = {
        i32(mouse_tile_position.x) / (SCREEN_TILE_WIDTH ),
        i32(mouse_tile_position.y) / (SCREEN_TILE_HEIGHT),
    }
    // get the focused screen
    screen := get_world_screen(world_screen_index.x, world_screen_index.y)

    // get mouse tile position relative to the focused screen
    mouse_tile_position -= { 
        f32(world_screen_index.x * SCREEN_TILE_WIDTH ),
        f32(world_screen_index.y * SCREEN_TILE_HEIGHT),
    }
    // get the index of the hovered tile in the tilemap
    mouse_tile_index = get_grid_index_checked(
        position    = mouse_tile_position, 
        tile_size = { 1, 1 }, 
        grid_size = { SCREEN_TILE_WIDTH, SCREEN_TILE_HEIGHT },
    )

    // if Mouse.right == KEYSTATE_PRESSED {
    //     imgui.OpenPopup("Editor Popup", {})
    // }
    // if imgui.BeginPopup("Editor Popup", {}) {
    //     if imgui.Button("Clear All Entities on Screen") {
    //         screen.entities = {}
    //         imgui.CloseCurrentPopup()
    //     }
    //     imgui.EndPopup()
    // }

    if Mouse.right == KEYSTATE_PRESSED {
        for &slot in screen.entities.slots {
            e     := &slot.data
            frect := get_entity_collision_frect(e^)
            if is_point_within_frect(mouse_tile_position, frect) {
                slot = {}
            }
        }
    }

    if !(world_screen_index.x < 0 || world_screen_index.x >= game_world.size.x ||
         world_screen_index.y < 0 || world_screen_index.y >= game_world.size.y) {
        if Mouse.middle == KEYSTATE_PRESSED {
            tile := get_tile(&screen.tilemap, mouse_tile_index)
            if tile != nil do selected_tile_id = tile.id
        }

        if Mouse.left & KEYSTATE_PRESSED != 0 {
            if selected_type == Tile {
                tile := get_tile(&screen.tilemap, mouse_tile_index)
                if tile != nil {
                    // TODO: add bucket fill
                    if .LCTRL in sdl.GetModState() {
                        flood_fill_tiles(
                            &screen.tilemap, 
                            { id = selected_tile_id }, 
                            tile^, 
                            i32(mouse_tile_position.x), 
                            i32(mouse_tile_position.y),
                        )
                    } else {
                        tile^ = { id = selected_tile_id }
                    }
                }
            }
            else if selected_type == Entity && Mouse.left == KEYSTATE_PRESSED {
                slot := get_next_empty_slot(&screen.entities)
                if slot != nil {
                    slot.occupied = true
                    slot.data = selected_entity
                    slot.data.base.position = {
                        snap_to_nearest_unit(mouse_tile_position.x, 0.5),
                        snap_to_nearest_unit(mouse_tile_position.y, 0.5),
                    }
                }
            }
        }
    }

    if editor_controller[TOGGLE_TILE_PICKER].state == KEYSTATE_PRESSED {
        show_tile_picker = !show_tile_picker
    }
    if show_tile_picker {
        flags : imgui.WindowFlags = { .NoNavInputs, .NoTitleBar, .NoCollapse, .NoMove }
        viewport : ^imgui.Viewport = imgui.GetMainViewport()
        imgui.SetNextWindowPos(viewport.Pos, .Always)
        imgui.SetNextWindowSize(viewport.Size, .Always)
        imgui.SetNextWindowBgAlpha(0.8)
        if imgui.Begin("Tile Picker", &show_tile_picker, flags) {
            img_size, img_uv0, img_uv1 : imgui.Vec2
            imgui.SeparatorText("Tiles")
            
            for tile_id in 1..<len(tile_info_lookup) {
                tile_info := tile_info_lookup[tile_id]
                tri := get_tile_render_info({ id = u32(tile_id) })
                if tile_id % 24 != 1 do imgui.SameLine()
                img_size = { 16, 16 }
                img_uv0    = { 
                    f32(tri.clip.x) / f32(tiles_texture.width ), 
                    f32(tri.clip.y) / f32(tiles_texture.height),
                }
                img_uv1    = img_uv0 + { 
                    f32(tri.clip.w) / f32(tiles_texture.width ), 
                    f32(tri.clip.h) / f32(tiles_texture.height),
                }

                border_color : imgui.Vec4 = (u32(tile_id) == selected_tile_id) ? { 1, 1, 1, 1 } : { 0, 0, 0, 0.5 }
                imgui.ImageEx(tiles_texture.sdl_texture, img_size, img_uv0, img_uv1, { 1, 1, 1, 1 }, border_color)
                if imgui.IsItemClicked() {
                    selected_type    = Tile
                    selected_tile_id = u32(tile_id)
                }
                imgui.SetItemTooltip(cstring(&tile_info.name[0]))
            }
            
            imgui.SeparatorText("Entities")
            img_uv0 = { 
                0 / f32(tiles_texture.width ), 
                0 / f32(tiles_texture.height),
            }
            img_uv1 = img_uv0 + { 
                16 / f32(tiles_texture.width ), 
                16 / f32(tiles_texture.height),
            }
            if imgui.ImageButtonEx("Octorock", entities_texture.sdl_texture, img_size, img_uv0, img_uv1, {}, { 1, 1, 1, 1 }) {
                selected_type     = Entity
                init_entity(&selected_entity, .OCTOROCK)
            }
            img_uv0 = { 
                 0 / f32(tiles_texture.width ), 
                16 / f32(tiles_texture.height),
            }
            img_uv1 = img_uv0 + { 
                16 / f32(tiles_texture.width ), 
                16 / f32(tiles_texture.height),
            }
            imgui.SameLine()
            if imgui.ImageButtonEx("Moblin", entities_texture.sdl_texture, img_size, img_uv0, img_uv1, {}, { 1, 1, 1, 1 }) {
                selected_type = Entity
                init_entity(&selected_entity, .MOBLIN)
            }
            imgui.End()
        }
    }
}

render_editor :: proc() {
    using EditorState

    sdl.RenderSetViewport(renderer, nil)
    sdl.SetRenderDrawColor(renderer, 0x22, 0x22, 0x22, 0xff)
    sdl.RenderClear(renderer)
    sdl.SetRenderDrawBlendMode(renderer, .BLEND)

    // draw focused screen and neighboring screens
    for i in 0..=game_world.size.y {
        for j in 0..=game_world.size.x {
            screen := get_world_screen(j, i)
            if screen == nil do continue

            // draw background rect for the screen
            sdl.SetRenderDrawColor(renderer, 0x00, 0x00, 0x00, 0xff)
            sdl.RenderFillRect(renderer, &{ 
                x = i32((f32(j * SCREEN_TILE_WIDTH ) - camera.x) * tile_unit), 
                y = i32((f32(i * SCREEN_TILE_HEIGHT) - camera.y) * tile_unit), 
                w = i32(SCREEN_TILE_WIDTH    * tile_unit), 
                h = i32(SCREEN_TILE_HEIGHT * tile_unit), 
            })

            // draw the screen's contents
            render_world_screen(screen, tile_unit, {
                f32(j * SCREEN_TILE_WIDTH ) - camera.x, 
                f32(i * SCREEN_TILE_HEIGHT) - camera.y, 
            })

            // draw a rectangle around the screen
            // focused screen is a different color
            if world_screen_index == { j, i } {
                sdl.SetRenderDrawColor(renderer, 0xff, 0x00, 0xff, 0xff)
            } else {
                sdl.SetRenderDrawColor(renderer, 0x88, 0x88, 0x88, 0xff)
            }
            sdl.RenderDrawRect(renderer, &{ 
                x = i32((f32(j * SCREEN_TILE_WIDTH ) - camera.x) * tile_unit), 
                y = i32((f32(i * SCREEN_TILE_HEIGHT) - camera.y) * tile_unit), 
                w = i32(SCREEN_TILE_WIDTH    * tile_unit), 
                h = i32(SCREEN_TILE_HEIGHT * tile_unit), 
            })
        }
    }

    base_render_offset := Vector2 {
        f32(SCREEN_TILE_WIDTH    * world_screen_index.x) - camera.x,
        f32(SCREEN_TILE_HEIGHT * world_screen_index.y) - camera.y,
    }

    // draw a preview of the tile the mouse will place
    if selected_type == Tile {
        if mouse_tile_position.x >= 0 && mouse_tile_position.x < SCREEN_TILE_WIDTH &&
             mouse_tile_position.y >= 0 && mouse_tile_position.y < SCREEN_TILE_HEIGHT {
            
            mouse_preview_tile_rect : sdl.Rect = {
                x = i32((math.floor(mouse_tile_position.x) + base_render_offset.x) * tile_unit),
                y = i32((math.floor(mouse_tile_position.y) + base_render_offset.y) * tile_unit),
                w = i32(tile_unit),
                h = i32(tile_unit),
            };

            tile := &Tile { id = selected_tile_id }
            if (tile.id != 0) {
                tri := get_tile_render_info(tile^)
                sdl.SetTextureColorMod(tri.texture, tri.color_mod.r, tri.color_mod.g, tri.color_mod.b)
                sdl.SetTextureAlphaMod(tri.texture, 0xbb)
                sdl.RenderCopy(renderer, tri.texture, &tri.clip, &mouse_preview_tile_rect)
            }

            // draw outline around the tile
            mouse_preview_tile_rect.x -= 1
            mouse_preview_tile_rect.y -= 1
            mouse_preview_tile_rect.w += 2
            mouse_preview_tile_rect.h += 2
            sdl.SetRenderDrawColor(renderer, 0x00, 0x00, 0xff, 0xff)
            sdl.RenderDrawRect(renderer, &mouse_preview_tile_rect)
        }
    } else if selected_type == Entity {
        render_entity(selected_entity, tile_unit, {
            snap_to_nearest_unit(mouse_tile_position.x, 0.5) + f32(base_render_offset.x),
            snap_to_nearest_unit(mouse_tile_position.y, 0.5) + f32(base_render_offset.y),
        })
    }
}

flood_fill_tiles :: proc(tilemap: ^Tilemap, new, orig: Tile, x, y: i32) {
    if new.id == orig.id do return
    tile := get_tile(tilemap, x, y)
    if tile == nil || tile.id != orig.id do return

    tile^ = new
    flood_fill_tiles(tilemap, new, orig, x + 1, y        )
    flood_fill_tiles(tilemap, new, orig, x - 1, y        )
    flood_fill_tiles(tilemap, new, orig, x        , y + 1)
    flood_fill_tiles(tilemap, new, orig, x        , y - 1)
}