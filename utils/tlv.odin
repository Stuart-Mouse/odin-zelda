
package utils

import "core:strconv"
import "core:fmt"
import "core:slice"
import "core:strings"

TLV_Token :: struct {
    tag    : string,
    length : int,
    value  : string,
}

TLV_Format :: struct {
    tag_len  : int,
    len_len  : int,
}

TLV_DEFAULT_FORMAT : TLV_Format : {
    tag_len = 3,
    len_len = 3,
}

tlv_parse :: proc(str: string, using format := TLV_DEFAULT_FORMAT, allocator := context.allocator, loc := #caller_location) -> ([] TLV_Token, bool)  {
    str := str
    tokens := make([dynamic] TLV_Token, allocator, loc)

    for {
        if len(str) == 0 do break
        token : TLV_Token

        // read tag
        if len(str) < tag_len {
            delete(tokens)
            fmt.printf("TLV parse error on tag of token #%v\n", len(tokens))
            return nil, false
        }
        token.tag = strings.clone(str[:tag_len], allocator, loc)
        str       = str[tag_len:]

        // read length
        if len(str) < len_len {
            delete(tokens)
            fmt.printf("TLV parse error on length of token #%v: tag='%v'\n", len(tokens), token.tag)
            return nil, false
        }
        token.length = strconv.atoi(str[:len_len])
        str          = str[len_len:]

        // read value
        if len(str) < token.length {
            delete(tokens)
            fmt.printf("TLV parse error on value of token #%v: tag='%v', length='%v'\n", len(tokens), token.tag, token.length)
            return nil, false
        }
        token.value = strings.clone(str[:token.length], allocator, loc)
        str         = str[token.length:]

        fmt.printf("TLV Parsed tag='%v', length='%v', value='%v'\n", token.tag, token.length, token.value)

        append(&tokens, token)
    }

    return tokens[:], true
}

tlv_delete_tokens :: proc(tokens: ^[]TLV_Token) {
    for token in tokens {
        delete(token.tag)
        delete(token.value)
    }
    delete(tokens^)
    tokens^ = {}
}

// Read_Tag_Proc :: proc(tag_len: int, data: string, callback_data: rawptr) -> (tag: string, data_remaining: string, success: bool);
// Read_Len_Proc :: proc(len_len: int, data: string, callback_data: rawptr) -> (len: int   , data_remaining: string, success: bool);
// Read_Val_Proc :: proc(val_len: int, data: string, callback_data: rawptr) -> (val: string, data_remaining: string, success: bool);

// parse_generic :: proc(
//     data      : string, 
//     format    : Format, 
//     read_tag  : Read_Tag_Proc,
//     read_len  : Read_Len_Proc,
//     read_val  : Read_Val_Proc,
//     read_tag_data : rawptr,
//     read_len_data : rawptr,
//     read_val_data : rawptr,
// ) -> (
//     tokens: [dynamic] Token, 
//     success: bool
// ) {
//     data := data

//     success = false
//     defer if !success {
//         delete(tokens)
//         tokens = nil
//     }

//     for len(data) > 0 { 
//         token   : Token

//         token.tag   , data = read_tag(format.tag_len, data, read_tag_data) or_return
//         token.length, data = read_len(format.len_len, data, read_len_data) or_return
//         token.value , data = read_val( token.length , data, read_val_data) or_return

//         append(&tokens, token)
//     }

//     success = true
//     return 
// }

// extract_bytes :: proc(str: string, count: int) -> (extracted: string, remaining: string, success: bool)  {
//     if count > len(str) {
//         return
//     }
//     extracted = str[count:]
//     remaining = str[:count]
//     return 
// }


/*
    TODO: implement ability to parse TLV of different inner format.
    Currently, it only parses TLV in ascii, but perhaps we also want binary or BCD (packed or unpacked).
    The overall structure should be the same, so we may just be able to pass a lambda function to the main parsing proc.
    I generally don't like to have overly generalized procedures, but if it simplifies the code drastically, it may be worth making TLV parsing sort of a higher-order function.
*/

// TODO: add BERTLV parsing







