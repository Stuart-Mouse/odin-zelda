package utils

import "core:fmt"
import "core:unicode"
import "core:time"
import "core:strconv"
import "core:mem"
import "shared:imgui"


BERTLV_Token_Type :: enum u8 {
    EOC                 	    = 0x00,
    BOOLEAN						= 0x01,
    INTEGER						= 0x02,
    BIT_STRING					= 0x03,
    OCTET_STRING				= 0x04,
    NULL						= 0x05,
    OBJECT_IDENTIFIER			= 0x06,
    Object_Descriptor			= 0x07,
    EXTERNAL					= 0x08,
    REAL        				= 0x09,
    ENUMERATED					= 0x0A,
    EMBEDDED_PDV				= 0x0B,
    UTF8String					= 0x0C,
    RELATIVE_OID				= 0x0D,
    TIME						= 0x0E,
    Reserved					= 0x0F,
    SEQUENCE_and_SEQUENCE_OF	= 0x10,
    SET_and_SET_OF				= 0x11,
    NumericString				= 0x12,
    PrintableString				= 0x13,
    T61String					= 0x14,
    VideotexString				= 0x15,
    IA5String					= 0x16,
    UTCTime						= 0x17,
    GeneralizedTime				= 0x18,
    GraphicString				= 0x19,
    VisibleString				= 0x1A,
    GeneralString				= 0x1B,
    UniversalString				= 0x1C,
    CHARACTER_STRING			= 0x1D,
    BMPString					= 0x1E,
    DATE						= 0x1F,
    TIME_OF_DAY					= 0x20,
    DATE_TIME					= 0x21,
    DURATION					= 0x22,
    OID_IRI						= 0x23,
    RELATIVE_OID_IRI			= 0x24,
}

BERTLV_Tag_Class :: enum u8 {
    UNIVERSAL   = 0b_0000_0000,
    APPLICATION = 0b_0100_0000,
    CONTEXTUAL  = 0b_1000_0000,
    PRIVATE     = 0b_1100_0000,
}

BERTLV_Token :: struct {
    type  : BERTLV_Token_Type,
    tag   : [2] u8,
    value : [ ] u8,
}

parse_ber_tlv :: proc(
    data      : string, 
    allocator := context.allocator
) -> (
    []BERTLV_Token, bool,
) {
    data := data

    tokens := make([dynamic]BERTLV_Token, allocator)

    for len(data) > 0 {
        if len(data) < 2 {
            return {}, false
        }
    
        tag := data[:2]
    
        tag_class   := cast(BERTLV_Tag_Class) \
                                  (tag[0] & 0b_1100_0000)
        constructed := cast(bool) (tag[0] & 0b_0010_0000) 
        tag_type    := cast(int ) (tag[0] & 0b_0001_1111)
    
        // NOTE: if the EMV encoding does not allow for tags longer than 2 bytes, it may allow otherwise invalid tag type values which have the 8th bit set.
        //       currently, this situation woudl be parsed incorrectly.
        data = data[1:]
        if tag_type == 0b_0001_1111 {
            tag_type = 0
            for bool(data[0] & 0b_1000_0000) {
                if len(data) < 1 {
                    return {}, false
                }
                tag_type <<= 8
                tag_type |= cast(int) data[0]
                data = data[1:]
            }
        }

        if len(data) < 1 {
            return {}, false
        }
    
        if data[0] == 0b1000_0000  { // indefinite form
            data = data[1:]
            // TODO
        }
        else { // definite form
            content_len := 0
            if (data[0] == 0b1000_0000) { // long form
                len_len := cast(int) (data[0] & 0b_0111_1111)
                data = data[1:]
                if len(data) < len_len {
                    return {}, false
                }
    
                content_len := 0
                for i in 0..<len_len {
                    content_len <<= 8
                    content_len |= cast(int) data[i]
                }
                data = data[len_len:]
            } else { // short form
                content_len := cast(int) (data[0] & 0b_0111_1111)
                data = data[1:]
            }
    
            if len(data) < content_len {
                return {}, false
            }
    
            // TODO parse content
        } 
    }

    return tokens[:], true
}