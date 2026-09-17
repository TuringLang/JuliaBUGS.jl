# Packs the example volumes into the artifact that ships with JuliaBUGS and updates
# JuliaBUGS/Artifacts.toml to point at it. Run it when the examples change and the
# installed package should follow:
#
#     julia BUGSExamples/snapshot.jl BUGSExamples-2026-09-17 out/
#     gh release create BUGSExamples-2026-09-17 out/BUGSExamples.tar.gz --title BUGSExamples-2026-09-17 --notes "Snapshot of BUGSExamples/"
#
# The tag names the release the tarball is uploaded to, and the tarball has to be the one
# this script wrote, since Artifacts.toml records its hash.

using Pkg.Artifacts, SHA

length(ARGS) == 2 || error("usage: snapshot.jl <tag> <out-dir>")
tag, out = ARGS
root = @__DIR__
toml = joinpath(root, "..", "JuliaBUGS", "Artifacts.toml")
url = "https://github.com/TuringLang/JuliaBUGS.jl/releases/download/$tag/BUGSExamples.tar.gz"

tree = create_artifact() do dir
    for volume in filter(startswith("volume_"), readdir(root))
        cp(joinpath(root, volume), joinpath(dir, volume))
    end
end

mkpath(out)
tarball = joinpath(out, "BUGSExamples.tar.gz")
archive_artifact(tree, tarball)
sha = bytes2hex(open(sha256, tarball))
bind_artifact!(
    toml,
    "BUGSExamples",
    tree;
    lazy = true,
    force = true,
    download_info = [(url, sha)],
)

println("tree     ", tree)
println("tarball  ", tarball, "  sha256 ", sha)
println("bound in ", normpath(toml), " to ", url)
