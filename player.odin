package main

import "core:math"
import "core:fmt"
import sdl "vendor:sdl2"

player_texture : Texture

PLAYER_HITBOX_WIDTH  :: 10.0 / 16.0
PLAYER_HITBOX_HEIGHT :: 10.0 / 16.0

PLAYER_HITBOX_OFFSET_X :: -PLAYER_HITBOX_WIDTH  / 2
PLAYER_HITBOX_OFFSET_Y :: -PLAYER_HITBOX_HEIGHT / 2

player_texture_WIDTH  :: 16
player_texture_HEIGHT :: 16

PLAYER_RENDER_WIDTH  :: TILE_RENDER_SIZE
PLAYER_RENDER_HEIGHT :: TILE_RENDER_SIZE

PLAYER_RENDER_OFFSET_X :: -8.0 / 16.0
PLAYER_RENDER_OFFSET_Y :: PLAYER_HITBOX_OFFSET_Y + PLAYER_HITBOX_HEIGHT - 1

Sword :: struct {
  counter : int,
  state   : SwordState,
}

SwordState :: enum {
  IDLE,
  SWING_1,
  SWING_2,
  SWING_3,
  HELD,
  CHARGED,
  SPIN,
  COUNT,
}

Player_Flags :: bit_set[Player_Flag]
Player_Flag :: enum {
  FALLING,
}

Player_Item :: enum {
  NONE,
  SWORD,
  SHIELD,
  CANDLE, 
  BOMB,
  BOW,
}

PlayerInputKeys :: enum {
  UP, 
  DOWN, 
  LEFT,
  RIGHT,
  ITEM_A,
  ITEM_B,
  COUNT,
}

Player :: struct {
  position     : Vector2,
  health       : int,
  money        : int,
  item_a       : Player_Item,
  // item_b       : Player_Item,
  // bombs        : int,
  // arrows       : int,
  facing       : Directions,
  pushing      : Directions,
  sword        : Sword,
  anim_counter : int,
  flags        : Player_Flags,
  controller   : [PlayerInputKeys.COUNT] InputKey,
}

update_sword :: proc(sword: ^Sword, sword_button: KeyState) {
	// sword animation can always be cancelled and restarted
	if sword_button == KEYSTATE_PRESSED {
		sword.state   = .SWING_1
		sword.counter = 0
	}

	#partial switch sword.state {
	case .SWING_1:
		fallthrough
	case .SWING_2:
		sword.counter += 1
		if sword.counter >= 3 {
			sword.state += SwordState(1)
			sword.counter = 0
		}

	case .SWING_3:
		sword.counter += 1
		if sword.counter >= 6 {
			//sword.state += 1
			sword.state   = .IDLE // TODO: reintroduce sword charge and spin attack as a stretch goal
			sword.counter = 0
		}

	case .HELD:
		if bool(sword_button & KEYSTATE_PRESSED) {
			sword.counter += 1
			if sword.counter >= 32 {
				sword.state  = .CHARGED
				sword.counter = 0
			}
		} else {
			sword.state   = .IDLE
			sword.counter = 0
		}

	case .CHARGED:
		if bool(sword_button & KEYSTATE_PRESSED) {
			sword.counter += 1
			if sword.counter >= 8 {
				sword.counter = 0
      }
		} else {
			sword.state   = .IDLE // TODO: change back to spin
			sword.counter = 0
		}

	case .SPIN:
		sword.counter += 1
		if sword.counter >= 12 * 4 {
			sword.state   = .IDLE
			sword.counter = 0
		}
	}
}

update_player :: proc(using player: ^Player) {
	if player == nil do return

	// update the player's input
	update_input_controller(controller[:]);

	// allow player to use held items
	// #partial switch item_a {
	// case .SWORD:
	update_sword(&sword, controller[PlayerInputKeys.ITEM_A].state)
	// }

	// player cannot move while swinging sword
	// player cannot change which direction they are facing while the sword is out at all
	falling := .FALLING in flags
	can_face := !falling && (sword.state == .IDLE)
	can_move := !falling && (sword.state == .IDLE || sword.state == .HELD || sword.state == .CHARGED)

	PLAYER_MOVE_SPEED :: 0.075

	// get the directions in which the player is trying to move
	move_player : Directions = {}

	// if the player is in the falling state, skip getting the directions to move and simply make the player fall
	if falling {
		position.y   += 0.125
		anim_counter += 1
	}
	else { // if the player is not in the falling state, get the directions to move as per usual
		if bool(controller[PlayerInputKeys.UP   ].state & KEYSTATE_PRESSED) {
			move_player |= { .U }
    }
		if bool(controller[PlayerInputKeys.DOWN ].state & KEYSTATE_PRESSED) {
			move_player |= { .D }
    }
		if bool(controller[PlayerInputKeys.LEFT ].state & KEYSTATE_PRESSED) {
			move_player |= { .L }
    }
		if bool(controller[PlayerInputKeys.RIGHT].state & KEYSTATE_PRESSED) {
			move_player |= { .R }
    }

		// negate conflicting directions
		if (move_player & { .U, .D }) == { .U, .D } {
      move_player &= ~{ .U, .D }
    }
		if (move_player & { .L, .R }) == { .L, .R } {
			move_player &= ~{ .L, .R };
    }
		// player will not change which direction they are facing while moving diagonally
		if (move_player & { .U, .D }) != {} && 
       (move_player & { .L, .R }) != {} {
			can_face = false
    }

		// move the player and/or change facing direction based on input
		if .U in move_player {
			if can_move do position.y -= PLAYER_MOVE_SPEED
			if can_face do facing = { .U }
		}
		else if .D in move_player {
			if can_move do position.y += PLAYER_MOVE_SPEED
			if can_face do facing = { .D }
		}
		if .L in move_player {
			if can_move do position.x -= PLAYER_MOVE_SPEED
			if can_face do facing = { .L } 
		}
		else if .R in move_player {
			if can_move do position.x += PLAYER_MOVE_SPEED
			if can_face do facing = { .R }
		}

		// if the player is moving, animate the walk cycle
		if move_player != {} {
			anim_counter += 1
		}
	}

	// check if player has left the screen
	if position.x >= SCREEN_TILE_WIDTH  {
		start_screen_transition(GameState.world_screen_index.x + 1, GameState.world_screen_index.y    , .RIGHT)
		return
	}
	if position.y >= SCREEN_TILE_HEIGHT {
		start_screen_transition(GameState.world_screen_index.x    , GameState.world_screen_index.y + 1, .DOWN)
		return
	}
	if position.x <  0 {
		start_screen_transition(GameState.world_screen_index.x - 1, GameState.world_screen_index.y    , .LEFT)
		return
	}
	if position.y <  0 {
		start_screen_transition(GameState.world_screen_index.x    , GameState.world_screen_index.y - 1, .UP)
		return
	}

	/* 
		check for collision with the tilemap 
		When performing tilemap collision tests, we will use a point-based collision test.
		With eight points located around the sides of the player's hitbox, 
			we can determine which tiles the player is in contact with and how to resolve any collision.
		This is preferrable to a rectangular collision test for tilemaps, since we can directly index a tile and immediately know what to do to resolve collision.
	*/
	pushing = {}
	{
		screen := &GameState.loaded_screens[GameState.active_screen]

		push_out     : Directions = {}
		push_out_dir : [4] Direction = { Direction(0), Direction(1), Direction(2), Direction(3) }

		points  : [8] Vector2
		indices : [8] Vec2i

		points[Direction.U].x = position.x
		points[Direction.U].y = position.y + PLAYER_HITBOX_OFFSET_Y
		points[Direction.D].x = position.x
		points[Direction.D].y = position.y + PLAYER_HITBOX_OFFSET_Y + PLAYER_HITBOX_HEIGHT
		points[Direction.L].x = position.x + PLAYER_HITBOX_OFFSET_X
		points[Direction.L].y = position.y
		points[Direction.R].x = position.x + PLAYER_HITBOX_OFFSET_X + PLAYER_HITBOX_WIDTH
		points[Direction.R].y = position.y

		points[Direction.UR].x = points[Direction.R].x
		points[Direction.UR].y = points[Direction.U].y
		points[Direction.DR].x = points[Direction.R].x
		points[Direction.DR].y = points[Direction.D].y
		points[Direction.UL].x = points[Direction.L].x
		points[Direction.UL].y = points[Direction.U].y
		points[Direction.DL].x = points[Direction.L].x
		points[Direction.DL].y = points[Direction.D].y

		// convert points to indices
		for dir_i in 0..<8 {
			indices[dir_i].x = cast(i32) math.floor(points[dir_i].x)
			indices[dir_i].y = cast(i32) math.floor(points[dir_i].y)
		}

		// get collision at each point
		for dir_i in 0..<8 {
			if indices[dir_i].x < 0 || indices[dir_i].x >= SCREEN_TILE_WIDTH  { /*printf("error with check_mask, index out of bounds in x\n");*/ continue }
			if indices[dir_i].y < 0 || indices[dir_i].y >= SCREEN_TILE_HEIGHT { /*printf("error with check_mask, index out of bounds in y\n");*/ continue }

			tile      := get_tile(&screen.tilemap, indices[dir_i].x, indices[dir_i].y);
			collision := get_tile_collision(tile^);
			#partial switch (collision) {
			case .NONE:
				// If the player is in the falling state an their top collision point contacts a walkable tile, take the player out of the falling state
				if .FALLING in flags && (Direction(dir_i) == Direction.U) {
					flags &= ~{ .FALLING }
        }
			case .SOLID:
				// If the player is in the falling state, then the player will not collide with solid wall tiles
				if .FALLING not_in flags {
					push_out |= { Direction(dir_i) }
        }
			case .LEDGE:
				// If the player's bottom collision point is in the bottom half of a ledge tile, then place the player into falling mode
				if Direction(dir_i) == Direction.D {
					y_position_in_tile := points[Direction.D].y - f32(indices[Direction.D].y)
					if (y_position_in_tile > 0.5) {
						flags |= { .FALLING }
          }
				}
			}
		}

		// resolve corner cases into primary direction collision
		x_frac, y_frac : f32
		if (.UR in push_out) && (push_out & { .U, .R } == {})  {
			x_frac =	     (points[Direction.UR].x - math.floor(points[Direction.UR].x))
			y_frac = 1.0 - (points[Direction.UR].y - math.floor(points[Direction.UR].y))
			if (x_frac > y_frac) {
				push_out |= { .U }
				push_out_dir[Direction.U] = Direction.UR
			} else {
				push_out |= { .R }
				push_out_dir[Direction.R] = Direction.UR
			}
		}
		if (.DR in push_out) && (push_out & { .D, .R } == {}) {
			x_frac = (points[Direction.DR].x - math.floor(points[Direction.DR].x))
			y_frac = (points[Direction.DR].y - math.floor(points[Direction.DR].y))
			if (x_frac > y_frac) {
				push_out |= { .D }
				push_out_dir[Direction.D] = Direction.DR
			} else {
				push_out |= { .R }
				push_out_dir[Direction.R] = Direction.DR
			}
		}
		if (.UL in push_out) && (push_out & { .U, .L } == {}) {
			x_frac = 1.0 - (points[Direction.UL].x - math.floor(points[Direction.UL].x))
			y_frac = 1.0 - (points[Direction.UL].y - math.floor(points[Direction.UL].y))
			if (x_frac > y_frac) {
				push_out |= { .U }
				push_out_dir[Direction.U] = Direction.UL
			} else {
				push_out |= { .L }
				push_out_dir[Direction.L] = Direction.UL
			}
		}
		if (.DL in push_out) && (push_out & { .D, .L } == {}) {
			x_frac = 1.0 - (points[Direction.DL].x - math.floor(points[Direction.DL].x))
			y_frac =	     (points[Direction.DL].y - math.floor(points[Direction.DL].y))
			if (x_frac > y_frac) {
				push_out |= { .D }
				push_out_dir[Direction.D] = Direction.DL
			} else {
				push_out |= { .L }
				push_out_dir[Direction.L] = Direction.DL
			}
		}

		// handle primary direction collision
		if .U in push_out {
			push_out_direction := push_out_dir[Direction.U]
			position_in_block  := 1.0 - (points[push_out_direction].y - f32(indices[push_out_direction].y))
			position.y += position_in_block;
		}
		if .D in push_out {
			push_out_direction := push_out_dir[Direction.D]
			position_in_block  := points[push_out_direction].y - f32(indices[push_out_direction].y)
			position.y -= position_in_block;
		}
		if .L in push_out {
			push_out_direction := push_out_dir[Direction.L]
			position_in_block  := 1.0 - (points[push_out_direction].x - f32(indices[push_out_direction].x))
			position.x += position_in_block;
		}
		if .R in push_out {
			push_out_direction := push_out_dir[Direction.R]
			position_in_block  := points[push_out_direction].x - f32(indices[push_out_direction].x)
			position.x -= position_in_block;
		}

		// the player cannot push things while actively swinging or holding out the sword
		if sword.state == .IDLE {
			// Determine which direction the player is pushing.
			// Player can push on walls and blocks in the world.
			// The player is considered to be pushing on a wall when they are actively moving in some direction and simultaneously are being pushed out of a wall in that direction.
			pushing = move_player & push_out;

			// If we are pushing in some direction, then if we are also facing that same direction, we will restrict pushing to that direction.
			// Otherwise, we will change to face the direction we are pushing.
      if pushing != {} {
				common := pushing & facing
				if common != {} do pushing = common
				else            do facing  = pushing
			}
		} else do pushing = {}
	}

	/*
		check for collision with entities
		For collision betwen the player and entities, we will use a simple instantaneous AABB check.
		Since our interactions with entities will probably not make use of directional information, we can get away with simply checking for overlap between hitboxes.
	*/
  player_rect : sdl.FRect = {
    x =  position.x + PLAYER_HITBOX_OFFSET_X,
    y =  position.y + PLAYER_HITBOX_OFFSET_Y,
    w =  PLAYER_HITBOX_WIDTH,
    h =  PLAYER_HITBOX_HEIGHT,
  }
	sword_rect, _ := get_player_sword_frect_and_clip_rect(player)

	screen := &GameState.loaded_screens[GameState.active_screen]
	for &slot in screen.entities.slots {
		if !slot.occupied do continue
		entity := &slot.data
    #partial switch entity.tag {
      case .OCTOROCK:
				octorock := &entity.octorock
        entity_collision_rect := get_entity_collision_frect(slot.data)
        if aabb_frect(player_rect, entity_collision_rect) {
          fmt.println("hit")
        }
        if aabb_frect(sword_rect, entity_collision_rect) {
          if octorock.immunity == 0 {
            octorock.immunity = OCTOROCK_IMMUNITY_TIME
						octorock.health -= 1
          }
          KNOCKBACK_FORCE :: 0.1
          octorock.knockback = unit_vector_between_points(position, octorock.position) * KNOCKBACK_FORCE
        }
			case .MOBLIN:
				moblin := &entity.octorock
				entity_collision_rect := get_entity_collision_frect(slot.data)
				if aabb_frect(player_rect, entity_collision_rect) {
					fmt.println("hit")
				}
				if aabb_frect(sword_rect, entity_collision_rect) {
					if moblin.immunity == 0 {
						moblin.immunity = OCTOROCK_IMMUNITY_TIME
						moblin.health -= 1
					}
					KNOCKBACK_FORCE :: 0.1
					moblin.knockback = unit_vector_between_points(position, moblin.position) * KNOCKBACK_FORCE
				}
      case .OCTOROCK_ROCK:
        entity_collision_rect := get_entity_collision_frect(slot.data)
        if aabb_frect(player_rect, entity_collision_rect) {
          fmt.println("hit")
        }
    }
	}

}

render_player :: proc(player: ^Player) {
  if player == nil do return
  using player

	// render the player character
	player_clip : sdl.Rect = {
		x = 0,
		y = 0,
		w = (player_texture_WIDTH),
		h = (player_texture_HEIGHT),
	}

	// if the player is falling, just play the falling animation
	if .FALLING in flags {
		player_clip.x = 8
		player_clip.y = 1
		FALL_CYCLE_LENGTH :: 21
		if anim_counter >= FALL_CYCLE_LENGTH * 2 / 3 {
			player_clip.x += 2
			if anim_counter >= FALL_CYCLE_LENGTH {
				anim_counter = 0
			}
		} 
    else if anim_counter >= FALL_CYCLE_LENGTH / 3 {
			player_clip.x += 1
		}
	}
	else {
		// If the player is swinging the sword, show different animation frames
		#partial switch sword.state {
      case .SWING_1:
        player_clip.y = 0
        switch transmute(u8) facing {
          case 1 << u8(Direction.U): player_clip.x = 8
          case 1 << u8(Direction.D): player_clip.x = 10
          case 1 << u8(Direction.L): player_clip.x = 12
          case 1 << u8(Direction.R): player_clip.x = 14
        }


      case .SWING_2:
      case .SWING_3:
        player_clip.y = 0
        switch transmute(u8) facing {
          case 1 << u8(Direction.U): player_clip.x = 9
          case 1 << u8(Direction.D): player_clip.x = 11
          case 1 << u8(Direction.L): player_clip.x = 13
          case 1 << u8(Direction.R): player_clip.x = 15
        }
        

      case: 
        // normal player standing / walking frames
        if pushing != {} {
          player_clip.y = 2
        }

        switch transmute(u8) facing {
          case 1 << u8(Direction.U): player_clip.x = 0
          case 1 << u8(Direction.D): player_clip.x = 2
          case 1 << u8(Direction.L): player_clip.x = 4
          case 1 << u8(Direction.R): player_clip.x = 6
        }

        WALK_CYCLE_LENGTH :: 16
        if anim_counter >= WALK_CYCLE_LENGTH / 2 {
					player_clip.x += 1
					// TODO: remove the logic here and move to update function. 
					// We really shouldn't be modifying the player's state in the render function.
          if anim_counter >= WALK_CYCLE_LENGTH {
            anim_counter = 0
          }
        }
		}
	}

	// multiply player clip positions by texture width and height to get actual clip coordinates
	// Since all player clips are the same size, I simply used the x/y indices of the tile in the spritesheet to specify clips in the code above
	player_clip.x *= player_texture_WIDTH;
	player_clip.y *= player_texture_HEIGHT;

	player_rect : sdl.Rect = {
		x = i32((position.x + PLAYER_RENDER_OFFSET_X) * TILE_RENDER_SIZE),
		y = i32((position.y + PLAYER_RENDER_OFFSET_Y) * TILE_RENDER_SIZE),
		w = PLAYER_RENDER_WIDTH,
		h = PLAYER_RENDER_HEIGHT,
	}

	//sdl.Color color_mod = { 0xff, 0xff, 0xff, 0xff };
	//if (flags & PLAYER_FLAGS_FALLING)
	//	color_mod = (sdl.Color) { 0xff, 0x88, 0x88, 0xff };
	//sdl.SetTextureColorMod(player_texture, color_mod.r, color_mod.g, color_mod.b);

	sdl.RenderCopy(renderer, player_texture.sdl_texture, &player_clip, &player_rect);

	// render the player's sword
	if (sword.state != .IDLE) {
		sword_frect, sword_clip := get_player_sword_frect_and_clip_rect(player)
		sword_rect := sdl_frect_to_rect(sdl_frect_scale(sword_frect, TILE_RENDER_SIZE))
		
		// Make the sword flash if fully charged. Color changes every 2 frames.
		sword_clip.y += 16 * i32(bool(sword.state == .CHARGED)) * ((i32(sword.counter) >> 2) % 2)

		sdl.RenderCopy(renderer, player_texture.sdl_texture, &sword_clip, &sword_rect);
	}
}

get_player_sword_frect_and_clip_rect :: proc(using player: ^Player) -> (sdl.FRect, sdl.Rect) {
	// clips for sword pointing in each direction
	sword_dir_clips : [8] sdl.Rect = {
		Direction.U  = { 488,  0,  8, 16 },
		Direction.D  = { 480,  0,  8, 16 },
		Direction.L  = { 496,  0, 16,  8 },
		Direction.R  = { 496,  8, 16,  8 },
		Direction.UL = { 480, 32, 16, 16 },
		Direction.UR = { 496, 32, 16, 16 },
		Direction.DL = { 480, 48, 16, 16 },
		Direction.DR = { 496, 48, 16, 16 },
	};

	ROX :: PLAYER_RENDER_OFFSET_X
	ROY :: PLAYER_RENDER_OFFSET_Y

	// ROX :: 0
	// ROY :: 0

	sword_clip : sdl.Rect
	sword_rect : sdl.FRect

	if (sword.state == .SPIN) {

	}
	else {
		switch transmute(u8) facing {
		case 1 << u8(Direction.U):
			#partial switch sword.state {
			case .SWING_1:
				sword_clip = sword_dir_clips[Direction.R]
				sword_rect = {
					x = position.x + ROX,
					y = position.y + ROY,
					w = 1.0,
					h = 0.5,
				}
			case .SWING_2:
				sword_clip = sword_dir_clips[Direction.UR]
				sword_rect = {
					x = position.x + ROX + (13.0 / 16.0),
					y = position.y + ROY - (13.0 / 16.0),
					w = 1.0,
					h = 1.0,
				}
			case .SWING_3:
				sword_clip = sword_dir_clips[Direction.U]
				sword_rect = {
					x = position.x + ROX,
					y = position.y + ROY - 1,
					w = 0.5,
					h = 1.0,
				}
			case .CHARGED:
			case .HELD:
				sword_clip = sword_dir_clips[Direction.U]
				sword_rect = {
					x = position.x + ROX,
					y = position.y + ROY - (13.0 / 16.0),
					w = 0.5,
					h = 1.0,
				}
			}
		case 1 << u8(Direction.D):
			#partial switch (sword.state) {
			case .SWING_1:
				sword_clip = sword_dir_clips[Direction.L]
				sword_rect = {
					x = position.x + ROX - 1,
					y = position.y + ROY + 0.5,
					w = 1.0,
					h = 0.5,
				};
				break;
			case .SWING_2:
				sword_clip = sword_dir_clips[Direction.DL]
				sword_rect = {
					x = position.x + ROX - (13.0 / 16.0),
					y = position.y + ROY + (13.0 / 16.0),
					w = 1.0,
					h = 1.0,
				}
			case .SWING_3:
				sword_clip = sword_dir_clips[Direction.D]
				sword_rect = {
					x = position.x + ROX + 0.5,
					y = position.y + ROY + 1,
					w = 0.5,
					h = 1.0,
				}
			case .CHARGED:
			case .HELD:
				sword_clip = sword_dir_clips[Direction.D]
				sword_rect = {
					x = position.x + ROX + 0.5,
					y = position.y + ROY + (13.0 / 16.0),
					w = 0.5,
					h = 1.0,
				}
			}
		case 1 << u8(Direction.L):
			#partial switch (sword.state) {
			case .SWING_1:
				sword_clip = sword_dir_clips[Direction.U]
				sword_rect = {
					x = position.x + ROX,
					y = position.y + ROY - TILE_RENDER_SIZE,
					w = 0.5,
					h = 1.0,
				}
			case .SWING_2:
				sword_clip = sword_dir_clips[Direction.UL]
				sword_rect = {
					x = position.x + ROX - (13.0 / 16.0),
					y = position.y + ROY - (13.0 / 16.0),
					w = 1.0,
					h = 1.0,
				}
			case .SWING_3:
				sword_clip = sword_dir_clips[Direction.L]
				sword_rect = {
					x = position.x + ROX - 1,
					y = position.y + ROY + 0.5,
					w = 1,
					h = 0.5,
				}
			case .CHARGED:
			case .HELD:
				sword_clip = sword_dir_clips[Direction.L]
				sword_rect = {
					x = position.x + ROX - (11.0 / 16.0),
					y = position.y + ROY + 0.5,
					w = 1.0,
					h = 0.5,
				}
			}
		case 1 << u8(Direction.R):
			#partial switch (sword.state) {
			case .SWING_1:
				sword_clip = sword_dir_clips[Direction.U]
				sword_rect = {
					x = position.x + ROX + 0.5,
					y = position.y + ROY - 1,
					w = 0.5,
					h = 1.0,
				}
			case .SWING_2:
				sword_clip = sword_dir_clips[Direction.UR]
				sword_rect = {
					x = position.x + ROX + (13.0 / 16.0),
					y = position.y + ROY - (13.0 / 16.0),
					w = 1.0,
					h = 1.0,
				}
			case .SWING_3:
				sword_clip = sword_dir_clips[Direction.R]
				sword_rect = {
					x = position.x + ROX + 1,
					y = position.y + ROY + 0.5,
					w = 1.0,
					h = 0.5,
				}
			case .CHARGED:
			case .HELD:
				sword_clip = sword_dir_clips[Direction.R]
				sword_rect = {
					x = position.x + ROX + (11.0 / 16.0),
					y = position.y + ROY + 0.5,
					w = 1.0,
					h = 0.5,
				}
			}
		}
	}

	return sword_rect, sword_clip
}