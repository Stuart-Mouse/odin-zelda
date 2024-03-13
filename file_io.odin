package main

import "core:os"
import "core:fmt"
import "core:mem"
import "core:strconv"
import "shared:gon"

// load_tile_info :: proc() -> bool {
//   file, ok := os.read_entire_file("data/tiles.gon")
//   if !ok {
//     fmt.println("Unable to open tile info file!")
//     return false
//   }
//   defer delete(file)

//   clear(&tile_info_lookup)
//   {
//     empty_tile_ti : Tile_Info
//     empty_tile_name := "Emtpy Tile"
//     mem.copy(&empty_tile_ti.name, raw_data(empty_tile_name), len(empty_tile_name)) 
//     append(&tile_info_lookup, empty_tile_ti)
//   }

//   parse_context := gon.SAX_Parse_Context {
//     file = string(file),
//     data_bindings = {
//       {
//         binding    = tile_info_lookup,
//         field_path = {"tiles"},
//       },
//     },
//   }
 
//   if !gon.SAX_parse_file(&parse_context) {
//     fmt.println("Unable to parse gon!")
//     return false
//   }

//   return true
// }

load_tile_info :: proc() -> bool {
  file, ok := os.read_entire_file("data/tiles.gon")
  if !ok {
    fmt.println("Unable to open tile info file!")
    return false
  }
  defer delete(file)

  gon_file : gon.DOM_File
  gon_file, ok = gon.DOM_parse_file(string(file))
  if !ok {
    fmt.println("Unable to parse gon!")
    return false
  }
  defer gon.DOM_file_destroy(&gon_file)

  using gon_file

  clear(&tile_info_lookup)
  {
    empty_tile_ti : Tile_Info
    empty_tile_name := "Emtpy Tile"
    mem.copy(&empty_tile_ti.name, raw_data(empty_tile_name), len(empty_tile_name)) 
    append(&tile_info_lookup, empty_tile_ti)
  }

  for gon_tile_i in fields[0].children {
    gon_tile := fields[gon_tile_i]
    
    ti : Tile_Info
    mem.copy(
      raw_data(ti.name[:]), 
      raw_data(gon_tile.name), 
      min(32, len(gon_tile.name)),
    )

    // set collision value
    collision := gon.get_value_or_default(&gon_file, gon_tile_i, "collision", {})
    switch collision {
      case "solid": ti.collision = .SOLID
      case "ledge": ti.collision = .LEDGE
    }

    // set frames
    ReadFrames: {
      gon_frames_i, ok := gon.get_child_by_name(&gon_file, gon_tile_i, "frames")
      gon_frames := fields[gon_frames_i]
      if !ok || gon_frames.type != .ARRAY {
        fmt.println("Error: Frames array was missing or wrong type.")
        return false
      }
      ti.animation.frame_count = cast(i32) len(gon_frames.children)

      for field_i, frame_i in gon_frames.children {
        gon_frame := fields[field_i]
        if gon_frame.type != .ARRAY {
          fmt.println("Error: Invalid frame in frames.")
          return false
        }

        switch len(gon_frame.children) {
          case 3:
            ti.animation.frames[frame_i].duration = cast(i32) strconv.atoi(gon_file.fields[gon_frame.children[2]].value)
            fallthrough
          case 2:
            ti.animation.frames[frame_i].clip_offset.x = cast(i32)strconv.atoi(gon_file.fields[gon_frame.children[0]].value)
            ti.animation.frames[frame_i].clip_offset.y = cast(i32)strconv.atoi(gon_file.fields[gon_frame.children[1]].value)
          case:
            fmt.println("Error: Invalid frame in frames.")
            return false
        }
      }
    }

    append(&tile_info_lookup, ti)
  }
  
  return true
}