defmodule Jalalix.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/jalalix/elixir"

  def project do
    [
      app: :jalalix,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "JalaliX",
      source_url: @source_url,
      homepage_url: "https://jalalix.com"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Jalali (Persian/Shamsi) calendar. Part of JalaliX — same API and outputs across languages. https://jalalix.com"
  end

  defp package do
    [
      name: "jalalix",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Website" => "https://jalalix.com",
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
