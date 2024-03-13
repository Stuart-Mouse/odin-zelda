package main

import "core:math/rand"
import "core:math"
import "core:fmt"

import sdl "vendor:sdl2"

MOBLIN_HITBOX_WIDTH    :: 10.0 / 16.0
MOBLIN_HITBOX_HEIGHT   :: 10.0 / 16.0
MOBLIN_HITBOX_OFFSET_X :: -MOBLIN_HITBOX_WIDTH  / 2
MOBLIN_HITBOX_OFFSET_Y :: -MOBLIN_HITBOX_HEIGHT / 2
MOBLIN_HITBOX_SIZE     : Vector2 : { MOBLIN_HITBOX_WIDTH,    MOBLIN_HITBOX_HEIGHT   } 
MOBLIN_HITBOX_OFFSET   : Vector2 : { MOBLIN_HITBOX_OFFSET_X, MOBLIN_HITBOX_OFFSET_Y } 

MOBLIN_INIT_HEALTH :: 3
MOBLIN_WALK_CYCLE_LENGTH :: 16

Moblin :: struct {
  using base : Entity_Base,

  health         : int,
  action_counter : int,
  action_state   : Moblin_Action_State,
  anim_counter   : int,
  facing         : Direction,
  immunity       : int,
  knockback      : Vector2,
}

Moblin_Action_State :: enum {
  IDLE,
  WALK_UP,
  WALK_DOWN,
  WALK_LEFT,
  WALK_RIGHT,
  ATTACK,
  COUNT,
}

MOBLIN_IMMUNITY_TIME :: 15

update_moblin :: proc(using moblin: ^Moblin) -> bool {
  if health <= 0 {
    return false
  }

  if immunity > 0 {
    immunity -= 1
    position += knockback
    action_state   = .IDLE
    action_counter = 0
  }
  else {
    if distance_between_points(position, GameState.player.position) < 5 {
      player_direction : Direction = .UL
      angle_to_player := angle_between_points(position, GameState.player.position)
      switch angle_to_player {
        case math.PI*-4/4..<math.PI*-3/4: player_direction = .L
        case math.PI*-3/4..<math.PI*-1/4: player_direction = .U
        case math.PI*-1/4..<math.PI*+1/4: player_direction = .R
        case math.PI*+1/4..<math.PI*+3/4: player_direction = .D
        case math.PI*+3/4..<math.PI*+4/4: player_direction = .L
      }
      if action_state == .ATTACK {
        action_counter = 10
        facing = player_direction
      }
      else if facing == player_direction {
        action_state   = .ATTACK
        action_counter = 10
        // p_slot := get_next_slot(&get_active_screen().particles)
        // p_slot.occupied = true
        // p_slot.data = {
        //   scale            = { 1, 1 },
        //   position         = position - 0.5, 
        //   velocity         = { 0, -0.01    },
        //   acceleration     = { 0,  0.01/60 },
        //   // angular_velocity = 5 * (rand.float32() - 0.5),
        //   texture          = decor_texture.sdl_texture,
        //   animation = {
        //     frame_count = 4,
        //     frames = {
        //       {
        //         clip = {  0, 32, 8, 8 },
        //         duration = 60,
        //       },
        //       {}, {}, {}, {}, {}, {}, {},
        //     },
        //   },
        // }
      }
    }

    action_counter -= 1
    if action_counter <= 0 {
      if action_state == .ATTACK {
        action_state   = .IDLE
        action_counter = 10
      } else {
        using Moblin_Action_State
        action_state = cast(Moblin_Action_State)\
          get_weighted_choice({
            { int(IDLE      ), 20 },
            { int(WALK_UP   ), 10 },
            { int(WALK_DOWN ), 10 },
            { int(WALK_LEFT ), 10 },
            { int(WALK_RIGHT), 10 },
          })
        action_counter = int(30 + rand.int63_max(150))
      }
    }
  }

  anim_counter += int(action_state != .IDLE)
  if anim_counter >= MOBLIN_WALK_CYCLE_LENGTH {
    anim_counter = 0
  }

  MOBLIN_WALK_SPEED :: 0.035
  #partial switch action_state {
    case .WALK_UP:
      position.y -= MOBLIN_WALK_SPEED
      facing = .U
    case .WALK_DOWN:
      position.y += MOBLIN_WALK_SPEED
      facing = .D
    case .WALK_LEFT:
      position.x -= MOBLIN_WALK_SPEED
      facing = .L
    case .WALK_RIGHT:
      position.x += MOBLIN_WALK_SPEED
      facing = .R
    case .ATTACK:
      position += MOBLIN_WALK_SPEED * 1.15 * unit_vector_between_points(position, GameState.player.position)
  }

  screen := get_active_screen()
  collision_result := do_tilemap_collision(&screen.tilemap, position, MOBLIN_HITBOX_SIZE, MOBLIN_HITBOX_OFFSET)
  position += collision_result.position_adjust
  
  // Keep entity on the screen
  if position.x < MOBLIN_HITBOX_OFFSET_X {
    collision_result.push_out += { .L }
    position.x = MOBLIN_HITBOX_OFFSET_X
  }
  if position.x > SCREEN_TILE_WIDTH - (MOBLIN_HITBOX_OFFSET_X + MOBLIN_HITBOX_WIDTH) {
    collision_result.push_out += { .R }
    position.x = SCREEN_TILE_WIDTH - (MOBLIN_HITBOX_OFFSET_X + MOBLIN_HITBOX_WIDTH)
  }
  if position.y < MOBLIN_HITBOX_OFFSET_Y {
    collision_result.push_out += { .U }
    position.y = MOBLIN_HITBOX_OFFSET_Y
  }
  if position.y > SCREEN_TILE_HEIGHT - (MOBLIN_HITBOX_OFFSET_Y + MOBLIN_HITBOX_HEIGHT) {
    collision_result.push_out += { .D }
    position.y = SCREEN_TILE_HEIGHT - (MOBLIN_HITBOX_OFFSET_Y + MOBLIN_HITBOX_HEIGHT)
  }

  if facing in collision_result.push_out {
    action_counter = 0
  }

  return true
}

render_moblin :: proc(using moblin: Moblin, tile_render_unit, offset: Vector2) {
  rect : sdl.Rect = {
    x = i32((position.x - 0.5 + offset.x) * tile_render_unit.x),
    y = i32((position.y - 0.5 + offset.y) * tile_render_unit.y),
    w = i32(tile_render_unit.x),
    h = i32(tile_render_unit.y),
  }
  clip : sdl.Rect = {
    y = 1 * TILE_TEXTURE_SIZE,
    w = TILE_TEXTURE_SIZE,
    h = TILE_TEXTURE_SIZE,
  }

  flip : sdl.RendererFlip
  #partial switch facing {
    case .U: 
      clip.x = 1 * TILE_TEXTURE_SIZE
      if anim_counter >= MOBLIN_WALK_CYCLE_LENGTH / 2 {
        flip |= .HORIZONTAL
      }
    case .D: 
      clip.x = 0
      if anim_counter >= MOBLIN_WALK_CYCLE_LENGTH / 2 {
        flip |= .HORIZONTAL
      }
    case .L: 
      flip |= .HORIZONTAL
      fallthrough
    case .R:
      clip.x = 2 * TILE_TEXTURE_SIZE
      if anim_counter >= MOBLIN_WALK_CYCLE_LENGTH / 2 {
        clip.x += TILE_TEXTURE_SIZE
      }
  }

  sdl.SetTextureAlphaMod(entities_texture.sdl_texture, u8(255.0 * (1.0 - f32(immunity) / f32(MOBLIN_IMMUNITY_TIME))))
  sdl.RenderCopyEx(renderer, entities_texture.sdl_texture, &clip, &rect, 0, nil, flip)
  sdl.SetTextureAlphaMod(entities_texture.sdl_texture, 0xff)
}


// MOBLIN_ARROW_HITBOX_WIDTH    :: 14.0 / 16.0
// MOBLIN_ARROW_HITBOX_HEIGHT   :: 14.0 / 16.0
// MOBLIN_ARROW_HITBOX_OFFSET_X :: -MOBLIN_ARROW_HITBOX_WIDTH  / 2
// MOBLIN_ARROW_HITBOX_OFFSET_Y :: -MOBLIN_ARROW_HITBOX_HEIGHT / 2
// MOBLIN_ARROW_HITBOX_SIZE     : Vector2 : { MOBLIN_ARROW_HITBOX_WIDTH,    MOBLIN_ARROW_HITBOX_HEIGHT   } 
// MOBLIN_ARROW_HITBOX_OFFSET   : Vector2 : { MOBLIN_ARROW_HITBOX_OFFSET_X, MOBLIN_ARROW_HITBOX_OFFSET_Y } 

// Moblin_Arrow :: struct {
//   position : Vector2,
//   velocity : Vector2,
// }

// update_moblin_arrow :: proc(using arrow: ^Moblin_Arrow) -> bool {
//   position += velocity
//   screen := get_active_screen()
//   if do_tilemap_collision(&screen.tilemap, position, MOBLIN_ARROW_HITBOX_SIZE, MOBLIN_ARROW_HITBOX_OFFSET) != {} || 
//      position.x < -1 || position.x > SCREEN_TILE_WIDTH + 1 || position.y < -1 || position.y > SCREEN_TILE_HEIGHT + 1 {
//     return false
//   }
//   return true
// }

// render_moblin_arrow :: proc(using arrow: Moblin_Arrow, tile_render_unit, offset: Vector2) {
//   clip : sdl.Rect = { 67, 3, 10, 10 }
//   rect : sdl.Rect = {
//     i32((position.x - 5.0 / 16.0 + offset.x) * tile_render_unit.x),
//     i32((position.y - 5.0 / 16.0 + offset.y) * tile_render_unit.y),
//     i32((10.0 / 16.0) * tile_render_unit.x),
//     i32((10.0 / 16.0) * tile_render_unit.y),
//   }
//   sdl.RenderCopy(renderer, entities_texture.sdl_texture, &clip, &rect)
// }