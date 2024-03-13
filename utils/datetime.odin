package utils

import "core:strconv"
import "core:time"
import "core:fmt"
import "core:strings"

Date_Time_Format :: struct {
    total_length : int,
    Y, M, D, h, m, s : struct {
        start, count : int
    }
}

DT_FORMAT_YYMM :: Date_Time_Format {
    total_length = 4,
    Y = { 0, 2 },
    M = { 2, 2 },
}

DT_FORMAT_MMDD :: Date_Time_Format {
    total_length = 4,
    M = { 0, 2 },
    D = { 2, 2 },
}

DT_FORMAT_YYMMDD :: Date_Time_Format {
    total_length = 64,
    Y = { 0, 2 },
    M = { 2, 2 },
    D = { 4, 2 },
}

DT_FORMAT_hhmmss :: Date_Time_Format {
    total_length = 6,
    h = { 0, 2 },
    m = { 2, 2 },
    s = { 4, 2 },
}

DT_FORMAT_MMDDhhmmss :: Date_Time_Format {
    total_length = 10,
    M = { 0, 2 },
    D = { 2, 2 },
    h = { 4, 2 },
    m = { 6, 2 },
    s = { 8, 2 },
}

parse_date_time_format :: proc(str: string) -> (Date_Time_Format, bool) {
    format : Date_Time_Format
    char   : u8
    start  : int
    count  : int

    i := 0
    for i < len(str) {
        char  = str[i]
        start = i
        count = 0

        for i < len(str) && char == str[i] {
            count += 1
            i     += 1
        }

        switch char {
            case 'Y': 
                if format.Y != {} {
                    fmt.println("Invalid date time format string.")
                    return {}, false
                }
                format.Y = { start, count }
            case 'M': 
                if format.M != {} {
                    fmt.println("Invalid date time format string.")
                    return {}, false
                }
                format.M = { start, count }
            case 'D':
                if format.D != {} {
                    fmt.println("Invalid date time format string.")
                    return {}, false
                }
                format.D = { start, count }
            case 'h':
                if format.h != {} {
                    fmt.println("Invalid date time format string.")
                    return {}, false
                }
                format.h = { start, count }
            case 'm':
                if format.m != {} {
                    fmt.println("Invalid date time format string.")
                    return {}, false
                }
                format.m = { start, count }
            case 's':
                if format.s != {} {
                    fmt.println("Invalid date time format string.")
                    return {}, false
                }
                format.s = { start, count }
            case: return {}, false
        }
    }

    format.total_length = format.Y.count + format.M.count + format.D.count + format.h.count + format.m.count + format.s.count 
    return format, true
}

parse_date_time :: proc(data: string, encoding: Data_Encoding, format: Date_Time_Format) -> (time.Time, bool){
    now := time.now()

    year, month_enum, day := time.date(now)
    month := int(month_enum)    // bad api for time.Date returns month as an enum, but datetime_to_time takes month as int
    hour, minute, second : int

    ok : bool
    if format.Y.count != 0 {
        year  , ok = extract_numeric(data, encoding, format.Y.start, format.Y.count)
        if !ok {
            fmt.println("Unable to parse date time string.")
            return {}, false
        }
        year += 2000 // compensate for 2 digit year, I suppose you would just have to update this value every century
    }
    if format.M.count != 0 {
        month , ok = extract_numeric(data, encoding, format.M.start, format.M.count)
        if !ok {
            fmt.println("Unable to parse date time string.")
            return {}, false
        }
    }
    if format.D.count != 0 {
        day   , ok = extract_numeric(data, encoding, format.D.start, format.D.count)
        if !ok {
            fmt.println("Unable to parse date time string.")
            return {}, false
        }
    }
    if format.h.count != 0 {
        hour  , ok = extract_numeric(data, encoding, format.h.start, format.h.count)
        if !ok {
            fmt.println("Unable to parse date time string.")
            return {}, false
        }
    }
    if format.m.count != 0 {
        minute, ok = extract_numeric(data, encoding, format.m.start, format.m.count)
        if !ok {
            fmt.println("Unable to parse date time string.")
            return {}, false
        }
    }
    if format.s.count != 0 {
        second, ok = extract_numeric(data, encoding, format.s.start, format.s.count)
        if !ok {
            fmt.println("Unable to parse date time string.")
            return {}, false
        }
    }

    // range check on month prevents a crash in time module
    if month < 1 || month > 12 {
        fmt.println("Invalid date time string, month was outside of valid range.")
        return {}, false
    }
    return time.datetime_to_time(year, month, day, hour, minute, second)
}

// returns number of characters written to the buffer or -1 on failure
serialize_date_time :: proc(data: [] u8, spec: Data_Spec, t: time.Time, format: Date_Time_Format) -> int {
    if len(data) < format.total_length {
        fmt.println("Unable to serialize date time string, provided buffer is too small.")
        return -1
    }

    year, month_enum, day := time.date(t)
    hour, minute, second  := time.clock(t)
    month := int(month_enum) // bad api for time.Date returns month as an enum, but datetime_to_time takes month as int

    ok : bool
    if format.Y.count != 0 {
        year %= 100
        if insert_numeric(data, spec, format.Y.start, format.Y.count, year) < 0 {
            fmt.println("Unable to serialize date time string.")
            return -1
        }
    }
    if format.M.count != 0 {
        if insert_numeric(data, spec, format.M.start, format.M.count, month) < 0 {
            fmt.println("Unable to serialize date time string.")
            return -1
        }
    }
    if format.D.count != 0 {
        if insert_numeric(data, spec, format.D.start, format.D.count, day) < 0 {
            fmt.println("Unable to serialize date time string.")
            return -1
        }
    }
    if format.h.count != 0 {
        if insert_numeric(data, spec, format.h.start, format.h.count, hour) < 0 {
            fmt.println("Unable to serialize date time string.")
            return -1
        }
    }
    if format.m.count != 0 {
        if insert_numeric(data, spec, format.m.start, format.m.count, minute) < 0 {
            fmt.println("Unable to serialize date time string.")
            return -1
        }
    }
    if format.s.count != 0 {
        if insert_numeric(data, spec, format.s.start, format.s.count, second) < 0 {
            fmt.println("Unable to serialize date time string.")
            return -1
        }
    }

    return format.total_length
}

datetime_from_date_and_time :: proc(d, t: time.Time) -> (time.Time, bool) {
    year, month, day     := time.date(d)
    hour, minute, second := time.clock(t)
    return time.datetime_to_time(year, int(month), day, hour, minute, second)
}

