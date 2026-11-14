defmodule JalaliXTimezoneTest do
  @moduledoc """
  Golden parity tests for testdata/timezone.json (instant-preserving contract).
  """

  use ExUnit.Case, async: true

  @timezone_path Path.join([__DIR__, "..", "testdata", "timezone.json"])

  setup_all do
    data =
      @timezone_path
      |> File.read!()
      |> Jason.decode!()

    {:ok, data: data}
  end

  test "contract cases", %{data: data} do
    for c <- data["cases"] do
      if Map.has_key?(c, "setTimezoneAlias") do
        d =
          c["unixMs"]
          |> JalaliX.create()
          |> JalaliX.setTimezone(c["setTimezoneAlias"])

        assert JalaliX.getTimezone(d) == c["expectTimezone"], c["id"]
      else
        d =
          c["unixMs"]
          |> JalaliX.create()
          |> JalaliX.setTimezone(c["withTimezone"])

        assert JalaliX.getTime(d) == c["unixMs"], c["id"]
        assert JalaliX.toISODate(d) == c["wallGregorian"], c["id"]
        assert JalaliX.format(d, "HH:mm:ss") == c["wallTime"], c["id"]
        assert JalaliX.format(d, "YYYY/MM/DD") == c["jalaliSlash"], c["id"]
        assert JalaliX.toISODate(d, "jalali") == c["jalaliIso"], c["id"]
      end
    end
  end
end
