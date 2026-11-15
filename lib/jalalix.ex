defmodule JalaliX do
  @moduledoc """
  Jalali (Persian / Shamsi) calendar for Elixir.

  Pure Elixir, no runtime timezone database dependency. Internally a
  `JalaliX` value is a UTC Unix millisecond instant (`ms`) plus an active
  IANA-style timezone id (`timezone`). Timezone support is intentionally
  simple: offsets for `UTC` and `Asia/Tehran` are hardcoded (Iran has not
  observed DST since 2022, so `Asia/Tehran` is a fixed `+03:30` offset
  year-round). `setTimezone/2` is **instant-preserving**: `getTime/1` stays
  the same; only the wall-clock / Jalali display changes.

  Elixir is immutable, so every "setter" returns a **new** `%JalaliX{}`
  struct rather than mutating in place.

  Method names intentionally mirror the TypeScript/Python ports
  (`@jalalix/typescript`, `jalalix` on PyPI) using camelCase, so porting
  code between languages is mostly 1:1.

  ## Month quirk

  Just like the JS/Python ports:

    * `getMonth/1` is **1-based** (Farvardin = 1 .. Esfand = 12)
    * `setMonth/2,3` and `setFullYear/2,3,4` take a **0-based** month
      (Farvardin = 0 .. Esfand = 11), matching JS `Date`.

  ## Example

      iex> d = JalaliX.create("2025-02-25")
      iex> JalaliX.format(d, "YYYY/MM/DD")
      "1403/12/07"
      iex> JalaliX.parseJalali("1403/12/07") |> JalaliX.toISODate()
      "2025-02-25"
  """

  @enforce_keys [:ms, :timezone]
  defstruct ms: 0, timezone: "UTC"

  @type t :: %__MODULE__{ms: integer(), timezone: String.t()}

  @date_length 86_400_000
  @leap_year_division 0.24219858156
  @first_day_of_week 6

  @persian_numbers ["۰", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹"]

  @week_days_names ["شنبه", "یکشنبه", "دوشنبه", "سه شنبه", "چهار شنبه", "پنج شنبه", "جمعه"]
  @week_days_letters ["ش", "ی", "د", "س", "چ", "پ", "ج"]

  @week_days_gregorian_names [
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday"
  ]

  @week_days_gregorian_letters ["S", "M", "T", "W", "T", "F", "S"]

  @months_names [
    "فروردین",
    "اردیبهشت",
    "خرداد",
    "تیر",
    "مرداد",
    "شهریور",
    "مهر",
    "آبان",
    "آذر",
    "دی",
    "بهمن",
    "اسفند"
  ]

  @months_gregorian_names [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December"
  ]

  @am "ق.ظ."
  @pm "ب.ظ."
  @am_gregorian "AM"
  @pm_gregorian "PM"

  # Hardcoded fixed (DST-less) UTC offsets, in milliseconds.
  @offsets %{
    "UTC" => 0,
    "Etc/UTC" => 0,
    "GMT" => 0,
    # Iran abolished DST in 2022; +03:30 year-round.
    "Asia/Tehran" => 12_600_000
  }

  @base_jalali %{year: 1348, month: 10, day: 11}

  @doc """
  Creates a `JalaliX` instance from a Gregorian date value.

  Accepts a Unix millisecond timestamp (`integer`/`float`), an ISO8601
  string, a `Date`/`DateTime`/`NaiveDateTime`, or another `JalaliX`.

  `opts` may contain `timezone:` to set the active zone (map or keyword list).
  """
  @spec create(
          integer() | float() | String.t() | Date.t() | DateTime.t() | NaiveDateTime.t() | t(),
          map() | keyword()
        ) ::
          t()
  def create(date, opts \\ %{}) do
    ms = parse_input(date)
    base = %__MODULE__{ms: ms, timezone: "UTC"}

    case opt_timezone(opts) do
      nil -> base
      tz -> setTimezone(base, tz)
    end
  end

  @doc """
  Parses a Jalali date string into a `JalaliX` instance.

  Accepts `YYYY/MM/DD` or `YYYY-MM-DD`, optional time (`HH:mm` / `HH:mm:ss`),
  and Persian digits.
  """
  @spec parseJalali(String.t(), map() | keyword()) :: t()
  def parseJalali(value, opts \\ %{}) do
    normalized =
      value
      |> to_string()
      |> fromPersian()
      |> String.trim()

    regex = ~r/^(\d{4})[\/-](\d{1,2})[\/-](\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?$/

    case Regex.run(regex, normalized) do
      nil ->
        raise ArgumentError, "JalaliX.parseJalali: invalid Jalali date #{inspect(value)}"

      [_full, year_s, month_s, day_s | rest] ->
        year = String.to_integer(year_s)
        month = String.to_integer(month_s)
        day = String.to_integer(day_s)
        hours = group_int(rest, 0)
        minutes = group_int(rest, 1)
        seconds = group_int(rest, 2)

        if month < 1 or month > 12 or day < 1 or day > 31 do
          raise ArgumentError, "JalaliX.parseJalali: invalid Jalali date #{inspect(value)}"
        end

        System.os_time(:millisecond)
        |> create(opts)
        |> setFullYear(year, month - 1, day)
        |> setHours(hours, minutes, seconds, 0)
    end
  end

  @doc "Returns true if `value` is a recognized date-like value."
  @spec isValidDate(any()) :: boolean()
  def isValidDate(%__MODULE__{}), do: true
  def isValidDate(%Date{}), do: true
  def isValidDate(%DateTime{}), do: true
  def isValidDate(%NaiveDateTime{}), do: true
  def isValidDate(_), do: false

  @doc "Converts Western numerals (0-9) to Persian numerals (۰-۹) in a string."
  @spec toPersian(String.t()) :: String.t()
  def toPersian(s) do
    Enum.reduce(0..9, s, fn i, acc ->
      String.replace(acc, Integer.to_string(i), Enum.at(@persian_numbers, i))
    end)
  end

  @doc "Converts Persian numerals (۰-۹) to Western numerals (0-9) in a string."
  @spec fromPersian(String.t()) :: String.t()
  def fromPersian(s) do
    Enum.reduce(0..9, s, fn i, acc ->
      String.replace(acc, Enum.at(@persian_numbers, i), Integer.to_string(i))
    end)
  end

  @doc "Returns true if `a` is before `b`."
  @spec compare(t(), t()) :: boolean()
  def compare(%__MODULE__{} = a, %__MODULE__{} = b), do: getTime(a) < getTime(b)

  @doc "Creates a copy of this `JalaliX` instance (same instant and timezone)."
  @spec clone(t()) :: t()
  def clone(%__MODULE__{ms: ms, timezone: tz}), do: %__MODULE__{ms: ms, timezone: tz}

  @doc "Gets the active IANA timezone id of this instance."
  @spec getTimezone(t()) :: String.t()
  def getTimezone(%__MODULE__{timezone: tz}), do: tz

  @doc """
  Creates a new `JalaliX` with the same UTC instant in a different timezone.

  Instant-preserving: `getTime/1` is unchanged; wall clock / Jalali day may
  change. Aliases: `local`/`system`/`default` -> host zone (or `UTC`),
  `utc`/`gmt` -> `UTC`. Raises `ArgumentError` for an unrecognized zone.
  """
  @spec setTimezone(t(), String.t() | nil) :: t()
  def setTimezone(%__MODULE__{} = j, tz \\ nil) do
    new_tz = normalize_timezone(tz, j.timezone)
    %__MODULE__{ms: j.ms, timezone: new_tz}
  end

  @doc "Full date string with weekday, day, month, year, and time."
  @spec toString(t()) :: String.t()
  def toString(%__MODULE__{} = j) do
    jalali = to_jalali(j)

    "#{get_week_day_name(j)} #{add_zero(jalali.day)} #{get_jalali_month_name(jalali.month)} " <>
      "#{add_zero(jalali.year)} #{jalali.hours}:#{add_zero(jalali.min)}:#{add_zero(jalali.sec)}" <>
      get_utc_timezone(j)
  end

  @doc "Date string with weekday, day, month, and year (no time)."
  @spec toDateString(t()) :: String.t()
  def toDateString(%__MODULE__{} = j) do
    jalali = to_jalali(j)

    "#{get_week_day_name(j)} #{add_zero(jalali.day)} #{get_jalali_month_name(jalali.month)} " <>
      add_zero(jalali.year)
  end

  @doc "Locale-formatted date string: `YYYY/MM/DD`."
  @spec toLocaleDateString(t()) :: String.t()
  def toLocaleDateString(%__MODULE__{} = j) do
    jalali = to_jalali(j)
    "#{add_zero(jalali.year)}/#{add_zero(jalali.month)}/#{add_zero(jalali.day)}"
  end

  @doc "Time string with meridiem, e.g. `10:30:45 ق.ظ.`."
  @spec toLocaleTimeString(t()) :: String.t()
  def toLocaleTimeString(%__MODULE__{} = j) do
    jalali = to_jalali(j)
    "#{rem(jalali.hours, 12)}:#{add_zero(jalali.min)}:#{add_zero(jalali.sec)} #{getMeridiem(j)}"
  end

  @doc "Gets the Jalali year."
  @spec getFullYear(t()) :: integer()
  def getFullYear(%__MODULE__{} = j), do: to_jalali(j).year

  @doc "Gets the Jalali month (1-12, Farvardin = 1)."
  @spec getMonth(t()) :: integer()
  def getMonth(%__MODULE__{} = j), do: to_jalali(j).month

  @doc "Gets the day of the month in the Jalali calendar (1-31)."
  @spec getDate(t()) :: integer()
  def getDate(%__MODULE__{} = j), do: to_jalali(j).day

  @doc "Gets the day of the week (1=Saturday .. 7=Friday in Jalali)."
  @spec getDay(t()) :: integer()
  def getDay(%__MODULE__{} = j) do
    Integer.mod(js_day(j) - @first_day_of_week + 7 + 1, 7)
  end

  @doc "Gets the hour (0-23) using wall time in the active timezone."
  @spec getHours(t()) :: integer()
  def getHours(%__MODULE__{} = j), do: local_parts(j).hour

  @doc "Gets the minutes (0-59) using wall time in the active timezone."
  @spec getMinutes(t()) :: integer()
  def getMinutes(%__MODULE__{} = j), do: local_parts(j).minute

  @doc "Gets the seconds (0-59) using wall time in the active timezone."
  @spec getSeconds(t()) :: integer()
  def getSeconds(%__MODULE__{} = j), do: local_parts(j).second

  @doc "Gets the milliseconds (0-999)."
  @spec getMilliseconds(t()) :: integer()
  def getMilliseconds(%__MODULE__{} = j), do: local_parts(j).ms

  @doc "Gets the Unix millisecond timestamp."
  @spec getTime(t()) :: integer()
  def getTime(%__MODULE__{ms: ms}), do: ms

  @doc "Gets the Jalali week number of the year (1-53)."
  @spec getWeekOfYear(t()) :: integer()
  def getWeekOfYear(%__MODULE__{} = j) do
    day_of_year = getDayOfYear(j)
    day_of_week = j |> getStartOfYear() |> getDayISO()
    ceil_pos(day_of_year + day_of_week - 1, 7)
  end

  @doc "Gets the Jalali day of the year (1-366)."
  @spec getDayOfYear(t()) :: integer()
  def getDayOfYear(%__MODULE__{} = j) do
    jalali = to_jalali(j)

    cond do
      jalali.month < 7 -> jalali.day + (jalali.month - 1) * 31
      jalali.month < 12 -> jalali.day + 186 + (jalali.month - 7) * 30
      true -> jalali.day + 336
    end
  end

  @doc "Gets the ISO day of the week (1=Monday .. 7=Sunday)."
  @spec getDayISO(t()) :: integer()
  def getDayISO(%__MODULE__{} = j), do: Integer.mod(getDay(j) + 6, 7) + 1

  @doc "Gets the hour in 12-hour format (1-12)."
  @spec getHoursISO(t()) :: integer()
  def getHoursISO(%__MODULE__{} = j) do
    hours = getHours(j)
    if hours > 12, do: hours - 12, else: hours
  end

  @doc "Gets the meridiem (AM/PM) in Persian."
  @spec getMeridiem(t()) :: String.t()
  def getMeridiem(%__MODULE__{} = j) do
    jalali = to_jalali(j)
    if jalali.hours > 12, do: @pm, else: @am
  end

  @doc "Sets the Unix millisecond timestamp."
  @spec setTime(t(), number()) :: t()
  def setTime(%__MODULE__{} = j, time), do: %{j | ms: trunc(time)}

  @doc "Sets the milliseconds using wall time in the active timezone."
  @spec setMilliseconds(t(), number()) :: t()
  def setMilliseconds(%__MODULE__{} = j, ms) do
    parts = local_parts(j)
    new_ms = wall_to_utc(parts.epoch_day, parts.hour, parts.minute, parts.second, trunc(ms), j.timezone)
    %{j | ms: new_ms}
  end

  @doc "Sets the seconds (and optionally milliseconds) using wall time."
  @spec setSeconds(t(), number(), number() | nil) :: t()
  def setSeconds(%__MODULE__{} = j, sec, ms \\ nil) do
    parts = local_parts(j)
    msv = if is_nil(ms), do: parts.ms, else: trunc(ms)
    new_ms = wall_to_utc(parts.epoch_day, parts.hour, parts.minute, trunc(sec), msv, j.timezone)
    %{j | ms: new_ms}
  end

  @doc "Sets the minutes (and optionally seconds/milliseconds) using wall time."
  @spec setMinutes(t(), number(), number() | nil, number() | nil) :: t()
  def setMinutes(%__MODULE__{} = j, min, sec \\ nil, ms \\ nil) do
    parts = local_parts(j)
    secv = if is_nil(sec), do: parts.second, else: trunc(sec)
    msv = if is_nil(ms), do: parts.ms, else: trunc(ms)
    new_ms = wall_to_utc(parts.epoch_day, parts.hour, trunc(min), secv, msv, j.timezone)
    %{j | ms: new_ms}
  end

  @doc "Sets the hour (and optionally minutes/seconds/milliseconds) using wall time."
  @spec setHours(t(), number(), number() | nil, number() | nil, number() | nil) :: t()
  def setHours(%__MODULE__{} = j, hours, min \\ nil, sec \\ nil, ms \\ nil) do
    parts = local_parts(j)
    minv = if is_nil(min), do: parts.minute, else: trunc(min)
    secv = if is_nil(sec), do: parts.second, else: trunc(sec)
    msv = if is_nil(ms), do: parts.ms, else: trunc(ms)
    new_ms = wall_to_utc(parts.epoch_day, trunc(hours), minv, secv, msv, j.timezone)
    %{j | ms: new_ms}
  end

  @doc "Sets the day of the month (Jalali) using wall time."
  @spec setDate(t(), integer()) :: t()
  def setDate(%__MODULE__{} = j, date) do
    jalali = to_jalali(j)
    normalize_date(j, date - jalali.day)
  end

  @doc """
  Sets the Jalali month using wall time.

  `month` is **0-based** (Farvardin = 0 .. Esfand = 11), matching JS `Date`.
  """
  @spec setMonth(t(), integer(), integer() | nil) :: t()
  def setMonth(%__MODULE__{} = j, month, date \\ nil) do
    jalali = to_jalali(j)
    new_ms = normalize_jalali(jalali, jalali.year, month + 1, jalali.day, j.timezone)
    j2 = %{j | ms: new_ms}

    if is_nil(date) do
      j2
    else
      jalali2 = to_jalali(j2)
      normalize_date(j2, date - jalali2.day)
    end
  end

  @doc """
  Sets the Jalali year (and optionally month/day) using wall time.

  `month` is **0-based** (Farvardin = 0 .. Esfand = 11), matching JS `Date`.
  """
  @spec setFullYear(t(), integer(), integer() | nil, integer() | nil) :: t()
  def setFullYear(%__MODULE__{} = j, year, month \\ nil, date \\ nil) do
    jalali = to_jalali(j)
    month_target = if is_nil(month), do: jalali.month, else: month + 1
    new_ms = normalize_jalali(jalali, year, month_target, jalali.day, j.timezone)
    j2 = %{j | ms: new_ms}

    if is_nil(date) do
      j2
    else
      jalali2 = to_jalali(j2)
      normalize_date(j2, date - jalali2.day)
    end
  end

  @doc "Adds the given number of Jalali years (can be negative)."
  @spec addYears(t(), integer()) :: t()
  def addYears(%__MODULE__{} = j, years) do
    jalali = to_jalali(j)
    new_ms = normalize_jalali(jalali, jalali.year + years, jalali.month, jalali.day, j.timezone)
    %{j | ms: new_ms}
  end

  @doc "Adds the given number of Jalali months (can be negative)."
  @spec addMonths(t(), integer()) :: t()
  def addMonths(%__MODULE__{} = j, months) do
    jalali = to_jalali(j)
    new_ms = normalize_jalali(jalali, jalali.year, jalali.month + months, jalali.day, j.timezone)
    %{j | ms: new_ms}
  end

  @doc "Adds the given number of weeks (can be negative)."
  @spec addWeeks(t(), integer()) :: t()
  def addWeeks(%__MODULE__{} = j, weeks), do: normalize_date(j, weeks * 7)

  @doc "Adds the given number of days (can be negative)."
  @spec addDays(t(), integer()) :: t()
  def addDays(%__MODULE__{} = j, days), do: normalize_date(j, days)

  @doc "Returns a new instance set to the start of the Jalali year."
  @spec getStartOfYear(t()) :: t()
  def getStartOfYear(%__MODULE__{} = j), do: j |> addDays(-getDayOfYear(j) + 1) |> getStartOfDay()

  @doc "Returns a new instance set to the start of the current Jalali month."
  @spec getStartOfMonth(t()) :: t()
  def getStartOfMonth(%__MODULE__{} = j), do: j |> addDays(-getDate(j) + 1) |> getStartOfDay()

  @doc "Returns a new instance set to the start of the current week (Saturday)."
  @spec getStartOfWeek(t()) :: t()
  def getStartOfWeek(%__MODULE__{} = j), do: j |> addDays(-getDayISO(j) + 1) |> getStartOfDay()

  @doc "Returns a new instance set to the start of the current day (00:00:00.000)."
  @spec getStartOfDay(t()) :: t()
  def getStartOfDay(%__MODULE__{} = j), do: setHours(j, 0, 0, 0, 0)

  @doc "Returns a new instance set to the end of the Jalali year (23:59:59.999)."
  @spec getEndOfYear(t()) :: t()
  def getEndOfYear(%__MODULE__{} = j) do
    jalali = to_jalali(j)
    last_day = if jalali.is_leap_year, do: 366, else: 365
    j |> addDays(last_day - getDayOfYear(j)) |> getEndOfDay()
  end

  @doc "Returns a new instance set to the end of the current Jalali month."
  @spec getEndOfMonth(t()) :: t()
  def getEndOfMonth(%__MODULE__{} = j) do
    jalali = to_jalali(j)

    last_day =
      cond do
        jalali.month > 6 and jalali.month < 12 -> 30
        jalali.month == 12 -> if jalali.is_leap_year, do: 30, else: 29
        true -> 31
      end

    j |> addDays(last_day - getDate(j)) |> getEndOfDay()
  end

  @doc "Returns a new instance set to the end of the current week (Friday)."
  @spec getEndOfWeek(t()) :: t()
  def getEndOfWeek(%__MODULE__{} = j), do: j |> addDays(7 - getDayISO(j)) |> getEndOfDay()

  @doc "Returns a new instance set to the end of the current day (23:59:59.999)."
  @spec getEndOfDay(t()) :: t()
  def getEndOfDay(%__MODULE__{} = j), do: setHours(j, 23, 59, 59, 999)

  @doc """
  Returns a calendar date string using wall getters in the active timezone
  (no UTC shift).

  `calendar` is `"gregorian"` (default, `YYYY-MM-DD` Gregorian) or
  `"jalali"` (Jalali `YYYY-MM-DD`).
  """
  @spec toISODate(t(), String.t()) :: String.t()
  def toISODate(%__MODULE__{} = j, calendar \\ "gregorian") do
    if calendar == "jalali" do
      format(j, "YYYY-MM-DD")
    else
      parts = local_parts(j)
      "#{parts.year}-#{add_zero(parts.month)}-#{add_zero(parts.day)}"
    end
  end

  @doc """
  Formats the date according to a format string.

  Prefer `format(j, str, %{calendar: ..., persianDigits: ...})`. Positional
  booleans remain supported: `format(j, str, persianDigits?, gregorian?)`.

  ## Tokens

      YYYY YYY YY Y       year
      MMM MM M            month name / number
      W w                 week of year (padded / not)
      DW dw WN wn WL wl    day-of-week (iso number / number / name / letter)
      DDDD DDD             day of year (padded / not)
      DD D                 day of month (padded / not)
      HH H                 hour, 24h (padded / not)
      hh h                 hour, 12h (padded / not)
      mm m                 minutes (padded / not)
      ss s                 seconds (padded / not)
      SSS sss              milliseconds
      A a                  meridiem
      X x                  unix seconds / milliseconds
  """
  @spec format(t(), String.t(), boolean() | map() | keyword(), boolean()) :: String.t()
  def format(%__MODULE__{} = j, pattern, persian_or_options \\ false, gregorian \\ false) do
    {persian, use_gregorian} =
      case persian_or_options do
        opts when is_map(opts) or is_list(opts) -> parse_format_opts(opts)
        flag -> {flag, gregorian}
      end

    do_format(j, pattern, persian, use_gregorian)
  end

  defp opt_timezone(opts) when is_list(opts), do: Keyword.get(opts, :timezone)

  defp opt_timezone(opts) when is_map(opts) do
    Map.get(opts, :timezone) || Map.get(opts, "timezone")
  end

  defp opt_timezone(_), do: nil

  defp parse_format_opts(opts) when is_map(opts) do
    persian = Map.get(opts, :persianDigits) || Map.get(opts, "persianDigits") || false
    calendar = Map.get(opts, :calendar) || Map.get(opts, "calendar")
    {persian, calendar == "gregorian"}
  end

  defp parse_format_opts(opts) when is_list(opts) do
    persian = Keyword.get(opts, :persianDigits, false)
    calendar = Keyword.get(opts, :calendar)
    {persian, calendar == "gregorian"}
  end

  defp group_int(list, idx) do
    case Enum.at(list, idx) do
      nil -> 0
      "" -> 0
      s -> String.to_integer(s)
    end
  end

  defp parse_input(%__MODULE__{ms: ms}), do: ms

  defp parse_input(%Date{year: y, month: m, day: d}), do: days_from_civil(y, m, d) * @date_length

  defp parse_input(%DateTime{} = dt), do: DateTime.to_unix(dt, :millisecond)

  defp parse_input(%NaiveDateTime{} = ndt) do
    {micro, _} = ndt.microsecond

    days_from_civil(ndt.year, ndt.month, ndt.day) * @date_length +
      ndt.hour * 3_600_000 + ndt.minute * 60_000 + ndt.second * 1000 + div(micro, 1000)
  end

  defp parse_input(ms) when is_integer(ms), do: ms
  defp parse_input(ms) when is_float(ms), do: trunc(ms)
  defp parse_input(s) when is_binary(s), do: parse_iso_string(s)

  defp parse_input(other) do
    raise ArgumentError, "JalaliX.create: unsupported date type #{inspect(other)}"
  end

  defp parse_iso_string(s) do
    trimmed = String.trim(s)

    if Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, trimmed) do
      [y, m, d] = trimmed |> String.split("-") |> Enum.map(&String.to_integer/1)
      days_from_civil(y, m, d) * @date_length
    else
      case DateTime.from_iso8601(trimmed) do
        {:ok, dt, _offset} ->
          DateTime.to_unix(dt, :millisecond)

        {:error, _} ->
          case NaiveDateTime.from_iso8601(trimmed) do
            {:ok, ndt} ->
              {micro, _} = ndt.microsecond

              days_from_civil(ndt.year, ndt.month, ndt.day) * @date_length +
                ndt.hour * 3_600_000 + ndt.minute * 60_000 + ndt.second * 1000 + div(micro, 1000)

            {:error, _} ->
              raise ArgumentError, "JalaliX.create: invalid date string #{inspect(s)}"
          end
      end
    end
  end

  defp offset_ms(tz), do: Map.get(@offsets, tz)

  defp offset_ms!(tz) do
    case offset_ms(tz) do
      nil -> raise ArgumentError, "invalid timezone: #{tz}"
      v -> v
    end
  end

  defp host_local_iana do
    case System.get_env("TZ") do
      nil -> "UTC"
      "" -> "UTC"
      tz -> if offset_ms(tz), do: tz, else: "UTC"
    end
  end

  defp normalize_timezone(nil, current), do: current

  defp normalize_timezone(tz, _current) when is_binary(tz) do
    trimmed = String.trim(tz)

    if trimmed == "" do
      raise ArgumentError, "invalid timezone: empty"
    end

    lowered = String.downcase(trimmed)

    cond do
      lowered in ["default", "local", "system"] ->
        host_local_iana()

      lowered in ["utc", "gmt"] ->
        "UTC"

      true ->
        _ = offset_ms!(trimmed)
        trimmed
    end
  end

  defp days_from_civil(y, m, d) do
    y = if m <= 2, do: y - 1, else: y
    era = div(if(y >= 0, do: y, else: y - 399), 400)
    yoe = y - era * 400
    mp = if m > 2, do: m - 3, else: m + 9
    doy = div(153 * mp + 2, 5) + d - 1
    doe = yoe * 365 + div(yoe, 4) - div(yoe, 100) + doy
    era * 146_097 + doe - 719_468
  end

  defp civil_from_days(z) do
    z = z + 719_468
    era = div(if(z >= 0, do: z, else: z - 146_096), 146_097)
    doe = z - era * 146_097
    yoe = div(doe - div(doe, 1460) + div(doe, 36524) - div(doe, 146_096), 365)
    y = yoe + era * 400
    doy = doe - (365 * yoe + div(yoe, 4) - div(yoe, 100))
    mp = div(5 * doy + 2, 153)
    d = doy - div(153 * mp + 2, 5) + 1
    m = if mp < 10, do: mp + 3, else: mp - 9
    y = if m <= 2, do: y + 1, else: y
    {y, m, d}
  end

  defp local_parts(%__MODULE__{ms: ms, timezone: tz}) do
    offset = offset_ms!(tz)
    wall = ms + offset
    day = Integer.floor_div(wall, @date_length)
    rem_ms = wall - day * @date_length
    hour = div(rem_ms, 3_600_000)
    rem2 = rem_ms - hour * 3_600_000
    minute = div(rem2, 60_000)
    rem3 = rem2 - minute * 60_000
    second = div(rem3, 1000)
    ms_part = rem3 - second * 1000
    {y, mo, da} = civil_from_days(day)

    %{year: y, month: mo, day: da, hour: hour, minute: minute, second: second, ms: ms_part, epoch_day: day}
  end

  defp js_day(%__MODULE__{} = j), do: Integer.mod(local_parts(j).epoch_day + 4, 7)

  defp wall_to_utc(day, h, mi, s, ms_part, tz) do
    wall_as_utc = day * @date_length + h * 3_600_000 + mi * 60_000 + s * 1000 + ms_part
    wall_as_utc - offset_ms!(tz)
  end

  defp normalize_date(%__MODULE__{} = j, days), do: %{j | ms: j.ms + days * @date_length}

  defp check_leap_year(year) when year > 0 do
    check = (year + 2346) * @leap_year_division
    check - trunc(check) < @leap_year_division
  end

  defp check_leap_year(_), do: false

  defp step_forward(%{year: y, month: m, day: d}) do
    d = d + 1

    cond do
      m < 7 and d > 31 ->
        %{year: y, month: m + 1, day: 1}

      m > 6 and m < 12 and d > 30 ->
        %{year: y, month: m + 1, day: 1}

      m == 12 ->
        leap = check_leap_year(y)

        cond do
          leap and d > 30 -> %{year: y + 1, month: 1, day: 1}
          not leap and d > 29 -> %{year: y + 1, month: 1, day: 1}
          true -> %{year: y, month: m, day: d}
        end

      true ->
        %{year: y, month: m, day: d}
    end
  end

  defp step_backward(%{year: y, month: m, day: d}) do
    d = d - 1

    if d < 1 do
      cond do
        m == 1 ->
          y2 = y - 1
          leap = check_leap_year(y2)
          %{year: y2, month: 12, day: if(leap, do: 30, else: 29)}

        m < 8 ->
          %{year: y, month: m - 1, day: 31}

        true ->
          %{year: y, month: m - 1, day: 30}
      end
    else
      %{year: y, month: m, day: d}
    end
  end

  defp epoch_day_to_jalali(diff_days) do
    jalali =
      cond do
        diff_days > 0 -> Enum.reduce(1..diff_days, @base_jalali, fn _, acc -> step_forward(acc) end)
        diff_days < 0 -> Enum.reduce(1..-diff_days, @base_jalali, fn _, acc -> step_backward(acc) end)
        true -> @base_jalali
      end

    Map.put(jalali, :is_leap_year, check_leap_year(jalali.year))
  end

  defp walk_to_target(cur, target, diff, _dir) when cur == target, do: diff

  defp walk_to_target(cur, target, diff, :forward) do
    walk_to_target(step_forward(cur), target, diff + 1, :forward)
  end

  defp walk_to_target(cur, target, diff, :backward) do
    walk_to_target(step_backward(cur), target, diff - 1, :backward)
  end

  defp jalali_to_epoch_day(ty, tm, td) do
    target = %{year: ty, month: tm, day: td}

    if @base_jalali == target do
      0
    else
      after_or_equal =
        ty > 1348 or (ty == 1348 and tm >= 10) or (ty == 1348 and tm == 10 and td >= 11)

      dir = if after_or_equal, do: :forward, else: :backward
      walk_to_target(@base_jalali, target, 0, dir)
    end
  end

  defp to_jalali(%__MODULE__{} = j) do
    parts = local_parts(j)
    jal = epoch_day_to_jalali(parts.epoch_day)

    %{
      year: jal.year,
      month: jal.month,
      day: jal.day,
      is_leap_year: jal.is_leap_year,
      hours: parts.hour,
      min: parts.minute,
      sec: parts.second,
      ms: parts.ms
    }
  end

  defp to_gregorian(jalali_map, tz) do
    day = jalali_to_epoch_day(jalali_map.year, jalali_map.month, jalali_map.day)
    wall_to_utc(day, jalali_map.hours, jalali_map.min, jalali_map.sec, jalali_map.ms, tz)
  end

  defp ceil_div(a, b) when b > 0, do: -Integer.floor_div(-a, b)
  defp ceil_pos(a, b) when b > 0, do: div(a + b - 1, b)

  defp normalize_month(year, month) when month < 1 do
    year_diff = ceil_div(1 - month, 12)
    {year - year_diff, 12 * year_diff + month}
  end

  defp normalize_month(year, month) when month > 12 do
    year_diff = Integer.floor_div(month - 1, 12)
    {year + year_diff, month - 12 * year_diff}
  end

  defp normalize_month(year, month), do: {year, month}

  defp clamp_day(year, month, day) do
    cond do
      month > 6 and month < 12 and day > 30 ->
        30

      month == 12 ->
        leap = check_leap_year(year)

        cond do
          leap and day > 30 -> 30
          not leap and day > 29 -> 29
          true -> day
        end

      true ->
        day
    end
  end

  defp normalize_jalali(jalali, year, month, day, tz) do
    {year2, month2} = normalize_month(year, month)
    day2 = clamp_day(year2, month2, day)
    new_jalali = %{jalali | year: year2, month: month2, day: day2}
    to_gregorian(new_jalali, tz)
  end

  defp add_zero(n) do
    prefix = if n > -1 and n < 10, do: "0", else: ""
    prefix <> Integer.to_string(n)
  end

  defp pad2(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  defp get_jalali_month_name(n), do: Enum.at(@months_names, n - 1)
  defp get_gregorian_month_name(n), do: Enum.at(@months_gregorian_names, n - 1)

  defp get_week_day_name(%__MODULE__{} = j) do
    Enum.at(@week_days_names, Integer.mod(getDay(j) + @first_day_of_week, 7))
  end

  defp get_week_day_letter(%__MODULE__{} = j) do
    Enum.at(@week_days_letters, Integer.mod(getDay(j) + @first_day_of_week, 7))
  end

  defp get_gregorian_week_day_name(%__MODULE__{} = j), do: Enum.at(@week_days_gregorian_names, js_day(j))
  defp get_gregorian_week_day_letter(%__MODULE__{} = j), do: Enum.at(@week_days_gregorian_letters, js_day(j))

  defp get_gregorian_meridiem(%__MODULE__{} = j) do
    if getHours(j) >= 12, do: @pm_gregorian, else: @am_gregorian
  end

  defp get_utc_timezone(%__MODULE__{timezone: tz}) do
    offset = offset_ms!(tz)
    offset_min = div(offset, 60_000)
    sign = if offset_min >= 0, do: "+", else: "-"
    abs_min = abs(offset_min)
    hh = div(abs_min, 60)
    mm = rem(abs_min, 60)
    " GMT#{sign}#{pad2(hh)}#{pad2(mm)}"
  end

  defp get_gregorian_day_of_year(%__MODULE__{} = j) do
    parts = local_parts(j)
    start_day = days_from_civil(parts.year, 1, 0)
    parts.epoch_day - start_day
  end

  defp get_gregorian_week_of_year(%__MODULE__{} = j) do
    parts = local_parts(j)
    day = parts.epoch_day
    dow = Integer.mod(day + 4, 7)
    iso_dow = if dow == 0, do: 7, else: dow
    thursday_day = day + 4 - iso_dow
    {ty, _, _} = civil_from_days(thursday_day)
    year_start = days_from_civil(ty, 1, 1)
    ceil_pos(thursday_day - year_start + 1, 7)
  end

  defp slice_last(s, n) do
    len = String.length(s)
    if len <= n, do: s, else: String.slice(s, len - n, n)
  end

  defp do_format(%__MODULE__{} = j, pattern, persian, use_gregorian) do
    parts = local_parts(j)

    year = if use_gregorian, do: parts.year, else: getFullYear(j)
    month = if use_gregorian, do: parts.month, else: getMonth(j)
    week_of_year = if use_gregorian, do: get_gregorian_week_of_year(j), else: getWeekOfYear(j)
    day_of_year = if use_gregorian, do: get_gregorian_day_of_year(j), else: getDayOfYear(j)
    date_n = if use_gregorian, do: parts.day, else: getDate(j)

    month_name = if use_gregorian, do: get_gregorian_month_name(month), else: get_jalali_month_name(month)
    week_day_name = if use_gregorian, do: get_gregorian_week_day_name(j), else: get_week_day_name(j)
    week_day_letter = if use_gregorian, do: get_gregorian_week_day_letter(j), else: get_week_day_letter(j)
    meridiem = if use_gregorian, do: get_gregorian_meridiem(j), else: getMeridiem(j)

    year_str = Integer.to_string(year)
    hours = getHours(j)

    hours_iso =
      cond do
        hours > 12 -> hours - 12
        hours == 0 -> 12
        true -> hours
      end

    minutes = getMinutes(j)
    seconds = getSeconds(j)
    millis = getMilliseconds(j)
    day_iso_value = getDayISO(j)

    dw_value =
      if use_gregorian do
        d = js_day(j)
        if d == 0, do: 7, else: d
      else
        getDay(j)
      end

    steps = [
      {~r/YYYY/, year_str},
      {~r/YYY/, slice_last(year_str, 3)},
      {~r/YY/, slice_last(year_str, 2)},
      {~r/Y/, slice_last(year_str, 1)},
      {~r/MMM/, month_name},
      {~r/MM/, add_zero(month)},
      {~r/M/, Integer.to_string(month)},
      {~r/W/, add_zero(week_of_year)},
      {~r/w/, Integer.to_string(week_of_year)},
      {~r/DW/, Integer.to_string(day_iso_value)},
      {~r/dw/, Integer.to_string(dw_value)},
      {~r/WN/, week_day_name},
      {~r/wn/, week_day_name},
      {~r/WL/, week_day_letter},
      {~r/wl/, week_day_letter},
      {~r/DDDD/, add_zero(day_of_year)},
      {~r/DDD/, Integer.to_string(day_of_year)},
      {~r/DD/, add_zero(date_n)},
      {~r/D/, Integer.to_string(date_n)},
      {~r/HH/, add_zero(hours)},
      {~r/H/, Integer.to_string(hours)},
      {~r/hh/, add_zero(hours_iso)},
      {~r/h/, Integer.to_string(hours_iso)},
      {~r/mm/, add_zero(minutes)},
      {~r/m/, Integer.to_string(minutes)},
      {~r/ss/, add_zero(seconds)},
      {~r/s/, Integer.to_string(seconds)},
      {~r/sss/, Integer.to_string(millis)},
      {~r/SSS/, Integer.to_string(millis)},
      {~r/A/, meridiem},
      {~r/a/, meridiem},
      {~r/X/, Integer.to_string(Integer.floor_div(getTime(j), 1000))},
      {~r/x/, Integer.to_string(getTime(j))}
    ]

    {output, placeholders} = Enum.reduce(steps, {pattern, []}, &apply_step/2)
    result = apply_placeholders(output, placeholders)

    if persian, do: toPersian(result), else: result
  end

  # Replaces every occurrence of `regex` in the accumulated output with a
  # unique, order-stable placeholder marker, remembering the real `value`
  # for each occurrence so it can be substituted back in at the very end
  # (this is what prevents a later, shorter token regex from re-matching
  # text produced by an earlier, longer one — e.g. `MMM` vs `M`).
  defp apply_step({regex, value}, {output, placeholders}) do
    case Regex.scan(regex, output) do
      [] ->
        {output, placeholders}

      matches ->
        start_index = length(placeholders)
        count = length(matches)
        new_placeholders = placeholders ++ List.duplicate(value, count)

        final_output =
          Enum.reduce(0..(count - 1), output, fn offset, acc ->
            idx = start_index + offset
            Regex.replace(regex, acc, "\uE000#{idx}\uE001", global: false)
          end)

        {final_output, new_placeholders}
    end
  end

  defp apply_placeholders(output, placeholders) do
    placeholders
    |> Enum.with_index()
    |> Enum.reduce(output, fn {val, idx}, acc ->
      String.replace(acc, "\uE000#{idx}\uE001", val)
    end)
  end
end
