defmodule JalaliXTest do
  @moduledoc """
  Basic API sanity tests, mirroring python/tests/test_jalalix.py.
  """

  use ExUnit.Case, async: true

  describe "create / format" do
    test "create from iso date string" do
      assert JalaliX.create("2025-02-25") |> JalaliX.format("YYYY/MM/DD") == "1403/12/07"
    end

    test "parseJalali to iso" do
      assert JalaliX.parseJalali("1403/12/07") |> JalaliX.toISODate() == "2025-02-25"
    end

    test "create from unix ms" do
      ms = 1_740_441_600_000
      d = JalaliX.create(ms)
      assert JalaliX.getTime(d) == ms
    end

    test "create from Date" do
      d = JalaliX.create(~D[2025-02-25])
      assert JalaliX.format(d, "YYYY/MM/DD") == "1403/12/07"
    end

    test "create from DateTime" do
      {:ok, dt, _} = DateTime.from_iso8601("2025-02-25T12:00:00Z")
      d = JalaliX.create(dt)
      assert JalaliX.format(d, "YYYY/MM/DD") == "1403/12/07"
    end
  end

  describe "parseJalali" do
    test "slash and dash equivalent" do
      a = JalaliX.parseJalali("1403/12/07")
      b = JalaliX.parseJalali("1403-12-07")
      assert JalaliX.toISODate(a) == JalaliX.toISODate(b)
      assert JalaliX.toISODate(a) == "2025-02-25"
    end

    test "persian digits and time" do
      d = JalaliX.parseJalali("۱۴۰۳-۱۲-۰۷ 14:30")
      assert JalaliX.format(d, "YYYY/MM/DD") == "1403/12/07"
      assert JalaliX.getHours(d) == 14
      assert JalaliX.getMinutes(d) == 30
    end

    test "invalid raises" do
      assert_raise ArgumentError, fn -> JalaliX.parseJalali("not-a-date") end
    end
  end

  describe "format" do
    test "persian digits option" do
      d = JalaliX.create("2025-02-25")
      assert JalaliX.format(d, "YYYY/MM/DD", %{persianDigits: true}) == "۱۴۰۳/۱۲/۰۷"
    end

    test "gregorian calendar option" do
      d = JalaliX.create("2025-02-25")
      assert JalaliX.format(d, "DD MMM YYYY", %{calendar: "gregorian"}) =~ "February"
    end

    test "positional api" do
      d = JalaliX.create("2025-02-25")
      assert JalaliX.format(d, "YYYY/MM/DD", true) == "۱۴۰۳/۱۲/۰۷"
    end
  end

  describe "persian helpers" do
    test "to/from persian" do
      assert JalaliX.toPersian("1403/12/07") == "۱۴۰۳/۱۲/۰۷"
      assert JalaliX.fromPersian("۱۴۰۳/۱۲/۰۷") == "1403/12/07"
    end
  end

  describe "month quirk" do
    test "getMonth 1-based, setFullYear 0-based" do
      d = JalaliX.create("2025-02-25")
      d = JalaliX.setFullYear(d, 1404, 0, 1)
      assert JalaliX.getMonth(d) == 1
      assert JalaliX.getDate(d) == 1
      assert JalaliX.getFullYear(d) == 1404
    end

    test "setMonth 0-based" do
      d = JalaliX.parseJalali("1403/01/15")
      d = JalaliX.setMonth(d, 11)
      assert JalaliX.getMonth(d) == 12
    end
  end

  describe "mutating helpers" do
    test "add and start chain" do
      result =
        JalaliX.create("2025-02-25")
        |> JalaliX.addMonths(1)
        |> JalaliX.getStartOfMonth()
        |> JalaliX.format("YYYY/MM/DD")

      assert result == "1404/01/01"
    end

    test "setters return new structs, do not mutate the original" do
      d = JalaliX.create("2025-02-25")
      d2 = JalaliX.setHours(d, 10, 20, 30, 0)
      assert JalaliX.getHours(d2) == 10
      assert JalaliX.getMinutes(d2) == 20
      assert JalaliX.getSeconds(d2) == 30
      assert JalaliX.getHours(d) == 0
      assert JalaliX.getTime(d) != JalaliX.getTime(d2)
    end

    test "clone" do
      a = JalaliX.create("2025-02-25")
      b = JalaliX.clone(a)
      assert JalaliX.getTime(a) == JalaliX.getTime(b)
      c = JalaliX.addDays(b, 1)
      assert JalaliX.getTime(a) != JalaliX.getTime(c)
    end
  end

  describe "compare and valid" do
    test "compare" do
      a = JalaliX.create("2025-02-25")
      b = JalaliX.create("2025-02-26")
      assert JalaliX.compare(a, b) == true
      assert JalaliX.compare(b, a) == false
    end

    test "isValidDate" do
      assert JalaliX.isValidDate(DateTime.utc_now()) == true
      assert JalaliX.isValidDate(Date.utc_today()) == true
      assert JalaliX.isValidDate(JalaliX.create("2025-02-25")) == true
      assert JalaliX.isValidDate("2025-02-25") == false
      assert JalaliX.isValidDate(nil) == false
    end
  end

  describe "round trip" do
    test "several dates" do
      samples = [
        {"2024-03-20", "1403/01/01"},
        {"2025-02-25", "1403/12/07"},
        {"2025-03-21", "1404/01/01"}
      ]

      for {iso, jalali} <- samples do
        assert JalaliX.create(iso) |> JalaliX.format("YYYY/MM/DD") == jalali
        assert JalaliX.parseJalali(jalali) |> JalaliX.toISODate() == iso
      end
    end
  end

  describe "timezone" do
    @ms 1_740_430_800_000
    @ms_noon 1_740_484_800_000

    test "tehran offset instant" do
      d = JalaliX.create(@ms) |> JalaliX.setTimezone("Asia/Tehran")
      assert JalaliX.getTime(d) == @ms
      assert JalaliX.getTimezone(d) == "Asia/Tehran"
      assert JalaliX.format(d, "YYYY/MM/DD") == "1403/12/07"
      assert JalaliX.format(d, "HH:mm:ss") == "00:30:00"
      assert JalaliX.toISODate(d) == "2025-02-25"
      assert JalaliX.toISODate(d, "jalali") == "1403-12-07"
    end

    test "same instant utc" do
      d = JalaliX.create(@ms) |> JalaliX.setTimezone("UTC")
      assert JalaliX.getTime(d) == @ms
      assert JalaliX.format(d, "YYYY/MM/DD") == "1403/12/06"
      assert JalaliX.format(d, "HH:mm:ss") == "21:00:00"
      assert JalaliX.toISODate(d) == "2025-02-24"
    end

    test "utc noon tehran" do
      d = JalaliX.create(@ms_noon) |> JalaliX.setTimezone("Asia/Tehran")
      assert JalaliX.format(d, "YYYY/MM/DD") == "1403/12/07"
      assert JalaliX.format(d, "HH:mm:ss") == "15:30:00"
    end

    test "alias utc" do
      d = JalaliX.create(@ms_noon) |> JalaliX.setTimezone("utc")
      assert JalaliX.getTimezone(d) == "UTC"
    end

    test "instant preserving and invalid" do
      d = JalaliX.create(@ms)
      tehran = JalaliX.setTimezone(d, "Asia/Tehran")
      utc = JalaliX.setTimezone(d, "UTC")
      assert JalaliX.getTime(d) == JalaliX.getTime(tehran)
      assert JalaliX.getTime(tehran) == JalaliX.getTime(utc)
      assert JalaliX.format(tehran, "YYYY/MM/DD") != JalaliX.format(utc, "YYYY/MM/DD")

      assert_raise ArgumentError, fn -> JalaliX.setTimezone(d, "Mars/Olympus") end
    end

    test "clone keeps timezone" do
      a = JalaliX.create(@ms) |> JalaliX.setTimezone("Asia/Tehran")
      b = JalaliX.clone(a)
      assert JalaliX.getTimezone(b) == "Asia/Tehran"
      assert JalaliX.format(b, "HH:mm:ss") == "00:30:00"
    end
  end
end
