package main

import "core:math/rand"
import "core:math"
import "core:fmt"

import sdl "vendor:sdl2"

entities_texture : Texture

Entity_Base :: struct {
  position : Vector2,
}

Entity_Type :: enum {
  NONE,
  OCTOROCK,
  OCTOROCK_ROCK,
  MOBLIN,
}

Entity :: struct {
  tag : Entity_Type,
  using variant : struct #raw_union {
    base          : Entity_Base,
    octorock      : Octorock,
    octorock_rock : Octorock_Rock,
    moblin        : Moblin,
  },
}

init_entity :: proc(entity: ^Entity, type: Entity_Type) {
  if entity == nil do return 
  entity.tag = type
  #partial switch type {
    case .OCTOROCK:
      entity.octorock = {
        health = OCTOROCK_INIT_HEALTH,
      }
    case .MOBLIN:
      entity.moblin = {
        health = MOBLIN_INIT_HEALTH,
        facing = .D,
      }
  }
}

update_entity :: proc(using entity: ^Entity) -> bool {
  if entity == nil do return true
  
  #partial switch tag {
    case .OCTOROCK      : return update_octorock     (&octorock     )
    case .OCTOROCK_ROCK : return update_octorock_rock(&octorock_rock)
    case .MOBLIN        : return update_moblin       (&moblin       )
  }
  return true 
}

render_entity :: proc(using entity: Entity, tile_render_unit, offset: Vector2) {
  #partial switch tag {
    case .OCTOROCK      : render_octorock     (octorock     , tile_render_unit, offset)
    case .OCTOROCK_ROCK : render_octorock_rock(octorock_rock, tile_render_unit, offset)
    case .MOBLIN        : render_moblin       (moblin       , tile_render_unit, offset)
  }

  // render vector pointing towards player
  v := unit_vector_between_points(base.position, GameState.player.position)
  v += base.position
  sdl.SetRenderDrawColor(renderer, 0xff, 0xff, 0xff, 0xff)
  sdl.RenderDrawLineF(
    renderer, 
    base.position.x * TILE_RENDER_SIZE, 
    base.position.y * TILE_RENDER_SIZE, 
    v.x * TILE_RENDER_SIZE, 
    v.y * TILE_RENDER_SIZE,
  )
}

get_entity_collision_rect :: proc(using entity: Entity) -> sdl.Rect {
  #partial switch tag {
    case .OCTOROCK      : return rect_from_position_size_offset(base.position, OCTOROCK_HITBOX_SIZE     , OCTOROCK_HITBOX_OFFSET     )
    case .OCTOROCK_ROCK : return rect_from_position_size_offset(base.position, OCTOROCK_ROCK_HITBOX_SIZE, OCTOROCK_ROCK_HITBOX_OFFSET)
    case .MOBLIN        : return rect_from_position_size_offset(base.position, MOBLIN_HITBOX_SIZE       , MOBLIN_HITBOX_OFFSET       )
  }
  return {}
}

get_entity_collision_frect :: proc(using entity: Entity) -> sdl.FRect {
  #partial switch tag {
    case .OCTOROCK      : return frect_from_position_size_offset(base.position, OCTOROCK_HITBOX_SIZE     , OCTOROCK_HITBOX_OFFSET     )
    case .OCTOROCK_ROCK : return frect_from_position_size_offset(base.position, OCTOROCK_ROCK_HITBOX_SIZE, OCTOROCK_ROCK_HITBOX_OFFSET)
    case .MOBLIN        : return frect_from_position_size_offset(base.position, MOBLIN_HITBOX_SIZE       , MOBLIN_HITBOX_OFFSET       )
  }
  return {}
}

frect_from_position_size_offset :: proc(position, size, offset: Vector2) -> sdl.FRect {
  return sdl.FRect {
    x = position.x + offset.x,
    y = position.y + offset.y,
    w = size.x,
    h = size.y,
  }
}

rect_from_position_size_offset :: proc(position, size, offset: Vector2) -> sdl.Rect {
  return sdl.Rect {
    x = i32(position.x + offset.x),
    y = i32(position.y + offset.y),
    w = i32(size.x),
    h = i32(size.y),
  }
}

make_entity_death_particles :: proc(entity: Entity) {
  position := entity.base.position
  velocity : Vector2

  cloud_particles_count := 2
  spark_particles_count := 2
  #partial switch entity.tag {
    case .OCTOROCK: fallthrough
    case .MOBLIN: 
      velocity = unit_vector_between_points(GameState.player.position, position) * 0.1
    case .OCTOROCK_ROCK: 
      cloud_particles_count = 0
      spark_particles_count = 2
      velocity = entity.octorock_rock.velocity

  }

  // spark particles
  for i in 0..<spark_particles_count {
    vel_var := Vector2 {
      0.15 * (rand.float32() - 0.5),
      0.15 * (rand.float32() - 0.5),
    }
    pos_var := Vector2 {
      0.75 * (rand.float32() - 0.5),
      0.75 * (rand.float32() - 0.5),
    }
    active_time := 15 + (rand.float32() * 15)
    p_slot := get_next_slot(&get_active_screen().particles)
    p_slot.occupied = true
    p_slot.data = {
      scale            = { 1, 1 },
      position         = position + pos_var, 
      velocity         = velocity + vel_var,
      acceleration     = -(velocity + vel_var) / active_time,
      angular_velocity = 5 * (rand.float32() - 0.5),
      texture          = decor_texture.sdl_texture,
      animation = {
        frame_count = 4,
        frames = {
          {
            clip = {  0, 0, 16, 16 },
            duration = int(active_time / 4),
          },
          {
            clip = { 16, 0, 16, 16 },
            duration = int(active_time / 4),
          },
          {
            clip = { 32, 0, 16, 16 },
            duration = int(active_time / 4),
          },
          {
            clip = { 48, 0, 16, 16 },
            duration = int(active_time / 4),
          },
          {}, {}, {}, {},
        },
      },
    }
  }  

  // cloud particles
  for i in 0..<cloud_particles_count {
    vel_var := Vector2 {
      0.15 * (rand.float32() - 0.5),
      0.15 * (rand.float32() - 0.5),
    }
    pos_var := Vector2 {
      0.75 * (rand.float32() - 0.5),
      0.75 * (rand.float32() - 0.5),
    }
    active_time := 20 + (rand.float32() * 20)
    p_slot := get_next_slot(&get_active_screen().particles)
    p_slot.occupied = true
    p_slot.data = {
      scale            = { 1, 1 },
      position         = position + pos_var, 
      velocity         = velocity + vel_var,
      acceleration     = -(velocity + vel_var) / active_time,
      angular_velocity = 5 * (rand.float32() - 0.5),
      texture          = decor_texture.sdl_texture,
      animation = {
        frame_count = 4,
        frames = {
          {
            clip = {  0, 16, 16, 16 },
            duration = int(active_time / 4),
          },
          {
            clip = { 16, 16, 16, 16 },
            duration = int(active_time / 4),
          },
          {}, {}, {}, {}, {}, {},
        },
      },
    }
  }  
}