# JalaliX - Elixir

<!-- jalalix:package lang=elixir hex=jalalix api=JalaliX parity=golden -->

Jalali (Persian / Shamsi) calendar on top of a millisecond Unix timestamp. Pure Elixir, no runtime timezone database required for UTC and Asia/Tehran (golden parity).

[![Hex.pm](https://img.shields.io/hexpm/v/jalalix.svg)](https://hex.pm/packages/jalalix)
[![license](https://img.shields.io/hexpm/l/jalalix.svg)](./LICENSE)

```bash
mix deps.get
# or add to mix.exs: {:jalalix, "~> 0.2.0"}
```

```elixir
d = JalaliX.create("2025-02-25")

JalaliX.format(d, "YYYY/MM/DD")
# => "1403/12/07"

JalaliX.format(d, "DD MMM YYYY", %{"persianDigits" => true})
# => "۰۷ اسفند ۱۴۰۳"

JalaliX.parseJalali("1403/12/07") |> JalaliX.toISODate()
# => "2025-02-25"
```

`toISODate/1` uses wall-clock getters in the active timezone. Prefer it over UTC-based formatting when you need a calendar date string.

## Install

```elixir
# mix.exs
defp deps do
  [{:jalalix, "~> 0.2.0"}]
end
```

```elixir
d = JalaliX.create("2025-02-25")
```

## Usage

### create / format

```elixir
now = JalaliX.create(System.system_time(:millisecond), %{"timezone" => "Asia/Tehran"})

JalaliX.format(now, "YYYY/MM/DD")
JalaliX.format(now, "WN، DD MMM YYYY")
JalaliX.format(now, "YYYY/MM/DD", %{"persianDigits" => true})
JalaliX.format(now, "DD MMM YYYY", %{"calendar" => "gregorian"})
```

`format/4` also accepts the older positional form: `format(d, str, persianDigits?, gregorian?)`.

### parseJalali

```elixir
JalaliX.parseJalali("1403/12/07")
JalaliX.parseJalali("۱۴۰۳-۱۲-۰۷ 14:30")
JalaliX.parseJalali("1403.12.07")
```

Accepts `/`, `-`, or `.` as the date separator.

### normalizeQueryDate

Soft-normalize loose API/query date values to Gregorian `Y-m-d H:i:s` (or `nil`). Does not raise on junk input.

```elixir
JalaliX.normalizeQueryDate("1403/12/07", %{"timezone" => "Asia/Tehran"})
# => "2025-02-25 00:00:00"

JalaliX.normalizeQueryDate("undefined")  # nil
JalaliX.normalizeQueryDate(1_740_430_800_000, %{"timezone" => "Asia/Tehran"})
# => "2025-02-25 00:30:00"
```

Handles sentinels (`nil`, `""`, `"null"`, `"undefined"`, `"Invalid Date"`, `NaN`) → `nil`; unix timestamps (seconds or milliseconds; non-positive → `nil`); Persian/Arabic-Indic digits; `/` `-` `.` separators.

Detects Jalali when the year is in `"jalaliYearMin"`…`"jalaliYearMax"` (default `1`…`1899`) **and** the civil date is valid; otherwise Gregorian when valid, or returns the digit-cleaned string. Other types pass through unchanged.

### toISODate

```elixir
d = JalaliX.create("2025-02-25T00:30:00+03:30")

JalaliX.toISODate(d)           # "2025-02-25"
JalaliX.toISODate(d, "jalali") # "1403-12-07"
```

### add / start / end

```elixir
JalaliX.create("2025-02-25")
|> JalaliX.addMonths(1)
|> JalaliX.getStartOfMonth()
|> JalaliX.format("YYYY/MM/DD")
# => "1404/01/01"

d = JalaliX.create("2025-02-25", %{"timezone" => "Asia/Tehran"})
d |> JalaliX.addDays(7) |> JalaliX.format("YYYY/MM/DD")
d |> JalaliX.getEndOfWeek() |> JalaliX.format("YYYY/MM/DD")
```

### Persian / Arabic digits

```elixir
JalaliX.toPersian("1403/12/07")   # "۱۴۰۳/۱۲/۰۷"
JalaliX.fromPersian("۱۴۰۳/۱۲/۰۷") # "1403/12/07"
JalaliX.fromPersian("١٤٠٣/١٢/٠٧") # "1403/12/07" (Arabic-Indic)
```

## Timezone

Internal storage is always a **UTC Unix millisecond instant** plus an IANA timezone id. `setTimezone/2` is **instant-preserving**: the timestamp stays the same; only the zone (and therefore wall clock / Jalali day) changes.

```elixir
d = JalaliX.create(1_740_430_800_000) # 2025-02-25T00:30:00+03:30

tehran = JalaliX.setTimezone(d, "Asia/Tehran")
JalaliX.format(tehran, "YYYY/MM/DD")  # "1403/12/07"
JalaliX.format(tehran, "HH:mm")        # "00:30"

utc = JalaliX.setTimezone(d, "UTC")
JalaliX.format(utc, "YYYY/MM/DD")  # "1403/12/06"
JalaliX.format(utc, "HH:mm")      # "21:00"

JalaliX.getTime(tehran) == JalaliX.getTime(utc)  # true
```

- **Aliases:** `utc` / `gmt` → `UTC`; `local` / `default` / `system` → `TZ` env when known, else `UTC`.
- **Invalid zone** → raises `ArgumentError`.
- Built-in fixed offsets include `UTC` and `Asia/Tehran` (+03:30; Iran abolished DST in 2022).

```elixir
JalaliX.create(System.system_time(:millisecond), %{"timezone" => "Asia/Tehran"})
```

## Months

Easy to get wrong:

- `getMonth/1` → **1…12** (Farvardin = 1)
- `setMonth/2` / `setFullYear/3` month argument → **0…11**, same as JS `Date` (Farvardin = 0)

```elixir
d = JalaliX.create(System.system_time(:millisecond))
d = JalaliX.setFullYear(d, 1404, 0, 1)  # 1 Farvardin 1404
JalaliX.getMonth(d)  # 1
```

Setters return a **new** `%JalaliX{}` (values are immutable).

## Format tokens

| Token               | Meaning                         |
| ------------------- | ------------------------------- |
| `YYYY` `YY`         | year                            |
| `MMM` `MM` `M`      | month name / number             |
| `DD` `D`            | day                             |
| `HH` `hh` `mm` `ss` | time                            |
| `A` `a`             | meridiem (ق.ظ. / ب.ظ. or AM/PM) |
| `WN` `WL`           | weekday name / letter           |
| `w` `DDD`           | week of year / day of year      |
| `X` `x`             | unix seconds / ms               |

## API

The API is **module-level**: pass `%JalaliX{}` as the first argument for instance operations. Method names match the TypeScript package (camelCase). Options maps use string keys such as `"timezone"`, `"persianDigits"`, `"calendar"`, `"jalaliYearMin"`, and `"jalaliYearMax"`.

### `JalaliX` struct

| API          | Description                                                              |
| ------------ | ------------------------------------------------------------------------ |
| `%JalaliX{}` | Opaque struct holding `ms` (unix milliseconds) and `timezone` (IANA id). |

### Module - static

| API                                            | Description                                                                                                     |
| ---------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `create/1`, `create/2`                         | Build from unix ms, ISO string, `DateTime`, `Date`, or `NaiveDateTime`. Optional options map with `"timezone"`. |
| `parseJalali/1`, `parseJalali/2`               | Parse a Jalali date/time string (`/` `-` `.`, Persian/Arabic digits, optional time).                            |
| `normalizeQueryDate/1`, `normalizeQueryDate/2` | Soft-normalize loose query/form values → Gregorian `Y-m-d H:i:s` or `nil`.                                      |
| `isValidDate/1`                                | `true` for `%JalaliX{}`, `Date`, `DateTime`, or `NaiveDateTime`.                                                |
| `toPersian/1`                                  | Replace Western digits `0-9` with Persian `۰-۹`.                                                                |
| `fromPersian/1`                                | Replace Persian `۰-۹` and Arabic-Indic `٠-٩` with Western digits.                                               |
| `compare/2`                                    | `true` if the first struct is strictly before the second (by unix ms).                                          |

### Module - getters (instance)

| API                                                                  | Description                                                           |
| -------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `getFullYear/1`                                                      | Jalali year in the active timezone.                                   |
| `getMonth/1`                                                         | Jalali month **1…12** (Farvardin = 1).                                |
| `getDate/1`                                                          | Jalali day of month **1…31**.                                         |
| `getDay/1`                                                           | Weekday **1…7** (Saturday = 1 … Friday = 7).                          |
| `getHours/1` / `getMinutes/1` / `getSeconds/1` / `getMilliseconds/1` | Wall-clock time in the active timezone.                               |
| `getTime/1`                                                          | Unix timestamp in milliseconds (UTC instant).                         |
| `getTimezone/1`                                                      | Active IANA timezone id.                                              |
| `getWeekOfYear/1`                                                    | Jalali week-of-year (1-based).                                        |
| `getDayOfYear/1`                                                     | Day of Jalali year (1…365/366).                                       |
| `getDayISO/1`                                                        | ISO-style weekday index used internally for week math.                |
| `getHoursISO/1`                                                      | Hours in 0…23 for formatting helpers.                                 |
| `getMeridiem/1`                                                      | Localized meridiem string (ق.ظ./ب.ظ. or AM/PM depending on calendar). |

### Module - setters (instance)

| API                              | Description                                                     |
| -------------------------------- | --------------------------------------------------------------- |
| `setTime/2`                      | Set the UTC instant from unix milliseconds; returns new struct. |
| `setMilliseconds/2`              | Set milliseconds (wall clock).                                  |
| `setSeconds/2`, `setSeconds/3`   | Set seconds (and optional ms).                                  |
| `setMinutes/2`…`setMinutes/4`    | Set minutes (and optional lower units).                         |
| `setHours/2`…`setHours/5`        | Set hours (and optional lower units).                           |
| `setDate/2`                      | Set Jalali day of month.                                        |
| `setMonth/2`, `setMonth/3`       | Set Jalali month **0…11** (Farvardin = 0); optional day.        |
| `setFullYear/2`…`setFullYear/4`  | Set Jalali year; optional month **0…11** and day.               |
| `setTimezone/1`, `setTimezone/2` | Instant-preserving zone change; returns new struct.             |

### Module - math, range, format (instance)

| API                                                                               | Description                                                   |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `addYears/2` / `addMonths/2` / `addWeeks/2` / `addDays/2`                         | Add calendar units; return new struct.                        |
| `getStartOfYear/1` / `getStartOfMonth/1` / `getStartOfWeek/1` / `getStartOfDay/1` | Start of unit.                                                |
| `getEndOfYear/1` / `getEndOfMonth/1` / `getEndOfWeek/1` / `getEndOfDay/1`         | End of unit.                                                  |
| `format/2`…`format/4`                                                             | Format with tokens above; options map or positional booleans. |
| `toISODate/1`, `toISODate/2`                                                      | `YYYY-MM-DD` in `"gregorian"` (default) or `"jalali"`.        |
| `clone/1`                                                                         | Copy with the same instant and timezone.                      |
| `toString/1` / `toDateString/1` / `toLocaleDateString/1` / `toLocaleTimeString/1` | String views of the date/time.                                |

## Links

- https://hex.pm/packages/jalalix
- https://jalalix.com
- https://github.com/jalalix/elixir
- [CHANGELOG.md](./CHANGELOG.md)

## License

MIT
