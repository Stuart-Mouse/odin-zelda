package main

import "core:fmt"
import "core:math"
import "core:mem"
import "core:math/rand"
import "core:strings"
import "core:strconv"
import sdl       "vendor:sdl2"
import sdl_image "vendor:sdl2/image"
import sdl_mixer "vendor:sdl2/mixer"

import imgui "shared:imgui"
import "shared:imgui/imgui_impl_sdl2"
import "shared:imgui/imgui_impl_sdlrenderer2"

app_quit : bool = false

WINDOW_TITLE  :: "The Legend of Linda"
WINDOW_WIDTH  : i32 = 640
WINDOW_HEIGHT : i32 = 480

window   : ^sdl.Window
renderer : ^sdl.Renderer
small_text_texture : ^sdl.Texture

ProgramMode :: enum {
  GAME,
  EDITOR,
  TILESET_EDITOR,
}

program_mode : ProgramMode = .GAME

ProgramInputKeys :: enum {
  SET_MODE_GAME,
  SET_MODE_EDITOR,
  SET_MODE_TILESET_EDITOR,
  RELOAD_SCREEN,
  STEP_FRAME,
  SHOW_DEBUG_WINDOW,
  COUNT,
}

program_controller : [ProgramInputKeys.COUNT] InputKey = {
  ProgramInputKeys.SET_MODE_GAME           = { sc = .F1 },
  ProgramInputKeys.SET_MODE_EDITOR         = { sc = .F2 },
  ProgramInputKeys.SET_MODE_TILESET_EDITOR = { sc = .F3 },
  ProgramInputKeys.RELOAD_SCREEN           = { sc = .F9 },
  ProgramInputKeys.SHOW_DEBUG_WINDOW       = { sc = .F5 },
}

ScreenTransitionType :: enum {
  NONE, 
  FADE,
  UP,
  DOWN,
  LEFT,
  RIGHT,
}

GameState : struct {
  player : Player,

  world_screen_index : Vec2i,
  loaded_screens : [2] World_Screen,
  active_screen  : int,

  screen_transition : struct {
    type     : ScreenTransitionType,
    progress : f32,

    // used to lerp position of player and screen during screen transitions
    player_start : Vector2,
    player_end   : Vector2,
    screen_move  : Vector2,
  },

  paused : bool
}

get_active_screen :: proc() -> ^World_Screen {
  using GameState
  return &loaded_screens[active_screen]
}

start_screen_transition :: proc(x, y: i32, transition_type: ScreenTransitionType) {
  using GameState
  screen := get_world_screen(x, y)
  if screen == nil do return 

  // overwrite inactive screen
  inactive_screen := int(!bool(active_screen))
  loaded_screens[inactive_screen] = screen^

  active_screen = inactive_screen
  world_screen_index = { i32(x), i32(y) }

  using screen_transition
  type = transition_type
  progress = 0
  player_start = { player.position.x, player.position.y }
  switch type {
    case .UP:
      player_end  = { player_start.x, SCREEN_TILE_HEIGHT - 0.5 }
      screen_move = { 0, -1 }
    case .DOWN:
      player_end  = { player_start.x, 0.5 }
      screen_move = { 0, 1 }
    case .LEFT:
      player_end  = { SCREEN_TILE_WIDTH - 0.5, player_start.y }
      screen_move = { -1, 0 }
    case .RIGHT:
      player_end  = { 0.5, player_start.y }
      screen_move = { 1, 0 }
    case .FADE:
      // need to determine location to place player on destination screen
    case .NONE:
      player.position = { SCREEN_TILE_WIDTH / 2, SCREEN_TILE_HEIGHT / 2 }
  }
}

init_application :: proc() -> bool {
  if sdl.Init({.VIDEO, .AUDIO}) < 0 {
    fmt.println("sdl could not initialize! sdl Error: %", sdl.GetError())
    return false
  }

  if sdl_mixer.OpenAudio(44100, sdl.AUDIO_S16SYS, 2, 512) < 0 {
    fmt.println("Unable to open audio: %s\n", sdl.GetError())
    return false
  }

	if sdl_image.Init({.PNG}) == nil {
		fmt.println("sdl.image could not initialize! sdl.mage Error: %\n", sdl_image.GetError())
		return false
	}

  window = sdl.CreateWindow(
		WINDOW_TITLE, sdl.WINDOWPOS_UNDEFINED, sdl.WINDOWPOS_UNDEFINED,
		WINDOW_WIDTH, WINDOW_HEIGHT, sdl.WINDOW_SHOWN,
  )
	if window == nil {
		fmt.println("Window could not be created! sdl Error: %s\n", sdl.GetError())
		return false
	}

  renderer = sdl.CreateRenderer(window, -1, {.ACCELERATED, .PRESENTVSYNC})
	if renderer == nil {
		fmt.println("Renderer could not be created! sdl Error: %s\n", sdl.GetError())
		return false
	}

  small_text_texture = load_sdl_texture(renderer, "data/gfx/8x8_text.png") or_return

  player_texture   = load_texture(renderer, "data/gfx/link.png"   ) or_return
  tiles_texture    = load_texture(renderer, "data/gfx/tiles.png"  ) or_return
  entities_texture = load_texture(renderer, "data/gfx/enemies.png") or_return
  decor_texture    = load_texture(renderer, "data/gfx/decor.png"  ) or_return

  {
    using Tileset_Editor
    texture = load_texture(renderer, "data/gfx/tiles2.png") or_return
    tile_size = 16
    tileset_size = { i32(texture.width) / tile_size, i32(texture.height) / tile_size }
  }

	imgui.CHECKVERSION()
	imgui.CreateContext(nil)
	io := imgui.GetIO()
	io.ConfigFlags += {.NavEnableKeyboard, .NavEnableGamepad}

	imgui_impl_sdl2.InitForSDLRenderer(window, renderer)
	imgui_impl_sdlrenderer2.Init(renderer)


  {
    using EditorState
    tile_unit = 16
    selected_type = Tile
  }

  return true
}

init_game :: proc() -> bool {
  using GameState

  // init player
  {
    using GameState.player
    controller[PlayerInputKeys.UP    ] = { sc = .UP    }
    controller[PlayerInputKeys.DOWN  ] = { sc = .DOWN  }
    controller[PlayerInputKeys.LEFT  ] = { sc = .LEFT  }
    controller[PlayerInputKeys.RIGHT ] = { sc = .RIGHT }
    controller[PlayerInputKeys.ITEM_A] = { sc = .X     }
    controller[PlayerInputKeys.ITEM_B] = { sc = .Z     }

    position = { SCREEN_TILE_WIDTH / 2, SCREEN_TILE_HEIGHT / 2 }

    item_a = .SWORD
    facing = { .D }
  }

  load_tile_info()

  game_world.screens = make([]World_Screen, WORLD_WIDTH * WORLD_HEIGHT)
  game_world.size = { WORLD_WIDTH, WORLD_HEIGHT }
  for &s in game_world.screens {
    set_all_tiles_on_tilemap(&s.tilemap, { id = 17 })
  }

  start_screen_transition(world_screen_index.x, world_screen_index.y, .NONE)

  return true
}

update_game :: proc() {
  using GameState
  if program_controller[ProgramInputKeys.RELOAD_SCREEN].state == KEYSTATE_PRESSED {
    start_screen_transition(world_screen_index.x, world_screen_index.y, .NONE)
  }

  if screen_transition.type != .NONE {
    using screen_transition
    SCREEN_TRANSITION_TIME :: 45.0
    progress = min(1, progress + 1 / SCREEN_TRANSITION_TIME)

    // move the player across the screen 
    player.position = ((1 - progress) * player_start) + (progress * player_end)

    // animate the player walking while screen transitions
    player.anim_counter += 1

    // NOTE: for fade case, don't do player walk animation, only move player while screen is black

    // end screen transition
    if progress >= 1 do type = .NONE
  }
  else {
    screen := &loaded_screens[active_screen]
    for &slot in screen.entities.slots {
      if slot.occupied && !update_entity(&slot.data) {
        make_entity_death_particles(slot.data)
        slot.occupied = false
      }
    }

    for &slot in screen.particles.slots {
      if slot.occupied && !update_particle(&slot.data) {
        slot.occupied = false
      }
    }

    update_player(&player)
  }
}

render_game :: proc() {
  using GameState
  sdl.RenderSetViewport(renderer, nil)
  sdl.SetRenderDrawColor(renderer, 0x00, 0x00, 0x00, 0xff)
  sdl.RenderClear(renderer)

  // render tilemap
  inactive_screen := int(!bool(active_screen))
  #partial switch screen_transition.type {
    case .FADE:
      if screen_transition.progress < 0.5 {
        render_world_screen(&loaded_screens[inactive_screen], TILE_RENDER_SIZE, {0, 0})
      } else {
        render_world_screen(&loaded_screens[  active_screen], TILE_RENDER_SIZE, {0, 0})
      }
    case .UP   : fallthrough
    case .DOWN : fallthrough
    case .LEFT : fallthrough
    case .RIGHT: 
      screen_dimens   : Vector2 = { SCREEN_TILE_WIDTH, SCREEN_TILE_HEIGHT }
      active_offset   := screen_transition.screen_move * screen_dimens *  (1 - screen_transition.progress)
      inactive_offset := screen_transition.screen_move * screen_dimens * -(    screen_transition.progress)
      render_world_screen(&loaded_screens[inactive_screen], TILE_RENDER_SIZE, {inactive_offset.x, inactive_offset.y})
      render_world_screen(&loaded_screens[  active_screen], TILE_RENDER_SIZE, {  active_offset.x,   active_offset.y})
    case:
      render_world_screen(&loaded_screens[  active_screen], TILE_RENDER_SIZE, {0, 0})
  }

  render_player(&player)
}

close_application :: proc() {
  imgui_impl_sdlrenderer2.Shutdown()
  imgui_impl_sdl2.Shutdown()
  imgui.DestroyContext(nil)

	// sdl_mixer.FreeChunk(sound_bloop_1)
	// sdl_mixer.FreeChunk(sound_bloop_2)
	// sdl_mixer.CloseAudio()

	sdl.DestroyRenderer(renderer)
	sdl.DestroyWindow(window)
	sdl.Quit()
}

handle_sdl_events :: proc() {
  e : sdl.Event
  for sdl.PollEvent(&e) {
    imgui_impl_sdl2.ProcessEvent(&e)
    #partial switch e.type {
      case .QUIT:
        app_quit = true
      case .MOUSEWHEEL:
        Mouse.wheel.x = e.wheel.x;
        Mouse.wheel.y = e.wheel.y;
        Mouse.wheel_updated = 1;
    }
  }
}

main :: proc() {
  if !init_application() do return
  if !init_game() do return

  for !app_quit {
    handle_sdl_events()

    update_mouse()
    update_input_controller(program_controller[:])
    if program_controller[ProgramInputKeys.SET_MODE_EDITOR].state == KEYSTATE_PRESSED {
      program_mode = .EDITOR
    }
    if program_controller[ProgramInputKeys.SET_MODE_GAME].state == KEYSTATE_PRESSED {
      program_mode = .GAME
    }
    if program_controller[ProgramInputKeys.SET_MODE_TILESET_EDITOR].state == KEYSTATE_PRESSED {
      program_mode = .TILESET_EDITOR
    }
    if program_controller[ProgramInputKeys.SHOW_DEBUG_WINDOW].state == KEYSTATE_PRESSED {
      show_debug_window = !show_debug_window
    }

    update_tile_animations()

    imgui_new_frame()
    imgui_update()

    update_tile_animations()

    switch(program_mode) {
      case .GAME:
        if !GameState.paused || program_controller[ProgramInputKeys.STEP_FRAME].state == KEYSTATE_PRESSED {
          update_game()
        }
        render_game()
      case .EDITOR:
        update_editor()
        render_editor()
      case .TILESET_EDITOR:
        update_tileset_editor()
        render_tileset_editor()
    }
    imgui_render()
    
    sdl.RenderPresent(renderer)
  }

  close_application()
}

imgui_new_frame :: proc() {
  imgui_impl_sdlrenderer2.NewFrame()
  imgui_impl_sdl2.NewFrame()
  imgui.NewFrame()
}

imgui_update :: proc() {
  if show_debug_window {
    flags : imgui.WindowFlags = { .NoNavInputs, .NoTitleBar, .NoCollapse, .NoMove }
    viewport : ^imgui.Viewport = imgui.GetMainViewport()
    imgui.SetNextWindowPos(viewport.Pos, .Always)
    imgui.SetNextWindowSize(viewport.Size, .Always)
    imgui.SetNextWindowBgAlpha(0.8)
    if imgui.Begin("Debug Window", &show_debug_window, flags) {
      if imgui.CollapsingHeader("Save / Load Level", {}) {
        @static level_path_buf : [64] u8 
        imgui.InputText("Level File Path", cstring(&level_path_buf[0]), len(level_path_buf), {})
        if imgui.Button("Save Level") {
          save_level(fmt.tprintf("data/levels/%v.world", cstring(&level_path_buf[0])))
        }
        imgui.SameLine()
        if imgui.Button("Load Level") {
          load_level(fmt.tprintf("data/levels/%v.world", cstring(&level_path_buf[0])))
        }
      }

      imgui.TreeNodeAny("EditorState", EditorState)
    }
    imgui.End()
  }
}

imgui_render :: proc() {
  imgui.Render()
  imgui_impl_sdlrenderer2.RenderDrawData(imgui.GetDrawData())
}

show_debug_window : bool