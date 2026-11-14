# JalaliX

<!-- jalalix:package lang=elixir hex=jalalix api=JalaliX parity=golden -->

Jalali (Persian / Shamsi) calendar for Elixir. Pure Elixir, no runtime timezone database required for UTC and Asia/Tehran (golden parity).

[![Hex.pm](https://img.shields.io/hexpm/v/jalalix.svg)](https://hex.pm/packages/jalalix)
[![license](https://img.shields.io/hexpm/l/jalalix.svg)](./LICENSE)

```bash
mix deps.get
# or: {:jalalix, "~> 0.1.0"}
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

`toISODate/1` uses local calendar getters. Prefer it when you need a calendar date string without UTC shift surprises.

## Install

```elixir
# mix.exs
defp deps do
  [{:jalalix, "~> 0.1.0"}]
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

`format` also accepts the older positional form: `format(d, str, persianDigits?, gregorian?)`.

### parseJalali

```elixir
JalaliX.parseJalali("1403/12/07")
JalaliX.parseJalali("۱۴۰۳-۱۲-۰۷ 14:30")
```

### toISODate

```elixir
d = JalaliX.create("2025-02-25")

JalaliX.toISODate(d)           # "2025-02-25"  (local Gregorian getters)
JalaliX.toISODate(d, "jalali") # "1403-12-07"
```

### add / start / end

```elixir
JalaliX.create("2025-02-25")
|> JalaliX.addMonths(1)
|> JalaliX.getStartOfMonth()
|> JalaliX.format("YYYY/MM/DD")
# => "1404/01/01"
```

### Persian digits

```elixir
JalaliX.toPersian("1403/12/07")   # "۱۴۰۳/۱۲/۰۷"
JalaliX.fromPersian("۱۴۰۳/۱۲/۰۷") # "1403/12/07"
```

## Months

This is easy to get wrong:

- `getMonth/1` -> 1..12 (Farvardin = 1)
- `setMonth/2` / `setFullYear/3` month arg -> 0..11, same as JS `Date` (Farvardin = 0)

```elixir
d = JalaliX.create(System.system_time(:millisecond))
d = JalaliX.setFullYear(d, 1404, 0, 1)  # 1 Farvardin 1404
JalaliX.getMonth(d)  # 1
```

Setters return a **new** `%JalaliX{}` (Elixir is immutable).

## Timezone

Internal storage is a **UTC Unix millisecond instant** plus an IANA timezone id. `setTimezone/2` is **instant-preserving**: the timestamp stays the same; wall clock / Jalali day may change.

```elixir
d = JalaliX.create(1_740_430_800_000)
tehran = JalaliX.setTimezone(d, "Asia/Tehran")
JalaliX.format(tehran, "YYYY/MM/DD")  # "1403/12/07"
JalaliX.format(tehran, "HH:mm:ss")    # "00:30:00"

utc = JalaliX.setTimezone(d, "UTC")
JalaliX.format(utc, "YYYY/MM/DD")  # "1403/12/06"
JalaliX.format(utc, "HH:mm:ss")    # "21:00:00"
```

- **Aliases:** `utc` / `gmt` -> `UTC`; `local` / `default` / `system` -> `TZ` env when known, else `UTC`.
- **Invalid zone** -> raises `ArgumentError`.
- Built-in fixed offsets include `UTC` and `Asia/Tehran` (+03:30; Iran abolished DST in 2022).

## Format tokens

| Token               |                                 |
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

Static:

- `create/1`, `create/2` — timestamp (ms), ISO string, `DateTime`, or `Date`
- `parseJalali/1`, `parseJalali/2`
- `isValidDate/1`
- `toPersian/1` / `fromPersian/1`
- `compare/2` — true if `a` is before `b`

`options` is `%{"timezone" => str}` (e.g. `"Asia/Tehran"`).

Instance (main ones; first arg is `%JalaliX{}`):

- `format/2`…`format/4`, `toISODate/1`, `toISODate/2`
- `toString/1`, `toDateString/1`, `toLocaleDateString/1`, `toLocaleTimeString/1`
- `getFullYear/1`, `getMonth/1`, `getDate/1`, `getDay/1`, …
- `setFullYear/2`…`setFullYear/4`, `setMonth/2`, `setDate/2`, `setHours/2`… (return new struct)
- `addYears/2`, `addMonths/2`, `addWeeks/2`, `addDays/2`
- `getStartOfYear/1` / `Month` / `Week` / `Day` and matching `getEndOf*`
- `clone/1`, `setTimezone/2`, `getTimezone/1`

Method names match the TypeScript package (camelCase).

## Links

- https://hex.pm/packages/jalalix
- https://jalalix.com
- https://github.com/jalalix/elixir
- [CHANGELOG.md](./CHANGELOG.md)

## License

MIT
