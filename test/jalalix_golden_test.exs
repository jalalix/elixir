defmodule JalaliX.GoldenTest do
  use ExUnit.Case, async: true

  @golden_path Path.expand("../testdata/golden.json", __DIR__)

  setup_all do
    data = @golden_path |> File.read!() |> Jason.decode!()
    assert data["version"] == 1
    {:ok, golden: data}
  end

  defp create_from(%{"unixMs" => ms} = spec) do
    d = JalaliX.create(ms)

    case spec do
      %{"timezone" => tz} -> JalaliX.setTimezone(d, tz)
      _ -> d
    end
  end

  defp create_from(%{"isoDate" => iso}) do
    JalaliX.create(iso)
  end

  test "golden calendar cases", %{golden: golden} do
    for case_ <- golden["calendar"] do
      d = create_from(case_["create"])
      expect = case_["expect"]
      id = case_["id"]

      assert JalaliX.format(d, "YYYY/MM/DD") == expect["formatYYYYMMDD"], id
      assert JalaliX.toISODate(d) == expect["toISODateGregorian"], id
      assert JalaliX.toISODate(d, "jalali") == expect["toISODateJalali"], id
    end
  end

  test "golden parse cases", %{golden: golden} do
    for case_ <- golden["parse"] do
      d = JalaliX.parseJalali(case_["input"])
      expect = case_["expect"]
      id = case_["id"]

      assert JalaliX.toISODate(d) == expect["toISODateGregorian"], id

      if Map.has_key?(expect, "formatYYYYMMDD") do
        assert JalaliX.format(d, "YYYY/MM/DD") == expect["formatYYYYMMDD"], id
      end
    end
  end

  test "golden format cases", %{golden: golden} do
    for case_ <- golden["format"] do
      if Map.has_key?(case_, "toPersian") do
        assert JalaliX.toPersian(case_["toPersian"]["input"]) == case_["toPersian"]["expect"]
        assert JalaliX.fromPersian(case_["fromPersian"]["input"]) == case_["fromPersian"]["expect"]
      else
        d = create_from(case_["create"])
        opts = case_["options"]
        assert JalaliX.format(d, case_["pattern"], opts) == case_["expect"], case_["id"]
      end
    end
  end

  test "golden timezone cases", %{golden: golden} do
    for case_ <- golden["timezone"] do
      if Map.has_key?(case_, "setTimezoneAlias") do
        d = JalaliX.create(case_["unixMs"]) |> JalaliX.setTimezone(case_["setTimezoneAlias"])
        assert JalaliX.getTimezone(d) == case_["expectTimezone"], case_["id"]
      else
        d = JalaliX.create(case_["unixMs"]) |> JalaliX.setTimezone(case_["withTimezone"])
        expect = case_["expect"]
        id = case_["id"]

        assert JalaliX.format(d, "YYYY/MM/DD") == expect["jalaliSlash"], id

        if Map.has_key?(expect, "jalaliIso") do
          assert JalaliX.toISODate(d, "jalali") == expect["jalaliIso"], id
        end

        if Map.has_key?(expect, "wallGregorian") do
          assert JalaliX.toISODate(d) == expect["wallGregorian"], id
        end

        if Map.has_key?(expect, "wallTime") do
          assert JalaliX.format(d, "HH:mm:ss") == expect["wallTime"], id
        end

        assert JalaliX.getHours(d) == expect["hours"], id
        assert JalaliX.getMinutes(d) == expect["minutes"], id

        if Map.has_key?(expect, "getTime") do
          assert JalaliX.getTime(d) == expect["getTime"], id
        end
      end
    end
  end

  test "golden mutation cases", %{golden: golden} do
    for case_ <- golden["mutations"] do
      d = create_from(case_["create"])

      if Map.has_key?(case_, "setFullYear") do
        sfy = case_["setFullYear"]

        d =
          JalaliX.setFullYear(d, sfy["year"], sfy["month0"], sfy["day"])

        assert JalaliX.getMonth(d) == case_["expect"]["getMonth"], case_["id"]
        assert JalaliX.format(d, "YYYY/MM/DD") == case_["expect"]["formatYYYYMMDD"], case_["id"]
      else
        d =
          Enum.reduce(case_["ops"], d, fn op, acc ->
            cond do
              String.starts_with?(op, "addMonths:") ->
                n = op |> String.split(":") |> Enum.at(1) |> String.to_integer()
                JalaliX.addMonths(acc, n)

              op == "getStartOfMonth" ->
                JalaliX.getStartOfMonth(acc)

              true ->
                flunk("unknown op #{op}")
            end
          end)

        assert JalaliX.format(d, "YYYY/MM/DD") == case_["expect"]["formatYYYYMMDD"], case_["id"]
      end
    end
  end
end
