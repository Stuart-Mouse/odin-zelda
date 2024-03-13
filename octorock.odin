package main

import "core:math/rand"
import "core:math"
import "core:fmt"

import sdl "vendor:sdl2"

OCTOROCK_HITBOX_WIDTH    :: 10.0 / 16.0
OCTOROCK_HITBOX_HEIGHT   :: 10.0 / 16.0
OCTOROCK_HITBOX_OFFSET_X :: -OCTOROCK_HITBOX_WIDTH  / 2
OCTOROCK_HITBOX_OFFSET_Y :: -OCTOROCK_HITBOX_HEIGHT / 2
OCTOROCK_HITBOX_SIZE     : Vector2 : { OCTOROCK_HITBOX_WIDTH,    OCTOROCK_HITBOX_HEIGHT   } 
OCTOROCK_HITBOX_OFFSET   : Vector2 : { OCTOROCK_HITBOX_OFFSET_X, OCTOROCK_HITBOX_OFFSET_Y } 

OCTOROCK_INIT_HEALTH :: 2
OCTOROCK_WALK_CYCLE_LENGTH :: 16

Octorock :: struct {
  using base     : Entity_Base,

  health         : int,
  action_counter : int,
  action_state   : Octorock_Action_State,
  anim_counter   : int,
  facing         : Direction,
  immunity       : int,
  knockback      : Vector2,
}

Octorock_Action_State :: enum {
  IDLE,
  WALK_UP,
  WALK_DOWN,
  WALK_LEFT,
  WALK_RIGHT,
  ATTACK,
  COUNT,
}

OCTOROCK_IMMUNITY_TIME :: 15

update_octorock :: proc(octorock: ^Octorock) -> bool {
  using octorock
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
    action_counter -= 1
    if action_counter <= 0 {
      using Octorock_Action_State
      action_state = cast(Octorock_Action_State)\
        get_weighted_choice({
          { int(IDLE      ), 20 },
          { int(WALK_UP   ), 10 },
          { int(WALK_DOWN ), 10 },
          { int(WALK_LEFT ), 10 },
          { int(WALK_RIGHT), 10 },
          { int(ATTACK    ), 20 },
        })
      if action_state == .ATTACK {
        action_counter = 30
      }
      else do action_counter = int(30 + rand.int63_max(150))
    }
  }

  anim_counter += int(action_state == .WALK_UP || action_state == .WALK_DOWN || action_state == .WALK_LEFT || action_state == .WALK_RIGHT)
  if anim_counter >= OCTOROCK_WALK_CYCLE_LENGTH {
    anim_counter = 0
  }

  OCTOROCK_WALK_SPEED :: 0.025
  #partial switch action_state {
    case .WALK_UP:
      position.y -= OCTOROCK_WALK_SPEED
      facing = .U
    case .WALK_DOWN:
      position.y += OCTOROCK_WALK_SPEED
      facing = .D
    case .WALK_LEFT:
      position.x -= OCTOROCK_WALK_SPEED
      facing = .L
    case .WALK_RIGHT:
      position.x += OCTOROCK_WALK_SPEED
      facing = .R
    case .ATTACK:
      action_state = .IDLE
      shoot_vec := direction_vectors[facing]
      screen := get_active_screen()
      slot := get_next_empty_slot(&screen.entities)
      if slot != nil {
        slot^ = { 
          occupied = true, 
          data = { 
            tag = .OCTOROCK_ROCK,
            octorock_rock = {
              position = position + shoot_vec * 0.5,
              velocity = shoot_vec * 0.1,
            },
          },
        }
      }
  }

  screen := get_active_screen()
  collision_result := do_tilemap_collision(&screen.tilemap, position, OCTOROCK_HITBOX_SIZE, OCTOROCK_HITBOX_OFFSET)
  position += collision_result.position_adjust

  // Keep entity on the screen
  if position.x < OCTOROCK_HITBOX_OFFSET_X {
    collision_result.push_out += { .L }
    position.x = OCTOROCK_HITBOX_OFFSET_X
  }
  if position.x > SCREEN_TILE_WIDTH - (OCTOROCK_HITBOX_OFFSET_X + OCTOROCK_HITBOX_WIDTH) {
    collision_result.push_out += { .R }
    position.x = SCREEN_TILE_WIDTH - (OCTOROCK_HITBOX_OFFSET_X + OCTOROCK_HITBOX_WIDTH)
  }
  if position.y < OCTOROCK_HITBOX_OFFSET_Y {
    collision_result.push_out += { .U }
    position.y = OCTOROCK_HITBOX_OFFSET_Y
  }
  if position.y > SCREEN_TILE_HEIGHT - (OCTOROCK_HITBOX_OFFSET_Y + OCTOROCK_HITBOX_HEIGHT) {
    collision_result.push_out += { .D }
    position.y = SCREEN_TILE_HEIGHT - (OCTOROCK_HITBOX_OFFSET_Y + OCTOROCK_HITBOX_HEIGHT)
  }

  if facing in collision_result.push_out {
    action_counter = 0
  }

  return true
}

render_octorock :: proc(using octorock: Octorock, tile_render_unit, offset: Vector2) {
  rect : sdl.Rect = {
    x = i32((position.x - 0.5 + offset.x) * tile_render_unit.x),
    y = i32((position.y - 0.5 + offset.y) * tile_render_unit.y),
    w = i32(tile_render_unit.x),
    h = i32(tile_render_unit.y),
  }
  clip : sdl.Rect = {
    w = TILE_TEXTURE_SIZE,
    h = TILE_TEXTURE_SIZE,
  }
  clip.x = (facing == .L || facing == .R ? 2 : 0) * TILE_TEXTURE_SIZE

  if anim_counter >= OCTOROCK_WALK_CYCLE_LENGTH / 2 {
    clip.x += TILE_TEXTURE_SIZE
  }
  flip : sdl.RendererFlip
  if facing == .R do flip |= .HORIZONTAL
  if facing == .D do flip |= .VERTICAL
  sdl.SetTextureAlphaMod(entities_texture.sdl_texture, u8(255.0 * (1.0 - f32(immunity) / f32(OCTOROCK_IMMUNITY_TIME))))
  sdl.RenderCopyEx(renderer, entities_texture.sdl_texture, &clip, &rect, 0, nil, flip)
  sdl.SetTextureAlphaMod(entities_texture.sdl_texture, 0xff)
}


OCTOROCK_ROCK_HITBOX_WIDTH    :: 14.0 / 16.0
OCTOROCK_ROCK_HITBOX_HEIGHT   :: 14.0 / 16.0
OCTOROCK_ROCK_HITBOX_OFFSET_X :: -OCTOROCK_ROCK_HITBOX_WIDTH  / 2
OCTOROCK_ROCK_HITBOX_OFFSET_Y :: -OCTOROCK_ROCK_HITBOX_HEIGHT / 2
OCTOROCK_ROCK_HITBOX_SIZE     : Vector2 : { OCTOROCK_ROCK_HITBOX_WIDTH,    OCTOROCK_ROCK_HITBOX_HEIGHT   } 
OCTOROCK_ROCK_HITBOX_OFFSET   : Vector2 : { OCTOROCK_ROCK_HITBOX_OFFSET_X, OCTOROCK_ROCK_HITBOX_OFFSET_Y } 

Octorock_Rock :: struct {
  using base : Entity_Base,
  velocity : Vector2,
}

update_octorock_rock :: proc(using rock: ^Octorock_Rock) -> bool {
  position += velocity
  screen := get_active_screen()
  if do_tilemap_collision(&screen.tilemap, position, OCTOROCK_ROCK_HITBOX_SIZE, OCTOROCK_ROCK_HITBOX_OFFSET).push_out != {} || 
     position.x < -1 || position.x > SCREEN_TILE_WIDTH + 1 || position.y < -1 || position.y > SCREEN_TILE_HEIGHT + 1 {
    return false
  }
  return true
}

render_octorock_rock :: proc(using rock: Octorock_Rock, tile_render_unit, offset: Vector2) {
  clip : sdl.Rect = { 67, 3, 10, 10 }
  rect : sdl.Rect = {
    i32((position.x - 5.0 / 16.0 + offset.x) * tile_render_unit.x),
    i32((position.y - 5.0 / 16.0 + offset.y) * tile_render_unit.y),
    i32((10.0 / 16.0) * tile_render_unit.x),
    i32((10.0 / 16.0) * tile_render_unit.y),
  }
  sdl.RenderCopy(renderer, entities_texture.sdl_texture, &clip, &rect)
}