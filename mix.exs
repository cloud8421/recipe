defmodule Recipe.Mixfile do
  use Mix.Project

  @version "0.2.0"
  @description """
  A library to compose multi-step, reversible workflows.
  """
  @maintainers ["Claudio Ortolina <cloud8421@gmail.com>"]

  def project do
    [app: :recipe,
     version: @version,
     description: @description,
     package: package(),
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     source_url: "https://github.com/cloud8421/recipe",
     homepage_url: "https://github.com/cloud8421/recipe",
     docs: [main: "readme", extras: ["README.md"]],
     deps: deps()]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [{:ex_doc, "~> 0.16.1", only: :docs, runtime: false},
     {:inch_ex, "~> 0.5.6", only: :docs, runtime: false},
     {:credo, "~> 0.8.1", only: :dev, runtime: false},
     {:dialyxir, "~> 0.5.0", only: :dev, runtime: false}]
  end

  defp package() do
    [maintainers: @maintainers,
     licenses: ["Apache 2.0"],
     links: %{"GitHub" => "https://github.com/cloud8421/recipe"}]
  end
end
