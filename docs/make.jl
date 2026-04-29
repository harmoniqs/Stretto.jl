using Stretto
using PiccoloDocsTemplate

pages = ["Home" => "index.md", "Library" => "lib.md"]

generate_docs(
    @__DIR__,
    "Stretto",
    [Stretto],
    pages;
    format_kwargs = (canonical = "https://docs.harmoniqs.co/Stretto.jl",),
    versions = ["dev" => "dev", "stable" => "v^", "v#.#"],
)
