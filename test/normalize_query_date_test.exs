defmodule JalaliX.NormalizeQueryDateTest do
  use ExUnit.Case, async: true

  test "fromPersian converts Persian and Arabic-Indic digits" do
    assert JalaliX.toPersian("1403/12/07") == "۱۴۰۳/۱۲/۰۷"
    assert JalaliX.fromPersian("۱۴۰۳/۱۲/۰۷") == "1403/12/07"
    assert JalaliX.fromPersian("١٤٠٣/١٢/٠٧") == "1403/12/07"
  end

  test "parseJalali accepts dot separator" do
    assert JalaliX.parseJalali("1403.12.07") |> JalaliX.toISODate() == "2025-02-25"
  end

  test "normalizeQueryDate sentinels and timestamps" do
    assert JalaliX.normalizeQueryDate(nil) == nil
    assert JalaliX.normalizeQueryDate("null") == nil
    assert JalaliX.normalizeQueryDate("") == nil
    assert JalaliX.normalizeQueryDate("undefined") == nil
    assert JalaliX.normalizeQueryDate("Invalid Date") == nil
    assert JalaliX.normalizeQueryDate("NaN") == nil
    assert JalaliX.normalizeQueryDate(0) == nil
    assert JalaliX.normalizeQueryDate(-1) == nil

    seconds = 1_740_430_800

    assert JalaliX.normalizeQueryDate(seconds, %{"timezone" => "UTC"}) ==
             "2025-02-24 21:00:00"

    assert JalaliX.normalizeQueryDate(seconds * 1000, %{"timezone" => "Asia/Tehran"}) ==
             "2025-02-25 00:30:00"
  end

  test "normalizeQueryDate Jalali and Gregorian" do
    utc = %{"timezone" => "UTC"}

    assert JalaliX.normalizeQueryDate("1403/12/07", utc) == "2025-02-25 00:00:00"

    assert JalaliX.normalizeQueryDate("۱۴۰۳-۱۲-۰۷ 14:30:00", utc) ==
             "2025-02-25 14:30:00"

    assert JalaliX.normalizeQueryDate("2025.02.25") == "2025-02-25 00:00:00"
    assert JalaliX.normalizeQueryDate("2025-02-25 12:30:45.123Z") == "2025-02-25 12:30:45"
    assert JalaliX.normalizeQueryDate("not-a-date") == "not-a-date"

    assert JalaliX.normalizeQueryDate("1200/01/01", utc) != nil
    assert JalaliX.normalizeQueryDate("1800/01/01", utc) != nil

    assert JalaliX.normalizeQueryDate("2025-01-01") == "2025-01-01 00:00:00"

    widened = %{"timezone" => "UTC", "jalaliYearMin" => 1, "jalaliYearMax" => 3000}

    refute JalaliX.normalizeQueryDate("2025-01-01", widened) == "2025-01-01 00:00:00"
  end
end
