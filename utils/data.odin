package utils

import "core:strconv"
import "core:time"
import "core:fmt"
import "core:strings"

Data_Spec :: struct {
    encoding : Data_Encoding,
    pad_type : Data_Pad, 
    pad_byte : byte,
    size     : int,
}
Data_Encoding :: enum u8 { 
    BINARY, 
    ASCII, 
    EBCDIC, 
    BCD, 
}
Data_Pad :: enum u8 {
    NONE,
    LEFT,
    RIGHT,
}

count_digits :: proc(value: int, base := 10) -> int {
    value  := value
    digits := 0
    for value > 0 {
        digits += 1
        value /= base
    }
    return digits
}

extract_numeric :: proc(
    data         : string, 
    encoding     : Data_Encoding, 
    start, count : int,
    base         := 10, // ignored when encoding is BCD
) -> (int, bool) {
    if start < 0 || count <= 0 {
        return 0, false
    }

    start := start
    end   := start + count
    data  := data

    #partial switch encoding {
        case .EBCDIC:
            if end > len(data) do return 0, false
            data = ascii_to_ebcdic_string(
                data[start:end], 
                context.temp_allocator,
            )
            fallthrough
            
        case .ASCII:
            // For credit/debit fields, C indicates a positive value and D indicates a negative value.
            // If either character is present, trim it before tring to convert the string to an integer.
            if end > len(data) do return 0, false
            if data[start] == 'C' || data[start] == 'D' {
                start += 1
            }
            result := strconv.atoi(data[start:end])
            if data[start] == 'D' {
                result = -result
            }
            return result, true
            
        case .BCD:
            // TODO: consider factoring this logic into the bcd_to_int proc.
            trim_left  := bool(start & 1 != 0)
            trim_right := bool(end   & 1 != 0)
            byte_start := start / 2
            byte_end   := end   / 2 + int(trim_right)
            if byte_end > len(data) do return 0, false
            return bcd_to_int(
                data[byte_start:byte_end],
                trim_left,
                trim_right,
            ), true

        case:
            return 0, false
    }
}

insert_numeric :: proc(data: []u8, spec: Data_Spec, start, count, value: int, radix := 10) -> int {
    if start < 0 do return -1
    end := count > 0 ? start + count : len(data)

    #partial switch spec.encoding {
        case .BCD: // only supports base 10! base param will be ignored
            nibbles_required := count_digits(value)
            bytes_required   := (nibbles_required / 2) + (nibbles_required & 1)
            if len(data) < bytes_required {
                return -1
            }
            odd_end    := bool(end & 1 != 0)
            byte_start := (start / 2)
            byte_end   := (end   / 2) + int(odd_end)
            if byte_end > len(data) do return -1
            return int_to_bcd(
                value,
                data[byte_start:byte_end],
                odd_end,
                count,
            )

        case .ASCII:
            // TODO: improve?
            bytes_required := count_digits(value, radix)
            if itoa_left_pad(data[start:start+count], value, radix) {
                return bytes_required
            }
            return -1

        // case .EBCDIC:
    }
    return -1
}

extract_text_copy :: proc(data: string, spec: Data_Spec, start, count: int, allocator := context.allocator) -> (string, bool) {
    if start < 0 do return {}, false
    end := count > 0 ? start + count : len(data)

    #partial switch spec.encoding {
        case .BCD:
            return {}, false
        case .ASCII:
            if end > len(data) {
                return {}, false
            }
            return strings.clone(data[start:end], allocator), true
        case .EBCDIC:
            if end > len(data) {
                return {}, false
            }
            result, err := strings.clone(data[start:end], allocator)
            if err != nil do return {}, false
            ebcdic_to_ascii_bytes(transmute([]u8) result)
            return result, true
    }
    return {}, false
}

extract_tlv_text :: proc(data: string, spec: Data_Spec, format := TLV_DEFAULT_FORMAT, allocator := context.allocator) -> ([] TLV_Token, bool) {
    #partial switch spec.encoding {
        case .ASCII:
            return tlv_parse(data, format, allocator)
        case .EBCDIC:
            // TODO: this string clone is a memory leak since we lose the pointer to this string and never free it, because we need it for the TLV data.
            // Either we can also return a string to the new buffer for the user to handle, or we can make all TLV tokens be individual allocations that are owned by the TLV_Tokens array.
            result, err := strings.clone(data, allocator)
            if err != nil {
                return {}, false
            }
            ebcdic_to_ascii_bytes(transmute([]u8) result)
            return tlv_parse(data, format, allocator)
    }
    return {}, false
}

/*
    Length can be in any numeric format.
    Tag and Value are extracted as raw bytes.
    If you need to perform post-processing on tag or value, 
        that should be done in a separate step.
*/
extract_tlv_data :: proc(
    data         : string, 
    len_encoding : Data_Encoding, 
    format       := TLV_DEFAULT_FORMAT, 
    allocator    := context.allocator,
) -> (
    tokens  : [] TLV_Token, 
    success : bool,
) {
    data := data
    _tokens := make([dynamic] TLV_Token, allocator)
    defer if !success {
        delete(tokens)
    }
    success = false

    for {
        if len(data) == 0 do break
        token : TLV_Token

        if len(data) < format.tag_len do return
        token.tag = data[:format.tag_len]
        data      = data[format.tag_len:]

        token.length = extract_numeric(data, len_encoding, 0, format.len_len) or_return 
        data         = data[format.len_len:]

        if len(data) < token.length do return
        token.value = data[:token.length]
        data        = data[token.length:]

        append(&_tokens, token)
    }

    tokens  = _tokens[:]
    success = true
    return
}

