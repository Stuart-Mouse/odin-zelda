package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:math"
import sdl "vendor:sdl2"
import imgui "shared:imgui"


tiles_texture : Texture

TILE_TEXTURE_SIZE :: 16
TILE_RENDER_SIZE  :: 32

Tile_Collision :: enum {
  NONE, 
  SOLID,
  LEDGE,
}

Tile :: struct {
  id : u32,
}

MAX_TILE_ANIM_FRAMES :: 8 

Tile_Info :: struct {
  name      : [32] u8,
  collision : Tile_Collision,

  // animations that act on a whole tile type
  animation : struct { 
    frames  : [MAX_TILE_ANIM_FRAMES] struct {
      clip_offset : Vec2i,
      duration    : i32,
    },
    frame_count   : i32 `gon_serialize_never`,
    current_frame : i32 `gon_serialize_never`,
    frame_clock   : i32 `gon_serialize_never`,
  },
}

tile_info_lookup : [dynamic] Tile_Info

get_tile_info :: proc(tile: Tile) -> ^Tile_Info {
  if tile.id < 0 && int(tile.id) >= len(tile_info_lookup) {
    fmt.println("Error: tile id was out of range.")
    return nil
  }
  return &tile_info_lookup[tile.id]
}

update_tile_animations :: proc() {
	for i in 1..<len(tile_info_lookup) {
		ti := &tile_info_lookup[i]
    using ti.animation
		if frame_count > 1 {
			frame_clock += 1
			if frame_clock >= frames[current_frame].duration {
				current_frame += 1
				frame_clock = 0
				if current_frame >= frame_count {
					current_frame  = 0
				}
			}
		}
	}
}

reset_tile_animations :: proc() {
	for i in 1..<len(tile_info_lookup) {
		ti := &tile_info_lookup[i]
		ti.animation.current_frame = 0
		ti.animation.frame_clock   = 0
	}
}

tile_dir_clips : [16] Vec2i = {
	int(Directions{}) = { 0, 0 },

	int(Directions{.U}) = { 1, 3 },
	int(Directions{.D}) = { 1, 0 },
	int(Directions{.L}) = { 3, 1 },
	int(Directions{.R}) = { 0, 1 },

	int(Directions{.U, .D}) = { 1, 2 },
	int(Directions{.U, .L}) = { 3, 3 },
	int(Directions{.U, .R}) = { 2, 3 },
	int(Directions{.D, .L}) = { 3, 2 },
	int(Directions{.D, .R}) = { 2, 2 },
	int(Directions{.L, .R}) = { 2, 1 },

	int(Directions{.U, .D, .L}) = { 0, 2 },
	int(Directions{.U, .D, .R}) = { 0, 3 },
	int(Directions{.U, .L, .R}) = { 2, 0 },
	int(Directions{.D, .L, .R}) = { 3, 0 },

	int(Directions{.U, .D, .L, .R}) = { 1, 1 },
}

Tile_Render_Info :: struct {
  texture       : ^sdl.Texture,
  clip          : sdl.Rect,
  render_offset : Vec2i,
  color_mod     : sdl.Color,
}

get_tile_render_info :: proc(tile: Tile) -> Tile_Render_Info {
  if tile.id == 0 do return {} 

  using tri : Tile_Render_Info;
  color_mod = tile.id == 0 ? {} : { 0xff, 0xff, 0xff, 0xff }

  ti := get_tile_info(tile)
  if ti == nil {
    fmt.println("Error: unable to retreive tile info.")
    return tri
  }

  tri.texture = tiles_texture.sdl_texture
  clip_offset := ti.animation.frames[ti.animation.current_frame].clip_offset

  clip = {
    x = clip_offset.x * TILE_TEXTURE_SIZE,
    y = clip_offset.y * TILE_TEXTURE_SIZE,
    w = TILE_TEXTURE_SIZE,
    h = TILE_TEXTURE_SIZE,
  }

  return tri
}

get_tile_collision :: proc(tile: Tile) -> Tile_Collision {
  return get_tile_info(tile).collision
}

SCREEN_TILE_WIDTH  :: 20
SCREEN_TILE_HEIGHT :: 15

Tilemap :: struct {
  data : [SCREEN_TILE_WIDTH * SCREEN_TILE_HEIGHT] Tile,
}

get_tile :: proc {
  get_tile_1D,
  get_tile_2D,
}

get_tile_1D :: proc(tilemap: ^Tilemap, i: i32) -> ^Tile {
  if i < 0 || i >= SCREEN_TILE_WIDTH * SCREEN_TILE_HEIGHT {
    return nil
  }
  return &tilemap.data[i]
}

get_tile_2D :: proc(tilemap: ^Tilemap, x, y: i32) -> ^Tile {
  if x < 0 || x >= SCREEN_TILE_WIDTH ||
     y < 0 || y >= SCREEN_TILE_HEIGHT {
    return nil
  }
  return &tilemap.data[y * SCREEN_TILE_WIDTH + x]
}

set_all_tiles_on_tilemap :: proc(tilemap: ^Tilemap, tile: Tile) {
  for i in 0..<SCREEN_TILE_WIDTH * SCREEN_TILE_HEIGHT {
    tilemap.data[i] = tile
  }
}

render_tilemap :: proc(tilemap: ^Tilemap, tile_render_unit: f32, offset: Vector2) {
  offset := offset * tile_render_unit

  for y: i32; y < SCREEN_TILE_HEIGHT; y += 1 {
    for x: i32; x < SCREEN_TILE_WIDTH; x += 1 {
      tile := &tilemap.data[y * SCREEN_TILE_WIDTH + x]
      if tile.id == 0 do continue

      tile_rect : sdl.FRect = {
        x = offset.x + f32(x) * tile_render_unit, 
        y = offset.y + f32(y) * tile_render_unit, 
        w = tile_render_unit,
        h = tile_render_unit,
      }

      tri := get_tile_render_info(tile^)
      sdl.SetTextureColorMod(tri.texture, tri.color_mod.r, tri.color_mod.g, tri.color_mod.b)
      sdl.SetTextureAlphaMod(tri.texture, tri.color_mod.a)
      sdl.RenderCopyF(renderer, tri.texture, &tri.clip, &tile_rect)
    }
  }
}

Tilemap_Collision_Results :: struct {
  push_out        : Directions,
	indexed_tiles	  : [Direction] ^Tile,
	points      	  : [Direction] Vector2,
	indices      	  : [Direction] Vec2i,
	resolutions	    : [Direction] Direction, // really only used for corner cases, so we can see what which primary case they resolved to
  position_adjust : Vector2,
  velocity_adjust : Vector2,
  set_velocity    : bool,
}

do_tilemap_collision :: proc(tilemap: ^Tilemap, position, size, offset: Vector2) -> Tilemap_Collision_Results {
	results : Tilemap_Collision_Results
  results.resolutions = { .U = .U, .D = .D, .L = .L, .R = .R, .UL = .UL, .UR = .UR, .DL = .DL, .DR = .DR }
  
	push_out     : Directions = {}
  push_out_dir : [4] Direction = { Direction(0), Direction(1), Direction(2), Direction(3) }

  points  : [Direction] Vector2
  indices : [Direction] Vec2i

  points[Direction.U].x = position.x + offset.x + size.x / 2
  points[Direction.U].y = position.y + offset.y
  points[Direction.D].x = position.x + offset.x + size.x / 2
  points[Direction.D].y = position.y + offset.y + size.y
  points[Direction.L].x = position.x + offset.x
  points[Direction.L].y = position.y + offset.y + size.y / 2
  points[Direction.R].x = position.x + offset.x + size.x
  points[Direction.R].y = position.y + offset.y + size.y / 2

  points[Direction.UR].x = points[Direction.R].x
  points[Direction.UR].y = points[Direction.U].y
  points[Direction.DR].x = points[Direction.R].x
  points[Direction.DR].y = points[Direction.D].y
  points[Direction.UL].x = points[Direction.L].x
  points[Direction.UL].y = points[Direction.U].y
  points[Direction.DL].x = points[Direction.L].x
  points[Direction.DL].y = points[Direction.D].y

  // convert points to indices
  for dir_i in Direction(0)..<Direction(8) {
    indices[dir_i].x = cast(i32) math.floor(points[dir_i].x)
    indices[dir_i].y = cast(i32) math.floor(points[dir_i].y)
  }

  // get collision at each point
  for dir_i in Direction(0)..<Direction(8) {
    if indices[dir_i].x < 0 || indices[dir_i].x >= SCREEN_TILE_WIDTH  do continue
    if indices[dir_i].y < 0 || indices[dir_i].y >= SCREEN_TILE_HEIGHT do continue

    tile := get_tile(tilemap, indices[dir_i].x, indices[dir_i].y)
    if tile == nil do continue
    
    collision := get_tile_collision(tile^)
    if collision == .SOLID {
      push_out |= { Direction(dir_i) }
    }
		
		results.indexed_tiles[Direction(dir_i)] = tile
  }

  results.indices  = indices
  results.points   = points
  results.push_out = push_out

  // leave early if no points have collision
  if push_out == {} do return results

  // resolve corner cases into primary direction collision
  x_frac, y_frac : f32
  if (.UR in push_out) && (push_out & { .U, .R } == {})  {
    x_frac =	     (points[Direction.UR].x - math.floor(points[Direction.UR].x))
    y_frac = 1.0 - (points[Direction.UR].y - math.floor(points[Direction.UR].y))
    if (x_frac > y_frac) {
      push_out |= { .U }
      push_out_dir[Direction.U] = Direction.UR
			results.resolutions[.UR] = .U
    } else {
      push_out |= { .R }
      push_out_dir[Direction.R] = Direction.UR
			results.resolutions[.UR] = .R
    }
  }
  if (.DR in push_out) && (push_out & { .D, .R } == {}) {
    x_frac = (points[Direction.DR].x - math.floor(points[Direction.DR].x))
    y_frac = (points[Direction.DR].y - math.floor(points[Direction.DR].y))
    if (x_frac > y_frac) {
      push_out |= { .D }
      push_out_dir[Direction.D] = Direction.DR
			results.resolutions[.DR] = .D
    } else {
      push_out |= { .R }
      push_out_dir[Direction.R] = Direction.DR
			results.resolutions[.DR] = .R
    }
  }
  if (.UL in push_out) && (push_out & { .U, .L } == {}) {
    x_frac = 1.0 - (points[Direction.UL].x - math.floor(points[Direction.UL].x))
    y_frac = 1.0 - (points[Direction.UL].y - math.floor(points[Direction.UL].y))
    if (x_frac > y_frac) {
      push_out |= { .U }
      push_out_dir[Direction.U] = Direction.UL
			results.resolutions[.UL] = .U
    } else {
      push_out |= { .L }
      push_out_dir[Direction.L] = Direction.UL
			results.resolutions[.UL] = .L
    }
  }
  if (.DL in push_out) && (push_out & { .D, .L } == {}) {
    x_frac = 1.0 - (points[Direction.DL].x - math.floor(points[Direction.DL].x))
    y_frac =	     (points[Direction.DL].y - math.floor(points[Direction.DL].y))
    if (x_frac > y_frac) {
      push_out |= { .D }
      push_out_dir[Direction.D] = Direction.DL
			results.resolutions[.DL] = .D
    } else {
      push_out |= { .L }
      push_out_dir[Direction.L] = Direction.DL
			results.resolutions[.DL] = .L
    }
  }

  results.push_out = push_out

  // handle primary direction collision
  if .U in push_out {
    push_out_direction := push_out_dir[Direction.U]
    position_in_block  := 1.0 - (points[push_out_direction].y - f32(indices[push_out_direction].y))
    results.position_adjust.y += position_in_block;
  }
  if .D in push_out {
    push_out_direction := push_out_dir[Direction.D]
    position_in_block  := points[push_out_direction].y - f32(indices[push_out_direction].y)
    results.position_adjust.y -= position_in_block;
  }
  if .L in push_out {
    push_out_direction := push_out_dir[Direction.L]
    position_in_block  := 1.0 - (points[push_out_direction].x - f32(indices[push_out_direction].x))
    results.position_adjust.x += position_in_block;
  }
  if .R in push_out {
    push_out_direction := push_out_dir[Direction.R]
    position_in_block  := points[push_out_direction].x - f32(indices[push_out_direction].x)
    results.position_adjust.x -= position_in_block;
  }

  return results
}


render_world_screen :: proc(screen: ^World_Screen, tile_render_unit: f32, offset: Vector2) {
  render_tilemap(&screen.tilemap, tile_render_unit, offset)

  for &slot in screen.entities.slots {
    if !slot.occupied do continue
    render_entity(slot.data, tile_render_unit, offset)
  }
  for &slot in screen.particles.slots {
    if !slot.occupied do continue
    render_particle(&slot.data, tile_render_unit, offset)
  }
}


WORLD_WIDTH  :: 8
WORLD_HEIGHT :: 8

game_world : struct {
  screens : [] World_Screen,
  size    : Vec2i,
}

World_Screen :: struct {
  tilemap   : Tilemap,
  entities  : SlotArray(Entity, 64),
  particles : SlotArray(Particle, 64),
}

get_world_screen :: proc(x, y: i32) -> ^World_Screen {
	if x < 0 || x >= game_world.size.x ||
     y < 0 || y >= game_world.size.y {
    return nil
  }
	return &game_world.screens[y * game_world.size.x + x]
}

delete_game_world :: proc() {
  using game_world
  delete(screens)
  screens = nil
}

save_level :: proc(path: string) {
  out_bytes : [dynamic] byte
  defer delete(out_bytes)
  append(&out_bytes, ..mem.any_to_bytes(game_world.size)) 
  append(&out_bytes, ..slice.to_bytes(game_world.screens))

  if !os.write_entire_file(path, out_bytes[:]) {
    fmt.println("Failed to save level:", path)
    return
  }
  fmt.println("Saved level:", path)
}

load_level :: proc(path: string) {
  file, ok := os.read_entire_file(path)
  defer delete(file)
  if !ok {
    fmt.println("Failed to load level:", path)
    return
  }

  using game_world
  delete_game_world()

  bytes := file

  mem.copy(&size, &bytes[0], size_of(Vec2i))
  bytes = bytes[size_of(Vec2i):]
  fmt.println(size)

  screen_count := size.x * size.y
  screens = make([]World_Screen, screen_count)

  mem.copy(&screens[0], &bytes[0], size_of(World_Screen) * int(screen_count))

  fmt.println("Loaded level:", path)

  {
    using GameState
    start_screen_transition(world_screen_index.x, world_screen_index.y, .NONE)
  }
}

Tileset_Editor : struct {
  selected_tile  : i32,
  mouseover_tile : i32,
  tile_size      : i32,

  texture        : Texture,
  tileset_size   : Vec2i, 

  selected_tile_info : int,
  selected_frame     : int,
  tileset : [dynamic] Tile_Info
}

update_tileset_editor :: proc() {
  using Tileset_Editor

  mouse_tile_position := pixel_to_internal_units(
		pixel_position  = Mouse.position, 
		internal_unit   = f32(tile_size), 
	)
  mouseover_tile = get_grid_index_checked(
		position  = mouse_tile_position, 
		tile_size = { 1, 1 }, 
		grid_size = { tileset_size.x, tileset_size.y },
	)

  if Mouse.left == KEYSTATE_PRESSED {
    selected_tile = mouseover_tile
  }

  if imgui.Begin("Tileset Editor", nil, {}) {
    imgui.TextUnformattedString(fmt.tprintf("tile_size: %v", tile_size))
    imgui.TextUnformattedString(fmt.tprintf("tileset_size: %v", tileset_size))
    imgui.TextUnformattedString(fmt.tprintf("mouseover_tile: %v", mouseover_tile))

    if imgui.Button("Add Tile") {
      append(&tileset, Tile_Info{})
      selected_tile_info = len(tileset)
    }
    
    for &ti, ti_i in tileset {  using ti
      imgui.BeginGroup()
      if imgui.TreeNodeEx(cstring(raw_data(
        fmt.tprintf("%v: %v###%v\x00", ti_i, string(cstring(raw_data(&name))), ti_i),
      )), {.SpanAvailWidth}) {
        imgui.InputText("Name", cstring(raw_data(&name)), len(name), {})
        
        imgui.ComboEnumDynamic("Collision", collision)
        imgui.TextUnformattedString(fmt.tprintf("Frame Count: %v", animation.frame_count))

        {
          using animation
          imgui.InputInt("Frame Count", &frame_count)
          frame_count = clamp(frame_count, 0, MAX_TILE_ANIM_FRAMES)
          imgui.Indent()
          for i in 0..<frame_count {
            imgui.PushID(cstring(raw_data(
              fmt.tprintf("%v\x00", i),
            )))
            frame := &frames[i]
            imgui.InputInt("Frame Duration", &frame.duration)
            imgui.TextUnformattedString(
              fmt.tprintf("clip_offset: %v", frame.clip_offset),
            )
            if imgui.Button("Set Frame") {
              frame.clip_offset = { 
                (selected_tile == 0) ? 0 : (selected_tile % tileset_size.x),
                (selected_tile == 0) ? 0 : (selected_tile / tileset_size.x),
              }
            }
            imgui.Separator()
            imgui.PopID()
          }
          imgui.Unindent()
        }

        imgui.TreePop()
      }
      imgui.EndGroup()
      if imgui.IsItemClickedEx(.Right) {
        selected_tile_info = ti_i
      }
    } 
  }
  imgui.End()
}

render_tileset_editor :: proc() {
  using Tileset_Editor

  sdl.RenderSetViewport(renderer, nil)
  sdl.SetRenderDrawColor(renderer, 0x00, 0x00, 0x00, 0xff)
  sdl.RenderClear(renderer)

  clip := sdl.Rect {
    x = 0, 
    y = 0,
    w = i32(texture.width ),
    h = i32(texture.height),
  }
  rect := sdl.Rect {
    x = 0, 
    y = 0,
    w = i32(texture.width ),
    h = i32(texture.height),
  }
  sdl.RenderCopy(renderer, texture.sdl_texture, &clip, &rect)


  tile_outline_from_index :: proc(index: i32) -> sdl.Rect {
    img_size_tiles_x := i32(texture.width) / tile_size
    return {
      x = (index == 0) ? 0 : (index % img_size_tiles_x) * tile_size,
      y = (index == 0) ? 0 : (index / img_size_tiles_x) * tile_size,
      w = tile_size,
      h = tile_size,
    }
  }

  hovered_tile_outline  := tile_outline_from_index(mouseover_tile)
  selected_tile_outline := tile_outline_from_index(selected_tile )
  
  sdl.SetRenderDrawColor(renderer, 0xff, 0xff, 0xff, 0xff)
  sdl.RenderDrawRect(renderer, &hovered_tile_outline )
  sdl.SetRenderDrawColor(renderer, 0xff, 0x00, 0xff, 0xff)
  sdl.RenderDrawRect(renderer, &selected_tile_outline)



}


/*
  


*/